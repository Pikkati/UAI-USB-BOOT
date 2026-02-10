GHCR PAT (CI) — instructions

Purpose
-------
This repository can optionally use a Personal Access Token (PAT) with package write permission to push container images to GitHub Container Registry (GHCR) from CI.

Why use a PAT
--------------
- Organization policies may prevent the default `GITHUB_TOKEN` from creating organization packages.
- A PAT scoped to `packages: write` (and repository access if needed) allows CI to push images reliably.

Quick steps
-----------
1. Create a PAT (recommended: Fine-grained Personal Access Token)
   - Go to GitHub > Settings > Developer settings > Personal access tokens > Fine-grained tokens > Generate new token.
   - Select repository access (prefer limiting to this repository)
   - Under Permissions, set `Packages` to **Write** (and `Contents` read if you need repo access).
   - Create the token and copy it (store it securely).

   Alternatively (classic tokens): create a classic token with `write:packages` (and `repo` if needed).

2. Add the PAT to repository secrets
   - Go to the repository > Settings > Secrets and variables > Actions > New repository secret
   - Name: `GHCR_PAT`
   - Value: the token string
   - (Optional) Add `GHCR_USERNAME` with the username that owns the token (useful when the token belongs to a machine/service user).

3. (Optional) Organization-level secret
   - If multiple repos share the same token, add it as an organization secret and scope it to required repositories.

4. Validate CI
   - When `GHCR_PAT` is set, the workflow will use it to log in and push images on `push` events.
   - If `GHCR_PAT` is not present, the workflow will build images but **will not push** them to GHCR (safe default to avoid failures).

Notes & best practices
----------------------
- Prefer a machine user or fine-grained token with minimal scope instead of a personal token tied to an individual.
- Set an expiration/rotation policy for the PAT and update the secret when rotated.
- Ensure organization settings allow the token account to create packages; org admins may need to adjust package creation policies.

If you want, I can also open a small PR adding these docs and the workflow changes to the default branch after you review.
