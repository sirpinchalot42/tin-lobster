# Admin guide

Operator reference for a Tin Lobster host: full stack from hypervisor to
OpenClaw runtime, day-two care, backup/restore, and troubleshooting.

Use this when you need to **fix, harden, or operate** the machine without
hand-holding. For first install, use the [user manual](user-manual.md). For the
short architecture picture, see the [design guide](design-guide.md).

## Contents

- [Stack map](#stack-map)
- [Host and hypervisor](#host-and-hypervisor)
- [Roles and access](#roles-and-access)
- [Security model](#security-model)
- [OpenClaw alignment](#openclaw-alignment)
- [Host hardening](#host-hardening)
- [Bot runtime and permissions](#bot-runtime-and-permissions)
- [Secrets and state](#secrets-and-state)
- [Operator hygiene](#operator-hygiene)
- [Day-two operations](#day-two-operations)
- [Backup and restore](#backup-and-restore)
- [Troubleshooting](#troubleshooting)
- [Validation and evidence](#validation-and-evidence)
- [Upstream watch](reference/upstream-watch.md)

---

## Stack map

Bottom to top — each layer has one job:

```text
Your devices (laptop / phone)
  -> private path (home LAN and/or Tailscale)
    -> Hypervisor or cloud (VM boundary, console, snapshots)
      -> Ubuntu guest (the lobster host)
        -> admin user (you: SSH + sudo)
        -> bot user (OpenClaw only: no sudo, no SSH)
          -> OpenClaw gateway (loopback by default)
             + optional rootless Docker
          -> ~/.openclaw state, credentials, secrets
          -> chat apps / Control UI
```

| Layer | Who owns it | This guide |
|-------|-------------|------------|
| Devices + private path | you | [Roles and access](#roles-and-access), [how-to/remote-access](how-to/remote-access.md) |
| Hypervisor / cloud VM | you | [Host and hypervisor](#host-and-hypervisor) |
| Ubuntu host hardening | Tin Lobster bootstrap | [Host hardening](#host-hardening) |
| Admin vs bot identity | Tin Lobster bootstrap | [Roles and access](#roles-and-access) |
| OpenClaw runtime | OpenClaw | [Bot runtime](#bot-runtime-and-permissions), [Day-two](#day-two-operations) |
| Secrets + backups | you + OpenClaw | [Secrets](#secrets-and-state), [Backup](#backup-and-restore) |

Tin Lobster owns the **Ubuntu host shell**. OpenClaw owns the **agent runtime**.
Stay current with both.

---

## Host and hypervisor

### Why a VM

Tin Lobster is built as a **dedicated bot appliance**. Recommended shape:

- one OpenClaw bot per Ubuntu VM (or bare metal only if you deliberately want that)
- the **VM boundary is the outer security perimeter**
- console access and snapshots are first-class recovery tools

A dedicated VM means root on the guest is painful, not automatically game-over
for your whole house or daily desktop. Compromising the bot still has to cross
a hypervisor (or cloud) boundary to reach other workloads.

Bare metal is supported for operators who know why they want it. It is **not**
the default teaching path.

### Any serious hypervisor is fine

Pick what you already have and how serious the bot is. Brand does not matter;
**isolation, console recovery, and a real network path** do.

| Situation | Typical pick | Why |
|-----------|--------------|-----|
| Learning / laptop lab | **VirtualBox** | Free, simple snapshots, easy undo |
| Windows desktop lab | **Hyper-V** | Built-in; good enough for a personal bot |
| Homelab / always-on | **Proxmox** (or similar) | Best long-term ops: console, snapshots, backups |
| Already in a cloud account | Cloud VM | Provider console = recovery; use `cloud` profile |
| Only one PC available | VM on that PC still preferred | Keeps the bot out of your daily OS |

Also fine: VMware Workstation/Fusion, other KVM front-ends, and similar. Same
rules apply.

### Non-negotiables (every hypervisor)

1. **Bridged / external networking** so the guest gets a real reachable IP — not
   NAT-only — unless you intentionally run Tailscale-only access.
2. **Console access before you harden SSH** (VirtualBox window, Hyper-V console,
   Proxmox console, cloud serial/VNC). If SSH breaks, console is the lifeboat.
3. **Snapshot before bootstrap** and before major OpenClaw or host upgrades.
4. **One bot appliance per VM** — do not share the guest with random other
   multi-user services.

Click-by-click NIC setup lives in the root
[README hypervisor section](../README.md#hypervisor-network-setup)
(VirtualBox, VMware, Proxmox, Hyper-V, cloud). This guide owns the *why* and
the operator checklist; the README owns the buttons.

### Recovery path (ask before every lock-down)

Before changing SSH, firewall, Tailscale, or gateway bind:

```text
If this breaks, how do I get back in?
```

Acceptable answers: VM console, Proxmox/Hyper-V/VBox console, cloud provider
console, physical keyboard/monitor, or another working admin SSH session.

Bad answer: “I hope it works.”

---

## Roles and access

### Two users, one machine

| Role | Who | sudo | SSH login | Purpose |
|------|-----|------|-----------|---------|
| Admin | you (OS install account) | yes | yes | manage the host |
| Bot (default `lobster`) | service account | no | no | run OpenClaw only |

```text
Your laptop
  -> SSH (admin user, key-authenticated)
       -> sudo -iu lobster
            -> openclaw / docker (rootless) commands
```

Even if OpenClaw were compromised, the attacker starts inside a low-privilege
account with no direct root path and no SSH inbox.

### SSH keys

Keys are generated on **your laptop**. Public key → admin
`~/.ssh/authorized_keys` on the server. Private key never leaves your devices.

- Never SSH as root — `PermitRootLogin no`
- Never SSH as the bot — `AllowUsers` is admin-only
- Never share or paste the private key

Platform setup: [SSH how-to](how-to/ssh.md).

### Access profiles

| Profile | SSH path | Best for |
|---------|----------|----------|
| `local-lan` | supplied LAN CIDR (e.g. `192.168.1.0/24`) | home lab / office |
| `tailnet` | Tailscale CGNAT `100.64.0.0/10` (+ Tailscale install) | reach from anywhere on your tailnet |
| `cloud` | narrow CIDR and/or Tailscale; no LAN assumption | VPS |

Profiles can combine: e.g. `local-lan` plus Tailscale later via
`--add-tailscale`. Remote path detail: [remote access](how-to/remote-access.md).

### Assumptions

- One trusted human owns the host.
- Fresh Ubuntu **24.04 or 26.04** LTS guest.
- OpenClaw is powerful and may receive local tool access.
- Messaging channels and backups can hold personal data.
- Gateway is not internet-exposed by default.
- Dedicated bot VM (see [Host and hypervisor](#host-and-hypervisor)).

---

## Security model

Tin Lobster creates a defensive **personal-agent** baseline. It is not a
guarantee, and it is not hostile multi-tenant isolation.

It matches OpenClaw’s published trust model: **one trusted operator boundary per
gateway**. Shared or adversarial multi-user setups need separate gateways
(ideally separate OS users/hosts), not one wide-open bot.

Defaults worth memorizing:

- Gateway port **18789** is **not** opened in UFW
- No API tokens or channel secrets as bootstrap flags
- SSH exposure is profile-based
- Backups and credentials are full-trust material
- Day-one path includes `openclaw doctor` + `openclaw security audit`

Official references:

- [OpenClaw security](https://docs.openclaw.ai/gateway/security)
- [Exposure runbook](https://docs.openclaw.ai/gateway/security/exposure-runbook)
- [Install](https://docs.openclaw.ai/install) · [Updating](https://docs.openclaw.ai/install/updating)
- Project policy: [SECURITY.md](../SECURITY.md)

### What this shell does not cover

- Public gateway exposure (deliberately out of scope)
- Automatic channel login or model-provider credentials (OpenClaw wizard)
- Moving secrets between machines (user-reviewed)
- Replacing OpenClaw backup / doctor / security tooling
- Custom AppArmor profile for Node/OpenClaw (nice later; workload-specific)
- Remote syslog (logs are local; a fully compromised host can wipe them)
- File integrity monitoring such as AIDE (good high-value add-on)

---

## OpenClaw alignment

Aligned to **OpenClaw 2.x** (`2026.8.x` line and current docs). Tin Lobster still
owns the **host shell**; OpenClaw owns agent brain, channels, memory, and optional
multiplayer/cloud placement.

| Concern | Tin Lobster | OpenClaw |
|---------|-------------|----------|
| OS user split, UFW, SSH profiles | yes | n/a |
| Node runtime floors | enforces supported set | requires 22.22.3+ / 24.15+ / 25.9+ (26 recommended; 23 unsupported) |
| CLI install | `npm install -g openclaw@latest` (+ `--allow-scripts=openclaw` when npm needs it) | same contract in install docs |
| First-run brain setup | points you here | `openclaw onboard --install-daemon` |
| First conversation surface | documents | Control UI via `openclaw dashboard` (chat-first in 2.x) |
| Day-two package updates | documents | prefer `openclaw update` |
| Posture checks | host validate + secrets-check | `openclaw doctor` (+ optional `--fix`), `openclaw security audit` |
| Memory embeddings | not configured by bootstrap | separate from chat model; local llama.cpp or API embeddings |
| Multiplayer / cloud workers | out of scope for bootstrap | optional OpenClaw features after a solid local gateway |
| Secrets in chat | discouraged | prefer masked credential requests / SecretRefs |

Before exposing the gateway beyond loopback, or allowing multi-person messaging,
run OpenClaw’s exposure checklist and deep audit. Maintainers track drift in
[Upstream watch](reference/upstream-watch.md).

**Workshop note:** chat provider (for example Grok-only) does **not** imply
working semantic memory. Teach `openclaw memory status` after upgrades.

---

## Host hardening

Canonical reference for what bootstrap applies. Other sections link here instead
of restating.

### Firewall (UFW)

- Default deny incoming
- SSH only from the selected network (LAN CIDR, Tailscale range, or both)
- OpenClaw gateway port **not** opened — loopback, Tailscale, or a reverse
  proxy you deliberately add
- UFW logging on; IPv4 and IPv6 rules together (no IPv6 bypass)

### SSH daemon

- `PermitRootLogin no`
- `AllowUsers <admin>`
- `MaxAuthTries 3`
- `LoginGraceTime 30`
- `PermitEmptyPasswords no`
- `ClientAliveInterval 300`
- `MaxSessions 3`
- `UseDNS no`
- `AcceptEnv LANG LC_*` only
- `AuthorizedKeysFile .ssh/authorized_keys`
- Key-only mode via `--harden-ssh` (only after key login works)

### Root account locked

`passwd -l root` during bootstrap. Combined with `PermitRootLogin no`, root is
unreachable by SSH and by local password `su`.

### fail2ban

SSH failures: 3 strikes in 10 minutes → 1-hour ban. Backstop if SSH is ever
opened wider than intended.

### Kernel hardening (sysctl)

`/etc/sysctl.d/99-tin-lobster.conf` at boot:

- ICMP redirects and source routing rejected
- Reverse path filtering (`rp_filter=1`)
- Martians logged; SYN cookies on
- `vm.mmap_min_addr=65536`
- ASLR level 2; symlink/hardlink restrictions
- `kptr_restrict=2`; `dmesg` root-only
- BPF JIT hardening; unprivileged BPF off
- `perf_event_paranoid` restricted
- **`kernel.yama.ptrace_scope=2`** — non-root processes cannot inspect other
  processes’ memory (protects in-memory API keys/tokens held by OpenClaw)

### sudo hardening

`/etc/sudoers.d/99-tin-lobster`:

- `use_pty` (blocks a class of fd-hijack tricks through sudo)
- audit log at `/var/log/sudo.log` when the sudo build supports I/O logging
- `timestamp_timeout=1`
- `!visiblepw`

### Audit logging (auditd)

Rules loaded and made immutable at boot (reboot to change):

- changes to passwd/shadow/group, sudoers, SSH config
- login/logout events
- access to the bot credentials directory
- non-root processes gaining root euid (privilege-escalation signal)

Logs: `/var/log/audit/audit.log`. Query with `ausearch` / `aureport`.

### AppArmor

Enforce mode at boot; shipped Ubuntu profiles enforced. Limits blast radius
independent of Unix permissions.

### Docker — rootless for the bot

The bot runs **rootless Docker**: a personal dockerd under the bot UID. **No
`docker` group** — membership is effective root (`docker run -v /:/host …`
chroot escape).

```text
Bot user process space
  -> rootless dockerd (bot UID)
       -> containers (user-namespace mapped to bot UIDs)
```

A container escape lands back in the bot account, not host root.

System Docker (admin via `sudo docker`) is also tightened: `icc: false`,
`no-new-privileges: true`, log rotation.

Escalation chain on a dedicated VM:

```text
Compromise bot
  -> container escape (needs kernel exploit)
  -> root on dedicated VM
  -> VM escape (needs hypervisor exploit)
  -> hypervisor / cloud host
```

Two hard steps, not zero — which is why the VM boundary matters
([Host and hypervisor](#host-and-hypervisor)).

### Session and resource limits

- Interactive shells: `TMOUT=900` (15 minutes). Does **not** stop the gateway
  service.
- Bot user: nproc 512 soft / 1024 hard; nofile 4096 soft / 8192 hard.

### Attack surface reduction

Removed/pinned if present: **snapd** (pinned priority -10), **whoopsie**,
**apport**, **popularity-contest**.

Disabled if present: **cups**, **avahi-daemon**, **bluetooth**.

### Security audit tools

- **lynis** — `sudo lynis audit system` (hardening index)
- **rkhunter** — `sudo rkhunter --check` (rootkit / binary drift)

### Unattended upgrades

Security patches applied automatically on a daily cadence.

---

## Bot runtime and permissions

The bot user (default `lobster`) runs OpenClaw and nothing that needs root.

### What the bot can do alone

| Action | Why |
|--------|-----|
| Run the OpenClaw gateway | process owned by bot user |
| Install/upgrade npm packages | `~/.npm-global` — no root |
| Read/write workspace | `~/.openclaw/` owned by bot |
| Outbound network | UFW allows outbound |
| `tools.exec` | runs as bot user |
| Restart gateway | `openclaw gateway restart` |
| Create/verify backups | OpenClaw backup on bot-owned files |
| Run Docker containers | rootless Docker (see [hardening](#docker--rootless-for-the-bot)) |

### Rootless Docker — operator use

```bash
# as bot user
docker run hello-world
docker ps
systemctl --user status docker
systemctl --user start docker   # if needed after fresh login
loginctl show-user "$USER" | grep Linger   # expect Linger=yes
```

`DOCKER_HOST` is set in the bot `~/.bashrc` to the rootless socket:

```bash
DOCKER_HOST=unix:///run/user/<uid>/docker.sock
```

### What needs a human admin

| Need | Admin action |
|------|----------------|
| System packages | `sudo apt-get install …` |
| Privileged ports (<1024) | gateway default 18789 is fine; only change `ip_unprivileged_port_start` if you truly need it |
| Firewall / SSH config | bot cannot touch `/etc` |
| System Node/Python replacement | bot may use user-level npm only |
| Host devices / GPU | group memberships or udev rules |

### Resource limits (symptoms)

Normal OpenClaw is nowhere near nproc/nofile caps. If you see
`fork: retry: Resource temporarily unavailable`:

```bash
ps -u lobster --no-headers | wc -l
# if stuck near 512, something is misbehaving:
sudo pkill -u lobster
```

### ptrace and debuggers

`ptrace_scope=2` is system-wide ([hardening](#kernel-hardening-sysctl)). Tools
that need ptrace must run as root via sudo. Normal bot operation never needs
this.

### Quick reference

```text
apt-get install?     No  → admin
docker?              Yes → rootless, no docker group
sudo?                No
SSH in as bot?       No
inspect other procs? No  → ptrace_scope=2
npm packages?        Yes → ~/.npm-global
~/.openclaw write?   Yes
outbound network?    Yes
TMOUT kills gateway? No  → service, not a shell
```

---

## Secrets and state

Clear layout, strict permissions, no accidental leaks. Graduate to Vault-class
tools later without throwing this away.

### Three buckets

| Bucket | Owner | Examples | Where |
|--------|-------|----------|--------|
| OpenClaw credentials | OpenClaw wizard/runtime | channel tokens, gateway auth | `~/.openclaw/credentials/` + config |
| Operator secrets | you | extra tool API keys, rotation notes | `~/.openclaw/secrets/` |
| Public repo / docs | git | install steps, templates | this repository |

**Rule:** secrets never live in the public Tin Lobster tree, workshop slides,
screenshots, or chat.

### What bootstrap creates

```text
~/.openclaw/
  credentials/     # OpenClaw-managed (700)
  secrets/         # operator helper area (700)
    README
    env.example
    .gitignore
```

Targets: directories `700`, secret files `600`. Bootstrap does **not** ask for API
keys — intentional.

### Day-one secret flow

1. Bootstrap host.
2. `sudo -iu lobster`
3. `openclaw onboard --install-daemon` — enter provider/channel secrets **only** here.
4. Optional operator env:

```bash
cp ~/.openclaw/secrets/env.example ~/.openclaw/secrets/env.local
chmod 600 ~/.openclaw/secrets/env.local
nano ~/.openclaw/secrets/env.local
```

5. Leak check:

```bash
~/tin-lobster/scripts/secrets-check.sh --bot-user lobster
```

6. Doctor, audit, verified backup:

```bash
openclaw doctor
openclaw security audit
mkdir -p ~/Backups/openclaw
openclaw backup create --output ~/Backups/openclaw --verify
# older builds:
# openclaw backup create && openclaw backup verify <backup-file>
```

### Common secret types

- **Model provider keys** — OpenClaw guided setup; extras in `env.local` mode 600
- **Channel tokens** — OpenClaw setup only; rotate if they hit screenshots, tickets, history, or git
- **Gateway auth** — leave UFW closed on 18789; do not open it “to make demos easier”
- **SSH private keys** — admin devices only; public keys on server

### Leak check

`scripts/secrets-check.sh` looks for world-readable `~/.openclaw` files, token-like
strings in workspace markdown, loose `.env` modes, private keys wider than 600,
secrets dirs not 700, and secret-looking strings under `~/tin-lobster` copies.

Run after first setup, before sharing logs, before cloning a profile to a new
machine, and as workshop definition-of-done.

### Secret managers (growth path)

| Stage | Tooling | When |
|-------|---------|------|
| v0 (now) | OpenClaw credentials + `~/.openclaw/secrets` + leak check | personal bot / club workshop |
| v1 | encrypted off-host copy (`age` / `sops`) | multi-machine recovery |
| v2 | systemd `EnvironmentFile=` + restricted service user | always-on env injection |
| v3 | 1Password / Bitwarden / Vault + short-lived tokens | team / higher threat |

### Safe help requests

Share: redacted errors, Ubuntu version, Tin Lobster/OpenClaw version,
secrets-check **summary** (not file contents).

Never share: `env.local`, `~/.openclaw/credentials/*`, gateway tokens, channel
tokens, private keys, unredacted config dumps, backup archives.

### Workshop script (60 seconds)

1. Secrets are radioactive.
2. Wizard is the front door; chat is not.
3. `~/.openclaw/secrets` is for operator extras only.
4. Run `secrets-check.sh` before you celebrate.
5. Backups are secret packages, not trophies.

Related: [SECURITY.md](../SECURITY.md), `scripts/secrets-check.sh`,
`scripts/init-secrets-layout.sh`.

---

## Operator hygiene

Short checklist — beginner teaching voice lives in the
[user manual](user-manual.md).

1. Keep private keys private; tokens out of chat and screenshots.
2. Do not expose ports to the internet unless you can name the reason and the rollback.
3. Prefer Tailscale (or similar) over router port-forwards for remote admin.
4. Backup before experiments and before major updates.
5. Enter channel/provider secrets through OpenClaw setup — not bootstrap flags.
6. Run `scripts/secrets-check.sh` before sharing logs.
7. When asking for help: errors and versions, not secrets or full configs.

**Usually safe to share:** public `.pub` keys, redacted errors, OpenClaw/Ubuntu
versions, Tin Lobster commit, UFW status without sensitive annotations.

**Never share:** private keys, API keys, gateway/channel tokens, `.env` files,
unredacted OpenClaw config, backups, screenshots with QR codes or credentials.

---

## Day-two operations

Day one is install. Day two is keeping the bot healthy.

### Daily or before a demo

```bash
ssh openclaw          # or ssh admin@vm-ip
uptime && df -h && free -h
sudo -iu lobster
openclaw status
openclaw gateway status
```

### Restart gateway (bot user)

```bash
openclaw gateway status
openclaw gateway restart
openclaw status
# if restart missing on older builds:
# openclaw gateway stop && openclaw gateway start
```

### Update the host (admin)

```bash
sudo apt update
sudo apt upgrade
# reboot only when the system says so, in a quiet window
```

### Update OpenClaw (bot user)

Prefer the supervised updater:
[Updating](https://docs.openclaw.ai/install/updating).

```bash
sudo -iu lobster
mkdir -p ~/Backups/openclaw
openclaw backup create --output ~/Backups/openclaw --verify
openclaw update          # optional: openclaw update --dry-run
openclaw --version
openclaw doctor
openclaw gateway restart
openclaw health
openclaw status
```

Manual npm is **recovery**, not the default path. npm 11.16+ / 12:

```bash
openclaw gateway stop
npm install -g openclaw@latest --allow-scripts=openclaw
openclaw gateway install --force
openclaw gateway restart
openclaw doctor
```

Older npm (≤11.15): omit `--allow-scripts=openclaw`. If docs disagree with this
guide for your version, trust current OpenClaw docs.

### Before you expose anything

Port 18789 stays closed in UFW by default. Tailscale Serve, LAN bind, reverse
proxy, or multi-person DMs are deliberate exposure changes:

1. Inventory who can reach the gateway and which tools the agent has.
2. Prefer loopback + SSH tunnel or Tailscale over public ports.
3. Keep DMs on pairing/allowlist; avoid `dmPolicy: open` with powerful tools.
4. Multi-person DMs: `session.dmScope: "per-channel-peer"`.
5. Run:

```bash
openclaw doctor
openclaw security audit
openclaw security audit --deep
openclaw health
```

6. Follow the
   [exposure runbook](https://docs.openclaw.ai/gateway/security/exposure-runbook)
   and keep rollback (loopback bind, tighter DM policy, token rotation).

### Cadence: weekly / monthly

**Host + OpenClaw posture (regularly):**

```bash
# bot user
openclaw doctor
openclaw security audit

# admin / checkout on host
~/tin-lobster/scripts/validate-tin-lobster.sh --bot-user lobster
~/tin-lobster/scripts/secrets-check.sh --bot-user lobster
sudo ufw status numbered
ss -ltnp
sudo aa-status | head -10
sudo systemctl status auditd --no-pager
sudo aureport --start today --summary
sudo ausearch -k privilege_escalation --start today
sudo tail -50 /var/log/sudo.log 2>/dev/null || sudo journalctl -u sudo -n 50 --no-pager
```

Expected: UFW active; SSH limited to intended path; **18789 not open in UFW**;
no surprise public listeners; AppArmor enforce profiles present.

**Monthly:**

```bash
sudo lynis audit system
sudo rkhunter --update && sudo rkhunter --check
sudo -iu lobster
systemctl --user status docker
docker ps
```

Address HIGH lynis findings. Whitelist confirmed-safe rkhunter noise in
`/etc/rkhunter.conf`.

**Tailscale hygiene (monthly):** prune dead devices in the admin console; confirm
`ssh openclaw` still works from phone/laptop.

**Backup rhythm:** before big changes; monthly copy off-host to private storage;
test restore on a disposable VM when practical. See
[Backup and restore](#backup-and-restore).

### When something feels wrong

1. Read the exact error.
2. `openclaw status` / `openclaw logs`
3. `df -h`
4. `sudo ufw status numbered`
5. [Troubleshooting](#troubleshooting)
6. Ask with redacted logs only.

### Change log habit

```text
Date / Changed / Why / Command / Result / Rollback plan
```

---

## Backup and restore

The shell starts you safely. The lifeboat gets you back.

### Day-one and pre-change backup

As bot user, after onboard (and before major updates):

```bash
mkdir -p ~/Backups/openclaw
openclaw backup create --output ~/Backups/openclaw --verify
```

Fallback:

```bash
openclaw backup create
openclaw backup verify <backup-file>
```

Optional wrapper (same idea, reminders included):

```bash
~/tin-lobster/scripts/backup-tin-lobster.sh
```

Treat every archive as **full-trust material** (config, credentials, sessions,
personal context depending on settings). Encrypt or lock the storage location.
Do not email backups to yourself “for safety.”

### Restore principles

- Verify before applying.
- Prefer a printed plan before changing files.
- Never overwrite live state without an explicit decision.
- Do not print secrets while validating.
- Prefer re-linking channels over blindly copying credentials across trust
  boundaries (new host, new threat model).

Helper (plan by default):

```bash
~/tin-lobster/scripts/restore-tin-lobster.sh --backup <file>
# only after you read the plan and confirm host/trust boundary:
~/tin-lobster/scripts/restore-tin-lobster.sh --backup <file> --apply
```

### Restore modes (how to think about it)

| Mode | Intent |
|------|--------|
| identity-only | workspace / identity / memory docs — no credentials |
| config-only | OpenClaw config without channel secrets |
| full-local | same-machine recovery for trusted personal use |
| migration | new host with explicit secret and channel review |

OpenClaw-native backup is the source of truth today. Tin Lobster wrappers add
guardrails; they do not invent a second state format.

---

## Troubleshooting

### Logs and services map

| Question | Where |
|----------|--------|
| OpenClaw app / gateway | `openclaw logs`, `openclaw gateway status` (bot user) |
| Gateway unit | bot user systemd/user units via OpenClaw install |
| SSH / sudo / generic system | `journalctl -u ssh`, `journalctl -u sudo` |
| Firewall | `sudo ufw status verbose` |
| Audit / privilege signals | `/var/log/audit/audit.log`, `ausearch`, `aureport` |
| Sudo I/O log (if supported) | `/var/log/sudo.log` |
| Rootless Docker | `systemctl --user status docker` (bot user) |
| Disk full | `df -h`, `du -sh ~/.openclaw ~/Backups` (bot) |

### Cannot SSH after bootstrap

Use the VM/cloud console ([recovery path](#recovery-path-ask-before-every-lock-down)).

```bash
sudo ufw status verbose
sudo sshd -t
sudo systemctl status ssh
```

If you used `--harden-ssh`, confirm the key works before closing the original
session.

### OpenClaw command not found

```bash
sudo -iu <bot-user>
echo "$PATH"
ls -la ~/.npm-global/bin/openclaw
```

Bootstrap appends `~/.npm-global/bin` to the bot `.bashrc`.

### Gateway does not start

```bash
openclaw config validate
openclaw gateway status
openclaw logs
# if onboard never finished:
openclaw onboard --install-daemon
```

### UFW blocked something

Gateway port is intentionally closed. Inspect with
`sudo ufw status numbered`. Open ports only when you understand exposure and
rollback.

### Docker commands fail (bot user)

```bash
systemctl --user status docker
systemctl --user start docker
loginctl show-user "$USER" | grep Linger
echo "$DOCKER_HOST"
```

### Disk pressure

```bash
df -h
sudo -iu lobster
du -sh ~/.openclaw ~/Backups ~/.npm-global 2>/dev/null
docker system df   # if rootless docker in use
```

### Backup failed

Run as bot user; verify path; never paste archive contents into chat.

```bash
openclaw backup create
openclaw backup verify <backup-file>
```

---

## Validation and evidence

```bash
# as admin, from a Tin Lobster checkout on the host
~/tin-lobster/scripts/validate-tin-lobster.sh --bot-user lobster
~/tin-lobster/scripts/secrets-check.sh --bot-user lobster
~/tin-lobster/scripts/collect-audit-evidence.sh --bot-user lobster --output-dir /tmp
~/tin-lobster/scripts/first-run-checklist.sh lobster
sudo ufw status numbered
ss -ltnp
```

| Script | Role |
|--------|------|
| `validate-tin-lobster.sh` | host posture checks |
| `secrets-check.sh` | permission / leak heuristics |
| `init-secrets-layout.sh` | (re)create secrets dirs safely |
| `first-run-checklist.sh` | day-one definition of done |
| `collect-audit-evidence.sh` | bundle evidence for review |
| `backup-tin-lobster.sh` | backup reminder wrapper |
| `restore-tin-lobster.sh` | verify/plan restore; optional apply |

Maintainer test matrix and release gate:
[reference/testing.md](reference/testing.md).

---

## Related

- [SECURITY.md](../SECURITY.md) — project security policy
- [User manual](user-manual.md) — install and first use
- [Design guide](design-guide.md) — short architecture
- [SSH how-to](how-to/ssh.md)
- [Remote access](how-to/remote-access.md)
- [Upstream watch](reference/upstream-watch.md)
- [Testing / release gate](reference/testing.md)
