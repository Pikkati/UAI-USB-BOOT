Summary
-------

We implemented IMAP and Key Vault support for the Enterprise Response Monitor (`fortune_500_response_monitor.py`) and added helpers and docs, but IMAP connectivity could not be verified because IMAP credentials were not found in accessible Key Vaults.

What was implemented
--------------------
- IMAP backend for `fortune_500_response_monitor.py` with:
  - CLI options: `--test-imap`, `--env-file`, `--keyvault`, `--keyvault-prefix`, `--keyvault-output-env`, `--keyvault-dry-run`
  - `load_env_file()` helper for local testing
  - `fetch_keyvault_imap_secrets()` helper (uses `az keyvault secret show`)
- Scripts:
  - `scripts/get_imap_secrets_from_keyvault.ps1` and `.sh` (fetch secrets into an env file)
  - `scripts/test_imap.ps1` / `scripts/test_imap.sh` (run IMAP connectivity test)
  - `scripts/fetch_mail_secrets_all_vaults.ps1` (scan vaults for mail-related secrets)
- Documentation: `docs/enterprise_response_monitor.md` (usage, Key Vault guidance, security notes)
- Added test run: `fortune_500_response_monitor.py --test-imap --env-file .env.imap` (non-destructive) and successful local backend simulation flows

Current status
--------------
- Local backend and simulated responses are working and verified.
- Key Vault scan (accessible vaults) found only a single mail-related secret name (`ALERT-EMAIL` → `ALERT_EMAIL`) and **no IMAP credentials**.
- Several vaults returned RBAC/Forbidden when enumerating secret names (see vault list below).
- We wrote fetched matches to `.env.imap` (per request: `delete_after=no`) and attempted `--test-imap`; test failed due to missing IMAP variables (`IMAP_HOST`, `IMAP_USER`, `IMAP_PASS`).

Vault scan summary (names only)
------------------------------
- shopify-hostaway-dev-kv: ALERT-EMAIL, ...
- uai-therapy-kv-2780: ALERT-RISK-THRESHOLD, ...
- uai-publishing-vault-2: ovsx-token, publisher-id, vsce-pat
- houdini-kv-staging: anthropic-api-key, azure-client-id, ...
- houdini-kv-prod: anthropic-api-key, database-password, ...
- kv-uai-conscious-dev: azure-client-id, azure-client-secret, ...
- Vaults that returned "Forbidden" (no listing possible):
  - uai-hr-kv-20251222, uai-publishing-vault, uai-copilot-kv, uai-pilot-prod-kv, aiom-kv-research

Requested action / Acceptance criteria
-------------------------------------
- Add IMAP secrets to an accessible Key Vault OR grant list/get permissions to a vault we should use.
  Required secret keys (recommended names):
  - `IMAP_HOST` (e.g., imap.example.com)
  - `IMAP_PORT` (optional; default 993)
  - `IMAP_USER` (login)
  - `IMAP_PASS` (app-specific password or token)
  - `IMAP_USE_SSL` (true/false)
  - `IMAP_FOLDER` (optional; default INBOX)

- After secrets are added / RBAC granted, the following should succeed:
  - `scripts/get_imap_secrets_from_keyvault.ps1 -VaultName <vault> -OutEnv .env.imap`
  - `python fortune_500_response_monitor.py --test-imap --env-file .env.imap` (should report success)
  - `python fortune_500_response_monitor.py --once --backend imap --no-dry-run --env-file .env.imap` should detect real responses (if any)

Optional follow-ups
-------------------
- Add a CI check or secret naming convention policy for Key Vaults.
- Add automated cleanup of temporary `.env.imap` files (on request) and guidance for secure local testing.
- Add a mailbox webhook/inbound-mail pipeline for faster real-time response handling.

Checklist
---------
- [ ] Add IMAP secrets to vault (or supply a `.env` file)
- [ ] Grant Key Vault `list/get` RBAC to runner (if necessary)
- [ ] Run IMAP connectivity test and one-time monitor
- [ ] Document the exact secret name naming convention and permission guide in docs

Notes
-----
- No secret values were exposed in this issue; `.env.imap` was created in the workspace per instructions and contains the fetched values (treat as sensitive).
- I can run the fetch/test steps if you provide a vault name or grant the necessary RBAC on an existing vault.

/cc @yushchyr
