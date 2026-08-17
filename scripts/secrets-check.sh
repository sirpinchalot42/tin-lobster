#!/usr/bin/env bash
# Read-only secrets hygiene check for a Tin Lobster / OpenClaw host.
# Does not print secret values. Safe to run and share the summary.

set -Eeuo pipefail

BOT_USER="${USER}"
STRICT="0"

usage() {
  cat <<'USAGE'
Usage: scripts/secrets-check.sh [--bot-user <user>] [--strict]

Checks common secret-hygiene problems without printing secret contents.
Exit 0 if no FAIL items. WARN items still exit 0 unless --strict is set.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bot-user) BOT_USER="${2:-}"; shift 2 ;;
    --strict) STRICT="1"; shift ;;
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

if ! id "$BOT_USER" >/dev/null 2>&1; then
  echo "user not found: ${BOT_USER}" >&2
  exit 1
fi

HOME_DIR="$(getent passwd "$BOT_USER" | cut -d: -f6)"
OPENCLAW_DIR="${HOME_DIR}/.openclaw"
SECRETS_DIR="${OPENCLAW_DIR}/secrets"
CRED_DIR="${OPENCLAW_DIR}/credentials"
WORKSPACE_DIR="${OPENCLAW_DIR}/workspace"
REF_DIR="${HOME_DIR}/tin-lobster"

mode_of() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    printf ''
    return 0
  fi
  stat -c '%a' "$path" 2>/dev/null || stat -f '%OLp' "$path" 2>/dev/null
}

check_layout() {
  if [[ -d "$OPENCLAW_DIR" ]]; then
    pass "OpenClaw dir exists: ${OPENCLAW_DIR}"
    local m
    m="$(mode_of "$OPENCLAW_DIR")"
    if [[ "$m" == "700" ]]; then
      pass ".openclaw mode is 700"
    else
      fail ".openclaw mode is ${m:-unknown}, expected 700"
    fi
  else
    fail "missing ${OPENCLAW_DIR}"
    return
  fi

  if [[ -d "$CRED_DIR" ]]; then
    local cm
    cm="$(mode_of "$CRED_DIR")"
    [[ "$cm" == "700" ]] && pass "credentials dir mode 700" || fail "credentials dir mode is ${cm:-unknown}, expected 700"
  else
    warn "credentials dir missing (okay before OpenClaw setup)"
  fi

  if [[ -d "$SECRETS_DIR" ]]; then
    local sm
    sm="$(mode_of "$SECRETS_DIR")"
    [[ "$sm" == "700" ]] && pass "secrets dir mode 700" || fail "secrets dir mode is ${sm:-unknown}, expected 700"
    [[ -f "${SECRETS_DIR}/env.example" ]] && pass "secrets/env.example present" || warn "secrets/env.example missing"
    if [[ -f "${SECRETS_DIR}/env.local" ]]; then
      local em
      em="$(mode_of "${SECRETS_DIR}/env.local")"
      [[ "$em" == "600" || "$em" == "400" ]] && pass "secrets/env.local mode is restrictive (${em})" \
        || fail "secrets/env.local mode is ${em:-unknown}, expected 600"
    else
      pass "no env.local yet (okay if OpenClaw wizard holds all secrets)"
    fi
  else
    warn "secrets dir missing — run scripts/init-secrets-layout.sh --bot-user ${BOT_USER}"
  fi
}

check_world_readable() {
  local bad=0
  if [[ ! -d "$OPENCLAW_DIR" ]]; then
    return
  fi
  # Files under .openclaw should not be group/world readable.
  while IFS= read -r -d '' f; do
    local m
    m="$(mode_of "$f")"
    # Fail if other-readable or other-writable; warn if group-readable.
    if [[ "$m" =~ [2367]$ ]]; then
      fail "world-accessible path: ${f} (mode ${m})"
      bad=1
    elif [[ "$m" =~ [4567][4567][0-9] ]]; then
      # crude group-read check for common modes like 640/660/750
      case "$m" in
        640|660|644|664|755|750)
          warn "group-accessible path: ${f} (mode ${m})"
          ;;
      esac
    fi
  done < <(find "$OPENCLAW_DIR" -type f -print0 2>/dev/null)

  if [[ "$bad" -eq 0 ]]; then
    pass "no world-accessible files found under .openclaw"
  fi
}

