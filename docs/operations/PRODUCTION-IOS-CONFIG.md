# iPhone配布版の公開接続設定

MEFRIONのReleaseは、開発用Supabaseには接続しない。配布版には独立した本番Supabaseプロジェクトの**公開**URLとpublishable keyだけを組み込む。service_role key、DBパスワード、SMTP認証情報、Apple/Googleの秘密鍵はアプリに入れない。

`ios/MEFRION/ProductionPublicConfiguration.json` をローカルで作る（Git管理対象外）。実値をチャットやログに貼らず、Supabase管理画面から取得する。

```json
{
  "url": "https://YOUR_PRODUCTION_PROJECT.supabase.co",
  "anon_key": "sb_publishable_YOUR_PRODUCTION_KEY"
}
```

XcodeのDebugは既存の`DevelopmentPublicConfiguration.json`だけを、Releaseは上記本番設定だけを同梱する。Releaseで本番設定がない、開発用URLを使う、予期しない項目を含む場合、ビルドを停止する。Archive時はさらに`dev.local.*`の開発用Bundle IDを拒否する。設定の検証は`scripts/copy_ios_public_configuration.py`、回帰試験は`tests/test_ios_public_configuration.py`。

本番設定を追加しただけでは申請できない。本番Supabaseに必要なマイグレーション・RLS・Storage・Edge Functions・Auth設定・メール配信を適用し、データ保護と削除連動を確認する。App Store用Bundle ID、Apple/Google認証、正式な規約・プライバシーURL、審査用アカウント、実機Releaseの通し試験も必要。準備の状態は`docs/release/APP-STORE-READINESS-20261013.md`と`PROGRESS.md`に記録する。
