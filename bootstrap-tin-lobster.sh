#!/usr/bin/env bash
# bootstrap-tin-lobster.sh
# Build a secure, zero-trust Ubuntu 24.04/26.04 infrastructure shell for OpenClaw.
#
# This script prepares the machine underneath OpenClaw. It intentionally does
# not choose a model provider, configure channels, create an agent identity, or
# restore secrets. Those belong in the OpenClaw first-run setup.
#
# User model:
#   Admin user  — your personal Ubuntu account (created during OS install),
#                 has sudo, SSH access. Manage the host as this user.
#   Bot user    — isolated service account created by this script, owns
#                 OpenClaw state, no sudo, no SSH, no docker group.
#                 Reach it via: sudo -iu <bot>
#   Docker      — bot uses rootless Docker (own user-space daemon, no root
#                 involvement). System Docker available to admin via sudo.

set -Eeuo pipefail

BOT_USER="lobster"
BOT_USER_GIVEN=""
ADMIN_USER=""
ACCESS_PROFILE="local-lan"
PROFILE_GIVEN=""
SSH_CIDR=""
OPENCLAW_PORT="18789"
RUN_UPGRADE="0"
INSTALL_DOCKER="1"
INSTALL_TAILSCALE="0"
ADD_TAILSCALE="0"
HARDEN_SSH="0"
FORCE_FRESH_HOST="0"
UNINSTALL="0"
IS_RERUN="0"
DRY_RUN="0"
ASSUME_YES="0"

# Suppress all apt/dpkg interactive prompts globally
export DEBIAN_FRONTEND=noninteractive

usage() {
  cat <<'USAGE'
Tin Lobster bootstrap

Beginner path (recommended):
  sudo bash bootstrap-tin-lobster.sh

That starts a short setup wizard. Press Enter to accept the defaults.
Most home users can accept every default.

Advanced / scripted path:
  sudo bash bootstrap-tin-lobster.sh --bot-user <user> --access-profile <profile> [options]

Profiles:
  local-lan   Home/office network. SSH limited to your LAN (auto-detected in wizard).
  tailnet     Tailscale network. Allows SSH from 100.64.0.0/10.
  cloud       Cloud VM. Requires a narrow --ssh-cidr and/or Tailscale.

Options:
  --bot-user <user>        Linux user that will own OpenClaw state. Default: lobster
  --admin-user <user>      Your admin SSH account (restricts SSH via AllowUsers).
                           Defaults to $SUDO_USER if detected.
  --access-profile <name>  local-lan, tailnet, or cloud
  --ssh-cidr <cidr>        Network allowed to SSH, e.g. 192.168.1.0/24
                           (wizard auto-detects this for home networks)
  --port <port>            Intended OpenClaw gateway port. Default: 18789
  --run-upgrade            Run apt-get upgrade during bootstrap
  --no-docker              Skip Docker installation entirely
  --install-tailscale      Install Tailscale using the official installer
  --add-tailscale          Add Tailscale to an existing Tin Lobster host (non-destructive)
  --harden-ssh             Disable password SSH after firewall/user setup
  --force-fresh-host       Reset UFW and reapply all config from scratch (lab/reinstall)
  --uninstall              Remove all Tin Lobster config files and the bot user account
  --dry-run                Print actions without changing the host
  --yes                    Accept the preflight confirmation prompt
  -h, --help               Show this help

Docker note:
  When Docker is installed, the bot user is configured with rootless Docker
  automatically. The bot never joins the docker group. Rootless Docker runs
  a personal daemon in the bot user's session — no root involved.
  Admin users can run: sudo docker ...

Re-run behaviour:
  The script is safe to re-run on an already-bootstrapped host. It will add
  missing config and update packages without resetting UFW or destroying state.
  Use --force-fresh-host when you want a clean reinstall (resets UFW).
  Use --uninstall to reverse the bootstrap entirely.

Examples:
  sudo bash bootstrap-tin-lobster.sh
  sudo bash bootstrap-tin-lobster.sh --bot-user lobster --access-profile local-lan --ssh-cidr 192.168.1.0/24
  sudo bash bootstrap-tin-lobster.sh --bot-user lobster --access-profile tailnet --install-tailscale
  sudo bash bootstrap-tin-lobster.sh --add-tailscale
  sudo bash bootstrap-tin-lobster.sh --bot-user lobster --uninstall

After bootstrap:
  sudo -iu <bot-user>
  openclaw onboard --install-daemon
  openclaw gateway status
  openclaw status
USAGE
}

log()  { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }
warn() { printf '[%s] WARN: %s\n' "$(date '+%H:%M:%S')" "$*" >&2; }
die()  { printf '[%s] ERROR: %s\n' "$(date '+%H:%M:%S')" "$*" >&2; exit 1; }

on_error() {
  local exit_code=$?
  die "line ${BASH_LINENO[0]} failed with exit ${exit_code}: ${BASH_COMMAND}"
}
trap on_error ERR

run() {
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '[dry-run] %q' "$1"
    shift || true
    for arg in "$@"; do printf ' %q' "$arg"; done
    printf '\n'
  else
    "$@"
  fi
}

write_file() {
  local path="$1"
  local mode="$2"
  local owner="$3"
  local group="$4"
  local tmp
  tmp="$(mktemp)"
  cat > "$tmp"
  if [[ "$DRY_RUN" == "1" ]]; then
    log "Would write ${path}"
    rm -f "$tmp"
    return 0
  fi
  install -o "$owner" -g "$group" -m "$mode" "$tmp" "$path"
  rm -f "$tmp"
}

valid_username() {
  [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]
}

detect_lan_cidr() {
  local ip=""
  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    ip="${SSH_CONNECTION%% *}"
  elif [[ -n "${SSH_CLIENT:-}" ]]; then
    ip="${SSH_CLIENT%% *}"
  fi
  if [[ -z "$ip" || "$ip" == "127."* ]]; then
    ip="$(ip -4 route get 8.8.8.8 2>/dev/null \
      | awk 'NR==1{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')" || true
  fi
  [[ -z "$ip" ]] && return 0
  printf '%s.0/24\n' "$(printf '%s' "$ip" | cut -d. -f1-3)"
}