check_key_files() {
  local found=0
  local paths=()
  [[ -d "$HOME_DIR" ]] || return
  while IFS= read -r -d '' f; do
    paths+=("$f")
  done < <(find "$HOME_DIR" -type f \( \
      -name 'id_rsa' -o -name 'id_ed25519' -o -name 'id_ecdsa' -o \
      -name '*.pem' -o -name '*.p12' -o -name '*.pfx' \
    \) ! -path '*/.npm-global/*' ! -path '*/node_modules/*' -print0 2>/dev/null)

  if [[ "${#paths[@]}" -eq 0 ]]; then
    pass "no obvious private-key files under bot home"
    return
  fi

  for f in "${paths[@]}"; do
    found=1
    local m
    m="$(mode_of "$f")"
    if [[ "$m" == "600" || "$m" == "400" ]]; then
      warn "private-key-like file present with safe mode: ${f}"
    else
      fail "private-key-like file with unsafe mode ${m:-unknown}: ${f}"
    fi
  done
  if [[ "$found" -eq 1 ]]; then
    warn "private keys under bot home are unusual — prefer admin device key storage"
  fi
}

# High-confidence leak patterns. We report file paths only, never matching text.
scan_tree_for_patterns() {
  local root="$1"
  local label="$2"
  [[ -d "$root" ]] || return 0

  local hits=0
  # Use grep -R without printing the match body: show file:line only via -l then count.
  # Patterns intentionally conservative to limit false positives.
  local pattern='BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY|xox[baprs]-[0-9A-Za-z-]{10,}|ghp_[0-9A-Za-z]{20,}|github_pat_[0-9A-Za-z_]{20,}|sk-[A-Za-z0-9]{20,}|AIza[0-9A-Za-z_-]{20,}|api[_-]?key[[:space:]]*=[[:space:]]*['\''\"]?[A-Za-z0-9_\-]{16,}'

  local files
  files="$(grep -RIlE --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=.npm-global \
    --exclude='*.png' --exclude='*.jpg' --exclude='*.jpeg' --exclude='*.gif' --exclude='*.webp' \
    --exclude='*.woff*' --exclude='*.pdf' \
    "$pattern" "$root" 2>/dev/null || true)"

  if [[ -n "$files" ]]; then
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      # env.example intentionally contains placeholders
      if [[ "$f" == *'/env.example' ]]; then
        continue
      fi
      # documentation talking about secrets is fine if it only has placeholders;
      # still warn so operators double-check.
      if [[ "$f" == *'/docs/'* || "$f" == *'admin-guide.md' || "$f" == *'SECURITY'* ]]; then
        warn "pattern match in docs (verify placeholders only): ${f}"
        continue
      fi
      fail "possible secret material in ${label}: ${f}"
      hits=1
    done <<< "$files"
  fi

  if [[ "$hits" -eq 0 ]]; then
    pass "no high-confidence secret patterns in ${label}"
  fi
}

check_env_files() {
  local root="$1"
  [[ -d "$root" ]] || return 0
  local found=0
  while IFS= read -r -d '' f; do
    found=1
    local base m
    base="$(basename "$f")"
    m="$(mode_of "$f")"
    if [[ "$base" == ".env.example" || "$base" == "env.example" ]]; then
      pass "example env file only: ${f}"
      continue
    fi
    if [[ "$m" == "600" || "$m" == "400" ]]; then
      warn "env file present (mode ${m}): ${f}"
    else
      fail "env file with loose mode ${m:-unknown}: ${f}"
    fi
  done < <(find "$root" -type f \( -name '.env' -o -name '.env.*' -o -name 'env.local' \) \
    ! -path '*/node_modules/*' -print0 2>/dev/null)
  if [[ "$found" -eq 0 ]]; then
    pass "no .env/env.local files under ${root}"
  fi
}

check_git_hygiene() {
  if [[ ! -d "${REF_DIR}/.git" && ! -d "${WORKSPACE_DIR}/.git" ]]; then
    pass "no git repos in common bot paths to audit"
    return
  fi
  for repo in "$REF_DIR" "$WORKSPACE_DIR"; do
    [[ -d "${repo}/.git" ]] || continue
    if git -C "$repo" ls-files 2>/dev/null | grep -E '(^|/)\.env($|\.)|env\.local|id_rsa$|id_ed25519$|\.pem$' >/dev/null; then
      fail "git-tracked secret-like path in ${repo}"
    else
      pass "no obvious secret paths tracked in git: ${repo}"
    fi
  done
}

main() {
  echo "Tin Lobster secrets check"
  echo "Bot user: ${BOT_USER}"
  echo "Home: ${HOME_DIR}"
  echo

  check_layout
  check_world_readable
  check_key_files
  check_env_files "$OPENCLAW_DIR"
  check_env_files "$WORKSPACE_DIR"
  scan_tree_for_patterns "$WORKSPACE_DIR" "workspace"
  scan_tree_for_patterns "$REF_DIR" "tin-lobster reference copy"
  check_git_hygiene

  echo
  echo "Summary: ${PASS} pass, ${WARN} warn, ${FAIL} fail"
  echo "Secrets were not printed. Review FAIL paths carefully before sharing logs."

  if [[ "$FAIL" -gt 0 ]]; then
    exit 1
  fi
  if [[ "$STRICT" == "1" && "$WARN" -gt 0 ]]; then
    exit 1
  fi
  exit 0
}

main "$@"
