# 公開共有Webの接続準備（2026-10-10）

承認を受け、Free検証環境の `shared-page` だけをゲストアクセス可能にした。原本・運営・認証APIの保護は維持する。実HTTPでは正常共有が200でも `text/plain` / `nosniff` になり、HTMLページとして利用できない。Supabase公式も標準Edge FunctionsのHTML配信をサポートしていないと説明する。

https://supabase.com/docs/guides/functions/http-methods

このため `backend.shared_server` を公開共有専用のオリジンとして用意した。`python -m backend.shared_server --port 9792` でループバックの検証が可能。`/cloud-shared/<UUID>`、その公開派生画像、`/shared.css` のGETのみを扱う。管理画面、家族原本、開発設定、デモAPI、書き込み経路はない。匿名projectionと公開派生APIだけを使い、service keyとユーザー資格を必要としない。画像取得前後にprojectionを再確認し、撤回・障害時に写真を返さない。HTMLはエスケープし、no-store/CSP/nosniffを適用する。

本番ホストと正式ドメインは未指定。標準ライブラリの検証HTTPサーバーをそのままインターネットへ開放しない。確定するHTTPS gatewayにはTLS、接続/応答制限、レート制限、ログで共有IDを不要に保持しない方針、稼働監視が必要。既存の管理・デモAPIを含む `backend.server` を公開共有ホストへ配備しない。

残る接続作業は、選定済みホストの設定、正式HTTPS URLと絶対OGP URL、Universal Links/AASAとApple署名、外部ゲスト表示・取消後404の確認。この情報が届くまでアプリの共有URLを有効にしない。ホストを推測して新しい外部契約を作成していない。

実証拠: `docs/evidence/p01-share-http.json`（外部HTTPの制約と専用ローカルHTML）、`p01-public-only-share.png`、Pythonの専用2試験を含む69件。公開の完了証拠ではない。
