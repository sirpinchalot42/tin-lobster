#!/usr/bin/env bash
# Collect non-secret Tin Lobster deployment evidence for review.

set -Eeuo pipefail

BOT_USER="openclaw"
OPENCLAW_PORT="18789"
OUTPUT_DIR="."

usage() {
  cat <<'USAGE'
Usage: scripts/collect-audit-evidence.sh [--bot-user <user>] [--port <port>] [--output-dir <dir>]

Collects read-only deployment evidence for Tin Lobster review.
The report intentionally avoids printing OpenClaw config files, environment
variables, channel credentials, tokens, private keys, and backup contents.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bot-user) BOT_USER="${2:-}"; shift 2 ;;
    --port) OPENCLAW_PORT="${2:-}"; shift 2 ;;
    --output-dir) OUTPUT_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$OUTPUT_DIR"
REPORT="${OUTPUT_DIR%/}/tin-lobster-audit-${timestamp}.txt"

run_section() {
  local title="$1"
  shift
  {
    printf '\n## %s\n\n' "$title"
    printf '$'
    printf ' %q' "$@"
    printf '\n'
    "$@" 2>&1 || printf '[command exited non-zero]\n'
  } >>"$REPORT"
}

append_section() {
  local title="$1"
  {
    printf '\n## %s\n\n' "$title"
    cat
  } >>"$REPORT"
}

as_bot() {
  local home_dir="/home/${BOT_USER}"
  if [[ "$(id -un)" == "$BOT_USER" ]]; then
    env HOME="$home_dir" PATH="${home_dir}/.npm-global/bin:${PATH}" "$@"
  else
    sudo -u "$BOT_USER" env HOME="$home_dir" PATH="${home_dir}/.npm-global/bin:${PATH}" "$@"
  fi
}

{
  echo "# Tin Lobster Audit Evidence"
  echo
  echo "Collected UTC: ${timestamp}"
  echo "Bot user: ${BOT_USER}"
  echo "Gateway port: ${OPENCLAW_PORT}"
  echo
  echo "Do not paste secrets into this file. If any local command prints a secret,"
  echo "redact it before sharing the report."
} >"$REPORT"

run_section "Operating System" cat /etc/os-release
run_section "Kernel" uname -a
run_section "Current User" id
run_section "Tin Lobster Git Revision" git rev-parse --short HEAD
run_section "Tin Lobster Git Status" git status --short --branch
run_section "Node Version" node --version
run_section "npm Version" npm --version
run_section "Bot User" id "$BOT_USER"
run_section "OpenClaw Directory Permissions" stat -c '%U %G %a %n' "/home/${BOT_USER}/.openclaw"
run_section "OpenClaw CLI Path" as_bot bash -c 'command -v openclaw'
run_section "OpenClaw CLI Version" as_bot openclaw --version
run_section "OpenClaw Config Validate" as_bot openclaw config validate
run_section "UFW Status" sudo ufw status verbose
run_section "UFW Numbered Rules" sudo ufw status numbered
run_section "Listening TCP Ports" ss -ltnp
run_section "fail2ban Service" systemctl --no-pager --full status fail2ban
run_section "unattended-upgrades Service" systemctl --no-pager --full status unattended-upgrades
run_section "Docker Service" systemctl --no-pager --full status docker
run_section "SSH Effective Security Settings" sudo sshd -T
run_section "Tin Lobster Validation" scripts/validate-tin-lobster.sh --bot-user "$BOT_USER" --port "$OPENCLAW_PORT"

append_section "Manual Reviewer Notes" <<'NOTES'
- Confirm the host was disposable Ubuntu 24.04 before bootstrap.
- Confirm SSH still works from the intended admin path after UFW and SSH changes.
- Confirm OpenClaw setup wizard was reachable as the bot user.
- Confirm gateway is not exposed publicly unless the operator deliberately changed it later.
- Confirm no tokens, private keys, channel credentials, or backup contents were copied into this report.
NOTES

echo "Audit evidence written to: ${REPORT}"
