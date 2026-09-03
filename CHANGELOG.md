# Changelog

All notable changes to Tin Lobster are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed

- OpenClaw **2.x / 2026.8** alignment pass for public-ready docs:
  - README lead-in: what OpenClaw is, why run one, why Tin Lobster exists
  - user manual: Control UI, doctor/`update`, memory embeddings note (chat ≠ vectors)
  - admin alignment table + upstream-watch signals for 2.x
  - first-run checklist includes `memory status`
- Docs reorganized into calm manuals: design guide, user manual, admin guide
- SSH platform guides merged into `docs/how-to/ssh.md`
- Tailscale guide moved to `docs/how-to/remote-access.md`
- Testing matrix moved to `docs/reference/testing.md`
- Root `START_HERE.md` is now a short pointer to the user manual
- Aligned host shell with current OpenClaw install/security/update guidance (2026-08):
  - bootstrap enforces OpenClaw Node floors (22.22.3+ / 24.15+ / 25.9+ / 26+; refuses Node 23)
  - OpenClaw npm install uses `--allow-scripts=openclaw` when local npm requires it
  - user/admin docs teach `openclaw doctor`, `security audit`, pairing/DM defaults,
    exposure preflight, and `openclaw update` as the day-two path
  - first-run checklist + SECURITY/design/README updated accordingly
  - added `docs/reference/upstream-watch.md` so maintainers can track upstream drift

### Planned

- Broader disposable VM matrix (24.04/26.04 × local-lan/tailnet/cloud)
- End-to-end backup/restore drill notes from public testers
- Optional release artifact checksums
- `tinlobster hatch` and public blueprints (post-0.1)
- Glossary + bootstrap "what just happened?" recap
- Optional CI/cron helper for upstream-watch Node/engines snapshot

## [0.1.0-rc.1] - 2026-08-16

First public release candidate.

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
