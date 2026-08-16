# Security For Normal People

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

Full layout and operator flow: `SECRETS_MANAGEMENT.md`.

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
