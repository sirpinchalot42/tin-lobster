#!/usr/bin/env bash
# Safe restore helper. Defaults to planning/verification only.

set -Eeuo pipefail

BACKUP_FILE=""
APPLY="0"

usage() {
  cat <<'USAGE'
Usage:
  scripts/restore-tin-lobster.sh --backup <file> [--apply]

Default behavior verifies the backup and prints restore guidance only.
Use --apply only after reading the plan and confirming you are on the intended
host/trust boundary.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --backup) BACKUP_FILE="${2:-}"; shift 2 ;;
    --apply) APPLY="1"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$BACKUP_FILE" ]] || { usage; exit 2; }
[[ -f "$BACKUP_FILE" ]] || { echo "Backup file not found: $BACKUP_FILE" >&2; exit 1; }
command -v openclaw >/dev/null 2>&1 || { echo "openclaw command not found" >&2; exit 1; }

echo "Tin Lobster restore plan"
echo "Backup: $BACKUP_FILE"
echo
openclaw backup verify "$BACKUP_FILE"

cat <<'PLAN'

Restore guidance:
- Prefer identity-only restore for migrations when possible.
- Re-link channels/secrets manually on a new trust boundary.
- Do not overwrite an existing working bot without a verified backup.
- Review OpenClaw's backup manifest before applying.
PLAN

if [[ "$APPLY" != "1" ]]; then
  echo
  echo "No restore applied. Re-run with --apply only after review."
  exit 0
fi

echo
echo "OpenClaw restore apply is intentionally not automated in this first Tin Lobster version."
echo "Use OpenClaw's documented restore flow after reviewing the backup manifest."
exit 1

