# Bot User Permissions

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
