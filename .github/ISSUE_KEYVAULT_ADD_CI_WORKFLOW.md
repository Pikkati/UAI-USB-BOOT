Title: Add and test Key Vault integration workflow (manual dispatch)

**Purpose**
Add a GitHub Actions workflow that runs Key Vault integration tests manually (workflow_dispatch) so maintainers can validate real Key Vault access without exposing secrets on every push.

**Steps**
1. Ensure the repository has the workflow file at `.github/workflows/keyvault-integration.yml` (created by the changes in this PR).
2. Confirm repository secrets exist: `AZURE_CREDENTIALS`, `KV_TEST_VAULT`, and `KV_TEST_SECRET_NAME` (see other issues).
3. Run the workflow manually:
   - Go to the **Actions** tab → **Key Vault Integration Tests** workflow → **Run workflow**
   - Choose `run_mode` input (`read-only` or `manage`) and click **Run workflow**
4. Inspect job logs:
   - Confirm `Verify configuration` step passes.
   - Confirm `Login to Azure` step completes (no auth errors).
   - Confirm `Run Key Vault integration tests` step runs and tests pass.

**Acceptance criteria**
- The workflow successfully runs via manual dispatch and completes integration tests.
- Failures are actionable (clear error logs about missing secrets or insufficient permissions).

**Notes**
- This workflow is intentionally manual to avoid exposing or running integration tests on every push.
- If you prefer scheduled runs, we can add an additional `schedule` trigger with careful gating.
