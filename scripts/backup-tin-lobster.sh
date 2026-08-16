#!/usr/bin/env bash
# Create and verify an OpenClaw backup as the current user.

set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/backup-tin-lobster.sh

Run this as the OpenClaw bot user after first-run setup.
It wraps OpenClaw's native backup command and reminds users that backups are
sensitive.
USAGE
}

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { usage; exit 0; }

command -v openclaw >/dev/null 2>&1 || {
  echo "openclaw command not found. Run as the OpenClaw bot user." >&2
  exit 1
}

echo "Tin Lobster Lifeboat backup"
echo "Backups may contain sensitive config, credentials, sessions, and personal data."
echo

cd "/home/${USER}"
openclaw backup create

cat <<'NEXT'

Next:
1. Find the backup path printed above.
2. Verify it:
   openclaw backup verify <backup-file>
3. Store it somewhere safe.
4. Do not paste backup contents into chat or public tickets.
NEXT

