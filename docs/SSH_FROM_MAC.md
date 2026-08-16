# SSH From macOS

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
