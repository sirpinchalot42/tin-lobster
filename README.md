# Tin Lobster

Tin Lobster builds a secure, generic Ubuntu shell for OpenClaw.

It is meant for people who want a safer starting point than a hand-built VM,
but who still want to choose their own agent identity, model provider, channels,
plugins, and workflows during OpenClaw first-run setup.

## What This Is

Tin Lobster is infrastructure under OpenClaw:

- Ubuntu 24.04 LTS / 26.04 LTS baseline
- non-root OpenClaw runtime user
- `git` installed for day-two clones and updates
- Node.js 22 from NodeSource
- user-global OpenClaw CLI install
- UFW firewall
- fail2ban
- unattended upgrades
- AppArmor/audit tooling
- optional Docker/containerd for isolated workloads
- optional Tailscale support
- locked-down OpenClaw state permissions
- practical secrets layout + leak-check helpers

Tin Lobster intentionally does **not** choose:

- your model provider
- your Ollama/OpenAI/local model setup
- your Telegram/Discord/channel credentials
- your agent identity or personality
- your backup destination
- public gateway exposure

Those choices happen after bootstrap with OpenClaw's normal setup flow.

## Minimum Requirements

- Ubuntu 24.04 LTS or 26.04 LTS (minimal or server install)
- 1 GB RAM (2 GB recommended for comfortable use)
- 5 GB free disk space (10 GB recommended)
- Internet access during bootstrap (packages downloaded from apt and NodeSource)
- A hypervisor or bare-metal machine with SSH access or console access
- A way to obtain this repo on first boot (`git clone` is preferred; on a brand-new
  Ubuntu minimal host you may need `sudo apt-get install -y git` once before the
  first clone — bootstrap then keeps `git` installed for day-two use)

## Security Stance

Tin Lobster is secure-by-default, not magic.

Defaults:

- OpenClaw gateway port is not opened in UFW.
- The script does not accept gateway tokens as command-line arguments.
- The script does not write channel secrets.
- The script does not configure model provider credentials.
- SSH exposure is profile-based instead of hardcoded to one homelab LAN.
- Re-runs on an already-bootstrapped host are safe by default — existing UFW
  rules are preserved. Use `--force-fresh-host` only for intentional clean reinstalls.
- Pre-flight checks confirm internet access, disk space, and RAM before making
  any changes.
- Operator secrets get a locked-down home layout and a leak-check script.

Use it on a fresh Ubuntu VM, mini PC, or lab machine. Review the script before
running it.

## Quick Start (git-first)

Clone the product, then run the setup wizard. Most people only need this:

```bash
# 1) Get Tin Lobster
git clone https://github.com/sirpinchalot42/tin-lobster.git tin-lobster
cd tin-lobster

# 2) Optional: peek at the script
less docs/user-manual.md

# 3) Run the wizard (recommended for everyone)
sudo bash bootstrap-tin-lobster.sh
```

The wizard asks a few plain-English questions:

1. Bot account name (default: `lobster`)
2. Your admin login (usually auto-detected)
3. Where the machine is (default: home/office network)
4. Optional Tailscale install
5. Who may SSH in — **auto-detected home network; press Enter**

You do **not** need to know CIDR notation. Press Enter to accept defaults.

Then type `TIN LOBSTER` to confirm.

### Advanced / scripted installs

Power users can skip the wizard with flags:

```bash
# Explicit home/office LAN
sudo bash bootstrap-tin-lobster.sh \
  --bot-user lobster \
  --access-profile local-lan \
  --ssh-cidr 192.168.1.0/24

# Tailscale-managed machine
sudo bash bootstrap-tin-lobster.sh \
  --bot-user lobster \
  --access-profile tailnet \
  --install-tailscale

# Cloud VM with narrow admin IP
sudo bash bootstrap-tin-lobster.sh \
  --bot-user lobster \
  --access-profile cloud \
  --ssh-cidr <your-admin-ip-or-cidr>
```

> **Lab reinstall only:** add `--force-fresh-host` when you intentionally want
> UFW reset on a disposable VM. Do **not** use it as the default day-one path.

### Why git-first (not curl one-liner)

- You get docs, scripts, and templates with the installer
- Bootstrap can copy the full reference tree to the bot user
- Workshops can teach “read before run”
- Releases can pin a tag (`v0.1.0-rc.1`) instead of a floating raw file

Public clone:

```bash
git clone https://github.com/sirpinchalot42/tin-lobster.git
cd tin-lobster
```

Tagged releases: `https://github.com/sirpinchalot42/tin-lobster/releases`

## Hypervisor Network Setup

Tin Lobster needs a real IP address on your local network so you can SSH into
it. Each hypervisor has a different way to get there.

**VirtualBox**

Change the adapter from **NAT** to **Bridged Adapter** (Machine → Settings →
Network → Adapter 1 → Bridged Adapter) before installing Ubuntu. Find the VM's
IP with `ip addr` at the console. SSH from your host:
`ssh <user>@<vm-ip-address>`.

**VMware Workstation / Fusion**

Use **Bridged** networking, not NAT. VMware Tools is not required for Tin
Lobster. Find the IP with `ip addr`.

**Proxmox**

VMs get a real IP on your LAN bridge (typically `vmbr0`). Find it at the
Proxmox console or with `qm guest exec <vmid> -- ip addr`. SSH in directly.

**Hyper-V**