prompt_missing() {
  [[ -t 0 ]] || return 0

  # Full advanced flags provided — skip the wizard entirely.
  if [[ -n "$BOT_USER_GIVEN" && -n "$PROFILE_GIVEN" && -n "$SSH_CIDR" ]]; then
    return 0
  fi
  # Profile was given and does not need a LAN CIDR prompt.
  if [[ -n "$BOT_USER_GIVEN" && -n "$PROFILE_GIVEN" && "$ACCESS_PROFILE" == "tailnet" ]]; then
    return 0
  fi
  # Profile given as cloud/tailnet with enough SSH path already set.
  if [[ -n "$BOT_USER_GIVEN" && -n "$PROFILE_GIVEN" && ( -n "$SSH_CIDR" || "$INSTALL_TAILSCALE" == "1" ) ]]; then
    return 0
  fi

  printf '\n'
  printf -- '==================================================\n'
  printf '  Tin Lobster setup wizard\n'
  printf '  Secure Ubuntu shell for OpenClaw\n'
  printf -- '==================================================\n'
  printf '\nYou do not need networking expertise.\n'
  printf 'Press Enter to accept the recommended defaults.\n'
  printf 'Advanced users can pass flags instead of using this wizard.\n\n'

  if [[ -z "$BOT_USER_GIVEN" ]]; then
    while true; do
      printf '1) Bot account name (the Linux user that will own OpenClaw) [lobster]: '
      local answer=""
      read -r answer || true
      BOT_USER="${answer:-lobster}"
      if valid_username "$BOT_USER"; then
        BOT_USER_GIVEN=1
        break
      fi
      printf 'Invalid username "%s" — use lowercase letters/numbers/hyphens/underscores\n' "$BOT_USER"
      printf 'starting with a letter (example: lobster)\n'
    done
  fi

  if [[ -z "$ADMIN_USER" ]]; then
    local detected_admin="${SUDO_USER:-}"
    while true; do
      if [[ -n "$detected_admin" ]]; then
        printf '2) Your admin login (who may SSH into this machine) [%s]: ' "$detected_admin"
      else
        printf '2) Your admin login (your normal Ubuntu username): '
      fi
      local answer=""
      read -r answer || true
      ADMIN_USER="${answer:-$detected_admin}"
      # Admin user is optional — allow blank (skip AllowUsers)
      if [[ -z "$ADMIN_USER" ]] || valid_username "$ADMIN_USER"; then
        break
      fi
      printf 'Invalid username "%s" — use lowercase letters/numbers/hyphens/underscores\n' "$ADMIN_USER"
      printf 'starting with a letter (example: alex)\n'
    done
  fi

  if [[ -z "$PROFILE_GIVEN" ]]; then
    printf '\n3) Where is this machine?\n'
    printf '   1) Home or office Wi-Fi / LAN   <- most people, recommended\n'
    printf '   2) Tailscale only\n'
    printf '   3) Cloud VM (DigitalOcean, AWS, etc.)\n'
    printf 'Choice [1]: '
    local answer=""
    read -r answer || true
    case "${answer:-1}" in
      1|""|local-lan) ACCESS_PROFILE="local-lan" ;;
      2|tailnet)      ACCESS_PROFILE="tailnet" ;;
      3|cloud)        ACCESS_PROFILE="cloud" ;;
      *)              ACCESS_PROFILE="local-lan" ;;
    esac
    PROFILE_GIVEN=1
  fi

  if [[ "$ACCESS_PROFILE" == "local-lan" || "$ACCESS_PROFILE" == "cloud" ]] \
      && [[ "$INSTALL_TAILSCALE" != "1" ]]; then
    printf '\n4) Also install Tailscale for easy secure remote access later? [y/N]: '
    local ts_answer=""
    read -r ts_answer || true
    [[ "${ts_answer,,}" == "y" ]] && INSTALL_TAILSCALE="1"
  fi

  if [[ "$ACCESS_PROFILE" == "local-lan" || "$ACCESS_PROFILE" == "cloud" ]] \
      && [[ -z "$SSH_CIDR" ]]; then
    local detected
    detected="$(detect_lan_cidr)"

    # Show the VM's own IP addresses so the user can orient themselves
    local my_ips
    my_ips="$(ip -4 addr show scope global | awk '/inet /{print $2}' | head -3)"

    printf '\n5) Who is allowed to log in over the network (SSH)?\n'
    printf '   This is usually "everyone on my home network."\n'
    printf '   You do not need to understand CIDR notation.\n'

    if [[ -n "$my_ips" ]]; then
      printf '\n   Current address(es) on this machine:\n'
      while IFS= read -r addr; do
        printf '     %s\n' "$addr"
      done <<< "$my_ips"
    fi

    printf '\n'
    if [[ -n "$detected" ]]; then
      printf '   Detected home/office network: %s\n' "$detected"
      printf '   Recommended: press Enter to allow that whole network.\n'
      printf '   Only type a custom value if you know you need one.\n'
      printf 'Network to allow [Press Enter = %s]: ' "$detected"
      local answer=""
      read -r answer || true
      SSH_CIDR="${answer:-$detected}"
    else
      printf '   Could not auto-detect your network.\n'
      if [[ "$ACCESS_PROFILE" == "cloud" ]]; then
        printf '   For cloud VMs, use your home public IP like 203.0.113.10/32\n'
        printf '   or install Tailscale and use that instead.\n'
      else
        printf '   Typical home network looks like 192.168.1.0/24\n'
      fi
      printf 'Network to allow (example 192.168.1.0/24): '
      local answer=""
      read -r answer || true
      SSH_CIDR="$answer"
    fi
  fi

  if [[ "$ACCESS_PROFILE" == "local-lan" && -z "$SSH_CIDR" ]]; then
    die "No network was chosen for SSH. Re-run and press Enter to accept the detected default, or pass --ssh-cidr."
  fi

  printf '\nWizard complete. Next you will see a summary and confirm with: TIN LOBSTER\n\n'
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --bot-user)          BOT_USER="${2:-}"; BOT_USER_GIVEN=1; shift 2 ;;
      --admin-user)        ADMIN_USER="${2:-}"; shift 2 ;;
      --access-profile)    ACCESS_PROFILE="${2:-}"; PROFILE_GIVEN=1; shift 2 ;;
      --ssh-cidr)          SSH_CIDR="${2:-}"; shift 2 ;;
      --port)              OPENCLAW_PORT="${2:-}"; shift 2 ;;
      --run-upgrade)       RUN_UPGRADE="1"; shift ;;
      --no-docker)         INSTALL_DOCKER="0"; shift ;;
      --install-tailscale) INSTALL_TAILSCALE="1"; shift ;;
      --add-tailscale)     ADD_TAILSCALE="1"; INSTALL_TAILSCALE="1"; shift ;;
      --harden-ssh)        HARDEN_SSH="1"; shift ;;
      --force-fresh-host)  FORCE_FRESH_HOST="1"; shift ;;
      --uninstall)         UNINSTALL="1"; shift ;;
      --dry-run)           DRY_RUN="1"; shift ;;
      --yes)               ASSUME_YES="1"; shift ;;
      -h|--help)           usage; exit 0 ;;
      *) die "Unknown argument: $1" ;;
    esac
  done
}

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "Run as root: sudo bash bootstrap-tin-lobster.sh ..."
}

require_ubuntu() {
  [[ -r /etc/os-release ]] || die "Cannot read /etc/os-release"
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == "ubuntu" ]] || die "Tin Lobster requires Ubuntu 24.04 or 26.04 LTS; found ${PRETTY_NAME:-unknown}"
  case "${VERSION_ID:-}" in
    24.04|26.04) ;;
    *) die "Tin Lobster requires Ubuntu 24.04 or 26.04 LTS; found ${VERSION_ID:-unknown}" ;;
  esac
  log "Ubuntu ${VERSION_ID} detected — OK"
}

require_environment() {
  if [[ "$DRY_RUN" == "1" ]]; then
    log "Dry-run mode — skipping environment pre-checks"
    return 0
  fi

  # ── Network connectivity ─────────────────────────────────────────────────
  # curl is not installed yet on Ubuntu minimal; try curl first, fall back to wget.
  local net_ok="0"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --connect-timeout 5 -o /dev/null https://deb.nodesource.com 2>/dev/null \
      && net_ok="1"
  elif command -v wget >/dev/null 2>&1; then
    wget -q --spider --timeout=5 https://deb.nodesource.com 2>/dev/null \
      && net_ok="1"
  fi

  if [[ "$net_ok" != "1" ]]; then
    die "No internet access — cannot reach deb.nodesource.com.

This usually means your VM's network adapter is set to NAT mode, which lets
the VM use your computer's internet but blocks outbound package downloads
from certain hosts.

Fix: In your hypervisor settings, change the network adapter from NAT to
Bridged mode. This gives the VM a real IP on your local network.

  VirtualBox: Machine Settings → Network → Adapter 1 → Attached to: Bridged Adapter
  VMware:     Virtual Machine Settings → Network Adapter → Bridged
  Proxmox:    Hardware → Network Device → Bridge

After switching, reboot the VM and run this script again."
  fi
  log "Internet connectivity — OK"

  # ── Disk space ───────────────────────────────────────────────────────────
  local avail_gb
  avail_gb="$(df -BG / | awk 'NR==2 {gsub(/G/,"",$4); print $4}')"
  if [[ -z "$avail_gb" || "$avail_gb" -lt 3 ]]; then
    die "Not enough disk space on /.

  Found:  ${avail_gb:-unknown}GB available
  Needed: at least 3GB free

Free up space or resize the disk before running Tin Lobster."
  fi
  log "Disk space: ${avail_gb}GB free on / — OK"

  # ── RAM ──────────────────────────────────────────────────────────────────
  local total_mb
  total_mb="$(free -m | awk '/^Mem:/{print $2}')"
  if [[ -n "$total_mb" && "$total_mb" -lt 900 ]]; then
    warn "Low memory detected: ${total_mb}MB total RAM.

OpenClaw may run slowly or fail to start on less than 1GB of RAM.
For a comfortable experience, allocate at least 1GB (1024MB) to this VM."
  else
    log "RAM: ${total_mb}MB — OK"
  fi
}

