# クラウドSNS公開境界（検証環境のみ）

2026-10-09。承認済みSupabase Freeプロジェクト内、合成試験写真のみ。正式サービス公開ではない。

実装：private schemaのpublic_profiles/posts/media/blocksはRLS、クライアント直接grantなし。公開プロフィールはownerの明示操作のみ。写真1〜4枚/本文500/公開明示/提供者の用途同意/同意versionをサーバーで確認し、同一request UUIDは同一投稿に対応。通常SNSと外部共有の用途を分ける。

公開依頼はpending。service-only workerが原写真を取得し向きを補正、1200px以下のJPEGに再符号化、EXIF/GPS/コメント/XMP/ICCを除く。公開派生もprivate bucketで保持。全画像の実オブジェクトと現在の同意を再確認するまで公開状態にしない。手動workerであり、自動配信は未実装。

公開feedはPetの公開項目/本文/派生mediaの不透明IDだけを返す。provider/actor/元画像path/私的写真IDを返さない。public-image gatewayが取得前後に公開状態と同意を再確認、no-store。無効なBearerは匿名として扱わず401。legacy-secretだけのJWT判定はOFF、Bearerがある場合は関数内Auth.getUserで実トークン検証。family-originalsは引き続きprivate-image専用であり、公開URL/署名付きURL/クライアント直接読取を許可しない。

同意version変更/写真削除/公開停止で同期的に露出を止め、派生画像の削除outboxも作成。撤回中の遅いworker完了は公開を拒否し、既に削除ack後でも再度purgeを積む。同意を戻しても過去投稿を復活させない。用途別撤回は他用途へ誤適用しない。

実検証：

- publication_boundary.sqlのトランザクション20項目成功。JWT role/storage metadataを模擬し、blob実体は生成せずrollback。SQL成功を実画像取得の証拠にしない。
- verify_publication_e2e.pyで実Auth/合成EXIF JPEG/実storage/加工worker/gatewayの31項目成功。公開前の拒否、明示/用途/上限、同一要求、safe feed、匿名派生取得、無効Bearer401、元写真ID404、直接/署名付き派生拒否、公開画像1200x800とメタデータ空、撤回後即時404、再同意で非復活を確認。試験終了時にPetを非公開へ戻し写真削除、手動削除workerで原写真/派生の2件処理。
- Python全59件成功。最初の加工テストでJPEG commentが再保存時に残ることを検出し、image.info.clear()を追加して修正。失敗ログpython-public-media.logと修正後python-public-media-final.logを保持。
- iPhoneに公開投稿の確認/用途同意/依頼/処理待ち/取り消しと検証用クラウドfeedを追加。最新native投稿操作テストは実行中。compile成功を操作成功と先取りしない。
- native初回はsheet初回描画で写真一覧が空になる問題で失敗。複数のStateとBool表示を、写真/画像を1つに保持するsheet(item:)へ修正。2回目は写真選択が成功したが、キーボード表示中のテストでラベル側へのタップがUISwitchを切り替えず依頼がdisabledのままになり失敗。入力完了UIと実UISwitchへの操作/状態assertionを追加し、再実行中。ios-cloud-publication / ios-cloud-publication-retryの失敗記録も保持。各失敗後はtest_onlyの本人IDとE2E合成試験Pet名を確認する専用cleanupで、自作合成写真のみ削除した。

未完了：自動worker/lease負荷/実HTTP競合試験、クラウド運営管理・本運営Auth/MFA、like/follow/comment/report/blockのAuth RPC接続、通知/検索/共有Web/全退会連動、実写真品質と全端末QA、正式公開設定/申請。SQL blocksはprojection検証の基礎のみで、native/一般ユーザー操作はまだ未接続。T-01〜69全件完了ではない。

画像ライブラリはローカルで確認したPillow12.3.0に固定。公式配布元：[PyPI](https://pypi.org/project/pillow/12.3.0/)。CIにインストール定義を追加したが、リモートCIは未実行。

最終再テストはSimulator UI 1件成功・失敗0・skip0（ios-cloud-publication-fixed-summary.json）。写真選択、同意2個が両方ONになるまで要求不可、実RPCのpending表示、停止RPC、プロフィール非公開化、私的写真削除まで実行。保存したpending/withdrawn画面を確認。失敗した2回の証拠も保持。手動削除workerでテスト由来の5件を処理・失敗0。公開画像自動worker・クラウドSNS交流/運営・全機能完成は未達。
