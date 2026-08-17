# User manual

From a fresh Ubuntu machine to “I can talk to my bot,” plus everyday use after
setup.

If you only read one long doc, read this. For the big picture, see the
[design guide](design-guide.md). For deep troubleshooting and hardening detail,
see the [admin guide](admin-guide.md).

## Who this is for

People standing up their own OpenClaw host who want clear steps without living
in the operator weeds every day.

## Before you start

- Ubuntu **24.04 or 26.04** LTS (VM recommended)
- Bridged/external networking so the VM gets a real LAN IP (not NAT-only)
- Ability to log in as the first admin user
- About 20–40 minutes for a careful first run

This is the short path from "fresh Ubuntu machine" to "I can talk to my
OpenClaw bot."

Tin Lobster teaches real operations. Some steps are technical on purpose, but
each step should explain what you are doing and why.

## The Journey

1. Create a fresh Ubuntu 24.04/26.04 VM, mini PC, or cloud VM.
2. Make sure you can log in as the first admin user.
3. Clone Tin Lobster and run the **Tin Lobster** setup wizard.
4. Log in as the OpenClaw bot user.
5. Run **OpenClaw onboarding** (model, gateway, channels, secrets).
6. Confirm the gateway is running.
7. Validate host + secrets hygiene.
8. Send the first test message (chat app or Control UI).
9. Make a verified backup before serious experiments.
10. Set up SSH shortcuts / Tailscale from your real devices.

## What Tin Lobster Does

Tin Lobster prepares the machine under OpenClaw:

- Creates a non-root OpenClaw user.
- Installs the OpenClaw CLI.
- Installs Node.js, git, and baseline packages.
- Turns on firewall and security tooling.
- Keeps the OpenClaw gateway closed to the public network.
- Creates a locked-down secrets layout and leak-check helpers.
- Leaves model provider, channels, identity, and credentials to OpenClaw.

## What Tin Lobster Does Not Do

Tin Lobster does not:

- Pick your model provider (cloud API, Ollama, etc.).
- Enter Telegram, Discord, OpenAI, or other secrets.
- Expose your gateway to the internet.
- Replace your need to understand SSH, backups, and updates.

## Before You Run Bootstrap

**Check your network adapter.** The most common first-timer problem is a NAT
network adapter — Tin Lobster needs the VM to have a real IP on your local
network so you can SSH into it. Use Bridged or External mode in your
hypervisor. See the README hypervisor section.

**Check minimum requirements.** You need at least 1 GB RAM, 5 GB free disk,
and internet access. See the README minimum requirements.

## Run The Tin Lobster Wizard

On the fresh Ubuntu machine:

```bash
# On a brand-new Ubuntu minimal host, install git once if needed:
# sudo apt-get update && sudo apt-get install -y git

git clone https://github.com/sirpinchalot42/tin-lobster.git tin-lobster
cd tin-lobster

# Tin Lobster host wizard (recommended)
sudo bash bootstrap-tin-lobster.sh
```

That is the whole beginner host command. No networking flags required.

### What the Tin Lobster wizard asks

Press **Enter** to accept each default unless you know you need something else:

1. **Bot account name** — default `lobster`
2. **Your admin login** — usually detected automatically
3. **Where is this machine?** — default home/office network
4. **Install Tailscale?** — default no (you can add it later)
5. **Who may SSH in?** — auto-detects your home network; press Enter

You do **not** need to understand CIDR, subnets, or firewall rules.

When the preflight summary looks right, type:

```text
TIN LOBSTER
```

That phrase confirms the script may change the machine.

### Advanced only

If you prefer flags instead of the Tin Lobster wizard:

```bash
sudo bash bootstrap-tin-lobster.sh \
  --bot-user lobster \
  --access-profile local-lan \
  --ssh-cidr 192.168.1.0/24
```

> **Not the default:** `--force-fresh-host` resets UFW and re-applies host
> config from scratch. Use it on disposable lab VMs when you intentionally want
> a clean reinstall — not for first-time installs that already look healthy.

## First Login As The Bot User

After bootstrap:

```bash
sudo -iu lobster
```

If you used a different bot user, replace `lobster` with that name.

All remaining OpenClaw commands in this guide are run **as the bot user**.

## OpenClaw Onboarding (current path)

OpenClaw has moved first-run setup to a guided onboarding flow.

Recommended:

```bash
openclaw onboard --install-daemon
```

That walks you through:

- local vs remote gateway mode (choose **local** for a home bot)
- model / auth (cloud providers **or local options like Ollama**)
- gateway settings (port defaults to **18789**, loopback is fine)
- optional channel setup (Telegram, Discord, etc.)
- installing the gateway service (`--install-daemon`)

### What to expect in the wizard