validate_options() {
  valid_username "$BOT_USER" || die "Invalid --bot-user '${BOT_USER}'"
  [[ "$OPENCLAW_PORT" =~ ^[0-9]+$ ]] || die "Invalid --port '${OPENCLAW_PORT}'"

  if [[ -n "$ADMIN_USER" ]]; then
    valid_username "$ADMIN_USER" || die "Invalid --admin-user '${ADMIN_USER}'"
    [[ "$ADMIN_USER" == "$BOT_USER" ]] && die "--admin-user and --bot-user must be different accounts"
  fi

  case "$ACCESS_PROFILE" in
    local-lan)
      [[ -n "$SSH_CIDR" ]] || die "local-lan requires --ssh-cidr"
      ;;
    tailnet)
      SSH_CIDR="${SSH_CIDR:-100.64.0.0/10}"
      ;;
    cloud)
      if [[ -z "$SSH_CIDR" && "$INSTALL_TAILSCALE" != "1" ]]; then
        die "cloud profile requires --ssh-cidr or --install-tailscale"
      fi
      if [[ -z "$SSH_CIDR" && "$INSTALL_TAILSCALE" == "1" ]]; then
        SSH_CIDR="100.64.0.0/10"
      fi
      ;;
    *)
      die "Unknown access profile: ${ACCESS_PROFILE}"
      ;;
  esac
}

fresh_host_guard() {
  local home_dir="/home/${BOT_USER}"

  # Detect if this is a re-run rather than a fresh install
  if [[ -e "${home_dir}/.openclaw" ]]; then
    if [[ "$FORCE_FRESH_HOST" == "1" ]]; then
      log "Existing OpenClaw install found — --force-fresh-host set, will reset UFW and reapply all config"
    else
      log "Existing OpenClaw install found in ${home_dir}/.openclaw — re-run mode (UFW preserved)"
      IS_RERUN="1"
    fi
  fi
}

print_preflight() {
  local home_dir="/home/${BOT_USER}"
  local current_user="${SUDO_USER:-${USER:-unknown}}"
  local ssh_source="not detected"
  local ufw_state="not installed"
  local docker_choice="system + rootless for bot"
  local tailscale_choice="skip"
  local ssh_hardening="baseline only"
  local allow_users_note="not set (any user can SSH)"

  if [[ -n "${SSH_CLIENT:-}" ]]; then
    ssh_source="${SSH_CLIENT%% *}"
  elif [[ -n "${SSH_CONNECTION:-}" ]]; then
    ssh_source="${SSH_CONNECTION%% *}"
  fi

  if command -v ufw >/dev/null 2>&1; then
    ufw_state="$(ufw status 2>/dev/null | sed -n '1p' || true)"
  fi

  [[ "$INSTALL_DOCKER" == "1" ]] || docker_choice="skip"
  [[ "$INSTALL_TAILSCALE" == "1" || "$ACCESS_PROFILE" == "tailnet" ]] && tailscale_choice="install/enable"
  [[ "$HARDEN_SSH" == "1" ]] && ssh_hardening="key-only SSH"
  [[ -n "$ADMIN_USER" ]] && allow_users_note="${ADMIN_USER} only"

  local run_mode="fresh install"
  [[ "$IS_RERUN" == "1" ]] && run_mode="re-run (existing state preserved, UFW not reset)"
  [[ "$FORCE_FRESH_HOST" == "1" ]] && run_mode="force-fresh (UFW will be reset)"
  [[ "$DRY_RUN" == "1" ]] && run_mode="${run_mode}, dry-run"

  cat <<PREFLIGHT

Tin Lobster preflight

Mode:               ${run_mode}
Target bot user:    ${BOT_USER}
Admin SSH user:     ${allow_users_note}
Home directory:     ${home_dir}
Access profile:     ${ACCESS_PROFILE}
Allowed SSH CIDR:   ${SSH_CIDR:-none}
Current SSH source: ${ssh_source}
Current sudo user:  ${current_user}
Gateway port:       ${OPENCLAW_PORT} (will not be opened in UFW)
Docker:             ${docker_choice}
Tailscale:          ${tailscale_choice}
SSH hardening:      ${ssh_hardening}
Run apt upgrade:    ${RUN_UPGRADE}
Existing UFW:       ${ufw_state}

Hardening: sysctl, auditd, AppArmor, session limits, sudo logging,
           root lock, telemetry removal, service reduction, lynis, rkhunter

Tin Lobster will prepare infrastructure only. It will not configure model
providers, channels, agent identity, gateway tokens, or public exposure.
PREFLIGHT
}

confirm_preflight() {
  if [[ "$DRY_RUN" == "1" || "$ASSUME_YES" == "1" ]]; then
    return 0
  fi

  printf '\nEverything looks good. Tin Lobster will now make the changes shown above.\n'
  printf 'This will install packages, create user accounts, configure the firewall,\n'
  printf 'and apply security hardening. These changes cannot be undone without\n'
  printf 'running --uninstall or restoring a VM snapshot.\n'
  printf '\nPress Ctrl+C to cancel, or type TIN LOBSTER and Enter to begin: '
  local answer
  read -r answer
  [[ "$answer" == "TIN LOBSTER" ]] || die "Preflight confirmation failed; no changes made"
}

install_base_packages() {
  log "Updating package index..."
  run apt-get update -y -q

  if [[ "$RUN_UPGRADE" == "1" ]]; then
    log "Running system upgrade — this may take several minutes..."
    run apt-get upgrade -y \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold"
  fi

  local packages=(
    ca-certificates curl git gnupg jq lsb-release rsync sudo
    openssh-server ufw fail2ban unattended-upgrades
    auditd apparmor apparmor-utils
    python3 python3-pip
    libpam-pwquality
    lynis rkhunter
  )

  # audispd-plugins was merged into auditd in newer Ubuntu releases
  if apt-cache show audispd-plugins >/dev/null 2>&1; then
    packages+=(audispd-plugins)
  else
    log "audispd-plugins not available (merged into auditd on this release) — skipping"
  fi

  if [[ "$INSTALL_DOCKER" == "1" ]]; then
    # Add the official Docker CE apt repo before checking for packages.
    # docker.io (Ubuntu's own package) lacks docker-ce-rootless-extras which
    # ships rootlesskit — without it, dockerd-rootless-setuptool.sh will fail.
    if [[ ! -f /etc/apt/sources.list.d/docker.list ]] && [[ "$DRY_RUN" != "1" ]]; then
      log "Adding Docker CE apt repository..."
      install -m 0755 -d /etc/apt/keyrings
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
          -o /etc/apt/keyrings/docker.asc 2>/dev/null
      chmod a+r /etc/apt/keyrings/docker.asc
      # Ubuntu 26.04 may not have a Docker release yet; fall back to noble (24.04).
      local detected_codename
      detected_codename="$(. /etc/os-release && printf '%s' "${UBUNTU_CODENAME:-${VERSION_CODENAME}}")"
      local docker_codename="$detected_codename"
      if ! curl -sf --max-time 10 \
            "https://download.docker.com/linux/ubuntu/dists/${detected_codename}/Release" \
            -o /dev/null 2>/dev/null; then
        log "No Docker repo for '${detected_codename}' — using noble packages (binary-compatible)"
        docker_codename="noble"
      fi
      printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu %s stable\n' \
          "$(dpkg --print-architecture)" "${docker_codename}" \
          > /etc/apt/sources.list.d/docker.list
      apt-get update -qq
    fi

    # Prefer docker-ce (official repo, includes rootless extras) over docker.io
    if apt-cache show docker-ce >/dev/null 2>&1; then
      packages+=(docker-ce docker-ce-cli containerd.io docker-ce-rootless-extras docker-buildx-plugin)
    elif apt-cache show docker.io >/dev/null 2>&1; then
      warn "docker-ce not found after repo add; falling back to docker.io — rootless setup may fail"
      packages+=(docker.io containerd)
    else
      warn "No Docker package found in apt — skipping Docker install"
      INSTALL_DOCKER="0"
    fi
    # rootless Docker user-space dependencies
    if [[ "$INSTALL_DOCKER" == "1" ]]; then
      packages+=(uidmap dbus-user-session slirp4netns)
      # fuse-overlayfs improves overlay storage for rootless containers — optional
      apt-cache show fuse-overlayfs >/dev/null 2>&1 && packages+=(fuse-overlayfs) || true
    fi
  fi

  log "Installing packages — takes 3-5 minutes on a fresh host, please wait..."
  if [[ "$DRY_RUN" == "1" ]]; then
    run apt-get install -y "${packages[@]}"
  else
    if ! apt-get install -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" \
        "${packages[@]}" > /tmp/tin-lobster-apt.log 2>&1; then
      die "Package installation failed. Details in /tmp/tin-lobster-apt.log"
    fi
    log "Packages installed."
  fi

  # Explicit day-two requirement: git must be present so operators can clone
  # profile repos / Tin Lobster updates without hunting packages first.
  ensure_git_installed
}

