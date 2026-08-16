#!/usr/bin/env bash
# Create / repair the Tin Lobster operator secrets layout for a bot user.
# Does not write real secrets. Safe to re-run.

set -Eeuo pipefail

BOT_USER="${USER}"
FORCE="0"

usage() {
  cat <<'USAGE'
Usage: scripts/init-secrets-layout.sh [--bot-user <user>] [--force]

Creates ~/.openclaw/secrets with safe permissions and starter files.
Does not create or overwrite env.local unless --force is set for templates only.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bot-user) BOT_USER="${2:-}"; shift 2 ;;
    --force) FORCE="1"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$BOT_USER" ]]; then
  echo "bot user required" >&2
  exit 2
fi

if ! id "$BOT_USER" >/dev/null 2>&1; then
  echo "user not found: ${BOT_USER}" >&2
  exit 1
fi

HOME_DIR="$(getent passwd "$BOT_USER" | cut -d: -f6)"
OPENCLAW_DIR="${HOME_DIR}/.openclaw"
SECRETS_DIR="${OPENCLAW_DIR}/secrets"
CRED_DIR="${OPENCLAW_DIR}/credentials"

run_as_bot() {
  if [[ "$(id -un)" == "$BOT_USER" ]]; then
    "$@"
  else
    sudo -u "$BOT_USER" "$@"
  fi
}

install_as_bot() {
  local mode="$1"
  local path="$2"
  if [[ "$(id -un)" == "$BOT_USER" ]]; then
    install -d -m "$mode" "$path"
  else
    sudo install -d -m "$mode" -o "$BOT_USER" -g "$BOT_USER" "$path"
  fi
}

write_as_bot() {
  local mode="$1"
  local path="$2"
  local content="$3"
  if [[ "$(id -un)" == "$BOT_USER" ]]; then
    printf '%s' "$content" > "$path"
    chmod "$mode" "$path"
  else
    printf '%s' "$content" | sudo -u "$BOT_USER" tee "$path" >/dev/null
    sudo chmod "$mode" "$path"
    sudo chown "$BOT_USER:$BOT_USER" "$path"
  fi
}

install_as_bot 700 "$OPENCLAW_DIR"
install_as_bot 700 "$CRED_DIR"
install_as_bot 700 "$SECRETS_DIR"

README_CONTENT='Tin Lobster secrets area

Put operator-managed secret files here (mode 600).
OpenClaw channel/provider credentials usually live under:
  ~/.openclaw/credentials/  and OpenClaw config

Do:
  cp env.example env.local
  chmod 600 env.local

Do not:
  commit this directory
  paste secrets into chat or screenshots
  chmod secrets into the public tin-lobster repo

Check for leaks:
  ~/tin-lobster/scripts/secrets-check.sh
'

ENV_EXAMPLE='# Copy to env.local and fill real values.
# chmod 600 env.local
#
# These are OPERATOR extras. Prefer OpenClaw wizard for channel/provider setup.
#
# Example placeholders only — replace before use:
# OPENAI_API_KEY=replace-me
# ANTHROPIC_API_KEY=replace-me
# CUSTOM_TOOL_TOKEN=replace-me
'

GITIGNORE_CONTENT='*
!.gitignore
!env.example
!README
'

if [[ ! -f "${SECRETS_DIR}/README" || "$FORCE" == "1" ]]; then
  write_as_bot 644 "${SECRETS_DIR}/README" "$README_CONTENT"
fi
if [[ ! -f "${SECRETS_DIR}/env.example" || "$FORCE" == "1" ]]; then
  write_as_bot 644 "${SECRETS_DIR}/env.example" "$ENV_EXAMPLE"
fi
if [[ ! -f "${SECRETS_DIR}/.gitignore" || "$FORCE" == "1" ]]; then
  write_as_bot 644 "${SECRETS_DIR}/.gitignore" "$GITIGNORE_CONTENT"
fi

# Never overwrite env.local
if [[ -f "${SECRETS_DIR}/env.local" ]]; then
  if [[ "$(id -un)" == "$BOT_USER" ]]; then
    chmod 600 "${SECRETS_DIR}/env.local" || true
  else
    sudo chmod 600 "${SECRETS_DIR}/env.local" || true
    sudo chown "$BOT_USER:$BOT_USER" "${SECRETS_DIR}/env.local" || true
  fi
fi

echo "Secrets layout ready: ${SECRETS_DIR}"
echo "Next: copy env.example -> env.local only if you need operator extras."
echo "Then run: scripts/secrets-check.sh --bot-user ${BOT_USER}"
