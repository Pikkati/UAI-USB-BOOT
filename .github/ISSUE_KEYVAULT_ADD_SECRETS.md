Title: Add repository secrets for Key Vault integration tests

**Purpose**
Add the GitHub repository secrets required for the Key Vault integration tests and set up the test secret in the Key Vault.

**Required secrets**
- `AZURE_CREDENTIALS` — JSON output from `az ad sp create-for-rbac ... --sdk-auth` (used by `azure/login` action)
- `KV_TEST_VAULT` — Key Vault name (short name, without `.vault.azure.net`)
- `KV_TEST_SECRET_NAME` — Name of an existing secret in the vault to use for read-only tests

**Optional secrets**
- `KV_TEST_SECRET_VALUE` — The expected value of the above secret (test will assert equality when present)
- `KV_TEST_MANAGE` — Set to `true` to enable the optional create/delete integration test (requires SP with `set`/`delete` permissions)

**Steps**
1. Create or verify the test secret in Key Vault (if it doesn't exist):

```bash
az keyvault secret set --vault-name <KV_TEST_VAULT> --name <KV_TEST_SECRET_NAME> --value "your-test-value"
```

2. Add repo secrets via GitHub UI (Repository → Settings → Secrets → Actions → New repository secret) or using `gh` CLI:

```bash
# Example using gh (replace values)
echo -n "$AZURE_JSON" | gh secret set AZURE_CREDENTIALS --repo <owner>/<repo> -b -
printf '%s' "my-vault-name" | gh secret set KV_TEST_VAULT --repo <owner>/<repo> -b -
printf '%s' "IMAP_HOST" | gh secret set KV_TEST_SECRET_NAME --repo <owner>/<repo> -b -
```

3. If you will run the manage-mode integration test, ensure the service principal has `set` and `delete` permissions, and set `KV_TEST_MANAGE=true` in repo secrets.

**Verification**
- After adding secrets, run the Key Vault integration workflow manually and confirm the job proceeds past the configuration validation step.

**Acceptance criteria**
- All required repo secrets are present.
- The optional `KV_TEST_MANAGE` can be set and is documented in the workflow to indicate manage-mode tests will run.
