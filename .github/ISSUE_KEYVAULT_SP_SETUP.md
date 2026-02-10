Title: Set up Azure Service Principal for Key Vault integration tests

**Purpose**
Create an Azure Service Principal (SP) with the minimum permissions required for CI to access the Key Vault for integration testing.

**Steps**
1. Replace placeholders below (<SUBSCRIPTION_ID>, <RESOURCE_GROUP>, <VAULT_NAME>) with your values.

2. Create a service principal scoped to the Key Vault (RBAC):

```bash
az ad sp create-for-rbac \
  --name "uai-ci-keyvault" \
  --role "Key Vault Secrets User" \
  --scopes "/subscriptions/<SUBSCRIPTION_ID>/resourceGroups/<RESOURCE_GROUP>/providers/Microsoft.KeyVault/vaults/<VAULT_NAME>" \
  --sdk-auth
```

The command returns a JSON object suitable for the `AZURE_CREDENTIALS` repository secret.

3. (Alternative) If your tenant uses Access Policies for Key Vaults, create an SP and grant secret permissions explicitly:

```bash
# Create SP (no role assignment)
az ad sp create-for-rbac --name "uai-ci-keyvault" --skip-assignment --sdk-auth

# Grant secret permissions to the SP by object id
az keyvault set-policy --name <VAULT_NAME> --secret-permissions get list --spn <CLIENT_ID>
```

4. Save the SDK auth JSON (`AZURE_CREDENTIALS`) as a **Repository secret** in GitHub (Settings → Secrets → Actions → New repository secret). Prefer the single `AZURE_CREDENTIALS` JSON (it contains clientId, clientSecret, tenantId, subscriptionId).

**Verification**
- From your local machine (replace values), verify the SP can read a secret:

```bash
az login --service-principal -u <CLIENT_ID> -p <CLIENT_SECRET> --tenant <TENANT_ID>
az keyvault secret show --vault-name <VAULT_NAME> --name <SECRET_NAME> --query value -o tsv
```

**Acceptance criteria**
- `AZURE_CREDENTIALS` repository secret exists and contains valid JSON.
- The SP can run `az keyvault secret show` and receive the secret value (or has appropriate error-level logs when firewall/network blocks occur).

**Notes & guidance**
- Prefer the least-privileged role: `Key Vault Secrets User` (RBAC) or the minimal Access Policy that grants `get` (and `set/delete` only if you opt-in to manage-mode tests).
- Consider using a dedicated test Key Vault to avoid touching production secrets.