ensure_git_installed() {
  if [[ "$DRY_RUN" == "1" ]]; then
    log "Would ensure git is installed for day-two clones"
    return 0
  fi

  if command -v git >/dev/null 2>&1; then
    log "git available: $(git --version | head -n1)"
    return 0
  fi

  log "git missing after base package install — installing git explicitly"
  if ! apt-get install -y \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" \
      git > /tmp/tin-lobster-git-install.log 2>&1; then
    die "git installation failed. Details in /tmp/tin-lobster-git-install.log"
  fi

  command -v git >/dev/null 2>&1 || die "git still missing after explicit install"
  log "git available: $(git --version | head -n1)"
}

install_node_22() {
  log "Installing Node.js 22 from NodeSource"
  if command -v node >/dev/null 2>&1; then
    local major
    major="$(node --version | sed 's/^v//' | cut -d. -f1)"
    if [[ "$major" -ge 22 ]]; then
      log "Node.js $(node --version) already satisfies requirement"
      return 0
    fi
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    log "Would install NodeSource Node.js 22 repository"
    return 0
  fi

  log "Adding NodeSource repository..."
  curl -fsSL https://deb.nodesource.com/setup_22.x -o /tmp/tin-lobster-nodesource.sh
  if ! bash /tmp/tin-lobster-nodesource.sh > /tmp/tin-lobster-nodesource.log 2>&1; then
    die "NodeSource setup failed. Details in /tmp/tin-lobster-nodesource.log"
  fi
  rm -f /tmp/tin-lobster-nodesource.sh
  log "Installing Node.js 22..."
  if ! apt-get install -y \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" \
      nodejs > /tmp/tin-lobster-apt.log 2>&1; then
    die "Node.js installation failed. Details in /tmp/tin-lobster-apt.log"
  fi
  node --version | grep -Eq '^v(22|2[3-9]|[3-9][0-9])\.' || die "Node.js 22+ required; got $(node --version)"
  log "Upgrading npm to latest..."
  npm install -g npm@latest > /tmp/tin-lobster-npm-upgrade.log 2>&1 || log "WARN: npm upgrade failed (non-fatal)"
}

remove_unnecessary_packages() {
  log "Removing telemetry and unnecessary packages"
  local to_remove=(snapd popularity-contest whoopsie apport)
  if [[ "$DRY_RUN" != "1" ]]; then
    for pkg in "${to_remove[@]}"; do
      if dpkg -l "$pkg" 2>/dev/null | grep -q '^ii'; then
        apt-get remove --purge -y "$pkg" > /dev/null 2>&1 || true
        log "Removed ${pkg}"
      fi
    done
    # Pin snapd so it cannot be reinstalled by apt
    write_file /etc/apt/preferences.d/99-tin-lobster-nosnap.pref 0644 root root <<'NOSNAP'
Package: snapd
Pin: release a=*
Pin-Priority: -10
NOSNAP
  else
    log "Would remove: ${to_remove[*]}"
    log "Would pin snapd to priority -10 to prevent reinstall"
  fi
}

disable_unused_services() {
  log "Disabling unused services"
  local services=(cups cups-browsed avahi-daemon bluetooth ModemManager)
  for svc in "${services[@]}"; do
    if systemctl list-unit-files "${svc}.service" 2>/dev/null | grep -q "${svc}"; then
      run systemctl disable --now "$svc" 2>/dev/null || true
      log "Disabled ${svc}"
    fi
  done
}

create_bot_user() {
  local home_dir="/home/${BOT_USER}"
  log "Creating runtime user ${BOT_USER}"
  if ! id "$BOT_USER" >/dev/null 2>&1; then
    run useradd -m -s /bin/bash -d "$home_dir" "$BOT_USER"
  else
    log "User ${BOT_USER} already exists"
  fi

  # Explicitly ensure the bot user has no sudo or admin privileges
  if [[ "$DRY_RUN" != "1" ]]; then
    deluser "$BOT_USER" sudo  2>/dev/null || true
    deluser "$BOT_USER" admin 2>/dev/null || true
  else
    log "Would remove ${BOT_USER} from sudo/admin groups"
  fi

  # Bot user is never added to the docker group — rootless Docker handles this
  log "Bot user will use rootless Docker (no docker group membership)"
}

lock_root_account() {
  log "Locking root password"
  # Root cannot SSH in (PermitRootLogin no) but this also closes the su - vector
  # from a physical console or compromised account
  run passwd -l root || warn "Could not lock root password — check manually"
}

configure_kernel_hardening() {
  log "Applying kernel/network hardening via sysctl"
  write_file /etc/sysctl.d/99-tin-lobster.conf 0644 root root <<'SYSCTL'
# IP redirect and source-route rejection
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_source_route = 0

# Reverse path filtering — reject packets with spoofed source IPs
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# SYN flood protection
net.ipv4.tcp_syncookies = 1

# Log packets with impossible source addresses
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# Address space layout randomisation
kernel.randomize_va_space = 2

# Prevent null pointer dereference exploits
vm.mmap_min_addr = 65536

# Filesystem hardening — prevent symlink/hardlink abuse
fs.protected_hardlinks = 1
fs.protected_symlinks = 1

# Hide kernel pointers from unprivileged users
kernel.kptr_restrict = 2

# Restrict dmesg to root
kernel.dmesg_restrict = 1

# BPF hardening
net.core.bpf_jit_harden = 2
kernel.unprivileged_bpf_disabled = 1

# Restrict perf to root
kernel.perf_event_paranoid = 3

# Restrict ptrace — prevents process memory inspection (protects in-memory secrets)
# 0=classic, 1=restricted, 2=root only, 3=disabled
kernel.yama.ptrace_scope = 2
SYSCTL

  if [[ "$DRY_RUN" != "1" ]]; then
    sysctl --system > /dev/null
    log "sysctl rules applied"
  fi
}

_ufw_apply_ssh_rules() {
  if [[ -n "$SSH_CIDR" ]]; then
    run ufw allow from "$SSH_CIDR" to any port 22 proto tcp comment "Tin Lobster SSH ${ACCESS_PROFILE}"
  else
    warn "No SSH CIDR configured by Tin Lobster"
  fi
  if [[ "$INSTALL_TAILSCALE" == "1" && "$ACCESS_PROFILE" != "tailnet" ]]; then
    run ufw allow from 100.64.0.0/10 to any port 22 proto tcp comment "Tin Lobster SSH tailscale"
  fi
}

