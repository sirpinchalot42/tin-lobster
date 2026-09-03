# Upstream watch (stay current with OpenClaw)

Tin Lobster is a **host shell under OpenClaw**. OpenClaw moves faster than our
release cadence. This note is how we avoid shipping a polished shell that
installs yesterday’s Node/npm/security contract.

## What we track

| Signal | Where | Why it matters |
|--------|--------|----------------|
| Node engines / recommended runtime | [Install](https://docs.openclaw.ai/install), [Getting started](https://docs.openclaw.ai/start/getting-started), GitHub `node-version.mjs` | Bootstrap NodeSource line + version gates |
| npm / pnpm / bun install flags | Install docs | `--allow-scripts=openclaw`, lifecycle script policy |
| First-run command | Getting started / wizard | Still `openclaw onboard --install-daemon`? |
| Control UI / dashboard | [Control UI](https://docs.openclaw.ai/web/control-ui), getting started | Still `openclaw dashboard` for first chat? |
| Update path | [Updating](https://docs.openclaw.ai/install/updating) | Prefer `openclaw update` vs manual npm |
| Doctor / migrations | CLI doctor docs, release notes | `doctor --fix`, breaking route migrations |
| Security baseline | [Security](https://docs.openclaw.ai/gateway/security), exposure runbook | doctor, `security audit`, DM/pairing, sandbox, masked secrets |
| Memory / embeddings | [Memory search](https://docs.openclaw.ai/concepts/memory-search), [llama.cpp](https://docs.openclaw.ai/plugins/llama-cpp) | Chat provider ≠ embeddings; local managed path |
| Cloud sessions (optional) | [Cloud sessions](https://docs.openclaw.ai/gateway/cloud-sessions) | Docs ceiling only; not bootstrap |
| Backup CLI | Backup / updating docs | `backup create --verify`, pre-update backups |
| Release version | npm `openclaw`, GitHub releases / [2026.8.1 notes](https://docs.openclaw.ai/releases/2026.8.1) | Workshop pin vs latest; OpenClaw 2.x line |

## Cadence

| When | Who | What |
|------|-----|------|
| **Before every public RC / go-live** | Maintainer or agent | Full checklist below |
| **Monthly** (or before a meetup) | Maintainer or agent | Quick drift scan |
| **When OpenClaw announces a breaking install/security change** | Whoever sees it | Open a Tin Lobster issue the same day |

Do **not** wait for a user to hit a bootstrap failure in a workshop.

## Full pre-release checklist

Run from a clean checkout of Tin Lobster `main`:

1. Read OpenClaw:
   - https://docs.openclaw.ai/
   - https://docs.openclaw.ai/install
   - https://docs.openclaw.ai/start/getting-started
   - https://docs.openclaw.ai/install/updating
   - https://docs.openclaw.ai/gateway/security
   - https://docs.openclaw.ai/gateway/security/exposure-runbook
   - latest release notes (e.g. OpenClaw 2.0 / `2026.8.1`)
   - https://docs.openclaw.ai/concepts/memory-search (embeddings)
2. Spot-check GitHub `openclaw/openclaw`:
   - `package.json` `version` + `engines`
   - `node-version.mjs` floors
   - README install snippet
3. Compare against Tin Lobster:
   - `bootstrap-tin-lobster.sh` Node install + OpenClaw npm install
   - `docs/user-manual.md` first-run path + memory note
   - `docs/admin-guide.md` update + exposure + alignment table
   - `scripts/first-run-checklist.sh`
   - `README.md` / `SECURITY.md` claims
4. Open a GitHub issue for any drift (one issue; branch from fresh main).
5. Smoke on a disposable Ubuntu 24.04 VM when install path changed:
   bootstrap → onboard → `doctor` → `security audit` → dashboard message →
   `memory status` → backup.

## Quick monthly scan (10–15 min)

```bash
# Published package signal
npm view openclaw version engines

# Local docs touchpoints (from tin-lobster checkout)
grep -nE 'Node\\.js|allow-scripts|openclaw update|security audit|22\\.22|onboard --install-daemon' \
  bootstrap-tin-lobster.sh docs/user-manual.md docs/admin-guide.md \
  scripts/first-run-checklist.sh README.md SECURITY.md
```

Then open the five OpenClaw URLs above and ask only:

1. Did the **install one-liner** change?
2. Did the **Node floor** change?
3. Did the **update** command change?
4. Did the **security ritual** change?
5. Did **onboard** still install the daemon the same way?
6. Did **memory/embeddings** defaults or local setup change?
7. Did **Control UI / dashboard** first-chat path change?

If any answer is yes → GitHub issue → small PR. No drive-by rewrites.

## Product rules that reduce thrash

1. **This public repo is the product surface** contributors should use (issues/PRs here).
2. Tin Lobster configures the **host**, not OpenClaw channel/model secrets.
3. Prefer linking official OpenClaw docs over copying long upstream prose.
4. Teach **OpenClaw’s own** doctor/audit/update tools; host scripts stay complementary.
5. For workshops, document whether class day uses **latest** or a **pinned** OpenClaw version.

## Optional automation later

Nice-to-haves (not required for v0.1):

- Cron/heartbeat note: “run upstream-watch quick scan”
- CI job that fails if bootstrap Node gate drifts from a pinned `engines` snapshot
- Release script that dumps `npm view openclaw version engines` into the RC notes

Until then, this document + a GitHub issue is enough.

## Related

- [Design guide](../design-guide.md)
- [Admin guide](../admin-guide.md)
- [Testing matrix](testing.md)
- OpenClaw docs: https://docs.openclaw.ai/
