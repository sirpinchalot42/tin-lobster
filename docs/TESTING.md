# Testing Tin Lobster

Tin Lobster should not be recommended publicly until it passes disposable-host
testing.

## Test Matrix

- Fresh Ubuntu 24.04 VM with `local-lan`.
- Fresh Ubuntu 24.04 VM with `tailnet`.
- Fresh Ubuntu 24.04 cloud VM with a narrow `--ssh-cidr`.
- Fresh Ubuntu 24.04 cloud VM with `--install-tailscale`.
- Fresh Ubuntu 26.04 VM with `local-lan`.
- Re-run on an already bootstrapped host without `--force-fresh-host` (safe add).
- Intentional reinstall with `--force-fresh-host` on a disposable lab VM.
- Run with cloud profile and no SSH path; it should refuse safely.
- Bad DNS/no internet; it should fail clearly.

## Minimum Commands

```bash
bash -n bootstrap-tin-lobster.sh
bash bootstrap-tin-lobster.sh --help
scripts/validate-tin-lobster.sh --help
scripts/secrets-check.sh --help
scripts/init-secrets-layout.sh --help
scripts/collect-audit-evidence.sh --help
scripts/backup-tin-lobster.sh --help
scripts/restore-tin-lobster.sh --help
```

On a disposable VM (git-first):

```bash
git clone https://github.com/PracticalAiClub/tin-lobster.git tin-lobster
cd tin-lobster

sudo bash bootstrap-tin-lobster.sh \
  --bot-user lobster \
  --access-profile local-lan \
  --ssh-cidr <your-test-cidr>

# Use --force-fresh-host only when intentionally resetting a lab host.
```

Then:

```bash
scripts/validate-tin-lobster.sh --bot-user lobster
scripts/secrets-check.sh --bot-user lobster
scripts/collect-audit-evidence.sh --bot-user lobster --output-dir .
sudo -iu lobster
openclaw onboard --install-daemon
openclaw gateway status
openclaw status
openclaw backup create
```

## Release Gate

A release candidate should include:

- syntax checks passing
- validation script passing on a disposable VM
- secrets-check script passing after setup
- audit evidence captured with `scripts/collect-audit-evidence.sh`
- no hardcoded private download URLs in docs
- no model provider assumptions
- no channel credentials in bootstrap
- no gateway token in shell history or command-line args
- git-first install path works end-to-end (docs + scripts copied for bot user)
- README quickstart reviewed by a non-expert
