# Admin guide

Full operator manual for a Tin Lobster host: security model, permissions,
secrets, day-two care, backup/restore, and troubleshooting.

Use this when you need to fix or harden the machine without hand-holding.
For first install, prefer the [user manual](user-manual.md). For the short
architecture picture, see the [design guide](design-guide.md).

## Contents

- [Security model](#security-model)
- [Bot permissions](#bot-permissions)
- [Security habits](#security-habits)
- [Secrets](#secrets)
- [Day-two operations](#day-two-operations)
- [Backup and restore](#backup-and-restore)
- [Troubleshooting](#troubleshooting)
- [Validation commands](#validation-commands)

## Security model

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

See [SSH how-to](how-to/ssh.md) for
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

See [Day-two operations](#day-two-operations) for the full maintenance rhythm.

## Release Requirements

Before a public release, add:

- Checksum or signature verification on downloaded scripts (NodeSource, Tailscale).
- Disposable Ubuntu 24.04 and 26.04 smoke tests for all access profiles.
- Documented rollback/uninstall path.
- Backup/restore walkthrough tested end-to-end.
- Clear troubleshooting for SSH and firewall mistakes.


## Bot permissions

The bot user (default: `lobster`) is an isolated service account. It has
exactly what it needs to run OpenClaw and nothing more.

This page explains what the bot can do on its own, what requires a human admin
to step in, and how the Docker isolation works.

## What The Bot Can Do Without Any Human Help

| Action | Why it works |
|---|---|
| Run the OpenClaw gateway | Node.js process owned by the bot user |
| Install and upgrade npm packages | Installs to `~/.npm-global` — no root needed |
| Read and write its own workspace | `~/.openclaw/` is owned entirely by the bot user |
| Make outbound network calls | UFW allows all outbound traffic |
| Execute `tools.exec` commands | Commands run as the bot user in its own context |
| Restart the gateway | `openclaw gateway restart` — no sudo needed |
| Create and verify backups | `openclaw backup create` — operates on its own files |
| **Run Docker containers** | Rootless Docker — bot's own user-space daemon |

The gateway, workspace, credentials, and logs are all inside the bot user's
home directory. Normal OpenClaw operations never need root.

## Docker — How It Works (No docker Group Needed)

The bot user runs **rootless Docker**: a personal Docker daemon that runs
entirely in user space under the bot user's UID. No `docker` group. No root
daemon interaction. The bot just runs `docker ...` and it works.

```bash
# As the bot user — this works out of the box after bootstrap
docker run hello-world
docker ps
docker build -t my-tool .
```

`DOCKER_HOST` is automatically set in the bot's `~/.bashrc` to point to the
rootless socket:

```bash
DOCKER_HOST=unix:///run/user/<uid>/docker.sock
```

**If docker commands fail after a fresh login**, the rootless daemon may need
a moment to start. Check:

```bash
systemctl --user status docker
systemctl --user start docker
```

If the daemon isn't starting automatically, verify linger is enabled:

```bash
loginctl show-user "$USER" | grep Linger
# Should say: Linger=yes
```

### Why Not the docker Group?

The `docker` group grants effective root — full stop. Any user in it can run:

```bash
docker run -v /:/host --rm -it ubuntu chroot /host
```

That gives a root shell on the entire host filesystem, bypassing UFW,
AppArmor, auditd, and every other restriction. Rootless Docker eliminates
this attack vector entirely. Containers a compromised bot runs are mapped to
unprivileged UIDs on the host — even a container escape stays within the
bot user's account.

## What Requires a Human Admin

### Installing system packages

The bot has no `sudo` access. If an OpenClaw tool or plugin needs a new
system package, an admin has to install it.

```bash
# As your admin user
sudo apt-get install <package-name>
```

### Binding a privileged port (below 1024)

Normal users cannot bind ports below 1024. The OpenClaw gateway runs on
`18789` by default, which is fine.

If you ever need a privileged port:

```bash
sudo sysctl -w net.ipv4.ip_unprivileged_port_start=80
```

To make it permanent, add it to `/etc/sysctl.d/99-tin-lobster.conf`.

### Modifying firewall or SSH config

Any change to UFW rules or SSH config requires an admin. The bot user cannot
touch `/etc/` at all.

### Changing system Python or Node.js versions

System-level package changes need `sudo apt-get`. The bot can install npm
packages under its own user freely, but cannot replace the system Node.js.

### Giving the bot access to host devices or GPU

If tools require `/dev/` access (USB, GPU passthrough, etc.), an admin must
add the appropriate group memberships or udev rules.

## Resource Limits

The bot user has enforced resource limits to prevent runaway processes:

| Limit | Soft | Hard |
|---|---|---|
| Max processes (nproc) | 512 | 1024 |
| Open file descriptors (nofile) | 4096 | 8192 |

**Normal OpenClaw use is nowhere near these limits.** Node.js typically uses
10–20 threads and a few dozen file descriptors.

If you see `fork: retry: Resource temporarily unavailable`:

```bash
# Check current process count
ps -u lobster --no-headers | wc -l

# If close to 512, something is misbehaving
sudo pkill -u lobster
```

## Session Timeout

Interactive shell sessions (including `sudo -iu lobster`) close automatically
after 15 minutes of inactivity. Applies to both admin and bot user shells.

This does **not** affect the OpenClaw gateway — it runs as a background
service, not a shell.

If your gateway unexpectedly stops:

```bash
sudo -iu lobster
openclaw gateway status
openclaw logs
```

## ptrace Restriction

`kernel.yama.ptrace_scope=2` is enforced system-wide. This means no process
can inspect another process's memory unless it is root. This protects API
keys, tokens, and credentials that OpenClaw holds in memory at runtime.

If a tool or debugger requires ptrace, it must be run as root (via sudo).
For normal bot operation this never comes up.

## Quick Reference

```
Can the bot apt-get install?      No  → admin installs system packages
Can the bot run docker?           Yes → rootless Docker, no docker group needed
Can the bot sudo?                 No  → explicitly removed from sudo/admin groups
Can the bot SSH in?               No  → AllowUsers restricts SSH to admin user only
Can the bot inspect other procs?  No  → ptrace_scope=2, root only
Can the bot install npm packages? Yes → installs to ~/.npm-global
Can the bot write to ~/.openclaw? Yes → it owns that directory
Can the bot make network calls?   Yes → UFW allows all outbound
Does TMOUT affect the gateway?    No  → gateway is a service, not a shell
```


## Security habits

This guide explains the security ideas behind Tin Lobster without pretending
they are optional.

Your OpenClaw bot may eventually know private things. Treat the machine like a
small personal server, not like a toy.

## The Simple Rules

1. Keep private keys private.
2. Keep tokens and passwords out of chat.
3. Do not expose ports to the internet unless you know why.
4. Use Tailscale for remote access.
5. Make backups before experiments.
6. Do not post screenshots without checking for secrets.
7. When asking for help, share errors, not secrets.
8. Enter channel/provider secrets through OpenClaw setup — not bootstrap flags.
9. Run `scripts/secrets-check.sh` before you share logs or celebrate day one.

Full layout and operator flow: [Secrets](#secrets).

## Safe To Share

Usually safe:

- Public SSH key ending in `.pub`.
- Tin Lobster command without tokens.
- Exact error messages after checking for secrets.
- UFW status if it does not include private details you care about.
- OpenClaw version.
- Ubuntu version.

## Do Not Share

Never share:

- Private SSH keys.
- API keys.
- Gateway tokens.
- Telegram or Discord bot tokens.
- `.env` files.
- OpenClaw config files unless reviewed and redacted.
- Backup files.
- Screenshots containing credentials, QR codes, tokens, or private keys.

## SSH In Plain English

SSH is the remote control for your server.

An SSH key is like a special lock:

- public key goes on the server
- private key stays on your device

If someone gets your private key and passphrase, they may be able to log in as
you.

## Firewall In Plain English

The firewall decides what doors are open.

Tin Lobster should leave only the needed doors open. The OpenClaw gateway port
is not opened by default.

Check:

```bash
sudo ufw status numbered
```

Be suspicious of rules that allow the whole internet:

```text
0.0.0.0/0
Anywhere
```

Sometimes they are correct. Most beginners should not add them casually.

## Tailscale In Plain English

Tailscale creates a private network between your devices.

It lets you reach the bot from a laptop or phone without opening SSH to the
public internet.

For most people, this is easier and safer than router port forwarding.

## Backups In Plain English

A backup is a lifeboat. It can also contain private data.

Do:

- make backups before big changes
- verify backups
- store backups privately

Do not:

- paste backup contents into chat
- put backups in public repos
- assume a backup works before testing it

## Asking For Help Safely

Good help request:

```text
I ran `openclaw gateway start` and got:
[redacted error message]

Ubuntu: 24.04
OpenClaw: <version>
Tin Lobster commit: <commit>
I already checked UFW and port 18789 is not open.
```

Bad help request:

```text
Here is my whole config file and backup zip. Can someone fix it?
```

## Screenshot Checklist

Before posting a screenshot, look for:

- tokens
- passwords
- QR codes
- private keys
- email addresses
- phone numbers
- home IPs or private hostnames
- backup filenames that reveal personal info

When in doubt, crop or redact.

## The Recovery Question

Before changing SSH, firewall, Tailscale, or OpenClaw gateway settings, ask:

```text
If this breaks, how do I get back in?
```

Acceptable answers:

- VM console
- Proxmox console
- cloud provider console
- physical keyboard and monitor
- another working SSH session

Bad answer:

```text
I hope it works.
```


## Secrets

Most people do not need HashiCorp Vault on day one. They need a **clear place
for secrets**, **strict permissions**, **no accidental leaks**, and a **habit
that survives workshops**.

Tin Lobster bakes in that baseline. You can graduate to stronger tools later
without throwing the layout away.

## Mental model

There are three buckets:

| Bucket | Who owns it | Examples | Where |
|--------|-------------|----------|--------|
| **OpenClaw credentials** | OpenClaw wizard / runtime | channel tokens, gateway auth material | `~/.openclaw/credentials/` and OpenClaw config |
| **Operator secrets** | You | extra API keys for tools, personal notes about rotations | `~/.openclaw/secrets/` |
| **Public repo / docs** | Git | install steps, architecture, templates | this repository |

**Rule:** secrets never live in the public Tin Lobster git tree, workshop
slides, screenshots, or chat.

## What Tin Lobster creates for you

On bootstrap, the bot home gets:

```text
~/.openclaw/
  credentials/          # OpenClaw-managed (mode 700)
  secrets/              # operator helper area (mode 700)
    README              # short local reminder
    env.example         # dummy template you can copy
    .gitignore          # refuse to commit anything here
```

Permissions target:

- directories: `700` (owner only)
- secret files: `600` (owner read/write only)

Tin Lobster **does not** invent a second password store or ask for API keys
during bootstrap. That is intentional.

## Day-one flow (recommended)

1. Bootstrap the host with Tin Lobster.
2. Switch to the bot user: `sudo -iu lobster`
3. Run OpenClaw onboarding: `openclaw onboard --install-daemon`
   - Enter provider and channel secrets **only** in onboarding / official flows.
4. Create operator env file only if you need extra keys for tools:

```bash
cp ~/.openclaw/secrets/env.example ~/.openclaw/secrets/env.local
chmod 600 ~/.openclaw/secrets/env.local
nano ~/.openclaw/secrets/env.local
```

5. Run the leak check:

```bash
~/tin-lobster/scripts/secrets-check.sh --bot-user lobster
```

6. Make a backup and treat the archive as sensitive:

```bash
openclaw backup create
openclaw backup verify <backup-file>
```

## How to handle common secret types

### Model provider API keys

Prefer OpenClaw's guided setup. If a tool needs an extra key:

- put it in `~/.openclaw/secrets/env.local` (mode 600), **or**
- use the provider's recommended local config path

Never:

- pass keys as bootstrap flags
- commit keys into a bot profile repo
- paste keys into Discord/Telegram group chats

### Channel tokens (Telegram, Discord, etc.)

Enter them through OpenClaw setup. Rotate them if they ever appear in:

- screenshots
- support tickets
- shell history
- git commits

### Gateway auth / loopback access

Tin Lobster leaves the gateway closed in UFW by design. Do not open
`18789/tcp` to the world to "make it easier."

### SSH private keys

Live on **your admin devices**, not in the bot workspace. Public keys only on
the server.

## Leak prevention (the heavy lifting most people need)

Tin Lobster ships `scripts/secrets-check.sh` to catch common mistakes:

- world-readable files under `~/.openclaw`
- likely tokens/keys in workspace markdown
- `.env` files with loose permissions
- private key files with mode wider than `600`
- secrets directories that are not mode `700`
- accidental secret-looking strings in `~/tin-lobster` copies

Run it:

- after first OpenClaw setup
- before asking for help with logs
- before cloning a profile repo to a new machine
- as part of workshop "definition of done"

## What about "real" secret managers?

When you outgrow files:

| Stage | Tooling | When |
|-------|---------|------|
| **v0 (now)** | OpenClaw credentials + `~/.openclaw/secrets` + leak check | personal bot, club workshop |
| **v1** | encrypted backup of secrets dir (`age`/`sops`) off-host | multi-machine recovery |
| **v2** | systemd `EnvironmentFile=` + restricted service user | always-on services needing env injection |
| **v3** | 1Password / Bitwarden / Vault + short-lived tokens | team or higher threat model |

Tin Lobster stays compatible with later stages because it never hardcodes
secrets into the shell and keeps a clean owner-only directory.

## Backup and restore implications

Backups may include credentials depending on OpenClaw settings. Treat every
backup as **full-trust material**.

- Store backups encrypted or on a locked volume.
- Do not email backups to yourself "for safety."
- When migrating hosts, prefer re-linking channels over blindly copying every
  secret across trust boundaries.

See [Backup and restore](#backup-and-restore).

## Safe help requests

When something breaks, share:

- redacted error messages
- Ubuntu version
- Tin Lobster / OpenClaw version
- `scripts/secrets-check.sh` summary (not file contents)

Do **not** share:

- `env.local`
- `~/.openclaw/credentials/*`
- gateway tokens
- channel bot tokens
- private keys
- unredacted config dumps

## Workshop teaching script (60 seconds)

1. Secrets are radioactive.
2. Wizard is the front door; chat is not.
3. `~/.openclaw/secrets` is for operator extras only.
4. Run `secrets-check.sh` before you celebrate.
5. Backups are secret packages, not trophies.

## Related

- [SECURITY.md](../SECURITY.md) (project policy)
- this guide’s security model section
- the security habits section below
- `scripts/secrets-check.sh`
- `scripts/init-secrets-layout.sh`


## Day-two operations

Day one is install. Day two is keeping the bot healthy.

This guide is the normal care rhythm for a Tin Lobster/OpenClaw host.

## Daily Or Before A Demo

Log in:

```bash
ssh openclaw
```

Check the machine:

```bash
uptime
df -h
free -h
```

Check OpenClaw:

```bash
sudo -iu lobster
openclaw status
```

Replace `lobster` with your bot user if different.

## Restart OpenClaw Gateway

As the bot user:

```bash
openclaw gateway status
openclaw gateway restart
openclaw status
```

If `restart` is not available in your OpenClaw version:

```bash
openclaw gateway stop
openclaw gateway start
```

## Update The Host

As the admin user:

```bash
sudo apt update
sudo apt upgrade
```

If the system says a reboot is required, schedule a quiet time:

```bash
sudo reboot
```

## Update OpenClaw

As the bot user:

```bash
sudo -iu lobster
npm update -g openclaw
openclaw --version
openclaw config validate
openclaw status
```

If your OpenClaw install uses a different update command, use the official
OpenClaw instructions for that version.

## Check Security Posture

Run:

```bash
scripts/validate-tin-lobster.sh --bot-user lobster
sudo ufw status numbered
ss -ltnp
```

Expected:

- UFW is active.
- SSH is limited to the intended network path.
- OpenClaw gateway port `18789` is not opened in UFW.
- No surprise public listeners.

Check AppArmor is running in enforce mode:

```bash
sudo aa-status | head -10
```

Expected: a number of profiles in enforce mode. If AppArmor is not running,
investigate before proceeding.

Check auditd is active and review recent events:

```bash
sudo systemctl status auditd
sudo aureport --start today --summary
```

Look for unexpected privilege escalation entries:

```bash
sudo ausearch -k privilege_escalation --start today
```

If you see entries that do not match your own `sudo` activity, investigate.

Check the sudo audit log for unexpected commands:

```bash
sudo tail -50 /var/log/sudo.log
```

Note: `/var/log/sudo.log` may not exist if the system's sudo version does not
support I/O logging (this is common on Ubuntu 26.04). If the file is missing,
use these alternatives instead:

```bash
sudo journalctl -u sudo
# or, if auditd is active:
sudo ausearch -k privilege_escalation
```

## Monthly Security Checks

Run a full security audit and note your hardening score:

```bash
sudo lynis audit system
```

Lynis produces a hardening index score out of 100 and flags specific
recommendations. Run it after bootstrap for a baseline, then again after
major changes. Aim to address any HIGH severity findings.

Scan for rootkits and system binary modifications:

```bash
sudo rkhunter --update
sudo rkhunter --check
```

Review any warnings. Most on a clean system will be false positives — verify
and whitelist them in `/etc/rkhunter.conf` if confirmed safe.

Check rootless Docker is healthy for the bot user:

```bash
sudo -iu lobster
systemctl --user status docker
docker ps
```

If the rootless daemon is not running:

```bash
systemctl --user start docker
```

## Backup Rhythm

Before big changes:

```bash
sudo -iu lobster
openclaw backup create
openclaw backup verify <backup-file>
```

Monthly:

- Create a backup.
- Copy it to the intended private storage location.
- Test restore on a disposable machine when practical.

## Tailscale Hygiene

Monthly:

- Check devices in the Tailscale admin console.
- Remove devices you no longer use.
- Confirm your phone/laptop can still `ssh openclaw`.

## When Something Feels Wrong

Do not keep changing random things.

Use this order:

1. Read the exact error.
2. Check `openclaw status`.
3. Check `openclaw logs`.
4. Check disk space with `df -h`.
5. Check firewall with `sudo ufw status numbered`.
6. See [Troubleshooting](#troubleshooting).
7. Ask for help with redacted logs.

## What To Record

Keep a small change log:

```text
Date:
Changed:
Why:
Command used:
Result:
Rollback plan:
```

This habit makes future troubleshooting much easier.


## Backup and restore

The deployment shell helps users start safely. The lifeboat helps them recover.

## Day-One Backup

After OpenClaw first-run setup and channel/model configuration:

```bash
openclaw backup create
openclaw backup verify <backup-file>
```

Treat backup archives as sensitive. They may contain config, credentials,
workspace data, sessions, and personal context depending on OpenClaw settings.

## Recommended Modes

The first public Tin Lobster restore flow should distinguish these use cases:

- `identity-only`: workspace, identity files, memory/docs, no credentials
- `config-only`: OpenClaw config without channel secrets
- `full-local`: same-machine recovery for trusted personal use
- `migration`: guided restore to a new host with secret/channel review

## Restore Principles

- Verify before applying.
- Show a restore plan before changing files.
- Never overwrite existing state without an explicit flag.
- Do not print secrets while validating.
- Prefer re-linking channels over blindly moving credentials to a new trust boundary.

## Future Helper Commands

Possible wrappers:

```bash
tinlobster backup create
tinlobster backup verify <backup-file>
tinlobster restore plan <backup-file>
tinlobster restore apply <backup-file>
```

These should wrap OpenClaw-native backup tooling instead of inventing a second
state format.


## Troubleshooting

## I cannot SSH after bootstrap

Use the VM console or cloud provider console.

Check:

```bash
sudo ufw status verbose
sudo sshd -t
sudo systemctl status ssh
```

If you used `--harden-ssh`, confirm your key is installed before closing the
original session.

## OpenClaw command not found

Become the bot user and check the path:

```bash
sudo -iu <bot-user>
echo "$PATH"
ls -la ~/.npm-global/bin/openclaw
```

The bootstrap appends `~/.npm-global/bin` to the bot user's `.bashrc`.

## Gateway does not start

Run:

```bash
openclaw config validate
openclaw gateway status
openclaw logs
```

If first-run setup was not completed, run:

```bash
openclaw onboard --install-daemon
```

## UFW blocked something

Tin Lobster intentionally does not open the gateway port.

Check rules:

```bash
sudo ufw status numbered
```

Open new ports only when you understand the exposure.

## Backup failed

Run as the bot user:

```bash
openclaw backup create
openclaw backup verify <backup-file>
```

Backups may contain sensitive data. Do not paste backup contents into tickets or
chat.


## Validation commands

```bash
# as admin, from a Tin Lobster checkout on the host
~/tin-lobster/scripts/validate-tin-lobster.sh --bot-user lobster
~/tin-lobster/scripts/secrets-check.sh --bot-user lobster
~/tin-lobster/scripts/collect-audit-evidence.sh --bot-user lobster --output-dir /tmp
sudo ufw status numbered
ss -ltnp
```

Maintainer test matrix: [reference/testing.md](reference/testing.md).

## Related

- Project security policy: [SECURITY.md](../SECURITY.md)
- [User manual](user-manual.md)
- [Design guide](design-guide.md)
- [SSH how-to](how-to/ssh.md)
- [Remote access](how-to/remote-access.md)
