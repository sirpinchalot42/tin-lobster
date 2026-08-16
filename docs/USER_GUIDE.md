# Tin Lobster Field Manual

This manual is for people who want to run an OpenClaw bot without becoming a
full-time system administrator.

It uses plain English, but it does not hide the technical parts. The goal is to
stretch new users just enough that they understand their machine and can keep it
safe.

## Manual Map

### Start
- `../START_HERE.md` - the whole journey in one short path.
- `THE_COMPLETE_STACK.md` - how the layers fit together.
- `../README.md` - product overview and options reference.

### Install and day one
- `SECRETS_MANAGEMENT.md` - where secrets live and how to check for leaks.
- `SSH_FROM_WINDOWS.md` / `SSH_FROM_MAC.md` / `SSH_FROM_ANDROID.md` - device access.
- `TAILSCALE_REMOTE_ACCESS.md` - secure remote access without public SSH.

### Security
- `../SECURITY.md` - project security policy.
- `SECURITY_MODEL.md` - host security assumptions.
- `SECURITY_FOR_NORMAL_PEOPLE.md` - what is safe, risky, or secret.
- `BOT_PERMISSIONS.md` - bot user vs admin responsibilities.

### Operations
- `DAY_TWO_OPERATIONS.md` - normal care and feeding after install.
- `BACKUP_RESTORE.md` - backup and restore guidance.
- `TROUBLESHOOTING.md` - common problems and recovery.
- `TESTING.md` - disposable host test matrix.

## Learning Contract

Tin Lobster tries to be kind to beginners, not pretend computers are magic.

You should learn:

- What machine your bot lives on.
- How you log into it.
- What SSH keys are.
- Why a firewall matters.
- Why Tailscale is safer than opening ports to the internet.
- Where OpenClaw state lives.
- How to back up before experiments.
- What information should never be posted publicly.

## The Three Important Names

You will see three kinds of names:

- Admin user: the first Ubuntu user you log in as.
- Bot user: the Linux user that owns OpenClaw, often `lobster`.
- Bot identity: the personality/name OpenClaw uses in chat.

These are related, but not the same thing.

## The Happy Path

Most new users should follow this order:

1. Build fresh Ubuntu 24.04/26.04.
2. `git clone` Tin Lobster and run bootstrap from the repo root.
3. Switch to the bot user.
4. Run `openclaw onboard --install-daemon` (secrets/models/channels enter here).
5. Confirm the gateway with `openclaw gateway status`.
6. Run `validate-tin-lobster.sh` and `secrets-check.sh`.
7. Send the first test message.
8. Create and verify a backup.
9. Set up SSH aliases / Tailscale.
10. Learn the maintenance rhythm.

## The Rule Of Recovery

Before a big change, know how you will get back in.

Good recovery paths:

- VM console.
- Proxmox console.
- Cloud provider console.
- Physical keyboard and monitor.
- A verified backup.

Bad recovery paths:

- "I hope SSH still works."
- "I saved the only key on the machine I am changing."
- "I posted my backup in chat so someone can help."

## Future Manual Format

These Markdown files are source material for a later designed manual, website,
PDF, or EPUB. Until the product is stable, keep the docs easy to edit and
review.
