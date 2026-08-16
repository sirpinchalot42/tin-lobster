#!/usr/bin/env bash
# Validate a Tin Lobster host without changing it.

set -Eeuo pipefail

BOT_USER="openclaw"
OPENCLAW_PORT="18789"

usage() {
  cat <<'USAGE'
Usage: scripts/validate-tin-lobster.sh [--bot-user <user>] [--port <port>]

Runs read-only checks for a Tin Lobster/OpenClaw host.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bot-user) BOT_USER="${2:-}"; shift 2 ;;
    --port) OPENCLAW_PORT="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

PASS=0
WARN=0
FAIL=0

pass() { printf '[PASS] %s\n' "$*"; PASS=$((PASS + 1)); }
warn() { printf '[WARN] %s\n' "$*"; WARN=$((WARN + 1)); }
fail() { printf '[FAIL] %s\n' "$*"; FAIL=$((FAIL + 1)); }

as_bot() {
  local home_dir="/home/${BOT_USER}"
  if [[ "$(id -un)" == "$BOT_USER" ]]; then
    env HOME="$home_dir" PATH="${home_dir}/.npm-global/bin:${PATH}" "$@"
  else
    sudo -u "$BOT_USER" env HOME="$home_dir" PATH="${home_dir}/.npm-global/bin:${PATH}" "$@"
  fi
}

check_os() {
  if [[ ! -r /etc/os-release ]]; then
    fail "cannot read /etc/os-release"
    return
  fi
  # shellcheck disable=SC1091
  . /etc/os-release
  if [[ "${ID:-}" == "ubuntu" ]]; then
    case "${VERSION_ID:-}" in
      24.04|26.04) pass "Ubuntu ${VERSION_ID} detected" ;;
      *) fail "expected Ubuntu 24.04 or 26.04, found ${PRETTY_NAME:-unknown}" ;;
    esac
  else
    fail "expected Ubuntu, found ${PRETTY_NAME:-unknown}"
  fi
}

check_user() {
  if id "$BOT_USER" >/dev/null 2>&1; then
    pass "bot user exists: ${BOT_USER}"
  else
    fail "bot user missing: ${BOT_USER}"
    return
  fi

  local openclaw_dir="/home/${BOT_USER}/.openclaw"
  if [[ -d "$openclaw_dir" ]]; then
    pass "OpenClaw state directory exists"
    local mode
    mode="$(stat -c '%a' "$openclaw_dir")"
    [[ "$mode" == "700" ]] && pass ".openclaw is mode 700" || warn ".openclaw mode is ${mode}, expected 700"
  else
    fail "missing ${openclaw_dir}"
  fi
}

check_git() {
  if command -v git >/dev/null 2>&1; then
    pass "git available ($(git --version | head -n1))"
  else
    fail "git missing — operators need it to clone profile repos / updates"
  fi
}

check_node_openclaw() {
  if command -v node >/dev/null 2>&1; then
    local major
    major="$(node --version | sed 's/^v//' | cut -d. -f1)"
    [[ "$major" -ge 22 ]] && pass "Node $(node --version) detected" || fail "Node 22+ required, found $(node --version)"
  else
    fail "node command missing"
  fi

  if as_bot bash -c 'command -v openclaw' >/dev/null 2>&1; then
    pass "OpenClaw CLI available for ${BOT_USER}"
    if as_bot openclaw --version >/dev/null 2>&1; then
      pass "OpenClaw CLI executes"
    else
      fail "OpenClaw CLI exists but does not execute"
    fi
    if as_bot openclaw config validate >/dev/null 2>&1; then
      pass "OpenClaw config validates"
    else
      warn "OpenClaw config validate did not pass; first-run setup may still be pending"
    fi
  else
    fail "OpenClaw CLI missing for ${BOT_USER}"
  fi
}

check_firewall() {
  if ! command -v ufw >/dev/null 2>&1; then
    fail "ufw command missing"
    return
  fi

  if ufw status | grep -q '^Status: active'; then
    pass "UFW is active"
  else
    fail "UFW is not active"
  fi

  if ufw status numbered | grep -q "${OPENCLAW_PORT}"; then
    fail "OpenClaw gateway port ${OPENCLAW_PORT} appears in UFW rules"
  else
    pass "OpenClaw gateway port ${OPENCLAW_PORT} is not opened in UFW"
  fi
}

