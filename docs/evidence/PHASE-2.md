# Phase 2 / 2026-10-08 JST
実装：backend/family.py、loopback開発API、単回/期限付き招待、認証後の範囲確認、取消、別DB接続からの並行承認、家族閲覧/写真追加、自分写真のみ編集削除、管理者全記録管理、用途別提供者同意、通知off/immediate/batched設定、退出/解除、退出後の同意撤回と削除依頼。
画像gatewayはリクエストごとに家族権限を照合、no-store。**画像は所有fixtureのみで、本物の家族写真の安全な保存・配信が完了した証明ではない。**
実試験：bundled Python `-m unittest discover -s tests -v`、35件成功(5.226秒)。初回はテスト側のasset名間違いと重複確認未指定で失敗、入力を修正し再実行成功。API guest/第三者拒否と解除後の画像URL/album拒否を実際にHTTPで確認。
未完了：Apple/Google/メール実認証、guest復帰、原写真server保存/中断再送/原本取得、managed private storage、本iPhone家族導線、実account停止/退会、プッシュ。外部project/資格なし。
追加：iPhone保護領域への端末内snapshot保存と失敗rollbackを実装、Swift試験中。これはサーバー保存ではない。
費用：追加外部課金0、契約/本公開なし。