configure_firewall() {
  log "Configuring UFW"

  # Ensure UFW manages IPv6 so rules apply to both stacks
  if [[ "$DRY_RUN" != "1" ]]; then
    sed -i 's/^IPV6=no/IPV6=yes/' /etc/default/ufw
    grep -q '^IPV6=' /etc/default/ufw || echo 'IPV6=yes' >> /etc/default/ufw
  else
    log "Would ensure IPV6=yes in /etc/default/ufw"
  fi

  local ufw_active="0"
  command -v ufw >/dev/null 2>&1 \
    && ufw status 2>/dev/null | grep -q '^Status: active' \
    && ufw_active="1"

  if [[ "$ufw_active" == "1" && "$FORCE_FRESH_HOST" != "1" ]]; then
    # Re-run mode: UFW is already active. Add any missing rules without resetting.
    # UFW ignores duplicate rules (same source/port/proto), so this is safe.
    log "UFW already active — adding missing rules (use --force-fresh-host to reset and reapply)"
    _ufw_apply_ssh_rules
    log "OpenClaw gateway port ${OPENCLAW_PORT} intentionally not opened."
    return 0
  fi

  # Fresh install or --force-fresh-host: clean slate
  run ufw --force reset
  run ufw default deny incoming
  run ufw default allow outgoing
  run ufw logging on
  _ufw_apply_ssh_rules
  log "OpenClaw gateway port ${OPENCLAW_PORT} is intentionally not opened; use loopback/Tailscale/proxy intentionally later."
  run ufw --force enable
}

configure_ssh() {
  log "Writing SSH baseline"
  write_file /etc/ssh/sshd_config.d/99-tin-lobster.conf 0644 root root <<SSHCFG
PermitRootLogin no
PubkeyAuthentication yes
PermitEmptyPasswords no
X11Forwarding no
AllowTcpForwarding no
PrintMotd yes
MaxAuthTries 3
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2
MaxSessions 3
UseDNS no
AcceptEnv LANG LC_*
AuthorizedKeysFile .ssh/authorized_keys
${ADMIN_USER:+AllowUsers ${ADMIN_USER}}
SSHCFG

  if [[ -n "$ADMIN_USER" ]]; then
    log "SSH restricted to user: ${ADMIN_USER}"
  else
    warn "No --admin-user set — AllowUsers not configured. Any user with valid credentials can SSH in."
    warn "Re-run with --admin-user <your-login> to lock this down."
  fi

  if [[ "$HARDEN_SSH" == "1" ]]; then
    write_file /etc/ssh/sshd_config.d/98-tin-lobster-key-only.conf 0644 root root <<'SSHKEYCFG'
PasswordAuthentication no
KbdInteractiveAuthentication no
SSHKEYCFG
    warn "Password login over SSH is now disabled. Make sure your SSH key works before closing this session."
  else
    warn "Password login over SSH is still allowed. Once you have confirmed you can log in with an SSH key, re-run with --harden-ssh to disable passwords."
  fi

  run systemctl reload ssh || run systemctl reload sshd || warn "Could not reload SSH; review service status manually"
}

configure_sudo() {
  log "Hardening sudo"

  # Baseline — universally supported
  write_file /etc/sudoers.d/99-tin-lobster 0440 root root <<'SUDOERS'
# Allocate a PTY — prevents file descriptor hijacking through sudo
Defaults use_pty
# Never echo password characters
Defaults !visiblepw
# Re-authenticate after 1 minute of sudo inactivity (default is 5)
Defaults timestamp_timeout=1
SUDOERS

  if [[ "$DRY_RUN" == "1" ]]; then
    log "Would attempt to enable sudo I/O logging if supported"
    return 0
  fi

  # I/O logging requires the iolog plugin — only add if visudo validates it
  local tmp
  tmp="$(mktemp)"
  cat > "$tmp" <<'SUDOERS_IOLOG'
Defaults use_pty
Defaults !visiblepw
Defaults timestamp_timeout=1
Defaults logfile=/var/log/sudo.log
Defaults log_input
Defaults log_output
SUDOERS_IOLOG
  if visudo -c -f "$tmp" >/dev/null 2>&1; then
    install -o root -g root -m 0440 "$tmp" /etc/sudoers.d/99-tin-lobster
    log "sudo I/O logging enabled"
  else
    rm -f "$tmp"
    log "sudo I/O logging not supported on this system — baseline hardening applied"
  fi
}

configure_fail2ban() {
  log "Configuring fail2ban"
  write_file /etc/fail2ban/jail.d/tin-lobster.conf 0644 root root <<'F2B'
[sshd]
enabled = true
maxretry = 3
bantime = 1h
findtime = 10m
F2B
  run systemctl enable fail2ban
  run systemctl restart fail2ban
}

configure_unattended_upgrades() {
  log "Configuring unattended upgrades"
  write_file /etc/apt/apt.conf.d/20auto-upgrades 0644 root root <<'APT'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
APT
  run systemctl enable unattended-upgrades || true
  run systemctl start unattended-upgrades || true
}

configure_auditd() {
  log "Configuring auditd rules"
  write_file /etc/audit/rules.d/99-tin-lobster.rules 0640 root root <<AUDITRULES
# Identity and credential files
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/gshadow -p wa -k identity

# Privilege escalation
-w /etc/sudoers -p wa -k sudo_rules
-w /etc/sudoers.d/ -p wa -k sudo_rules

# SSH configuration changes
-w /etc/ssh/sshd_config -p wa -k sshd_config
-w /etc/ssh/sshd_config.d/ -p wa -k sshd_config

# Login and logout events
-w /var/log/faillog -p wa -k logins
-w /var/log/lastlog -p wa -k logins
-w /var/run/utmp -p wa -k session
-w /var/log/wtmp -p wa -k session

# Bot user credentials directory
-w /home/${BOT_USER}/.openclaw/credentials -p rwa -k bot_credentials

# Privilege escalation via execve by non-root users gaining root
-a always,exit -F arch=b64 -S execve -F euid=0 -F auid>=1000 -F auid!=-1 -k privilege_escalation
-a always,exit -F arch=b32 -S execve -F euid=0 -F auid>=1000 -F auid!=-1 -k privilege_escalation

# Make rules immutable until next reboot (prevents in-memory tampering)
-e 2
AUDITRULES

  run systemctl enable auditd
  run systemctl restart auditd || warn "auditd restart failed; new rules will apply after reboot"
}

