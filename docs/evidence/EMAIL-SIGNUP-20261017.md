# メール新規登録の復旧作業（2026-10-17）

## 判明した原因

Supabase の `MEFRION-development` では `Authentication > Emails > SMTP Settings > Enable custom SMTP` が OFF。Supabase 標準のメール送信はプロジェクトチーム内の承認済みアドレスに限定されるため、一般利用者は確認メールを受け取れない。アプリの入力条件だけを変えても解消しない。

## 実装・検証

- ウェルカム画面からメール新規登録へ直接進める。現在利用できない Apple / Google の選択肢は一時的に非表示。
- 家族共有のログイン画面からもメール新規登録を直接開ける。メール確認・復旧の導線は維持。
- iPhone 17 / iOS 27 Simulator で `testSignupRequiresMatchingPasswordAndExplicitChecks` と `testSignupExplainsRequirementsAndConfirmsPassword` を実行し、2件成功・失敗0・skip0。結果: `/tmp/mefrion-signup-sim/Logs/Test/Test-MEFRION-2026.10.17_12-06-24-+0900.xcresult`。
- iPhone 16 実機向け Debug ビルドとコード署名検証成功。最初のインストールは接続エラー、再試行でインストール成功。アプリ起動成功。

## SMTP 接続とテンプレート

- Brevo の無料アカウントと `MEFRION <nextedovation@gmail.com>` の送信元確認を Dashboard で確認。本人の電話番号認証と、キー作成時の追加メール認証が完了した。
- 専用キー `MEFRION Supabase Auth` を1件作成し、Brevo 画面で Active、有効期限 2027-10-17 を確認。秘密値はリポジトリ、チャット、ログへ保存していない。
- Supabase `MEFRION-development` で custom SMTP を ON。送信元、Brevo SMTP host/port/login とパスワードを保存後に再表示し、ON と「Stored password is hidden」を確認。
- 登録確認とパスワード復旧の件名・本文を日本語の6桁コード用に変更し、`{{ .Token }}` を含む保存済みテンプレートを確認。iOS の登録後案内もリンク方式からコード方式へ修正。
- 最終変更後、iPhone 17 / iOS 27 Simulator で `MEFRIONTests` 42件成功、失敗0・skip0。結果: `/tmp/mefrion-email-test/Logs/Test/Test-MEFRION-2026.10.17_15-30-23-+0900.xcresult`。iPhone 16 実機向け Debug ビルドとコード署名検証、上書きインストール成功。端末ロック中の初回 CLI 起動は失敗したが、ロック解除後の再試行で起動成功。
- 専用のGmail plus aliasでSupabase `/auth/v1/signup` を1件実行し、HTTP 200を確認。Brevoの Real time に同件名・同宛先の `Sent` と `Delivered` が表示された。受信者の端末やメール本文の目視、コードの入力・認証は行っていない。この未確認テストユーザーは残っている。
- 本人から、iPhoneで確認メールを受信し、メール内コードでの登録と最初のPet作成まで完了したと報告を受けた。本人の画面操作は開発者側で直接記録していない。

## 未検証

Brevo上での配達イベントに加え、本人のiPhoneで確認メール受信・コード確認・初回Pet作成まで報告された。再送、パスワード復旧、コード期限切れは今回未検証。正式公開に向けて独自送信ドメインの取得・認証と配信量・悪用対策が残る。

Brevo の無料枠は 300 通/日。独自ドメインがない場合、Gmail 送信元は Brevo 側の代替ドメインに書き換えられるため、正式運用には送信ドメインの取得・認証が必要。費用発生や契約の最終操作は具体的な条件を確認してから実行する。
