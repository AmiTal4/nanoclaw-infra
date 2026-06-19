/**
 * Check WhatsApp reachout timelock status and test DM sending.
 *
 * Requires Baileys rc13+ (fetchAccountReachoutTimelock is not in rc.9).
 * Stop the NanoClaw service before running — only one connection per auth.
 *
 * Usage (from nanoclaw project root):
 *   node --import tsx/esm /home/ubuntu/scripts/whatsapp-diagnostics/check-timelock.ts [recipient-jid]
 *
 * Default recipient: 972523968011@s.whatsapp.net
 */
import makeWASocket, { useMultiFileAuthState, fetchLatestBaileysVersion } from '@whiskeysockets/baileys';
import pino from 'pino';

const logger = pino({ level: 'silent' });
const recipientJid = process.argv[2] || '972523968011@s.whatsapp.net';

async function main() {
  const { state, saveCreds } = await useMultiFileAuthState('store/auth');
  const { version } = await fetchLatestBaileysVersion();

  const sock = makeWASocket({
    version,
    auth: state,
    logger,
    printQRInTerminal: false,
  });

  sock.ev.on('creds.update', saveCreds);

  sock.ev.on('connection.update', async (update) => {
    if (update.connection === 'open') {
      console.log('Connected to WhatsApp.\n');

      // Check timelock
      console.log('--- Reachout Timelock ---');
      try {
        const result = await (sock as any).fetchAccountReachoutTimelock();
        if (result.isActive) {
          console.log(`ACTIVE — enforcement: ${result.enforcementType}`);
          console.log(`Expires: ${result.timeEnforcementEnds}`);
        } else {
          console.log('No active timelock.');
        }
        console.log('Raw:', JSON.stringify(result, null, 2));
      } catch (e: any) {
        console.log(`Not available: ${e.message}`);
        console.log('(fetchAccountReachoutTimelock requires Baileys rc13+)');
      }

      // Test send
      console.log(`\n--- Test Send to ${recipientJid} ---`);
      try {
        const result = await sock.sendMessage(recipientJid, { text: `[diagnostic] timelock check ${new Date().toISOString()}` });
        console.log(`SUCCESS — status: ${result?.status}, msgId: ${result?.key?.id}`);
      } catch (e: any) {
        console.log(`FAILED — ${e.message}`);
        if (e.output?.statusCode) console.log(`Status code: ${e.output.statusCode}`);
        if (e.data) console.log('Error data:', JSON.stringify(e.data, null, 2));
      }

      setTimeout(() => process.exit(0), 3000);
    }

    if (update.connection === 'close') {
      console.log('Connection closed:', update.lastDisconnect?.error?.message);
      process.exit(1);
    }
  });
}

main().catch((e) => { console.error(e); process.exit(1); });
