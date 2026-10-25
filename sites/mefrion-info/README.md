# MEFRION public website

Vercel project: `mefrion` in `toshiki-endos-projects`.
Site directory: `sites/mefrion-info`. Runtime: Node.js 22, no external runtime dependencies.

The API adapter reuses `worker/index.js` for public legal/support pages, the operator console, and allowlisted Supabase shared pages. The console contains only a public configuration; all moderator privileges and MFA are enforced by Supabase. Email delivery and TOTP enrollment are completed by the account owner. Tokens are memory-only and never included in the deployment.

`node --test scripts/*.test.mjs` runs routing and isolated authentication-flow tests without sending real emails or using real authentication codes.

Encrypted off-site backups remain at the existing independent object-store endpoint. `/internal-backup/*` deliberately returns 404 on Vercel. Do not move backup tokens, recovery keys, data, or credentials into this project. Existing app URLs remain valid until the new host passes public checks and app/store configuration is updated.

Deployment status and migration evidence: `docs/evidence/FINAL-VERCEL-MIGRATION-20261025.md` in the repository root.
