# Missing credentials audit — remediation steps & links 🔐

**Summary**

A recent audit `reports/env-credentials-audit.csv` shows several missing or placeholder credentials that block local CI publishing and secret-sync automation. This issue tracks collecting the required credentials, storing them securely, and validating end-to-end local CI flows (build → push → Swarm update).

---

## Goal ✅

- Ensure all required secrets are available in a secure store (Azure Key Vault or GitHub repo secrets) and/or set for local CI testing.
- Validate that the local CI can build images and publish them either to GHCR or to the local registry fallback.

---

## Quick checklist (priority items)

- [ ] GHCR credentials: `GHCR_USER`, `GHCR_TOKEN` (needed to push images to `ghcr.io`) — create a Personal Access Token with **write:packages** and **repo** scopes.
- [ ] `GITHUB_TOKEN` (for authenticated git push / release operations) — PAT with **repo** and **workflow** scopes.
- [ ] `REPO_SECRETS_PAT` (used by secret-sync fallback) — PAT with **repo** scope.
- [ ] `OPENAI_API_KEY` — OpenAI API key for AI features.
- [ ] `PINECONE_API_KEY` — Pinecone API key for vector DB features.
- [ ] `SUPABASE_ACCESS_TOKEN` — Supabase service key.
- [ ] Azure service principal: `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_SUBSCRIPTION_ID`, `AZURE_TENANT_ID` — for Key Vault and Azure deployments.
- [ ] AWS `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` — if using AWS services.
- [ ] `UAI_MARKETPLACE_PAT` / `VSCE_PAT` and `PUBLISHER_ID` — for publishing VS Code extension.
- [ ] `OVSX_TOKEN` — for Open VSX (if publishing there).
- [ ] Platform provider tokens (Netlify/Render/Vercel/Koyeb): `NETLIFY_TOKEN`, `NETLIFY_SITE_ID`, `RENDER_API_KEY`, `VERCEL_TOKEN`, `KOYEB_API_KEY`.
- [ ] `LOCAL_REGISTRY` (e.g., `localhost:5000`) and `USE_LOCAL_REGISTRY=true` (for local end-to-end tests without GHCR).

> See full per-file, per-key statuses in `reports/env-credentials-audit.csv` (committed to this repo).

---

## How to obtain each credential (links & quick steps)

- GHCR (GitHub Container Registry): create a Personal Access Token
  - Docs: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token
  - Required scopes: **write:packages**, **repo**. Use this for `GHCR_USER` and `GHCR_TOKEN`.

- GitHub token for repo operations (push, release, workflow):
  - Docs: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token
  - Recommend scopes: **repo**, **workflow**, **write:packages**.

- VS Code Marketplace / `vsce` PAT and `PUBLISHER_ID`:
  - Docs: https://code.visualstudio.com/api/working-with-extensions/publishing-extension
  - Use `vsce login <publisher> --pat <token>` to validate.

- OpenAI API key (`OPENAI_API_KEY`):
  - Get from: https://platform.openai.com/account/api-keys

- Pinecone API key (`PINECONE_API_KEY`):
  - Docs & console: https://www.pinecone.io/ (console: https://app.pinecone.io)

- Supabase service key (`SUPABASE_ACCESS_TOKEN`):
  - Console: https://app.supabase.com/ → Project → Settings → API (service_role key)
  - Docs: https://supabase.com/docs

- Azure service principal (for Key Vault automation):
  - Create SP with CLI: `az ad sp create-for-rbac --name "uai-local-ci" --role Contributor --sdk-auth`
  - Docs: https://learn.microsoft.com/cli/azure/create-an-azure-service-principal-azure-cli

- AWS access keys: create an IAM user with programmatic access
  - Docs: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_users_create.html

- Netlify / Render / Vercel / Koyeb tokens and site IDs:
  - Netlify: https://docs.netlify.com/cli/get-started/#create-a-personal-access-token
  - Vercel: https://vercel.com/docs/rest-api#authentication
  - Render: https://render.com/docs/api#authentication
  - Koyeb: https://www.koyeb.com/docs/api

