# Security Policy

Tin Lobster is a **secure-by-default host shell** for OpenClaw. It hardens the
machine and keeps secrets out of the installer path. It is not a vault product
and it is not a substitute for careful operator habits.

## What Tin Lobster protects by default

- Separate non-root bot user for OpenClaw state
- Gateway port **not** opened in UFW
- No gateway tokens, API keys, or channel secrets accepted as CLI flags
- Profile-based SSH exposure (`local-lan`, `tailnet`, `cloud`)
- Locked-down OpenClaw state directory permissions
- Fail2ban, unattended upgrades, AppArmor/audit baseline tooling
- Docs that point operators at OpenClaw's personal-assistant security model
  (pairing/allowlists, doctor, `security audit`, exposure runbook)

## What Tin Lobster does **not** do

- Store or rotate cloud API keys for you
- Encrypt secrets at rest with a hardware enclave
- Prevent you from pasting tokens into chat, screenshots, or git
- Replace OpenClaw's own credential handling during `openclaw onboard`
- Replace `openclaw doctor` / `openclaw security audit` / channel DM policy

## OpenClaw security model (upstream)

Tin Lobster is designed for OpenClaw's **single trusted operator** posture, not
hostile multi-tenant sharing of one gateway. After install, operators should:

```bash
openclaw doctor
openclaw security audit
# before remote exposure or multi-person messaging:
openclaw security audit --deep
```

Prefer DM pairing or allowlists; keep the gateway loopback/private; use
Tailscale or SSH tunnels instead of public port forwards.

After upgrades, run `openclaw doctor` (and intentional `doctor --fix` only when
you mean it). Memory vector search uses an **embedding** path separate from your
chat model — see the user manual memory section if search is paused.

Upstream:

- https://docs.openclaw.ai/gateway/security
- https://docs.openclaw.ai/gateway/security/exposure-runbook

## Reporting a vulnerability

If you find a security issue in Tin Lobster itself (bootstrap, scripts, docs that
mislead operators into unsafe defaults):

1. Do **not** open a public issue with exploit details.
2. Contact the maintainers privately via GitHub Security Advisories on this
   repository (preferred), or email the Practical AI Club maintainer address
   listed on the GitHub org/profile.
3. Include: affected version/tag/commit, host OS, minimal reproduction, impact.
4. Allow reasonable time for a fix before public disclosure.

If the issue is in OpenClaw upstream, report it to the OpenClaw project.

## Operator checklist (minimum)

1. Prefer SSH keys; use `--harden-ssh` only after key login works.
2. Keep channel tokens and model API keys out of shell history and chat.
3. After onboard: `openclaw doctor` and `openclaw security audit`.
4. Run `scripts/secrets-check.sh` after first setup and before sharing logs.
5. Treat backups as sensitive; verify restores on a disposable host.
6. Use Tailscale (or equivalent private mesh) instead of public gateway ports.
7. Before exposure changes, re-run `openclaw security audit --deep` and read
   the upstream exposure runbook.

See also:

- `docs/admin-guide.md` (security model, habits, secrets, exposure)
- `docs/design-guide.md` (big picture)
- `docs/reference/upstream-watch.md` (how maintainers track OpenClaw drift)
