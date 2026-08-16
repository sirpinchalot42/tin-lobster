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

3. Choose model/auth (cloud or local like Ollama), channels, and gateway options.
   Do not paste tokens into chat, screenshots, or git.

4. Confirm the gateway service:
   openclaw gateway status
   openclaw status
   # If daemon was skipped during onboarding:
   # openclaw gateway install --port ${PORT}
   # openclaw gateway start

5. Validate the host:
   ~/tin-lobster/scripts/validate-tin-lobster.sh --bot-user ${BOT_USER} --port ${PORT}

6. Check secrets hygiene (paths only; no secret values printed):
   ~/tin-lobster/scripts/secrets-check.sh --bot-user ${BOT_USER}

7. Create and verify first backup (treat archive as sensitive):
   openclaw backup create
   openclaw backup verify <backup-file>

8. Send a small test message through the chosen channel.

9. Optional operator extras:
   ~/tin-lobster/scripts/init-secrets-layout.sh --bot-user ${BOT_USER}
   # then copy env.example -> env.local only if needed

10. After SSH key login works from your admin device:
    re-run bootstrap with --harden-ssh
    add Tailscale if you need remote access

Definition of done:
  validate green, secrets-check green, one real message, verified backup.
CHECKLIST
