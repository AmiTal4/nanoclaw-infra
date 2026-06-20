# whatsapp-diagnostics

Scripts for diagnosing WhatsApp Baileys connection and messaging issues.

## Before running

`check-timelock.ts` requires a recipient JID to send a test message. **You must supply your own test number as the first argument** — there is no hardcoded default:

```bash
cd /home/ubuntu/nanoclaw-v2
pnpm exec tsx /home/ubuntu/scripts/whatsapp-diagnostics/check-timelock.ts <your-number>@s.whatsapp.net
```

Replace `<your-number>` with the phone number (including country code, no `+`) you want to use for the diagnostic send.

## Notes

- Stop the NanoClaw service before running — only one Baileys connection per auth is allowed.
- Requires Baileys rc13+ for `fetchAccountReachoutTimelock`; rc.9 does not have it.
