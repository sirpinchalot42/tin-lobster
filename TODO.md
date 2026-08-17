# Tin Lobster — Outstanding Work

This file tracks the next build work for turning Tin Lobster from a secure
OpenClaw deployment shell into a beginner-friendly launcher for reusable bot
blueprints.

## Current Product Direction

**v0.1 focus:** ship a polished, git-first deployment shell with accurate docs,
validation, and practical secrets hygiene. Defer hatch/full blueprints until the
shell is solid.

Tin Lobster should stay generic. It prepares the machine, installs the OpenClaw
runtime pieces, teaches the operator what happened, and provides safe defaults.

The long-term model is:

- **Tin Lobster core:** generic installer, validation, backup/restore, docs, and
  runtime shell.
- **Blueprints:** public starter profiles for common use cases.
- **Private bot profile repos:** real bot identity, memory seeds, local tools,
  owner context, and deployment-specific notes.
- **Showcase bots:** optional public demos, with private operational files kept
  out of the generic core.

## Build Next

### 1. `tinlobster hatch`

Build a friendly command that guides a user through creating or attaching a bot
profile after the base host is ready.

Open work:

- [ ] Decide whether `hatch` is a shell script, OpenClaw command wrapper, or
      small CLI.
- [ ] Ask which blueprint to start from.
- [ ] Ask whether to create a new local profile or clone an existing repo.
- [ ] Ask where the profile should live on disk.
- [ ] Copy or render starter files from the selected blueprint.
- [ ] Print the next OpenClaw setup commands.
- [ ] Avoid writing secrets into files or command history.

### 2. Blueprint System

Create public, sanitized starter profiles that help people begin without mixing
private identity files into the Tin Lobster core repo.

Starter blueprint candidates:

- [ ] `blank-lobster`
- [ ] `personal-assistant`
- [ ] `small-business-admin`
- [ ] `real-estate-assistant`
- [ ] `family-household-helper`
- [ ] `coding-project-helper`
- [ ] `finance-research`
- [ ] `club-demo-bot`

Each blueprint should include:

- [ ] sample `AGENTS.md`
- [ ] sample `SOUL.md`
- [ ] sample `USER.md`
- [ ] suggested folder structure
- [ ] starter tool notes
- [ ] starter memory categories
- [ ] suggested heartbeat/cron patterns
- [ ] safety and privacy notes

### 3. Profile Overlay Contract

Define exactly how Tin Lobster uses a private bot profile repo.

Open work:

- [ ] Decide whether profiles live inside the OpenClaw workspace or beside it.
- [ ] Document the expected profile folder layout.
- [ ] Document required versus optional files.
- [ ] Support a profile repo URL in the hatch flow.
- [ ] Support a local profile path in the hatch flow.
- [ ] Make private profile files easy to back up without leaking them into the
      generic Tin Lobster repo.

### 4. Repo Cleanup

Keep Tin Lobster generic. Owner-specific material stays in private profile repos.

Open work:

- [ ] Inventory files as `generic`, `blueprint`, `audit`, or `private/local`.
- [x] Move private identity and operational files to a separate profile repo.
- [x] Keep only sanitized demo/showcase material in this public repo.
- [x] Move audit files into either a private audit repo or a clearly marked
      `docs/audit/` area if they are safe to share.
- [ ] Replace removed private files with generic examples or templates.
- [x] Public GitHub export uses a clean orphan history (private forge history stays private).

### 5. Admin Manual

Turn the existing Markdown docs into a polished admin manual that teaches the
full stack without hiding the important parts.

Open work:

- [ ] Create a generic Tin Lobster admin manual outline in this repo.
- [ ] Add a glossary for SSH, keys, firewall, gateway, Tailscale, repo, branch,
      commit, backup, restore, and profile.
- [ ] Add "what just happened?" recap after bootstrap.
- [ ] Add first-message walkthrough.
- [ ] Add day-two maintenance checklist.
- [ ] Add backup/restore drill checklist.
- [ ] Add common failure recovery paths.
- [ ] Add workshop facilitator run sheet.
- [ ] Decide how to publish PDF/EPUB/website versions later.

### 6. Public Release Hygiene

Make the project safe and understandable before publishing widely.

Open work:

- [x] Prefer git-first install path (no curl one-liner as primary docs).
- [x] Add practical secrets layout + `secrets-check` helper.
- [x] Add `SECURITY.md` and secrets management guide.
- [x] Public GitHub clone URL set for sirpinchalot42/tin-lobster (change if org/repo differs).
- [ ] Add checksum/signature verification for release artifacts (optional tarball).
- [ ] Add release tags on the public GitHub repo (`v0.1.0-rc.1`, then `v0.1.0`).
- [x] Add a contribution guide (`CONTRIBUTING.md`).
- [ ] Add issue templates.
- [x] Add license decision: **MIT**, Copyright (c) 2026 PracticalAiClub.
- [ ] Document rollback/uninstall path in a dedicated short guide.
- [ ] Consider a custom AppArmor profile for Node.js/OpenClaw.
- [ ] Run disposable Ubuntu 24.04 and 26.04 smoke tests for all access profiles.
- [ ] Test backup/restore end-to-end on a disposable VM.
- [ ] Run cloud, local LAN, and Tailscale path tests.
- [x] Secrets scrub of published tree before first public push.
- [x] Do not publish private forge history; orphan export only.

## Principle

Tin Lobster should be beginner-friendly, not beginner-limited. It should
automate the repetitive parts, explain the important parts, and leave each user
with a working OpenClaw foundation they understand well enough to maintain.
