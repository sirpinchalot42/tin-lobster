# Troubleshooting

## I cannot SSH after bootstrap

Use the VM console or cloud provider console.

Check:

```bash
sudo ufw status verbose
sudo sshd -t
sudo systemctl status ssh
```

If you used `--harden-ssh`, confirm your key is installed before closing the
original session.

## OpenClaw command not found

Become the bot user and check the path:

```bash
sudo -iu <bot-user>
echo "$PATH"
ls -la ~/.npm-global/bin/openclaw
```

The bootstrap appends `~/.npm-global/bin` to the bot user's `.bashrc`.

## Gateway does not start

Run:

```bash
openclaw config validate
openclaw gateway status
openclaw logs
```

If first-run setup was not completed, run:

```bash
openclaw onboard --install-daemon
```

## UFW blocked something

Tin Lobster intentionally does not open the gateway port.

Check rules:

```bash
sudo ufw status numbered
```

Open new ports only when you understand the exposure.

## Backup failed

Run as the bot user:

```bash
openclaw backup create
openclaw backup verify <backup-file>
```

Backups may contain sensitive data. Do not paste backup contents into tickets or
chat.

