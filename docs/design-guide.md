# Design guide

A short picture of what Tin Lobster is, how the pieces fit, and what it
deliberately does not do.

## What you are building

Tin Lobster is a **secure Ubuntu host shell** for OpenClaw.

It prepares the machine underneath the bot:

- dedicated non-root bot user
- firewall, fail2ban, updates, baseline hardening
- OpenClaw CLI install
- secrets layout and leak-check helpers
- optional Docker (rootless for the bot) and Tailscale

It does **not** choose your model provider, chat channels, bot personality, or
public exposure. Those happen later in OpenClaw onboarding.

Think of Tin Lobster as the appliance frame. OpenClaw is the brain you install
inside it.

## Stack (bottom to top)

```text
Your devices (laptop / phone)
    -> private path (home LAN or Tailscale)
        -> Ubuntu VM (the lobster host)
            -> admin user (you, SSH + sudo)
            -> bot user (runs OpenClaw, no sudo/SSH)
                -> OpenClaw gateway (loopback by default)
                    -> chat apps / Control UI
```

## Two users, one machine

| Role | Who | Can sudo | SSH login | Purpose |
|------|-----|----------|-----------|---------|
| Admin | you | yes | yes | manage the host |
| Bot (default `lobster`) | service account | no | no | run OpenClaw only |

You reach the bot with:

```bash
sudo -iu lobster
```

## Security stance (defaults)

- Gateway port is **not** opened in UFW
- No API tokens or channel secrets accepted as bootstrap flags
- SSH is limited by access profile (`local-lan`, `tailnet`, or `cloud`)
- Backups and credentials are treated as sensitive
- VM boundary is the outer perimeter — one bot appliance per VM

Secure-by-default, not magic. You still own keys, updates, and judgment.

## Supported shape

**Recommended:** Ubuntu 24.04/26.04 **VM** (Proxmox, VirtualBox, VMware, cloud).

Why VM-first:

- clean blast radius
- easy to snapshot, clone, and throw away while experimenting
- matches how normal people can run a “small personal server”

LXC/Docker delivery paths may appear later as advanced options. They are not
the core product.

## Main journeys

1. **Day one** — create Ubuntu VM → bootstrap Tin Lobster → OpenClaw onboard →
   first message → first backup  
   See [User manual](user-manual.md).

2. **Day two** — updates, health checks, remote access, recovery  
   See [Admin guide](admin-guide.md).

3. **Identity** — give the bot a purpose with templates under `../templates/`
   (keep real private identity in your own profile repo).

## What stays out of this repo

- personal bot memory and owner notes
- homelab hostnames and private forge URLs
- real API keys, tokens, backups
- club ops / mailing lists

## Related

- [User manual](user-manual.md) — install and first use
- [Admin guide](admin-guide.md) — operator reference
- [Docs home](README.md)
