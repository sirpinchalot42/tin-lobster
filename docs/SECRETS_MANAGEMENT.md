# Secrets Management (Practical)

Most people do not need HashiCorp Vault on day one. They need a **clear place
for secrets**, **strict permissions**, **no accidental leaks**, and a **habit
that survives workshops**.

Tin Lobster bakes in that baseline. You can graduate to stronger tools later
without throwing the layout away.

## Mental model

There are three buckets:

| Bucket | Who owns it | Examples | Where |
|--------|-------------|----------|--------|
| **OpenClaw credentials** | OpenClaw wizard / runtime | channel tokens, gateway auth material | `~/.openclaw/credentials/` and OpenClaw config |
| **Operator secrets** | You | extra API keys for tools, personal notes about rotations | `~/.openclaw/secrets/` |
| **Public repo / docs** | Git | install steps, architecture, templates | this repository |

**Rule:** secrets never live in the public Tin Lobster git tree, workshop
slides, screenshots, or chat.

## What Tin Lobster creates for you

On bootstrap, the bot home gets:

```text
~/.openclaw/
  credentials/          # OpenClaw-managed (mode 700)
  secrets/              # operator helper area (mode 700)
    README              # short local reminder
    env.example         # dummy template you can copy
    .gitignore          # refuse to commit anything here
```

Permissions target:

- directories: `700` (owner only)
- secret files: `600` (owner read/write only)

Tin Lobster **does not** invent a second password store or ask for API keys
during bootstrap. That is intentional.

## Day-one flow (recommended)

1. Bootstrap the host with Tin Lobster.
2. Switch to the bot user: `sudo -iu lobster`
3. Run OpenClaw onboarding: `openclaw onboard --install-daemon`
   - Enter provider and channel secrets **only** in onboarding / official flows.
4. Create operator env file only if you need extra keys for tools:

```bash
cp ~/.openclaw/secrets/env.example ~/.openclaw/secrets/env.local
chmod 600 ~/.openclaw/secrets/env.local
nano ~/.openclaw/secrets/env.local
```

5. Run the leak check:

```bash
~/tin-lobster/scripts/secrets-check.sh --bot-user lobster
```

6. Make a backup and treat the archive as sensitive:

```bash
openclaw backup create
openclaw backup verify <backup-file>
```

## How to handle common secret types

### Model provider API keys

Prefer OpenClaw's guided setup. If a tool needs an extra key:

- put it in `~/.openclaw/secrets/env.local` (mode 600), **or**
- use the provider's recommended local config path

Never:

- pass keys as bootstrap flags
- commit keys into a bot profile repo
- paste keys into Discord/Telegram group chats

### Channel tokens (Telegram, Discord, etc.)

Enter them through OpenClaw setup. Rotate them if they ever appear in:

- screenshots
- support tickets
- shell history
- git commits

### Gateway auth / loopback access

Tin Lobster leaves the gateway closed in UFW by design. Do not open
`18789/tcp` to the world to "make it easier."

### SSH private keys

Live on **your admin devices**, not in the bot workspace. Public keys only on
the server.

## Leak prevention (the heavy lifting most people need)

Tin Lobster ships `scripts/secrets-check.sh` to catch common mistakes:

- world-readable files under `~/.openclaw`
- likely tokens/keys in workspace markdown
- `.env` files with loose permissions
- private key files with mode wider than `600`
- secrets directories that are not mode `700`
- accidental secret-looking strings in `~/tin-lobster` copies

Run it:

- after first OpenClaw setup
- before asking for help with logs
- before cloning a profile repo to a new machine
- as part of workshop "definition of done"

## What about "real" secret managers?

When you outgrow files:

| Stage | Tooling | When |
|-------|---------|------|
| **v0 (now)** | OpenClaw credentials + `~/.openclaw/secrets` + leak check | personal bot, club workshop |
| **v1** | encrypted backup of secrets dir (`age`/`sops`) off-host | multi-machine recovery |
| **v2** | systemd `EnvironmentFile=` + restricted service user | always-on services needing env injection |
| **v3** | 1Password / Bitwarden / Vault + short-lived tokens | team or higher threat model |

Tin Lobster stays compatible with later stages because it never hardcodes
secrets into the shell and keeps a clean owner-only directory.

## Backup and restore implications

Backups may include credentials depending on OpenClaw settings. Treat every
backup as **full-trust material**.

- Store backups encrypted or on a locked volume.
- Do not email backups to yourself "for safety."
- When migrating hosts, prefer re-linking channels over blindly copying every
  secret across trust boundaries.

See `BACKUP_RESTORE.md`.

## Safe help requests

When something breaks, share:

- redacted error messages
- Ubuntu version
- Tin Lobster / OpenClaw version
- `scripts/secrets-check.sh` summary (not file contents)

Do **not** share:

- `env.local`
- `~/.openclaw/credentials/*`
- gateway tokens
- channel bot tokens
- private keys
- unredacted config dumps

## Workshop teaching script (60 seconds)

1. Secrets are radioactive.
2. Wizard is the front door; chat is not.
3. `~/.openclaw/secrets` is for operator extras only.
4. Run `secrets-check.sh` before you celebrate.
5. Backups are secret packages, not trophies.

## Related

- `SECURITY.md` (project policy)
- `SECURITY_MODEL.md` (host assumptions)
- `SECURITY_FOR_NORMAL_PEOPLE.md` (plain-language rules)
- `scripts/secrets-check.sh`
- `scripts/init-secrets-layout.sh`
