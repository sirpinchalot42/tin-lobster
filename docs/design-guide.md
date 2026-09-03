# Design guide

A short picture of what Tin Lobster is, how the pieces fit, and what it
deliberately does not do.

## What you are building

**OpenClaw** is the open-source agent runtime: your own AI that can chat, use
tools, keep memory, and automate work on a machine you control. See the
[README lead-in](../README.md#what-is-openclaw) for the short “what / why.”

**Tin Lobster** is a **secure Ubuntu host shell** for OpenClaw — the deployment
frame so normal people and workshops are not left with a bare OS and a hope.

It prepares the machine underneath the bot:

- dedicated non-root bot user
- firewall, fail2ban, updates, baseline hardening
- OpenClaw CLI install
- secrets layout and leak-check helpers
- optional Docker (rootless for the bot) and Tailscale

It does **not** choose your model provider, chat channels, bot personality, or
public exposure. Those happen later in OpenClaw onboarding.

Think of Tin Lobster as the appliance frame. OpenClaw is the brain you install
inside it. OpenClaw 2.x can grow into multiplayer and cloud workers later; day
one remains one trusted operator and a closed gateway.

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
- Matches OpenClaw's **personal assistant** trust model (one operator boundary
  per gateway; not hostile multi-tenant sharing)
- Day-one path includes OpenClaw `doctor` + `security audit` after onboard

Secure-by-default, not magic. You still own keys, updates, and judgment.

Upstream security docs Tin Lobster aligns with:

- https://docs.openclaw.ai/gateway/security
- https://docs.openclaw.ai/gateway/security/exposure-runbook

## Supported shape

**Recommended:** Ubuntu 24.04/26.04 **VM**. Hypervisor brand is your choice
(VirtualBox, Hyper-V, Proxmox, VMware, cloud, …) based on what you have and how
serious the bot is. Operator detail:
[Admin guide → Host and hypervisor](admin-guide.md#host-and-hypervisor).

Why VM-first:

- clean blast radius (VM boundary is the outer perimeter)
- easy to snapshot, clone, and throw away while experimenting
- console recovery before you harden SSH
- matches how normal people can run a “small personal server”

LXC/Docker delivery paths may appear later as advanced options. They are not
the core product.

## Main journeys

1. **Day one** — create Ubuntu VM → bootstrap Tin Lobster → OpenClaw onboard →
   doctor/security audit → first message → first backup  
   See [User manual](user-manual.md).

2. **Day two** — `openclaw update`, health checks, remote access, recovery  
   See [Admin guide](admin-guide.md).

3. **Identity** — give the bot a purpose with templates under `../templates/`
   (keep real private identity in your own profile repo).

4. **Stay current** — before each RC or meetup, run the upstream drift scan  
   See [Upstream watch](reference/upstream-watch.md).

## Runtime contract (OpenClaw)

Tin Lobster does not pin a single OpenClaw release by default (workshops may).
It does pin **host expectations** to OpenClaw's published install contract:

- supported Node floors (22.22.3+ / 24.15+ / 25.9+ / 26+; Node 23 unsupported)
- npm global install with lifecycle-script allow when the local npm requires it
- first-run: `openclaw onboard --install-daemon`
- day-two: prefer `openclaw update` over ad-hoc `npm update`

When OpenClaw changes that contract, update bootstrap + docs via a small PR —
do not let workshop day be the first test.

## What stays out of this repo

- personal bot memory and owner notes
- private hostnames, internal URLs, or lab-only inventory
- real API keys, tokens, backups
- private club ops / mailing lists

## Related

- [User manual](user-manual.md) — install and first use
- [Admin guide](admin-guide.md) — operator reference
- [Docs home](README.md)