OpenClaw onboarding may offer **QuickStart** vs **Advanced**:

- **QuickStart** — good defaults for a personal local bot
- **Advanced** — more control over every step

You can point the model at:

- a cloud provider API key, or
- a local stack such as **Ollama** on your home network / same machine

Enter secrets **only** in this onboarding flow (or OpenClaw's official config
commands). Do **not** paste tokens into group chats, screenshots, or public
help tickets.

### Useful related commands

```bash
# Re-run or adjust config later
openclaw configure

# Older alias still works on many installs
openclaw setup --wizard

# Repair / health suggestions
openclaw doctor
```

Need operator extras later (tool API keys outside OpenClaw)? Use:

```bash
~/tin-lobster/scripts/init-secrets-layout.sh --bot-user lobster
cp ~/.openclaw/secrets/env.example ~/.openclaw/secrets/env.local
chmod 600 ~/.openclaw/secrets/env.local
```

Read: `admin-guide.md#secrets`

## Confirm The Gateway

If you used `--install-daemon`, the gateway service should already be installed.
Check it:

```bash
openclaw gateway status
openclaw status
```

If the service is not installed yet:

```bash
openclaw gateway install --port 18789
openclaw gateway start
openclaw gateway status
```

Tin Lobster does **not** open port `18789` in the firewall. That is intentional.
The gateway stays on loopback / private access unless you deliberately change
that later.

## Talk To The Bot

Fastest first chat (no phone channel required):

```bash
openclaw dashboard
```

That opens the Control UI. Send a test message there.

Or use a chat channel you configured during onboarding (Telegram, Discord,
etc.) and send a small test message from your phone/desktop.

## Validate Before You Celebrate

```bash
~/tin-lobster/scripts/validate-tin-lobster.sh --bot-user lobster
~/tin-lobster/scripts/secrets-check.sh --bot-user lobster
~/tin-lobster/scripts/first-run-checklist.sh lobster
```

## Make The First Backup

Before experimenting:

```bash
openclaw backup create
openclaw backup verify <backup-file>
```

Backups can contain private bot data. Treat them like sensitive files.

## Make SSH Easy

Once the bot works, set up SSH keys and an alias from your daily computer.

Goal:

```bash
ssh openclaw
```

Use the platform guide for your device:

- `how-to/ssh.md#windows`
- `how-to/ssh.md#macos`
- `how-to/ssh.md#android`

After key login works, consider re-running bootstrap with `--harden-ssh` to
disable password SSH.

## Add Secure Remote Access

If you need to reach the bot away from home, use Tailscale:

- `how-to/remote-access.md`

## Keep It Healthy

After the bot is alive, use:

- `admin-guide.md#day-two-operations`
- `admin-guide.md#backup-and-restore`
- `admin-guide.md#troubleshooting`
- `admin-guide.md#security-habits`
- `admin-guide.md#secrets`

## Record Your Build In Your Profile Repo

If you are building a specific bot for a group, business, family, or project,
record the steps in that bot's own profile repo.

Tin Lobster should stay generic. Real build logs, acceptance notes, and
identity-specific docs belong with the bot they describe.


## Everyday use (after setup)

### Talk to the bot

- Control UI: `openclaw dashboard` (as bot user)
- Or your configured chat app (Telegram, Discord, etc.)

### Check that it is alive

```bash
ssh openclaw          # or ssh admin@vm-ip
sudo -iu lobster
openclaw status
openclaw gateway status
```

### Restart the gateway

```bash
sudo -iu lobster
openclaw gateway restart
# if needed:
# openclaw gateway stop && openclaw gateway start
```

### Give the bot a personality (light start)

Copy a starter template into your OpenClaw workspace identity files, then edit
placeholders:

- `templates/personal-helper.SOUL.md`
- `templates/coding-project-helper.SOUL.md`
- `templates/business-assistant.SOUL.md`
- `templates/club-demo-bot.SOUL.md`

Keep real private identity and memory in **your** profile/workspace, not in the
Tin Lobster git tree.

### Safe habits

1. Do not paste tokens into chat or screenshots
2. Run `~/tin-lobster/scripts/secrets-check.sh --bot-user lobster` before sharing logs
3. Backup before big experiments
4. Prefer Tailscale over opening ports to the internet

## When something breaks

1. Read the exact error
2. `openclaw status` / `openclaw logs`
3. Disk space: `df -h`
4. Firewall: `sudo ufw status numbered`
5. [Admin guide → Troubleshooting](admin-guide.md#troubleshooting)

## Related

- [Design guide](design-guide.md)
- [Admin guide](admin-guide.md)
- [SSH how-to](how-to/ssh.md)
- [Remote access](how-to/remote-access.md)