check_services() {
  systemctl is-enabled unattended-upgrades >/dev/null 2>&1 && pass "unattended-upgrades enabled" || warn "unattended-upgrades not enabled"
  systemctl is-active fail2ban >/dev/null 2>&1 && pass "fail2ban active" || warn "fail2ban not active"

  if systemctl list-unit-files 'docker.service' >/dev/null 2>&1 && command -v docker >/dev/null 2>&1; then
    systemctl is-active docker >/dev/null 2>&1 && pass "docker active" || warn "docker installed but not active"
  else
    warn "docker not installed; okay if --no-docker was intended"
  fi
}

check_ssh_security() {
  local pw_auth
  pw_auth="$(sshd -T 2>/dev/null | awk '/^passwordauthentication /{print $2}')" || true
  if [[ "${pw_auth:-}" == "no" ]]; then
    pass "SSH password authentication is disabled"
  elif [[ "${pw_auth:-}" == "yes" ]]; then
    warn "SSH password authentication is enabled — re-run bootstrap with --harden-ssh to disable it"
  else
    warn "Could not determine SSH password auth setting"
  fi
}

check_secrets_layout() {
  local secrets_dir="/home/${BOT_USER}/.openclaw/secrets"
  local cred_dir="/home/${BOT_USER}/.openclaw/credentials"

  if [[ -d "$secrets_dir" ]]; then
    local mode
    mode="$(stat -c '%a' "$secrets_dir" 2>/dev/null || true)"
    [[ "$mode" == "700" ]] && pass "secrets dir exists with mode 700" \
      || warn "secrets dir mode is ${mode:-unknown}, expected 700"
  else
    warn "secrets dir missing; run scripts/init-secrets-layout.sh --bot-user ${BOT_USER}"
  fi

  if [[ -d "$cred_dir" ]]; then
    local cmode
    cmode="$(stat -c '%a' "$cred_dir" 2>/dev/null || true)"
    [[ "$cmode" == "700" ]] && pass "credentials dir mode 700" \
      || warn "credentials dir mode is ${cmode:-unknown}, expected 700"
  else
    warn "credentials dir missing; okay before OpenClaw setup"
  fi

  if [[ -x "/home/${BOT_USER}/tin-lobster/scripts/secrets-check.sh" ]] || [[ -x "./scripts/secrets-check.sh" ]]; then
    pass "secrets-check helper is present"
  else
    warn "secrets-check helper not found in expected locations"
  fi
}

check_listeners() {
  if ! command -v ss >/dev/null 2>&1; then
    warn "ss command unavailable; skipping listener check"
    return
  fi

  local listeners
  listeners="$(ss -ltn 2>/dev/null | awk 'NR > 1 {print $4}' || true)"
  if printf '%s\n' "$listeners" | grep -Eq "0\\.0\\.0\\.0:${OPENCLAW_PORT}|\\[::\\]:${OPENCLAW_PORT}"; then
    fail "gateway port ${OPENCLAW_PORT} is listening on all interfaces"
  elif printf '%s\n' "$listeners" | grep -Eq "127\\.0\\.0\\.1:${OPENCLAW_PORT}|\\[::1\\]:${OPENCLAW_PORT}"; then
    pass "gateway port ${OPENCLAW_PORT} is loopback-only"
  else
    warn "gateway port ${OPENCLAW_PORT} is not listening; okay before gateway install/start"
  fi
}

main() {
  echo "Tin Lobster validation"
  echo "Bot user: ${BOT_USER}"
  echo "Gateway port: ${OPENCLAW_PORT}"
  echo

  check_os
  check_user
  check_git
  check_node_openclaw
  check_firewall
  check_ssh_security
  check_services
  check_secrets_layout
  check_listeners

  echo
  echo "Summary: ${PASS} pass, ${WARN} warn, ${FAIL} fail"
  [[ "$FAIL" -eq 0 ]]
}

main "$@"
