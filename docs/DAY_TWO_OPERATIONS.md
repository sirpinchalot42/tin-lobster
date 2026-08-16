# Day-Two Operations

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
6. Check `docs/TROUBLESHOOTING.md`.
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
