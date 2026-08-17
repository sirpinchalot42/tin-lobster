# Changelog

All notable changes to Tin Lobster are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Planned

- Broader disposable VM matrix (24.04/26.04 × local-lan/tailnet/cloud)
- End-to-end backup/restore drill notes from public testers
- Optional release artifact checksums
- `tinlobster hatch` and public blueprints (post-0.1)

## [0.1.0-rc.1] - 2026-08-16

First public release candidate. Clean public history (no private forge history).

### Added

- Git-first bootstrap for Ubuntu 24.04 LTS / 26.04 LTS
- Interactive setup wizard (beginner path) plus advanced flags
- Access profiles: `local-lan`, `tailnet`, `cloud`
- Non-root bot user, UFW, fail2ban, unattended upgrades, AppArmor/audit tooling
- Optional Docker (rootless for bot user) and optional Tailscale install
- Secrets layout helpers and `scripts/secrets-check.sh` (no secret values printed)
- Validation, first-run checklist, backup/restore helpers, audit evidence collector
- Security docs for operators (`SECURITY.md`, model, normal-people guide)
- Generic identity starter templates (not full blueprints)
- MIT license (Copyright 2026 PracticalAiClub)

### Security

- Gateway port not opened in UFW by default
- No gateway tokens or channel/model secrets accepted as CLI flags
- SSH exposure is profile-based (not hardcoded to one lab network)
- Safe re-run by default; `--force-fresh-host` only for intentional lab resets

### Notes

- This RC is intended for early testers and workshop dry-runs.
- Prefer the tagged release over cloning an arbitrary commit when teaching.
- Report security issues privately (see `SECURITY.md`).

[Unreleased]: https://github.com/sirpinchalot42/tin-lobster/compare/v0.1.0-rc.1...HEAD
[0.1.0-rc.1]: https://github.com/sirpinchalot42/tin-lobster/releases/tag/v0.1.0-rc.1