configure_apparmor() {
  log "Configuring AppArmor"
  run systemctl enable apparmor
  run systemctl start apparmor || warn "AppArmor failed to start; may need kernel parameter enforcement"
  if [[ "$DRY_RUN" != "1" ]]; then
    aa-enforce /etc/apparmor.d/* 2>/dev/null || true

    # Ubuntu 23.10+ restricts unprivileged user namespace creation via AppArmor
    # via /proc/sys/kernel/apparmor_restrict_unprivileged_userns=1.
    # Ubuntu 26.04 ships stub profiles for rootlesskit and runc; aa-disable
    # leaves them truly unconfined, but "unconfined" is also blocked by the
    # kernel restriction. The correct fix is a profile that explicitly grants
    # the userns capability while leaving all other access unrestricted.
    if [[ -f /proc/sys/kernel/apparmor_restrict_unprivileged_userns ]] && \
       [[ "$(cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns)" == "1" ]]; then
      # Remove the broken stubs so they don't conflict with our replacements.
      for _prof in rootlesskit runc; do
        local _f="/etc/apparmor.d/${_prof}"
        if [[ -f "$_f" ]]; then
          aa-disable "$_f" 2>/dev/null || true
          log "AppArmor: removed incomplete ${_prof} stub (replacing with userns-granting profile)"
        fi
      done

      # Write and load a proper rootlesskit profile that grants userns.
      # ref: https://ubuntu.com/blog/ubuntu-23-10-restricted-unprivileged-user-namespaces
      cat > /etc/apparmor.d/usr.bin.rootlesskit <<'AAPROF'
abi <abi/4.0>,
include <tunables/global>

/usr/bin/rootlesskit flags=(unconfined) {
  userns,

  # Site-specific additions and overrides. See local/README for details.
  include if exists <local/usr.bin.rootlesskit>
}
AAPROF
      apparmor_parser -r /etc/apparmor.d/usr.bin.rootlesskit 2>/dev/null \
        && log "AppArmor: loaded userns-granting profile for rootlesskit" \
        || warn "AppArmor: failed to load rootlesskit profile — rootless Docker may not work"
    fi

    local enforced
    enforced="$(aa-status 2>/dev/null | grep 'profiles are in enforce mode' || true)"
    log "AppArmor: ${enforced:-see aa-status for details}"
  else
    log "Would configure AppArmor profiles for rootless Docker compatibility"
  fi
}

configure_session_security() {
  log "Configuring session security"

  # Auto-logout idle SSH sessions after 15 minutes
  write_file /etc/profile.d/99-tin-lobster-timeout.sh 0644 root root <<'TMOUT'
TMOUT=900
readonly TMOUT
export TMOUT
TMOUT

  # Resource limits for the bot user — prevent runaway or fork-bomb
  write_file /etc/security/limits.d/99-tin-lobster-bot.conf 0644 root root <<LIMITS
${BOT_USER}  soft  nproc   512
${BOT_USER}  hard  nproc   1024
${BOT_USER}  soft  nofile  4096
${BOT_USER}  hard  nofile  8192
LIMITS
}

install_tailscale_if_requested() {
  [[ "$INSTALL_TAILSCALE" == "1" || "$ACCESS_PROFILE" == "tailnet" ]] || return 0
  log "Installing Tailscale support"
  if command -v tailscale >/dev/null 2>&1; then
    log "Tailscale already installed"
  elif [[ "$DRY_RUN" == "1" ]]; then
    log "Would install Tailscale"
  else
    curl -fsSL https://tailscale.com/install.sh -o /tmp/tin-lobster-tailscale.sh
    sh /tmp/tin-lobster-tailscale.sh
    rm -f /tmp/tin-lobster-tailscale.sh
  fi
  run systemctl enable tailscaled || true
  run systemctl start tailscaled || true
  warn "Tailscale is installed but not joined. Run 'sudo tailscale up' when ready."
}

add_tailscale_addon() {
  log "Adding Tailscale to existing Tin Lobster host (non-destructive)"
  install_tailscale_if_requested
  if ufw status | grep -q "100.64.0.0/10"; then
    log "Tailscale UFW rule already present — skipping"
  else
    log "Adding Tailscale CIDR to UFW"
    run ufw allow from 100.64.0.0/10 to any port 22 proto tcp comment "Tin Lobster SSH tailscale"
  fi
  warn "Tailscale installed. Run: sudo tailscale up"
  warn "Then verify SSH access over Tailscale before closing this session."
}

enable_docker_if_installed() {
  [[ "$INSTALL_DOCKER" == "1" ]] || return 0
  log "Enabling Docker with hardened daemon config"

  write_file /etc/docker/daemon.json 0644 root root <<'DOCKERD'
{
  "icc": false,
  "no-new-privileges": true,
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
DOCKERD

  run systemctl enable containerd || true
  run systemctl enable docker || true
  run systemctl start containerd || true
  run systemctl start docker || true
}

configure_rootless_docker() {
  [[ "$INSTALL_DOCKER" == "1" ]] || return 0

  local home_dir="/home/${BOT_USER}"
  local uid
  uid="$(id -u "$BOT_USER")"

  log "Setting up rootless Docker for ${BOT_USER} (no docker group needed)"

  if [[ "$DRY_RUN" == "1" ]]; then
    log "Would configure rootless Docker for ${BOT_USER}"
    return 0
  fi

  # Ensure subuid/subgid ranges exist for the bot user (useradd normally creates these)
  grep -q "^${BOT_USER}:" /etc/subuid || echo "${BOT_USER}:100000:65536" >> /etc/subuid
  grep -q "^${BOT_USER}:" /etc/subgid || echo "${BOT_USER}:100000:65536" >> /etc/subgid

  # Enable linger — bot user's systemd session persists after logout
  loginctl enable-linger "$BOT_USER"

  # Create XDG_RUNTIME_DIR now; systemd-logind creates it lazily on first login
  # but the rootless setup tool needs it to exist immediately.
  mkdir -p "/run/user/${uid}"
  chmod 0700 "/run/user/${uid}"
  chown "${BOT_USER}:${BOT_USER}" "/run/user/${uid}"

  # After enabling linger, wait up to 10 s for systemd to start the user session
  # and create the D-Bus socket. Without this, systemctl --user inside the setup
  # tool fails with "Failed to connect to bus: No such file or directory".
  local dbus_sock="/run/user/${uid}/bus"
  local wait_secs=0
  while [[ ! -S "$dbus_sock" && $wait_secs -lt 10 ]]; do
    sleep 1
    wait_secs=$((wait_secs + 1))
  done
  if [[ -S "$dbus_sock" ]]; then
    log "User systemd session ready (D-Bus socket found after ${wait_secs}s)"
  else
    log "D-Bus socket not yet present after ${wait_secs}s — setup tool will proceed anyway"
  fi

  # Find the setup tool — location varies between docker.io and docker-ce packages
  local setup_tool=""
  for candidate in \
    "$(command -v dockerd-rootless-setuptool.sh 2>/dev/null)" \
    /usr/bin/dockerd-rootless-setuptool.sh \
    /usr/libexec/docker/dockerd-rootless-setuptool.sh \
    /usr/lib/docker/dockerd-rootless-setuptool.sh; do
    if [[ -x "$candidate" ]]; then
      setup_tool="$candidate"
      break
    fi
  done

  if [[ -z "$setup_tool" ]]; then
    warn "dockerd-rootless-setuptool.sh not found — rootless Docker cannot be configured automatically"
    warn "After install, run as ${BOT_USER}:"
    warn "  dockerd-rootless-setuptool.sh install"
    return 0
  fi

  # Install rootless Docker as the bot user.
  # --skip-iptables: use slirp4netns for networking (avoids iptables failures in VMs).
  # XDG_RUNTIME_DIR + DBUS_SESSION_BUS_ADDRESS must both be set so that
  # `systemctl --user` works inside su -l without an interactive login session.
  local xdg_rt="/run/user/${uid}"
  local dbus_addr="unix:path=${xdg_rt}/bus"
  local log_file="/tmp/tin-lobster-rootless-docker.log"

  if su -l "$BOT_USER" -c \
    "XDG_RUNTIME_DIR=${xdg_rt} DBUS_SESSION_BUS_ADDRESS=${dbus_addr} ${setup_tool} install --skip-iptables" \
    > "$log_file" 2>&1; then
    log "Rootless Docker installed for ${BOT_USER}"
    su -l "$BOT_USER" -c \
      "XDG_RUNTIME_DIR=${xdg_rt} DBUS_SESSION_BUS_ADDRESS=${dbus_addr} systemctl --user enable docker" \
      >> "$log_file" 2>&1 || true
    su -l "$BOT_USER" -c \
      "XDG_RUNTIME_DIR=${xdg_rt} DBUS_SESSION_BUS_ADDRESS=${dbus_addr} systemctl --user start docker" \
      >> "$log_file" 2>&1 || true
    log "Rootless Docker daemon started for ${BOT_USER}"
  else
    warn "Rootless Docker setup failed — full log at ${log_file}"
    warn "Last output:"
    tail -20 "$log_file" | while IFS= read -r line; do warn "  ${line}"; done
    warn "Bot user can retry after login:"
    warn "  dockerd-rootless-setuptool.sh install --skip-iptables"
  fi

  # Wire DOCKER_HOST into bot user's environment
  if ! grep -q 'DOCKER_HOST' "${home_dir}/.bashrc" 2>/dev/null; then
    cat >> "${home_dir}/.bashrc" <<'DOCKERENV'

# Rootless Docker — runs as this user, no docker group needed
export DOCKER_HOST="unix:///run/user/$(id -u)/docker.sock"
export PATH="${HOME}/bin:${PATH}"
DOCKERENV
    chown "$BOT_USER:$BOT_USER" "${home_dir}/.bashrc"
  fi

  log "Bot user can run 'docker ...' commands without docker group membership"
}

configure_motd() {
  log "Writing login banner"
  write_file /etc/update-motd.d/99-tin-lobster 0755 root root <<MOTD_SCRIPT
#!/bin/sh
printf '\n'
printf '  Tin Lobster  |  OpenClaw ready\n'
printf '  Bot user:    ${BOT_USER}\n'
printf '\n'
printf '  Next step:   sudo -iu ${BOT_USER}\n'
printf '               (switches you to the bot account)\n'
printf '  Then run:    openclaw onboard --install-daemon\n'
printf '\n'
MOTD_SCRIPT
}

prepare_openclaw_home() {
  local home_dir="/home/${BOT_USER}"
  local openclaw_dir="${home_dir}/.openclaw"
  local workspace_dir="${openclaw_dir}/workspace"
  local secrets_dir="${openclaw_dir}/secrets"
  local npm_global="${home_dir}/.npm-global"

  log "Preparing OpenClaw directories"
  run install -d -m 0700 -o "$BOT_USER" -g "$BOT_USER" "$openclaw_dir" "$workspace_dir"
  run install -d -m 0700 -o "$BOT_USER" -g "$BOT_USER" "${openclaw_dir}/credentials" "${openclaw_dir}/logs" "$secrets_dir"
  run install -d -m 0755 -o "$BOT_USER" -g "$BOT_USER" "$npm_global"

  if [[ "$DRY_RUN" != "1" ]]; then
    # Operator secrets helpers (no real secrets written)
    write_file "${secrets_dir}/README" 0644 "$BOT_USER" "$BOT_USER" <<'SECRETS_README'
Tin Lobster secrets area

Put operator-managed secret files here (mode 600).
OpenClaw channel/provider credentials usually live under:
  ~/.openclaw/credentials/  and OpenClaw config

Do:
  cp env.example env.local
  chmod 600 env.local

Do not:
  commit this directory
  paste secrets into chat or screenshots
  store secrets in the public tin-lobster repo

Check for leaks:
  ~/tin-lobster/scripts/secrets-check.sh
SECRETS_README

    write_file "${secrets_dir}/env.example" 0644 "$BOT_USER" "$BOT_USER" <<'SECRETS_ENV'
# Copy to env.local and fill real values.
# chmod 600 env.local
#
# These are OPERATOR extras. Prefer OpenClaw wizard for channel/provider setup.
#
# Example placeholders only — replace before use:
# OPENAI_API_KEY=replace-me
# ANTHROPIC_API_KEY=replace-me
# CUSTOM_TOOL_TOKEN=replace-me
SECRETS_ENV

    write_file "${secrets_dir}/.gitignore" 0644 "$BOT_USER" "$BOT_USER" <<'SECRETS_GI'
*
!.gitignore
!env.example
!README
SECRETS_GI

    grep -q 'Tin Lobster OpenClaw path' "${home_dir}/.bashrc" 2>/dev/null || cat >> "${home_dir}/.bashrc" <<'BASHRC'

# Tin Lobster OpenClaw path
export NPM_CONFIG_PREFIX="${HOME}/.npm-global"
export PATH="${HOME}/.npm-global/bin:${PATH}"
BASHRC
    chown "$BOT_USER:$BOT_USER" "${home_dir}/.bashrc"
  fi
}

install_openclaw_cli() {
  local home_dir="/home/${BOT_USER}"
  local npm_global="${home_dir}/.npm-global"
  local workspace_dir="${home_dir}/.openclaw/workspace"
  local bot_path="${npm_global}/bin:${PATH}"

  log "Installing OpenClaw CLI for ${BOT_USER}"
  if [[ "$DRY_RUN" == "1" ]]; then
    log "Would install npm package: openclaw@latest"
    return 0
  fi

  sudo -u "$BOT_USER" env HOME="$home_dir" NPM_CONFIG_PREFIX="$npm_global" PATH="$bot_path" \
    npm install -g openclaw@latest

  if sudo -u "$BOT_USER" env HOME="$home_dir" NPM_CONFIG_PREFIX="$npm_global" PATH="$bot_path" \
      openclaw --version >/tmp/tin-lobster-openclaw-version.txt 2>/dev/null; then
    log "OpenClaw installed: $(tr -d '\r' </tmp/tin-lobster-openclaw-version.txt | head -n1)"
  else
    warn "OpenClaw installed but version could not be read"
  fi

  if sudo -u "$BOT_USER" env HOME="$home_dir" NPM_CONFIG_PREFIX="$npm_global" PATH="$bot_path" \
      openclaw setup --non-interactive --accept-risk --workspace "$workspace_dir"; then
    log "OpenClaw non-interactive setup complete"
  else
    warn "openclaw setup exited non-zero (gateway not yet running is normal); config and workspace were still prepared"
  fi

  if sudo -u "$BOT_USER" env HOME="$home_dir" NPM_CONFIG_PREFIX="$npm_global" PATH="$bot_path" \
      openclaw config validate; then
    log "OpenClaw config validates"
  else
    warn "OpenClaw config validate did not pass; first-run setup is still needed (openclaw onboard --install-daemon)"
  fi
}

copy_repo_to_bot() {
  local home_dir="/home/${BOT_USER}"
  local dest="${home_dir}/tin-lobster"

  local repo_root
  repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  log "Copying tin-lobster reference files to ${dest}"

  if [[ "$DRY_RUN" == "1" ]]; then
    log "Would copy docs/, scripts/, templates/ and top-level guides from ${repo_root} to ${dest}"
    return 0
  fi

  run install -d -m 0755 -o "$BOT_USER" -g "$BOT_USER" "$dest"

  for dir in docs scripts templates; do
    if [[ -d "${repo_root}/${dir}" ]]; then
      cp -r "${repo_root}/${dir}" "${dest}/"
      chown -R "$BOT_USER:$BOT_USER" "${dest}/${dir}"
    fi
  done

  for file in README.md START_HERE.md TODO.md SECURITY.md LICENSE; do
    if [[ -f "${repo_root}/${file}" ]]; then
      cp "${repo_root}/${file}" "${dest}/"
      chown "$BOT_USER:$BOT_USER" "${dest}/${file}"
    fi
  done

  # Ensure helper scripts remain executable after copy
  if [[ -d "${dest}/scripts" ]]; then
    find "${dest}/scripts" -type f -name '*.sh' -exec chmod 0755 {} +
    chown -R "$BOT_USER:$BOT_USER" "${dest}/scripts"
  fi

  log "Reference files available at ${dest}"
}

print_summary() {
  local home_dir="/home/${BOT_USER}"
  local openclaw_version="unknown"
  if [[ -f /tmp/tin-lobster-openclaw-version.txt ]]; then
    openclaw_version="$(tr -d '\r' </tmp/tin-lobster-openclaw-version.txt | head -n1)"
  fi

  cat <<SUMMARY

Tin Lobster infrastructure shell complete.

Bot user:       ${BOT_USER}
Access profile: ${ACCESS_PROFILE}
SSH CIDR:       ${SSH_CIDR:-not configured by Tin Lobster}
Admin SSH user: ${ADMIN_USER:-not set — AllowUsers was not configured}
Workspace:      ${home_dir}/.openclaw/workspace
Secrets dir:    ${home_dir}/.openclaw/secrets (operator extras only)
OpenClaw:       ${openclaw_version}
Gateway port:   ${OPENCLAW_PORT} (not opened in UFW)

What happened:
- Hardened Ubuntu host shell for OpenClaw
- Created bot user and locked-down OpenClaw directories
- Installed baseline tools including git (for day-two clones/updates)
- Installed Node.js 22 + OpenClaw CLI
- Copied docs/scripts/templates for day-one operations
- Did NOT configure model providers, channels, or secrets

Definition of done (day one):
1. Switch to the bot account:
   sudo -iu ${BOT_USER}

2. Run OpenClaw onboarding (enter secrets only here):
   openclaw onboard --install-daemon
   (Prefer SSH over the VM console)

3. Confirm the gateway:
   openclaw gateway status
   openclaw status
   # If needed:
   # openclaw gateway install --port ${OPENCLAW_PORT}
   # openclaw gateway start

4. Validate the host:
   ~/tin-lobster/scripts/validate-tin-lobster.sh --bot-user ${BOT_USER}

5. Check secrets hygiene:
   ~/tin-lobster/scripts/secrets-check.sh --bot-user ${BOT_USER}

6. Send one real test message on your channel.

7. Create and verify a backup (treat the file as sensitive):
   openclaw backup create
   openclaw backup verify <backup-file>

Reference files copied to ~${BOT_USER}/tin-lobster/:
   ~/tin-lobster/docs/        — guides, security model, secrets management
   ~/tin-lobster/scripts/     — validate, secrets-check, backup, restore helpers
   ~/tin-lobster/templates/   — identity starter SOUL.md files (not full blueprints)

Security hardening applied:
- UFW: deny-all, LAN/Tailscale SSH only, logging, IPv6 covered
- SSH: PermitRootLogin no, AllowUsers${ADMIN_USER:+ ${ADMIN_USER}}, MaxAuthTries 3,
       LoginGraceTime 30s, UseDNS no, AcceptEnv restricted
- Root password locked (su - is closed)
- fail2ban: 3 attempts → 1h ban
- sysctl: redirects, rp_filter, SYN cookies, ASLR, mmap_min_addr,
          ptrace_scope=2, BPF hardening, kptr/dmesg restrict
- auditd: auth files, sudoers, SSH config, bot credentials, privesc; immutable
- AppArmor: enforce mode
- sudo: use_pty, full logging, 1-min timeout
- Session: 15-min idle timeout, bot nproc/nofile limits
- Docker: system daemon hardened (icc:false, no-new-privileges)
          bot user uses rootless Docker — no docker group, no root daemon
- Telemetry removed: snapd (pinned), whoopsie, apport, popularity-contest
- Unused services disabled: cups, avahi, bluetooth
- Security tools: lynis (run: sudo lynis audit system)
                  rkhunter (run: sudo rkhunter --check)$( [[ "$HARDEN_SSH" == "1" ]] && printf '\n- SSH: password authentication disabled' )

Remaining operator work:
- Add your SSH public key:  ssh-copy-id ${ADMIN_USER:-<your-user>}@<this-host>
- After key login works, re-run with --harden-ssh to disable password SSH
- If Tailscale installed: sudo tailscale up
- Read secrets guidance: ~/tin-lobster/docs/SECRETS_MANAGEMENT.md
- Optional baseline: sudo lynis audit system
SUMMARY
}

uninstall_tin_lobster() {
  local home_dir="/home/${BOT_USER}"

  cat <<PLAN

Tin Lobster uninstall — bot user: ${BOT_USER}

Will remove:
  Bot user '${BOT_USER}' and home directory ${home_dir}
  /etc/sudoers.d/99-tin-lobster
  /etc/sysctl.d/99-tin-lobster.conf
  /etc/security/limits.d/99-tin-lobster-bot.conf
  /etc/ssh/sshd_config.d/99-tin-lobster.conf
  /etc/ssh/sshd_config.d/98-tin-lobster-key-only.conf
  /etc/fail2ban/jail.d/tin-lobster.conf
  /etc/audit/rules.d/99-tin-lobster.rules
  /etc/apt/preferences.d/99-tin-lobster-nosnap.pref
  /etc/profile.d/99-tin-lobster-timeout.sh
  /etc/update-motd.d/99-tin-lobster

Will reload: sshd, fail2ban (sysctl reloaded from remaining files)

Will NOT remove: Docker, Node.js, fail2ban, auditd, lynis, rkhunter,
                 UFW rules, /etc/apt/apt.conf.d/20auto-upgrades,
                 /etc/docker/daemon.json

PLAN

  if [[ "$ASSUME_YES" != "1" ]]; then
    printf 'Type UNINSTALL to confirm: '
    local answer
    read -r answer
    [[ "$answer" == "UNINSTALL" ]] || { log "Uninstall cancelled — no changes made."; return 0; }
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    log "Dry-run: would remove user ${BOT_USER} and all tin-lobster config files"
    return 0
  fi

  # Remove bot user and home directory
  if id "$BOT_USER" >/dev/null 2>&1; then
    loginctl disable-linger "$BOT_USER" 2>/dev/null || true
    # Stop any running rootless Docker daemon for the user
    local uid; uid="$(id -u "$BOT_USER" 2>/dev/null)" || uid=""
    if [[ -n "$uid" ]]; then
      su -l "$BOT_USER" -c \
        "XDG_RUNTIME_DIR=/run/user/${uid} systemctl --user stop docker" \
        2>/dev/null || true
    fi
    userdel -r "$BOT_USER" 2>/dev/null \
      || { warn "userdel -r failed; trying without -r"; userdel "$BOT_USER" 2>/dev/null || true; }
    log "Removed user ${BOT_USER} and home directory"
  else
    log "User ${BOT_USER} does not exist — skipping"
  fi

  # Remove all tin-lobster managed config files
  local config_files=(
    /etc/sudoers.d/99-tin-lobster
    /etc/sysctl.d/99-tin-lobster.conf
    /etc/security/limits.d/99-tin-lobster-bot.conf
    /etc/ssh/sshd_config.d/99-tin-lobster.conf
    /etc/ssh/sshd_config.d/98-tin-lobster-key-only.conf
    /etc/fail2ban/jail.d/tin-lobster.conf
    /etc/audit/rules.d/99-tin-lobster.rules
    /etc/apt/preferences.d/99-tin-lobster-nosnap.pref
    /etc/profile.d/99-tin-lobster-timeout.sh
    /etc/update-motd.d/99-tin-lobster
  )
  for f in "${config_files[@]}"; do
    if [[ -f "$f" ]]; then
      rm -f "$f"
      log "Removed ${f}"
    fi
  done

  # Reload affected services
  sysctl --system > /dev/null 2>&1 && log "sysctl reloaded" || warn "sysctl reload failed"
  systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null \
    && log "sshd reloaded" || warn "sshd reload failed — check manually"
  systemctl restart fail2ban 2>/dev/null && log "fail2ban restarted" || warn "fail2ban restart failed"

  log ""
  log "Tin Lobster uninstall complete."
  warn "auditd: if rules were made immutable (-e 2), changes take effect after reboot"
  warn "UFW rules were not changed — run 'sudo ufw reset' to clear the firewall if needed"
  warn "Docker daemon.json at /etc/docker/daemon.json was not removed — review if needed"
}

main() {
  parse_args "$@"
  require_root

  if [[ "$UNINSTALL" == "1" ]]; then
    require_ubuntu
    # Prompt for bot user if not given on the command line
    if [[ -z "$BOT_USER_GIVEN" && -t 0 ]]; then
      printf 'Bot user to remove [%s]: ' "$BOT_USER"
      local answer=""
      read -r answer || true
      BOT_USER="${answer:-$BOT_USER}"
    fi
    valid_username "$BOT_USER" || die "Invalid --bot-user '${BOT_USER}'"
    uninstall_tin_lobster
    return 0
  fi

  if [[ "$ADD_TAILSCALE" == "1" ]]; then
    add_tailscale_addon
    return 0
  fi

  # Auto-detect admin user from sudo context when not supplied
  if [[ -z "$ADMIN_USER" && -n "${SUDO_USER:-}" ]]; then
    ADMIN_USER="$SUDO_USER"
  fi

  require_ubuntu
  require_environment
  prompt_missing
  validate_options
  fresh_host_guard
  print_preflight
  confirm_preflight

  log "Starting Tin Lobster bootstrap"
  install_base_packages
  remove_unnecessary_packages
  disable_unused_services
  install_node_22
  create_bot_user
  lock_root_account
  install_tailscale_if_requested
  configure_kernel_hardening
  configure_firewall
  configure_ssh
  configure_sudo
  configure_fail2ban
  configure_unattended_upgrades
  configure_auditd
  configure_apparmor
  configure_session_security
  enable_docker_if_installed
  configure_rootless_docker
  configure_motd
  prepare_openclaw_home
  install_openclaw_cli
  copy_repo_to_bot
  print_summary
}

main "$@"
