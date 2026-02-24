Secrets handling & best practices

Purpose
-------
This document explains how to store and manage secrets for this repository. Follow these practices to avoid leaking credentials into the git history and CI logs.

Recommended approach
--------------------
- Store long‑lived or production secrets in Azure Key Vault (preferred), AWS Secrets Manager, or other secret stores.
- For CI usage, sync Key Vault secrets into GitHub Actions secrets using `scripts/monitoring/sync_keyvault_to_github.ps1`.
- For container pushes to GHCR, create a PAT with `packages: write` and set repository secret `GHCR_PAT` (optional `GHCR_USERNAME`). See `.github/GHCR_PAT_INSTRUCTIONS.md`.

Files & templates
-----------------
- Do not commit files containing real credentials (`*_credentials.env`). Use the `*.template` files included in the repo to populate values locally.
- Templates in the repo:
  - `aws_credentials.env.template`
  - `azure_credentials.env.template`
  - `gcp_credentials.env.template`

Secrets scanning
----------------
- CI now runs `gitleaks` as part of the `security-scan` job to detect accidental secret leaks and fail the run if any findings are detected.
- There is also a `.gitleaks.toml` baseline in the repo to tune allowed patterns and reduce false positives.

If you find sensitive values already in the repo
-----------------------------------------------
1. Rotate the exposed secrets immediately (rotate keys/secrets where possible).
2. Replace the committed secrets with placeholders and commit the sanitized files (done in this change).
3. If you want to expunge secrets from history, consider using `git-filter-repo` or BFG. This is destructive and will rewrite history; coordinate with collaborators and backups before running it.

Automation
----------
- Use `scripts/monitoring/sync_keyvault_to_github.ps1` to copy secrets safely from Key Vault into GitHub repository or environment secrets.
- For CI secrets, prefer repository or environment secrets and avoid printing secrets in logs.

Programmatic access (SDK preferred)
----------------------------------
- For programmatic access from Python, prefer the Azure SDK using `DefaultAzureCredential` and `SecretClient` (e.g., via the repository helper `uai_keyvault.get_secret()`) so code works in interactive, CI, and managed identity scenarios.
- Ensure credentials are available to `DefaultAzureCredential` (for example: `az login` for local dev, or set `AZURE_CLIENT_ID`/`AZURE_TENANT_ID`/`AZURE_CLIENT_SECRET` for a service principal, or rely on a managed identity in cloud hosts).
- The helper falls back to the `az` CLI when the SDK or credentials are unavailable, preserving behavior for minimal environments.

CI Integration Tests (Key Vault)
--------------------------------
- We provide an optional, manual GitHub Actions workflow `.github/workflows/keyvault-integration.yml` that runs integration tests against a real Key Vault. The workflow is *manual* (workflow_dispatch) to avoid running secrets-backed tests on every push.
- Required repository secrets for the workflow:
  - `AZURE_CREDENTIALS` — SP JSON from `az ad sp create-for-rbac ... --sdk-auth`
  - `KV_TEST_VAULT` — Key Vault name (short)
  - `KV_TEST_SECRET_NAME` — An existing secret to validate (read-only tests), or set `KV_TEST_MANAGE=true` to allow create/delete tests
- To run the workflow:
  1. Create the SP and store the JSON as `AZURE_CREDENTIALS` (see `ISSUE_KEYVAULT_SP_SETUP.md`).
  2. Add `KV_TEST_VAULT` and `KV_TEST_SECRET_NAME` as secrets.
  3. Manually dispatch the workflow (Actions → Key Vault Integration Tests → Run workflow).
- For local testing, follow `.github/ISSUE_KEYVAULT_LOCAL_RUN.md` which documents environment variables and a helper script to run tests locally.

If you want, I can prepare a PR that also includes an automated history purge and we can coordinate secret rotation as part of that change.
