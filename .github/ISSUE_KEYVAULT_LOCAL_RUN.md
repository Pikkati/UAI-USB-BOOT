Title: Local run guide for Key Vault integration tests

**Purpose**
Describe how to run Key Vault integration tests locally for development and troubleshooting.

**Prerequisites**
- `az` CLI installed and authenticated (`az login`) or set `AZURE_CLIENT_ID`/`AZURE_CLIENT_SECRET`/`AZURE_TENANT_ID` env vars for a service principal
- Python dev environment with `pytest` installed

**Steps**
1. Export configuration environment variables locally (example for bash):

```bash
export KV_TEST_VAULT="my-test-vault"
export KV_TEST_SECRET_NAME="MY-EXISTING-SECRET"
# Optional if you want the test to assert exact value
export KV_TEST_SECRET_VALUE="expected-value"
# Optional: enable create/delete manage test
export KV_TEST_MANAGE=true

# Provide SP creds for DefaultAzureCredential if you're not using az login
export AZURE_CLIENT_ID="..."
export AZURE_CLIENT_SECRET="..."
export AZURE_TENANT_ID="..."
```

2. Install dependencies (for manage test you need Azure SDK packages):

```bash
python -m pip install --upgrade pip
pip install pytest azure-identity azure-keyvault-secrets
```

3. Run the tests locally:

```bash
pytest -q tests/test_keyvault_integration.py -m "integration and network" -q
```

**Optional helper script**
- A helper local run script is available at `scripts/ci/run_keyvault_integration_local.sh` (Unix) to simplify the steps.

**Acceptance criteria**
- Tests run locally and either pass or are skipped with a clear message explaining missing configuration.
