# Tailscale Remote Access

Tailscale gives your devices a private network so you can reach the bot without
opening SSH to the public internet.

Plain English version:

- Without Tailscale, you may need to expose ports or remember changing home IPs.
- With Tailscale, your laptop, phone, and bot join the same private network.
- You SSH to the bot through that private network.

## When To Use Tailscale

Use Tailscale when:

- You want to SSH into the bot away from home.
- The bot is in a cloud VM.
- You do not want to expose SSH to the internet.
- You want stable names through MagicDNS.

You may not need it when:

- The bot never leaves your home network.
- You only access it from one local machine.
- You are still in a short workshop lab.

## Install On The Bot Host

Tin Lobster can install Tailscale support during bootstrap:

```bash
sudo bash bootstrap-tin-lobster.sh \
  --access-profile tailnet \
  --install-tailscale \
  --force-fresh-host
```

If Tailscale is already installed or you install it later, start it:

```bash
sudo tailscale up
```

Follow the login URL it prints.

## Install On Your Device

Install Tailscale on the device you use to manage the bot:

- Windows laptop
- Mac
- Linux laptop
- Android phone
- iPhone or iPad

Sign in to the same tailnet.

## Find The Bot's Tailscale Address

On the bot host:

```bash
tailscale ip -4
tailscale status
```

If MagicDNS is enabled in Tailscale, you may also get a stable name such as:

```text
openclaw.tailnet-name.ts.net
```

## SSH Over Tailscale

From your device:

```bash
ssh <admin-user>@<tailscale-ip-or-name>
```

Then create an SSH alias:

```sshconfig
Host openclaw
  HostName <tailscale-ip-or-magicdns-name>
  User <admin-user>
  IdentityFile ~/.ssh/id_ed25519
```

Now:

```bash
ssh openclaw
```

## Firewall Expectations

Tin Lobster should:

- allow SSH only from the chosen trusted network path
- keep the OpenClaw gateway port closed in UFW
- avoid public gateway exposure

Check:

```bash
sudo ufw status numbered
ss -ltnp
```

## Security Habits

Do:

- Remove old devices from Tailscale when you no longer use them.
- Use device lock screens.
- Keep SSH keys private.
- Prefer Tailscale over opening router ports.

Do not:

- Open SSH to `0.0.0.0/0` unless you truly understand the risk.
- Publish the OpenClaw gateway directly to the internet by accident.
- Share Tailscale admin screenshots that show sensitive names or users.

## Test Before You Travel

Before relying on remote access:

1. Connect laptop or phone to a different network.
2. Confirm Tailscale is connected.
3. Run `ssh openclaw`.
4. Run `openclaw status`.
5. Confirm you know your recovery path if SSH fails.
