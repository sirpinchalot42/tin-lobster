# Tin Lobster Lifeboat

The deployment shell helps users start safely. The lifeboat helps them recover.

## Day-One Backup

After OpenClaw first-run setup and channel/model configuration:

```bash
openclaw backup create
openclaw backup verify <backup-file>
```

Treat backup archives as sensitive. They may contain config, credentials,
workspace data, sessions, and personal context depending on OpenClaw settings.

## Recommended Modes

The first public Tin Lobster restore flow should distinguish these use cases:

- `identity-only`: workspace, identity files, memory/docs, no credentials
- `config-only`: OpenClaw config without channel secrets
- `full-local`: same-machine recovery for trusted personal use
- `migration`: guided restore to a new host with secret/channel review

## Restore Principles

- Verify before applying.
- Show a restore plan before changing files.
- Never overwrite existing state without an explicit flag.
- Do not print secrets while validating.
- Prefer re-linking channels over blindly moving credentials to a new trust boundary.

## Future Helper Commands

Possible wrappers:

```bash
tinlobster backup create
tinlobster backup verify <backup-file>
tinlobster restore plan <backup-file>
tinlobster restore apply <backup-file>
```

These should wrap OpenClaw-native backup tooling instead of inventing a second
state format.

