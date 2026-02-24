Notify templates

This folder contains example notification templates for Slack and Microsoft Teams used by the release upload workflows.

Files:
- `slack-default.md` — Slack message example using placeholders
- `teams-default.md` — Teams message example using placeholders

Placeholders:
- `{repo}` — owner/repo
- `{release_name}` — release name
- `{release_tag}` — release tag
- `{release_url}` — link to the release
- `{uploads}` — rendered list of uploaded files (each line looks like: • filename (id: ...))

How to use:
1. Copy or adapt a template and add it to repository secrets (Settings → Secrets → Actions): `SLACK_TEMPLATE` or `TEAMS_TEMPLATE`.
2. The workflows will use these secrets when available to render messages.

Security: treat templates as non-secret content but do not include secret URLs directly in templates; store webhook URLs separately in `SLACK_WEBHOOK_URL` / `TEAMS_WEBHOOK_URL` secrets.
