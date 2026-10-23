# MEFRION 外部検証環境の構築案（2026-10-09 JST・作成承認済み）

目的：実際の2アカウントで認証・家族写真共同編集を確認し、第3者/退出者に画像もAPIも見せない試験を実行する。現在の固定demo認証でこのゲートを完了扱いにしない。

## 作成するもの
- Supabase Free の検証プロジェクト **MEFRION-development** を1件。APAC、日本リージョンを選択できれば東京。選択不可の場合は具体的リージョンを確認してから保存。
- managed Auth（最初は検証者のメール認証）、PostgreSQL、家族原写真用の **private bucket**、公開派生用の別bucket（初期private）、認証画像gateway。
- 写真・人間データは合成試験データから開始。実家族写真や本番データを自動投入しない。
- DBの直接匿名アクセスをRLSでdeny。運営者は一般利用者と別権限/MFA、私的アルバムを任意取得できない。
- 原写真のURLを公開しない。画像を取得するたびにmembership/失効versionを確認。gateway外の直接取得を敵対試験する。
- APIの検証用接続とアカウント設定のみ。App Store/TestFlight/一般公開、本番データ移行はこの承認の対象外。

## 費用と制限
公式料金はFree **$0/月**。DB500MB、file storage1GB、egress5GB、非活動1週で停止、active project最大2件（2026-10-09確認）。
有料プランへ自動変更しない。有料オプション・SMTP契約・独自ドメイン・追加resourceは別承認。
Freeは自動backupを含まないため、公開運用向けの契約・保持・復旧計画として採用したとは扱わない。
Apple Developer ProgramとAppleログインの正式設定、Google OAuth project、メール配信の本番設定も個別に確認する。

## 接続・秘密
パスワード/秘密鍵をチャットに送らない。認証は本人操作。必要なキーはgit除外の端末設定へ保持し、名前だけを記録する。
service-role keyをiPhoneへ埋め込まず、公開利用するのはpublishable keyだけ。秘密をスクリーンショット・ログ・Gitに含めない。

## 検証ゲート
1. 実認証2名で記録追加、第三者/匿名/運営roleをAPIと画像から拒否。
2. 単回招待/並行承認、退出/解除commit後の全画像拒否。
3. 原写真再取得・失敗分再送、提供者用途別同意・取消・削除連動。
4. 実iPhoneまたはSimulatorで操作、実施ログと未実施項目を保存。

ユーザーが2026-10-09にSupabase Free検証環境1件、$0範囲の作成を承認。本人がサインイン/認証情報設定/作成を実施。MEFRION-development（pmrvzpuznwzuejbuhaqm）の作成、Freeプラン、非公開DB/bucketsと17件のSQL権限試験を確認。詳細はdocs/evidence/SUPABASE-DEVELOPMENT.md。Stripe Projects catalogにはSupabase auth/database/storageを確認済みだが、Projects init/規約同意/アカウント連携は実行していない。
公式根拠：https://supabase.com/pricing
