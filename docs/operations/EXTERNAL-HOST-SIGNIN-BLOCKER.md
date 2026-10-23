# 外部ホスト接続の本人認証待ち

2026-10-11。検索とpreflightのみ実行。外部契約や配備は未実行。Stripe Projectsの経路を利用する場合の実エラーと対処をそのまま記録する。直接ホストへログインする別経路を選ぶ場合はこのStripeアカウント自体を必須とはしない。

## 実際のエラー（原文）

BROWSER_AUTH_REQUIRED

No Stripe session with a live-mode account is signed in. Rerun this same `stripe projects init` command without `--preflight`, keeping every other argument (such as `--from` or a project name) and including `--json --yes`. It returns `BROWSER_AUTH_REQUIRED` with `details.reason` `handoff_prepared`, an `onboarding_url`, a `browser_url` and a `verification_code`. Ask the user to open `onboarding_url` to create or choose their Stripe Projects account, then approve the sign-in at `browser_url` with the code. Once they have, run that command again. Do not run `stripe login` yourself.

## スキルの停止条件

`If any check fails with BROWSER_AUTH_REQUIRED, PROJECTS_SESSION_UNUSABLE, or ACCOUNT_NOT_ELIGIBLE, stop here.`

出典: /Users/toshiki/.codex/plugins/cache/openai-curated-remote/stripe/8.0.0/skills/stripe-projects/SKILL.md 。今回の包括承認だけでは本人ブラウザー認証を完了できないため、init/規約同意/契約を進めていない。外部配備は本人ログイン後に再開する。
