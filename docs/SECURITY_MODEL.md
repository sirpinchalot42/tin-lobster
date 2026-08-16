# Tin Lobster Security Model

Tin Lobster creates a defensive personal-agent baseline. It is not a guarantee
of security, and it is not a hostile multi-tenant isolation platform.

## Assumptions

- One trusted human owns the host.
- The host starts as a fresh Ubuntu 24.04 or 26.04 LTS install.
- OpenClaw is powerful and may receive access to local tools.
- Messaging channels and backups can contain sensitive personal data.
- The gateway should not be internet-exposed by default.
- The VM is dedicated to the bot — it does not share a host with other users
  or services. This means the VM boundary is the outer security perimeter.

## Two Users, One Machine

Tin Lobster creates a deliberate separation between you and your bot.

**Admin user** — your personal Ubuntu account, created during OS install.
Has `sudo`. This is how you manage the machine. SSH logs in as this user.

**Bot user** — a locked-down service account created by the bootstrap script
(default name `lobster`). Owns and runs OpenClaw. Has no `sudo`, no SSH
access, no root-equivalent group memberships. You reach it by running
`sudo -iu lobster` after SSHing in as yourself.

```
Your laptop
    └─ SSH (your admin user, key-authenticated)
           └─ sudo -iu lobster
                  └─ openclaw commands
```

The bot user is isolated by design. Even if OpenClaw were somehow compromised,
an attacker is trapped inside a low-privilege account with no direct escalation
path.

## SSH Keys

SSH keys are generated on **your laptop** (the machine you connect from).
Your public key goes into the admin user's `~/.ssh/authorized_keys` on the
server. The private key never leaves your laptop.

- Never SSH directly as root — `PermitRootLogin no` is enforced.
- Never SSH directly as the bot user — `AllowUsers` restricts SSH to your
  admin account only.
- Never share your private key. Never paste it anywhere.

See `SSH_FROM_MAC.md`, `SSH_FROM_WINDOWS.md`, or `SSH_FROM_ANDROID.md` for
platform-specific key setup instructions.

## Hardening Layers

### Firewall (UFW)

- Default deny all incoming traffic.
- SSH allowed only from the selected network (LAN CIDR, Tailscale range, or
  both).
- OpenClaw gateway port is not opened — access it via loopback, Tailscale, or
  a reverse proxy you deliberately configure.
- UFW logging enabled.
- IPv6 rules applied alongside IPv4 (prevents IPv6 stack-bypass).

### SSH Daemon

- `PermitRootLogin no` — root cannot log in over SSH.
- `AllowUsers <admin>` — only your named admin account can SSH in.
- `MaxAuthTries 3` — limits brute-force attempts per connection.
- `LoginGraceTime 30` — unauthenticated connections time out in 30 seconds.
- `PermitEmptyPasswords no` — blank passwords are rejected.
- `ClientAliveInterval 300` — detects dropped connections and cleans up.
- `MaxSessions 3` — limits concurrent sessions.
- `UseDNS no` — prevents SSH delays and DNS rebinding attacks.
- `AcceptEnv LANG LC_*` — restricts which environment variables can be
  injected over SSH to locale settings only.
- `AuthorizedKeysFile .ssh/authorized_keys` — explicit key location.
- Key-only mode available via `--harden-ssh`.

### Root Account Locked

`passwd -l root` is run during bootstrap. This closes the `su -` vector —
even someone with physical console access or a compromised account cannot
switch to root using a password. Combined with `PermitRootLogin no`, root
is unreachable by both SSH and local login.

### fail2ban

Monitors SSH login failures. Three failed attempts in 10 minutes results in a
1-hour ban on that source IP. Protects against automated brute-force even if
the firewall is misconfigured to allow wider SSH access.

### Kernel Hardening (sysctl)

Applied at boot via `/etc/sysctl.d/99-tin-lobster.conf`:

- ICMP redirects rejected (prevents route hijacking).
- Source routing rejected.
- **Reverse path filtering** (`rp_filter=1`) — rejects packets with spoofed
  source IPs that could not have arrived via the correct interface.
- Suspicious packets logged (martians).
- SYN flood protection enabled (`tcp_syncookies`).
- **`vm.mmap_min_addr=65536`** — closes a class of null pointer dereference
  kernel exploits by preventing mapping at the zero page.
- ASLR enforced at level 2 (randomise all memory layouts).
- Symlink/hardlink abuse prevented.
- Kernel pointers hidden from unprivileged users (`kptr_restrict=2`).
- `dmesg` restricted to root.
- BPF JIT hardening and unprivileged BPF disabled.
- `perf_event_paranoid` restricted to root.
- **`kernel.yama.ptrace_scope=2`** — restricts `ptrace` to root only. This
  prevents any process from inspecting another process's memory. Without this,
  a compromised bot process could read API keys, tokens, and gateway
  credentials directly from OpenClaw's memory at runtime.

### sudo Hardening

`/etc/sudoers.d/99-tin-lobster` applies:

- `use_pty` — allocates a real PTY for sudo sessions. This prevents file
  descriptor hijacking attacks where a process passes a malicious fd through
  a sudo invocation.
- Full audit log at `/var/log/sudo.log` — every sudo command, with input and
  output, is recorded.
- `timestamp_timeout=1` — sudo re-authentication required after 1 minute of
  inactivity (default is 5).
- `!visiblepw` — password characters are never echoed.

### Audit Logging (auditd)

Rules are loaded and made immutable at boot (require reboot to change, which
prevents in-memory tampering):