Use an **External virtual switch** connected to your physical NIC, not the
Default Switch (which is NAT). Find the IP at the Hyper-V console with
`ip addr`.

**Cloud VMs (AWS, DigitalOcean, Linode, etc.)**

Use the `cloud` access profile with `--ssh-cidr <your-home-ip>/32` or pair
with `--install-tailscale`. The cloud provider's console shows the public IP.

---

If SSH does not work after bootstrap, the most common cause is a NAT network
adapter — switch to Bridged/External and re-run.

## Access Profiles

`local-lan`

Use when the machine sits on a trusted local network. Requires `--ssh-cidr`.

`tailnet`

Use when the machine should be managed through Tailscale. Allows SSH from the
Tailscale CGNAT range and installs/enables Tailscale support when requested.
You still run `sudo tailscale up` yourself.

`cloud`

Use for cloud VMs. It does not assume a private LAN. Provide a narrow
`--ssh-cidr`, or pair it with `--install-tailscale` so SSH is limited to the
Tailscale range.

## After Bootstrap

Log in as the bot user:

```bash
sudo -iu lobster
```

Run OpenClaw onboarding (this is where model/provider/channel secrets belong):

```bash
sudo -iu lobster
openclaw onboard --install-daemon
```

That guided flow configures auth/models (including local options like Ollama),
gateway settings, optional channels, and can install the gateway service.

Confirm:

```bash
openclaw gateway status
openclaw status
openclaw dashboard   # fastest first chat in the Control UI
```

If the daemon was not installed during onboarding:

```bash
openclaw gateway install --port 18789
openclaw gateway start
openclaw gateway status
```

Validate host + secrets hygiene:

```bash
~/tin-lobster/scripts/validate-tin-lobster.sh --bot-user lobster
~/tin-lobster/scripts/secrets-check.sh --bot-user lobster
```

Create the first backup before serious experimentation:

```bash
openclaw backup create
openclaw backup verify <backup-file>
```

Other helpers:

```bash
~/tin-lobster/scripts/first-run-checklist.sh lobster
~/tin-lobster/scripts/init-secrets-layout.sh --bot-user lobster
~/tin-lobster/scripts/collect-audit-evidence.sh --bot-user lobster
~/tin-lobster/scripts/backup-tin-lobster.sh
~/tin-lobster/scripts/restore-tin-lobster.sh --backup <backup-file>
```

## Options

Run `sudo bash bootstrap-tin-lobster.sh --help` for the full reference at any time.

```text
--bot-user <user>        Linux user that will own OpenClaw state. Default: lobster
--admin-user <user>      Your admin SSH account (restricts SSH via AllowUsers).
                         Defaults to $SUDO_USER if detected.
--access-profile <name>  local-lan, tailnet, or cloud
--ssh-cidr <cidr>        CIDR allowed to SSH, e.g. 192.168.1.0/24
--port <port>            Intended OpenClaw gateway port. Default: 18789
--run-upgrade            Run apt-get upgrade during bootstrap
--no-docker              Skip Docker/containerd installation
--install-tailscale      Install Tailscale using the official installer
--add-tailscale          Add Tailscale to an already-bootstrapped host (non-destructive)
--harden-ssh             Disable password SSH after firewall/user setup
--force-fresh-host       Reset UFW and reapply all config from scratch (lab/reinstall)
--uninstall              Remove all Tin Lobster config files and the bot user account
--dry-run                Print actions without changing the host
--yes                    Accept the preflight confirmation prompt
-h, --help               Show full usage
```

The script is safe to re-run on an already-bootstrapped host — it will add
missing config without resetting the firewall or destroying bot state. Use
`--force-fresh-host` only when you want a clean slate on a disposable VM.

By default, the bootstrap prints a preflight summary and asks you to type
`TIN LOBSTER` before changing the host. Use `--yes` only for reviewed scripted
installs.

## Docs

| Doc | What it is |
|-----|------------|
| [docs/design-guide.md](docs/design-guide.md) | Big picture (short) |
| [docs/user-manual.md](docs/user-manual.md) | Install + everyday use |
| [docs/admin-guide.md](docs/admin-guide.md) | Operator manual / troubleshooting |
| [docs/README.md](docs/README.md) | Full docs index |
| [SECURITY.md](SECURITY.md) | Security policy |
| [CHANGELOG.md](CHANGELOG.md) | Releases |
| [CONTRIBUTING.md](CONTRIBUTING.md) | How to help |

How-tos: [SSH](docs/how-to/ssh.md) · [Remote access](docs/how-to/remote-access.md)

Identity starters live in `templates/`.

Roadmap: [TODO.md](TODO.md) · version: [VERSION](VERSION)

## Project Direction

The public Tin Lobster project has two parts:

1. **Deployment Shell:** a secure OpenClaw-ready Ubuntu base.
2. **Lifeboat:** backup/restore + secrets hygiene so new users can recover safely.

Private owner identity files, personal notes, local lab hostnames, and
model-provider assumptions do not belong in the generic public bootstrap.

Owner-specific bot identity material belongs in a private profile/showcase
repo, not in Tin Lobster core.

## License

Tin Lobster is free and open source under the **MIT License**.

- Use it, copy it, modify it, share it.
- Commercial use is allowed.
- Keep the copyright and license notice.
- No warranty — use at your own risk.

Charging for **support, workshops, or events** is separate from this software
license and is allowed.

See [`LICENSE`](LICENSE) for the full text.
