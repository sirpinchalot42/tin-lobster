# SSH From Android

Android can be a useful emergency console for your bot, but it should not be
your only recovery path.

Goal:

```bash
ssh openclaw
```

from an Android SSH app or terminal.

## Pick An SSH Client

Use an Android SSH client that supports:

- ed25519 keys
- saving hosts
- importing or generating keys
- copying text cleanly

Some people use a terminal-style app. Others use a graphical SSH client. The
exact app matters less than keeping your private key private.

## Create Or Import A Key

Best beginner path:

1. Generate a new SSH key inside the Android SSH app.
2. Export or copy only the public key.
3. Add that public key to the Ubuntu host.

If your Android environment has `ssh-keygen`, the command is:

```bash
ssh-keygen -t ed25519 -C "openclaw-android"
```

## Add The Android Public Key To Ubuntu

On the Ubuntu bot host:

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
nano ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

Paste the Android public key on its own line.

## Create A Host Alias

If your Android SSH app supports host aliases, create one:

```sshconfig
Host openclaw
  HostName <vm-ip-address-or-tailscale-name>
  User <admin-user>
  IdentityFile <path-to-android-private-key>
```

Some apps store this through a form instead of a text file. Use:

- Host name: VM IP, Tailscale IP, or Tailscale MagicDNS name
- Username: admin user
- Key: Android private key
- Port: `22`

## Use Tailscale For Remote Android Access

For access away from home:

1. Install Tailscale on Android.
2. Join the same tailnet as the bot host.
3. Connect to the bot using its Tailscale IP or MagicDNS name.

Do not expose SSH to the whole internet just so your phone can connect.

## Emergency Use

Android SSH is good for:

- checking status
- restarting a service
- reading logs
- confirming the bot is alive

It is not ideal for:

- long setup sessions
- editing large files
- recovery from serious lockout

Keep a better recovery path such as VM console, Proxmox console, or cloud
provider console.

## Do Not Share

Never share:

- Android private key
- QR codes or exports that include private keys
- SSH screenshots that show tokens or config secrets

Usually safe to share:

- public key
- app name
- connection error, after checking for secrets
