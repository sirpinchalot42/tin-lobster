# The Complete Tin Lobster Stack

This document explains the full picture — from the physical machine all the way to a running, secure, and remotely accessible OpenClaw bot.

The goal is to help you understand what you're actually building, why each layer exists, and how the pieces fit together.

---

## The Big Picture

Tin Lobster is a **secure base layer** for running OpenClaw.

Think of it like this:

- You want a helpful AI assistant that runs on *your* hardware and respects your privacy.
- Running AI agents safely is harder than it looks.
- Tin Lobster handles the hard security and infrastructure parts so you can focus on what your bot actually *does*.

The Tin Lobster shell is the "stamp." Once you have a healthy lobster, you can give it a purpose (personal assistant, realtor helper, family organizer, small business tool, etc.).

---

## The Full Stack (Simplified)

Here’s the complete picture, from the bottom up:

```
┌─────────────────────────────────────────────────────────────┐
│  Your Devices (Laptop, Phone, Tablet)                       │
│  - Connect via Tailscale (private network)                  │
│  - SSH into the machine                                     │
│  - Talk to your bot through chat apps                       │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  OpenClaw Gateway (runs as the 'lobster' user)              │
│  - Your actual AI agent lives here                          │
│  - Connects to chat apps (Telegram, Discord, etc.)          │
│  - Uses your chosen AI model                                │
│  - Gateway port is NOT exposed to the internet              │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Bot User ('lobster') — Low-privilege service account       │
│  - Owns and runs OpenClaw                                   │
│  - Cannot log in directly via SSH                           │
│  - Uses rootless Docker (safer containers)                  │
│  - Limited permissions by design                            │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Admin User (you)                                           │
│  - Your personal account on the Ubuntu machine              │
│  - Has sudo access                                          │
│  - SSHs into the machine using SSH keys                     │
│  - Manages the system and the bot user                      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Ubuntu 24.04 LTS (the operating system)                    │
│  - Hardened during bootstrap (firewall, fail2ban, etc.)     │
│  - UFW firewall blocks everything except trusted SSH        │
│  - AppArmor + audit logging enabled                         │
│  - Unattended security updates                              │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  The Physical / Virtual Machine                             │
│  Common options:                                            │
│  - Proxmox (recommended for serious use)                    │
│  - VirtualBox on Windows/Mac                                │
│  - Cloud VPS (with narrow SSH access or Tailscale)          │
│  - Old mini PC or laptop                                    │
└─────────────────────────────────────────────────────────────┘
```

---

## The Two Most Common Paths

### Path 1: Proxmox (Recommended for Most People)

**Best for:** People who want something reliable and are willing to learn a bit more.

- Buy a cheap used mini PC (Lenovo ThinkCentre, HP EliteDesk, etc.)
- Install Proxmox (a free virtualization platform)
- Create an Ubuntu 24.04 virtual machine
- Run the Tin Lobster bootstrap script inside the VM

**Why this path is good:**
- Cheap hardware (~$150–300 for a capable mini PC)
- Easy to back up and manage multiple machines
- Good performance
- The VM is isolated from the host

### Path 2: VirtualBox on Windows (or Mac)

**Best for:** People who want to try it on their existing laptop first.

- Install VirtualBox (free)
- Create an Ubuntu 24.04 virtual machine
- Run the Tin Lobster bootstrap script

**Why this path exists:**
- Lowest barrier to entry — you can start today on your current computer
- Good for learning and testing
- Not ideal for long-term daily use (slower, more fragile)

---

## Why Tailscale Matters

One of the most important decisions in Tin Lobster is **how you reach your bot remotely**.

The default answer is: **use Tailscale**.

Tailscale creates a private network between your devices and your bot. This means:

- You don’t need to open ports on your router
- You don’t expose SSH to the public internet
- Your connection is encrypted and authenticated
- It just works from home, work, or while traveling

Tin Lobster makes Tailscale easy to set up, and we strongly recommend it over opening ports.

---

## The Philosophy

Tin Lobster tries to strike a balance:

- **Simple enough** that a motivated normal person can follow the instructions and succeed.
- **Honest enough** that you actually understand what’s happening and why it matters.
- **Secure by default**, not secure if you remember to do seventeen extra steps.

We don’t hide the technical parts — but we also don’t throw you into the deep end without a life jacket.

---

## What Comes Next

After you have a running Tin Lobster machine, the next steps are usually:

1. Run `openclaw onboard --install-daemon` (as the bot user)
2. Start the gateway
3. Send your first test message
4. Create a backup
5. Set up easy SSH access from your devices
6. Add Tailscale for remote access
7. Give your lobster a purpose (this is where the fun begins)

---

## Questions This Document Answers

- What am I actually building?
- Why does the "admin user vs bot user" split exist?
- Why is Tailscale recommended so strongly?
- What hardware options do I have?
- How does everything connect together?

If anything in this document is unclear, that’s feedback we want. The goal is to keep improving these explanations until they actually help people.

---

*Document version: First draft — Tin Lobster*