# 公開共有専用サーバーの配備手順

2026-10-11。実装・ローカルHTTPは検証済み。外部配備・TLS・Universal Linksの実機接続は未完了。

`docker build -f deploy/share/Dockerfile -t mefrion-share .`

必要な環境変数:

- `MEFRION_PUBLIC_KEY`: 既存検証プロジェクトのsb_publishable_キー。service keyやJWTは配置しない。
- `MEFRION_PUBLIC_ORIGIN`: ホストが発行したHTTPS origin。空欄なら絶対OGP/AASAは無効。
- `MEFRION_ASSOCIATED_APP_ID`: 署名後のTeam ID.Bundle ID。空欄ならAASAは404。

Dockerには公開用の3 PythonファイルとCSSだけをコピーする。.local、管理画面、家族API、写真、認証設定、デモサーバーは含めない。Gunicornは非root、2 process/4 thread、65秒の上限、HTTPヘッダー上限、1000件ごとの再起動。共有IDとクエリーをアクセスログに保存しない。全レスポンスno-store/noindex。共有・公開派生画像は毎回Supabaseの公開projectionで再認可し、撤回・障害時は表示しない。

ホストでTLS終端、接続上限、分散レート制限、監視/費用アラートを設定する。8080をインターネットへ直接公開しない。画像/CDNキャッシュは無効にする。healthzの成功はサーバープロセス応答の確認だけで、Supabase、同意、メール配信の合格ではない。

配備後は外部端末でHTTPS/content-type、公開カード、撤回後404、旧画像拒否、管理/認証/原本ルート404を確認する。AASAは公開カードだけが対象で、招待秘密を公開Webへ渡さない。アプリのAssociated Domainsと受信処理を接続して実機試験するまではsharedURLの無効状態を維持する。

このMacにはDockerがなく、Docker image自体のbuild/runは未実施。Gunicorn26.2.0は隔離venvで起動し、実HTTPを確認済み。MITライセンス: https://pypi.org/project/gunicorn/ 。Pythonのbase image/tagは実配備時にdigest固定と脆弱性検査を行う。