- Changes to `/etc/passwd`, `/etc/shadow`, `/etc/group` logged.
- Changes to `/etc/sudoers` and `sudoers.d/` logged.
- Changes to SSH config logged.
- Login and logout events logged.
- Reads, writes, and attribute changes to the bot user's credentials directory
  logged.
- Any process executed by a non-root user that gains root effective UID logged
  (privilege escalation detection).

Audit logs are in `/var/log/audit/audit.log`. Query them with `ausearch` or
`aureport`.

### AppArmor

Mandatory access control framework. Enforces per-process restrictions on what
files, capabilities, and system calls are permitted.

- Enabled in enforce mode at boot.
- All shipped Ubuntu profiles set to enforce.

AppArmor limits the blast radius of a compromised process by confining it to
what the profile allows, independent of user permissions.

### Docker — Rootless for the Bot

The bot user runs **rootless Docker**: a personal Docker daemon in user space,
owned entirely by the bot user. No `docker` group membership is required or
granted — ever.

**Why this matters:** the `docker` group grants effective root. Any user in
that group can run `docker run -v /:/host --rm -it ubuntu chroot /host` and
get a root shell on the host filesystem, bypassing every other restriction.
Rootless Docker eliminates this vector entirely.

**How it works:**

```
Bot user's process space
    └─ rootless dockerd (running as bot user UID)
           └─ containers (mapped to bot user's UID namespace)
```

Containers run by the bot are mapped to unprivileged UIDs on the host via
user namespaces. A container escape lands the attacker back inside the bot
user's account, not on the host as root.

The system Docker daemon (used by admin via `sudo docker`) is also hardened:

- `icc: false` — containers cannot communicate with each other by default.
- `no-new-privileges: true` — containers cannot escalate privileges.
- Log rotation enforced.

**The escalation chain on a dedicated VM:**

```
Compromise bot → container escape (kernel exploit needed)
              → root on dedicated VM
              → VM escape (hypervisor exploit needed)
              → Proxmox host
```

Two hard exploit steps rather than zero. The dedicated VM boundary means root
on the VM is not game over — the Proxmox firewall and network isolation form
the outer perimeter.

### Session Security

- Interactive shell sessions close automatically after 15 minutes of
  inactivity (`TMOUT=900`). Applies to both admin and bot user shells.
  Does not affect the OpenClaw gateway service.
- The bot user has resource limits: maximum 512 processes (soft) / 1024
  (hard), and file descriptor limits. Prevents runaway processes and
  fork-bomb attacks.

### Telemetry and Attack Surface Reduction

The following packages are removed if present, and snapd is pinned to
prevent reinstallation:

- **snapd** — snaps run with root-level daemon involvement and expand the
  trusted package surface. Pinned at priority -10.
- **whoopsie** and **apport** — Ubuntu crash reporters that can phone home
  with process memory dumps.
- **popularity-contest** — sends package usage telemetry.

The following services are disabled if present:

- **cups** — printing service, unnecessary on a bot host.
- **avahi-daemon** — mDNS/zeroconf service discovery, unnecessary and
  exposes network information.
- **bluetooth** — not needed, removes a known attack surface.

### Security Audit Tools

Two security tools are installed for ongoing posture verification:

- **lynis** — runs a comprehensive security audit and produces a hardening
  index score. Run after bootstrap and after any significant change:
  `sudo lynis audit system`
- **rkhunter** — rootkit scanner. Checks for known rootkits, suspicious
  files, and system binary modifications:
  `sudo rkhunter --check`

### Unattended Upgrades

Security patches are applied automatically. System packages are updated daily
without human intervention.

## Access Profiles

**`local-lan`** — allows SSH from a supplied LAN CIDR (e.g. `192.168.1.0/24`).
Best for home lab or office deployments.

**`tailnet`** — installs Tailscale and allows SSH from `100.64.0.0/10` (the
Tailscale CGNAT range). Best for machines you need to reach from anywhere.

**`cloud`** — no LAN assumption. Requires either a narrow SSH CIDR or
Tailscale. Best for VPS deployments.

Profiles can be combined: select `local-lan` during setup and answer yes to the
Tailscale prompt, or add Tailscale later with `--add-tailscale`.

## What This Does Not Cover

- Public gateway exposure — deliberately out of scope.
- Automatic channel login — handled by OpenClaw's setup wizard.
- Automatic model-provider credentials — same.
- Moving secrets between machines — user-reviewed process.
- Replacing OpenClaw's own backup, doctor, and security tooling.
- A custom AppArmor profile for Node.js/OpenClaw — beneficial but requires
  profiling your specific workload.
- Remote syslog — logs are local only; a compromised host could wipe them.
- File integrity monitoring (AIDE/tripwire) — good addition for high-value hosts.

## What To Check Regularly

```bash
# Firewall
sudo ufw status numbered

# AppArmor
sudo aa-status

# Audit log summary (last 24h)
sudo aureport --start today --summary

# Recent privilege escalation events
sudo ausearch -k privilege_escalation --start today

# Bot credentials access
sudo ausearch -k bot_credentials --start recent

# Sudo audit log
sudo tail -50 /var/log/sudo.log

# Security posture score
sudo lynis audit system

# Rootkit scan
sudo rkhunter --check

# Listening ports — nothing unexpected should appear
ss -ltnp
```

See `DAY_TWO_OPERATIONS.md` for the full maintenance rhythm.

## Release Requirements

Before a public release, add:

- Checksum or signature verification on downloaded scripts (NodeSource, Tailscale).
- Disposable Ubuntu 24.04 and 26.04 smoke tests for all access profiles.
- Documented rollback/uninstall path.
- Backup/restore walkthrough tested end-to-end.
- Clear troubleshooting for SSH and firewall mistakes.
