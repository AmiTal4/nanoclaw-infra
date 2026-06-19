# Scripts

Reusable diagnostic scripts and issue documentation created during NanoClaw troubleshooting sessions.

## Structure

Each subdirectory covers a specific problem domain:

| Directory | Purpose |
|-----------|---------|
| `whatsapp-diagnostics/` | WhatsApp Baileys connection issues — timelock checks, token debugging |

## Usage

Scripts are written in TypeScript and run via `pnpm exec tsx` from the NanoClaw project root (`/home/ubuntu/nanoclaw-v2`):

```bash
cd /home/ubuntu/nanoclaw-v2
pnpm exec tsx /home/ubuntu/scripts/whatsapp-diagnostics/check-timelock.ts
```

Each subdirectory has a `README.md` documenting the issue, root cause, and fix for future reference.
