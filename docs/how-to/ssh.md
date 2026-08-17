# SSH access

Set up key-based SSH so you can run:

```bash
ssh openclaw
```

instead of remembering IPs and usernames.

Private keys stay on **your** device. Only public keys go on the server.

## Windows

Goal:

```powershell
ssh openclaw
```

Instead of memorizing an IP address and username.

## What SSH Keys Are

An SSH key is a safer login method than a password.

It has two parts:

- Private key: stays on your Windows computer. Do not share it.
- Public key: goes on the Ubuntu bot host. This part is safe to copy.

## Check For SSH

Open PowerShell and run:

```powershell
ssh -V
```

If Windows prints a version, SSH is available.

## Create A Key

In PowerShell:

```powershell
ssh-keygen -t ed25519 -C "openclaw"
```

When asked where to save it, press Enter for the default path.

When asked for a passphrase, use one if you can handle typing it. A passphrase
protects the key if your computer is stolen.

Default files:

```text
C:\Users\<you>\.ssh\id_ed25519
C:\Users\<you>\.ssh\id_ed25519.pub
```

The `.pub` file is the public key.

## Copy The Public Key

Show the public key:

```powershell
type $env:USERPROFILE\.ssh\id_ed25519.pub
```

Copy the whole line. It starts with `ssh-ed25519`.

On the Ubuntu host, add it to the admin user's authorized keys:

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
nano ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

Paste the public key on its own line, save, and exit.

## Test Login

From Windows:

```powershell
ssh <admin-user>@<vm-ip-address>
```

Example:

```powershell
ssh alex@192.168.1.50
```

## Create An SSH Alias

Edit:

```text
C:\Users\<you>\.ssh\config
```

Add:

```sshconfig
Host openclaw
  HostName <vm-ip-address-or-tailscale-name>
  User <admin-user>
  IdentityFile ~/.ssh/id_ed25519
```

Now test:

```powershell
ssh openclaw
```

## Common Problems

`Permission denied`

- The public key may not be in `authorized_keys`.
- You may be using the wrong username.
- The server may not allow key login yet.

`Connection timed out`

- The IP may be wrong.
- The VM may be off.
- UFW may not allow SSH from your network.
- You may need Tailscale or bridged VM networking.

## Do Not Share

Never share:

- `id_ed25519`
- screenshots showing private keys
- passphrases
- passwords

Usually safe to share:

- the public key ending in `.pub`
- the exact error message, after checking it does not include secrets


## macOS

Goal:

```bash
ssh openclaw
```

Instead of remembering the bot host IP address and username.

## Create A Key

Open Terminal:

```bash
ssh-keygen -t ed25519 -C "openclaw"
```

Press Enter for the default path:

```text
~/.ssh/id_ed25519
```

Use a passphrase if you can. It protects the private key.

## Show The Public Key

```bash
cat ~/.ssh/id_ed25519.pub
```

Copy the whole line. It starts with `ssh-ed25519`.

## Add The Public Key To Ubuntu

On the Ubuntu bot host, log in through the VM console or existing SSH session:

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
nano ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

Paste the public key on its own line.

## Test Login

From macOS:

```bash
ssh <admin-user>@<vm-ip-address>
```

Example:

```bash
ssh alex@192.168.1.50
```

## Create An SSH Alias

Edit:

```bash
nano ~/.ssh/config
```

Add:

```sshconfig
Host openclaw
  HostName <vm-ip-address-or-tailscale-name>
  User <admin-user>
  IdentityFile ~/.ssh/id_ed25519
```

Fix permissions:

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/config
```

Now test:

```bash
ssh openclaw
```

## Optional: Add Key To macOS Keychain

Some users prefer letting macOS remember the key passphrase.

```bash
ssh-add --apple-use-keychain ~/.ssh/id_ed25519
```

If that option is not available on your macOS version, run:

```bash
ssh-add ~/.ssh/id_ed25519
```

## Do Not Share

Never share:

- `~/.ssh/id_ed25519`
- key passphrases
- screenshots of private keys

Usually safe to share:

- `~/.ssh/id_ed25519.pub`
- error messages after checking for secrets


## Android

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


## After key login works

Consider hardening password SSH (only after you confirm key login from a second
session or console recovery path):

```bash
sudo bash bootstrap-tin-lobster.sh --harden-ssh
```

For access away from home, see [Remote access](remote-access.md).
