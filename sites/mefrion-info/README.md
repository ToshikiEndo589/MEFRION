# MEFRION public website

Vercel project: `mefrion` in `toshiki-endos-projects`.
Site directory: `sites/mefrion-info`. Runtime: Node.js 22. Pinned Vercel OIDC/functions dependencies, audited lockfile.

The API adapter reuses `worker/index.js` for public legal/support pages, the operator console, and allowlisted Supabase shared pages. The console contains only a public configuration; all moderator privileges and MFA are enforced by Supabase. Email delivery and TOTP enrollment are completed by the account owner. Tokens are memory-only and never included in the deployment.

`node --test scripts/*.test.mjs` runs routing and isolated authentication-flow tests without sending real emails or using real authentication codes.

Encrypted off-site backups remain at the existing independent object-store endpoint. `/internal-backup/*` deliberately returns 404 on Vercel. Do not move backup tokens, recovery keys, data, or credentials into this project. Existing app URLs remain valid until the new host passes public checks and app/store configuration is updated.

Deployment status and migration evidence: `docs/evidence/FINAL-VERCEL-MIGRATION-20261025.md` in the repository root.


Security operations: `/console/security`. `console/security-panel.html`, `console/security.js` and `console/security.css` are readable source assets; `node scripts/security-assets.mjs` embeds them in the existing router. The build is deterministic. Security ingestion uses short-lived Vercel OIDC restricted to this production project, never a Supabase service key in Vercel. Sensitive request bodies, full URLs, authentication headers and raw addresses are not persisted.

The console requires a confirmed operator, verified TOTP, active Auth session and unexpired moderator role. Recording runs without a console session. This is application security telemetry, not a complete replacement for Vercel Firewall or Supabase platform logs. Coverage and omissions appear in the console. See `docs/security/SECURITY-OPERATIONS.md` in the repository root for retention, incident handling, limitations and deployment/rollback.

## Ads

Vercel serves the separate Ads workspace at `/ads`. Reporting requires an active
moderator or administrator session with verified TOTP. Changing delivery also
requires the administrator's publish permission. The workspace does not use the Supabase
service-role key. Preview deployments do not contact live advertisers or Apple.

### Connect an advertiser

Set variables on the Vercel **Production** environment. Give tokens access only
to the intended MEFRION ad account. Begin with read access and with activation
disabled. Check the first report against the native dashboard before enabling
writes.

| Platform | Server-only connection variables | Delivery controls |
| --- | --- | --- |
| X | `X_ADS_ACCOUNT_ID`, `X_ADS_CONSUMER_KEY`, `X_ADS_CONSUMER_SECRET`, `X_ADS_ACCESS_TOKEN`, `X_ADS_ACCESS_TOKEN_SECRET` | `X_ADS_ENABLE_ACTIVATION`, `X_ADS_CURRENCY`, `X_ADS_MAX_TOTAL_MICROS` |
| Instagram | `META_ADS_ACCOUNT_ID` (digits without `act_`), `META_ADS_ACCESS_TOKEN`, `META_ADS_API_VERSION` (a supported Graph API version), `META_ADS_APP_SECRET` (when using app secret proof) | `META_ADS_ENABLE_ACTIVATION`, `META_ADS_CURRENCY`, `META_ADS_MAX_TOTAL_MICROS`, `META_ADS_OPERATOR_USER_ID` (optional verified operator ID for Instagram only) |
| TikTok | `TIKTOK_ADS_ADVERTISER_ID`, `TIKTOK_ADS_ACCESS_TOKEN` | `TIKTOK_ADS_ENABLE_ACTIVATION`, `TIKTOK_ADS_CURRENCY`, `TIKTOK_ADS_MAX_TOTAL_MICROS` |

X requires an approved Ads API app and user access. Instagram requires Meta
Marketing API access (`ads_read` for reporting and `ads_management` for writes).
TikTok requires an approved TikTok API for Business app and advertiser access
for campaign management and reporting. Do not put tokens in the browser, Git,
or public environment variables.

