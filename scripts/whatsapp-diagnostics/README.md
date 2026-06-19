# WhatsApp DM Sending Failure (428/463 — Reachout Timelock)

## Symptom

Messages from NanoClaw's WhatsApp adapter (Baileys) appear as "delivered" in the host logs (`Message delivered` with a valid `platformMsgId`), but the recipient never receives them. WhatsApp silently drops the messages. No error is visible in NanoClaw logs — you only see the failure by directly testing with Baileys, which returns status code **428** (Precondition Required) or **463**.

## Root Cause

Two compounding issues:

### 1. Missing tctoken/cstoken in outgoing messages (Baileys rc.9)

WhatsApp requires privacy tokens (`tctoken` and `cstoken`) in outgoing 1:1 messages. These tokens prove the sender is a legitimate WhatsApp client. **Baileys 7.0.0-rc.9 does not include these tokens** — it receives and stores them but never attaches them to outgoing messages.

Other linked devices (WhatsApp Web, WhatsApp Desktop) handle these tokens correctly, which is why they can send DMs while Baileys rc.9 cannot.

### 2. Reachout Timelock (`RESTRICT_ALL_COMPANIONS`)

When WhatsApp detects messages without valid privacy tokens, it treats them as spam-like "reachout" attempts and imposes a server-side rate limit called a **reachout timelock**. The enforcement type `RESTRICT_ALL_COMPANIONS` blocks all linked/companion devices from sending DMs. Each failed retry extends the lock duration.

The timelock is a red herring in isolation — it's a *consequence* of sending without tokens, not the root cause. Fix the token handling and the timelock becomes irrelevant (it eventually expires, and new sends with proper tokens won't trigger it again).

## Fix

Upgrade `@whiskeysockets/baileys` from `7.0.0-rc.9` to `7.0.0-rc13` (or rc10+). These versions include:

- **PR #2339** (merged April 24, 2026): Full tctoken lifecycle — issuance, expiration, re-issuance, pruning, and attachment to outgoing 1:1 messages.
- **PR #2438** (merged May 29, 2026): cstoken (NCT) fallback — self-computed token when no tctoken exists.
- Built-in 463 error handlers and reachout timelock detection (`fetchAccountReachoutTimelock()`).

### ESM compatibility issue with rc10+

Baileys rc10+ depends on `whatsapp-rust-bridge`, which is an ESM-only package (`"type": "module"` with only an `"import"` export condition). NanoClaw's host runs via `tsx` which uses a CJS resolver that can't resolve ESM-only exports.

**Fix**: Patch `whatsapp-rust-bridge`'s `package.json` in `node_modules` to add a `"default"` export:

```json
"exports": {
  ".": {
    "import": "./dist/index.js",
    "default": "./dist/index.js",
    "types": "./dist/index.d.ts"
  }
}
```

The file is at:
```
node_modules/.pnpm/@whiskeysockets+baileys@7.0.0-rc13_sharp@0.35.1/node_modules/whatsapp-rust-bridge/package.json
```

**Important**: This patch is lost on `pnpm install`. Use the pnpm `patchedDependencies` feature or a postinstall script to persist it. Or add a `pnpm.overrides` entry if a fixed version of `whatsapp-rust-bridge` is published.

### Steps

```bash
cd /home/ubuntu/nanoclaw-v2

# 1. Upgrade Baileys
pnpm install @whiskeysockets/baileys@7.0.0-rc13

# 2. Rebuild and restart
pnpm run build
rm -f data/circuit-breaker.json
systemctl --user restart nanoclaw-v2-2a38bd3e   # or your service unit name
```

The ESM patch is persisted via pnpm's `patchedDependencies` feature — no manual patching needed after `pnpm install`. The patch file lives at `patches/whatsapp-rust-bridge@0.5.4.patch` and is referenced in `pnpm-workspace.yaml`:

```yaml
patchedDependencies:
  whatsapp-rust-bridge@0.5.4: patches/whatsapp-rust-bridge@0.5.4.patch
```

If `whatsapp-rust-bridge` publishes a new version (e.g. 0.5.5) that adds a `"default"` export, the patch can be removed. If they bump to a new version without fixing it, regenerate the patch:

```bash
pnpm patch whatsapp-rust-bridge@<new-version>
# edit package.json to add "default": "./dist/index.js" to exports
pnpm patch-commit '<path-printed-above>'
```

## Diagnostic Scripts

### check-timelock.ts

Connects to WhatsApp using stored auth, checks the reachout timelock status, and attempts a test send. **Requires rc13** for `fetchAccountReachoutTimelock()`.

Must stop the NanoClaw service first (only one Baileys connection per auth session):

```bash
systemctl --user stop nanoclaw-v2-2a38bd3e
cd /home/ubuntu/nanoclaw-v2
node --import tsx/esm /home/ubuntu/scripts/whatsapp-diagnostics/check-timelock.ts
systemctl --user start nanoclaw-v2-2a38bd3e
```

Output examples:

```
# Active timelock:
Timelock result: { "isActive": true, "timeEnforcementEnds": "2026-06-26T00:05:57.000Z", "enforcementType": "RESTRICT_ALL_COMPANIONS" }

# No timelock:
Timelock result: { "isActive": false }

# Successful send:
Send succeeded! status: 1
```

## References

- [Baileys #2441 — 463 error investigation](https://github.com/WhiskeySockets/Baileys/issues/2441)
- [Baileys PR #2339 — tctoken lifecycle](https://github.com/WhiskeySockets/Baileys/pull/2339)
- [Baileys PR #2438 — cstoken (NCT) support](https://github.com/WhiskeySockets/Baileys/pull/2438)
- [WAHA #1992 — tctoken not included in outgoing messages](https://github.com/devlikeapro/waha/issues/1992)
