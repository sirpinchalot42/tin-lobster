# SSH From Windows

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
