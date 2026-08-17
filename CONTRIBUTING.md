# Contributing to Tin Lobster

Thanks for helping make a safer starting point for self-hosted OpenClaw.

## What belongs here

Tin Lobster is a **generic deployment shell**. Good contributions:

- Bootstrap reliability and clearer errors
- Docs accuracy for beginners
- Validation / secrets hygiene / backup helpers
- Access-profile and platform fixes (Ubuntu 24.04/26.04)
- Security hardening that stays usable for normal people

## What does **not** belong here

- Personal bot identity, memory, or owner notes
- Homelab hostnames, private IPs, internal git servers
- Real API keys, tokens, channel credentials, or backups
- Club ops, mailing lists, or private workshop logistics
- Full private “showcase bot” profiles (use a separate repo)

If a change needs a real secret to demonstrate, use a placeholder and document
where the operator should put the real value.

## Development basics

```bash
git clone https://github.com/sirpinchalot42/tin-lobster.git
cd tin-lobster

# Syntax / help smoke (safe on any machine)
bash -n bootstrap-tin-lobster.sh
bash bootstrap-tin-lobster.sh --help
for s in scripts/*.sh; do bash -n "$s"; done
```

Test host changes on a **disposable** Ubuntu VM. See `docs/TESTING.md`.

## Pull requests

1. Fork and branch from `main`.
2. Keep the diff focused; explain the user-facing problem.
3. Update docs when behavior changes.
4. Do not force-push shared branches.
5. Never commit `.env`, keys, backups, or audit dumps with secrets.

## Security issues

Do not file public exploit details. Follow `SECURITY.md`.

## License

By contributing, you agree your changes are licensed under the MIT License
in `LICENSE`.