- Open VSX (`OVSX_TOKEN`):
  - Publishing docs: https://github.com/eclipse/openvsx/wiki/Publish-Extensions

- Local registry (`LOCAL_REGISTRY`) — if you prefer to avoid GHCR for now:
  - Default local registry runs at `localhost:5000` via `deploy/local-ci/docker-compose.local-ci.yml`.
  - Docker registry docs: https://docs.docker.com/registry/

---

## Where to store secrets (recommended)

1. Preferred (recommended): Azure Key Vault — add secrets and then run our sync script to propagate to GitHub repo secrets.
   - Example (dry run):
     ```pwsh
     pwsh ./scripts/sync-keyvault-to-github.ps1 -VaultName "uai-copilot-kv" -Repo "yushchyr/UAI_Copilot_Automation_Tool" -DryRun
     # then (live):
     pwsh ./scripts/sync-keyvault-to-github.ps1 -VaultName "uai-copilot-kv" -Repo "yushchyr/UAI_Copilot_Automation_Tool"
     ```
   - Key Vault quickstart: https://learn.microsoft.com/azure/key-vault/general/quick-create-portal

2. Alternative: GitHub repo secrets
   - Use web UI: Settings → Secrets and variables → Actions → New repository secret
   - Or via CLI: `gh secret set GHCR_TOKEN -b "<token>" --repo yushchyr/UAI_Copilot_Automation_Tool`

3. Local testing (do NOT commit to repo): set values in `deploy/local-ci/.env` or export as environment variables on your host and then restart local CI.

---

## Test / Validation steps (step-by-step)

1. Confirm secrets present (Key Vault or GitHub secrets).
2. Ensure `deploy/local-ci/.env` (local-only) has:

```text
LOCAL_REGISTRY=localhost:5000
USE_LOCAL_REGISTRY=true
# set GHCR_USER/GHCR_TOKEN/GITHUB_TOKEN locally for full flow if available
```

3. Start local registry and local CI stack:

```bash
docker compose -f deploy/local-ci/docker-compose.local-ci.yml up -d --build local-registry local-ci
```

4. Trigger a test build (build-ssh-key-server):

```bash
curl -s -X POST http://localhost:18080/run -H 'Content-Type: application/json' -d '{"workflow":"build-ssh-key-server","ref":"main"}' | jq
# note the job_id and poll status
curl http://localhost:18080/jobs/<job_id> | jq
# or follow logs
docker logs -f uai-local-ci
```

5. Verify image appears in local registry:

```bash
curl -s http://localhost:5000/v2/_catalog | jq
curl -s http://localhost:5000/v2/<owner>/<repo>/tags/list | jq
```

6. If you provided GHCR credentials, verify image pushed to `ghcr.io/<owner>/<repo>` instead.

7. If ENABLE_SWARM_UPDATE is `true` in environment and Swarm is available, verify the service was updated: `docker service ls` and `docker service inspect ssh-key-server`.

---

## Acceptance criteria

- [ ] All missing or placeholder values in `reports/env-credentials-audit.csv` have been remedied (added to Key Vault or GitHub secrets)
- [ ] Local CI can build and push images to a registry (GHCR or local) successfully
- [ ] A test build runs successfully and logs show push and optional Swarm update
- [ ] `reports/env-credentials-audit.csv` is updated and committed if the status changed

---

## Notes / Security

- **Do not commit secrets to git.** Use Key Vault or GitHub secrets.
- Use least-privilege tokens and rotate them regularly.

---

If you'd like, I can: (A) re-run the Key Vault sync once you restore vault access, (B) accept tokens you place into `deploy/local-ci/.env` to run a local-registry end-to-end test, or (C) attempt a dry-run publish with a local registry and report results. Please let me know which option you prefer or assign this issue to others if needed.

---

_Assigned to: @yushchyr_
_Label: infra, security, priority:high_