Create the ad, creative, targeting, schedule and App Store URL in the media
manager. Ads can start and stop an existing eligible campaign. Activation is
opt-in per platform and requires the reviewed budget in the configured currency
to be within the per-campaign cap. For example, JPY 5,000 is 5,000,000,000 micros.
X also requires a daily budget. Instagram writes require explicit Instagram-only
placements on every applicable ad set and a campaign lifetime budget to start.
TikTok writes cover regular campaigns and require a lifetime budget to start.
Each write checks the latest available provider state. Check the media manager
after an unconfirmed write before trying again. The media manager is the source
of truth for billing and delivery. Vercel runtime logs record the provider,
campaign ID, requested state and confirmation outcome, without credentials.

For Instagram, verify the MEFRION Instagram identity and payment setup in the
intended Meta ad account before enabling delivery. Use a token scoped to that
account and store it in the Vercel Production environment. The optional operator
ID is the Supabase Auth user UUID, not an email address. This setting grants
Instagram delivery access only after the server verifies the active operator
role, current session, MFA, and matching user ID. It does not grant broader
admin rights. Start by reviewing a campaign that is already paused, with
Instagram-only placements, a lifetime budget and an end date, without changing
its status. Use the approved currency and per-campaign cap before turning on
activation.

### Interpret the reports

- The comparison view shows each media account separately. Select a platform
  for campaign and daily data. Instagram and TikTok also expose ad set/group
  and ad-level breakdowns. Use the same-length prior period to compare deltas.
- X reporting covers `ALL_ON_TWITTER` in UTC for the first 20 campaigns.
  Instagram uses `publisher_platform=instagram` rows. TikTok Ads may include
  other network placements if the advertiser selected them. Meta and TikTok
  use account time zones. The page marks results when a pagination limit is
  reached. Shorten the time range or use the media manager for a full export.
- Blank results may be unsupported, delayed, privacy-limited, or unreported.
  The dashboard avoids computing ratios when their inputs are incomplete.
  CTR and CPC use link or destination clicks. Attribution and video definitions
  vary by media. The diagnostic rules only suggest what to investigate.
- Ads uses the existing Apple Sales and Reports credential in `ASC_KEY_ID`,
  `ASC_ISSUER_ID` and `ASC_PRIVATE_KEY`. Request the detailed download report
  from the page for selected dates. Coverage and privacy limitations are
  shown alongside Apple's campaign-token counts. A report may still be
  unavailable or incomplete after the standard store dashboard is populated.
- Generate campaign links from an existing MEFRION App Store Connect link.
  The Ads CSV template can map Apple tokens to media campaign IDs and include
  aggregate D1/D7/D30 retention from App Store Connect. Enter percentages
  between 0 and 100 and leave suppressed numbers blank. CSV data stays in the
  current browser session. Apple CPI requires matching media and Apple dates
  and a complete media spend figure.

Build with `node scripts/security-assets.mjs`. Run
`node --test scripts/*.test.mjs`. Tests use mock advertisers and Apple fixtures.

The Creative Lab creates up to 24 JPEG variants on-device and exports a ZIP
with distinct App Store campaign links. Set `META_ADS_BUSINESS_ID` in production
to read Creative Tests for the connected Meta business. Create a `SPLIT_TEST_V2`
in Meta Experiments with one ad per cell, balanced assignment, a single ad set
with Instagram-only manual placements, and matching ad copy. Start and end on
the ad account's midnight boundaries and use a duration of at most seven days.
Use fresh campaign links exclusively for the test. The workspace refreshes the
selected study while open and joins Apple counts to the verified creative URLs.
The result uses measured first downloads per unit of spend, waits for Apple's
attribution window and complete report dates, and requires 20 visible downloads
per arm, a multiple-comparison adjusted rate test, and a practical 15% difference.
Privacy-suppressed or incomplete data stays unresolved. Meta owns scheduling and
delivery. A suggested image never starts or changes a campaign automatically.

[X Ads API](https://docs.x.com/x-ads-api/analytics) ·
[Meta Marketing API SDK](https://github.com/meta/facebook-nodejs-business-sdk) ·
[TikTok API for Business](https://business-api.tiktok.com/portal/docs/marketing-api/v2.0) ·
[Apple campaign links](https://developer.apple.com/help/app-store-connect-analytics/acquisition/campaign-links/)
