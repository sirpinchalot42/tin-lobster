#!/usr/bin/env bash
# Print the day-one OpenClaw handoff checklist.

set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/first-run-checklist.sh [bot-user] [port]

Prints the day-one OpenClaw handoff checklist.
If bot-user is omitted, uses $USER (or "lobster" when root).
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -ge 1 && "$1" != "" ]]; then
  BOT_USER="$1"
else
  if [[ "$(id -un)" == "root" ]]; then
    BOT_USER="lobster"
  else
    BOT_USER="$(id -un)"
  fi
fi

PORT="${2:-18789}"

cat <<CHECKLIST
Tin Lobster first-run checklist

Bot user: ${BOT_USER}
Gateway:  ${PORT}

1. Become the OpenClaw bot user:
   sudo -iu ${BOT_USER}

2. Run OpenClaw onboarding (enter secrets only here):
   openclaw onboard --install-daemon

3. During onboarding, prefer safe defaults:
   - gateway mode: local / loopback
   - DM access: pairing (or a strict allowlist), not open
   - groups: require mention / allowlists
   - one trusted operator per gateway (not a shared multi-tenant bot)

4. Confirm the gateway service:
   openclaw gateway status
   openclaw status
   # If daemon was skipped during onboarding:
   # openclaw gateway install --port ${PORT}
   # openclaw gateway start

5. Run OpenClaw doctor + security audit:
   openclaw doctor
   openclaw security audit
   # Before Tailscale Serve, LAN bind, reverse proxy, or multi-person DMs:
   openclaw security audit --deep
   # After major OpenClaw upgrades, review repairs intentionally:
   # openclaw doctor --fix

6. Check memory search health (embeddings are separate from chat models):
   openclaw memory status
   # If vector search is paused or local embeddings unavailable, see:
   # docs/user-manual.md#memory-search-embeddings
   # https://docs.openclaw.ai/concepts/memory-search

7. Validate the host:
   ~/tin-lobster/scripts/validate-tin-lobster.sh --bot-user ${BOT_USER} --port ${PORT}

8. Check secrets hygiene (paths only; no secret values printed):
   ~/tin-lobster/scripts/secrets-check.sh --bot-user ${BOT_USER}

9. Create and verify first backup (treat archive as sensitive):
   mkdir -p ~/Backups/openclaw
   openclaw backup create --output ~/Backups/openclaw --verify
   # Older OpenClaw builds may only support:
   # openclaw backup create
   # openclaw backup verify <backup-file>

10. Send a small test message (Control UI or your channel):
    openclaw dashboard

11. Optional operator extras:
    ~/tin-lobster/scripts/init-secrets-layout.sh --bot-user ${BOT_USER}
    # then copy env.example -> env.local only if needed

12. After SSH key login works from your admin device:
    re-run bootstrap with --harden-ssh
    add Tailscale if you need remote access
    re-run: openclaw security audit --deep

Definition of done:
  doctor clean enough to run, security audit understood,
  memory status understood (embeddings optional but checked),
  validate green, secrets-check green, one real message, verified backup.

Official OpenClaw references:
  https://docs.openclaw.ai/start/getting-started
  https://docs.openclaw.ai/gateway/security
  https://docs.openclaw.ai/gateway/security/exposure-runbook
  https://docs.openclaw.ai/concepts/memory-search
CHECKLIST
