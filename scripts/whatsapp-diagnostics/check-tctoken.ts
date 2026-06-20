/**
 * Test tctoken pre-issuance and first-contact DM sending.
 *
 * Verifies the fix for error 463 (SenderReachoutTimelocked / missing tctoken).
 * Pre-issues a tctoken before sending, so the first message to a new contact
 * carries a valid privacy token.
 *
 * Stop the NanoClaw service before running — only one Baileys connection per auth.
 *
 * Usage (from nanoclaw project root):
 *   pnpm exec tsx /path/to/check-tctoken.ts <recipient-jid>
 *   e.g. pnpm exec tsx check-tctoken.ts 972501234567@s.whatsapp.net
 */
import { pino } from 'pino';
import {
  makeWASocket,
  Browsers,
  useMultiFileAuthState,
  makeCacheableSignalKeyStore,
  fetchLatestWaWebVersion,
  jidNormalizedUser,
  proto,
} from '@whiskeysockets/baileys';
import { storeTcTokensFromIqResult } from '@whiskeysockets/baileys/lib/Utils/tc-token-utils.js';

const recipientJid = process.argv[2];
if (!recipientJid || !recipientJid.endsWith('@s.whatsapp.net')) {
  console.error('Usage: check-tctoken.ts <recipient-jid>');
  console.error('  e.g. check-tctoken.ts 972501234567@s.whatsapp.net');
  process.exit(1);
}

const logger = pino({ level: 'warn' });

async function resolveVersion(): Promise<[number, number, number]> {
  try {
    const res = await fetch('https://wppconnect.io/whatsapp-versions/', {
      signal: AbortSignal.timeout(5000),
    });
    if (res.ok) {
      const html = await res.text();
      const match = html.match(/2\.3000\.(\d+)/);
      if (match) return [2, 3000, Number(match[1])];
    }
  } catch {}
  const { version } = await fetchLatestWaWebVersion({});
  return version;
}

async function main() {
  const { state, saveCreds } = await useMultiFileAuthState('store/auth');
  const version = await resolveVersion();
  console.log('WA Web version:', version.join('.'));

  const keys = makeCacheableSignalKeyStore(state.keys, logger);

  const sock = makeWASocket({
    version,
    auth: { creds: state.creds, keys },
    printQRInTerminal: false,
    logger,
    browser: Browsers.macOS('Chrome'),
    getMessage: async () => proto.Message.create({}),
  });

  sock.ev.on('creds.update', saveCreds);

  sock.ev.on('messages.update', (updates) => {
    for (const u of updates) {
      const update = u.update as Record<string, unknown>;
      if (update.status !== undefined || update.messageStubType !== undefined) {
        console.log('\nMessage status update:', JSON.stringify(u.key), JSON.stringify(update));
      }
    }
  });

  await new Promise<void>((resolve, reject) => {
    sock.ev.on('connection.update', (update) => {
      if (update.connection === 'open') resolve();
      if (update.connection === 'close') {
        const reason = (update.lastDisconnect?.error as any)?.output?.statusCode;
        reject(new Error(`Connection closed: ${reason}`));
      }
    });
  });

  console.log('Connected.\n');

  const normalized = jidNormalizedUser(recipientJid);

  // 1. Check if number is on WhatsApp
  console.log(`--- Verify ${normalized} ---`);
  try {
    const [result] = await sock.onWhatsApp(normalized.replace('@s.whatsapp.net', ''));
    if (!result?.exists) {
      console.log('Number is NOT on WhatsApp. Aborting.');
      sock.end(undefined);
      process.exit(1);
    }
    console.log('Number is on WhatsApp: YES');
  } catch (err: any) {
    console.log('onWhatsApp check failed:', err.message);
  }

  // 2. Check existing tctoken
  console.log('\n--- tctoken status ---');
  const existing = await keys.get('tctoken', [normalized]);
  const entry = existing[normalized];
  if (entry?.token?.length) {
    console.log(`Existing tctoken: YES (length: ${entry.token.length}, timestamp: ${entry.timestamp})`);
  } else {
    console.log('Existing tctoken: none');
  }

  // 3. Pre-issue tctoken
  console.log('\n--- Pre-issuing tctoken ---');
  try {
    const timestamp = Math.floor(Date.now() / 1000);
    const result = await (sock as any).issuePrivacyTokens([normalized], timestamp);
    await storeTcTokensFromIqResult({
      result,
      fallbackJid: normalized,
      keys,
      getLIDForPN: async () => null,
    });

    const updated = await keys.get('tctoken', [normalized]);
    const newEntry = updated[normalized];
    if (newEntry?.token?.length) {
      console.log(`Token issued and stored: YES (length: ${newEntry.token.length})`);
    } else {
      console.log('Token issued and stored: NO (server returned empty — account likely timelocked)');
    }
  } catch (err: any) {
    console.log('issuePrivacyTokens failed:', err.message);
  }

  // 4. Send test message
  console.log('\n--- Sending test message ---');
  const text = `[diagnostic] tctoken test ${new Date().toISOString()}`;
  try {
    const sent = await sock.sendMessage(recipientJid, { text });
    console.log(`SUCCESS — msgId: ${sent?.key?.id}, status: ${sent?.status}`);
  } catch (err: any) {
    console.log(`FAILED — ${err.message}`);
  }

  // Wait for delivery receipts / error callbacks
  console.log('\nWaiting 10s for delivery status...');
  await new Promise((r) => setTimeout(r, 10000));

  console.log('Done.');
  sock.end(undefined);
  process.exit(0);
}

main().catch((err) => {
  console.error('Fatal:', err);
  process.exit(1);
});
