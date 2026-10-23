# MEFRION メール登録の配信設定

対象は Supabase `MEFRION-development` の Auth メール。確認を必須のまま維持し、一般ユーザー宛てに送信できる SMTP を接続する。

1. Brevo の本人登録と初期設定を完了する。送信元に `nextedovation@gmail.com` を登録し、本人のメールで確認する。独自ドメイン取得後は MEFRION 所有ドメインの送信元に変更し、SPF/DKIM/DMARC を認証する。
2. Brevo の Transactional > SMTP で SMTP ログインと専用 SMTP キーを取得する。API キーは SMTP パスワードとして使用しない。秘密値をリポジトリ・チャット・ログへ保存しない。
3. Supabase Dashboard > Authentication > Emails > SMTP Settings で custom SMTP を有効にする。Sender email は確認済みの送信元、Sender name は `MEFRION`、Host は `smtp-relay.brevo.com`、Port は `587`、Username は Brevo に表示された SMTP ログイン、Password は専用 SMTP キーを設定する。
4. 確認メールと復旧メールのテンプレートには `email-templates/confirmation.html` と `email-templates/recovery.html` を使用する。コードは `{{ .Token }}` で、アプリのコード入力へ戻る。テンプレート設定後に件名・文面を目視する。
5. 一般のアドレスで新規登録し、受信、コード確認、ログイン、最初の Pet 作成を実機で試す。再送、既登録、期限切れコード、パスワード復旧も別々に試す。試験用アカウントとメールの削除は、依存関係と本人承認を確認してから行う。

Brevo 無料枠は 300 通/日。Gmail 送信元は Brevo 側の代替ドメインに書き換えられる暫定運用なので、正式公開前に独自ドメインを取得して送信元認証を済ませる。Supabase custom SMTP 設定後も初期の送信上限があるため、配信量と悪用対策を監視する。
