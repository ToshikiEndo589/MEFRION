# Supabase無料検証環境（2026-10-09 JST）

ユーザーがFree検証プロジェクト1件の作成を承認。サインイン/CAPTCHA/DBパスワード設定/プロジェクト作成は本人が実施。作成成功をUIで確認。
- 名称MEFRION-development、project ref pmrvzpuznwzuejbuhaqm。
- 作成前Tokyo、テーブル自動公開OFF、RLS自動ONを設定。DB organizationのSubscriptionがFreeであることを作成後確認。有料化操作なし。
- migration 202610090001_private_family.sqlをSQL Editorで適用し「Success. No rows returned.」。mefrion_private schemaの8テーブル/RLS/直接grant無し、認証RPC allowlist、家族原写真family-originalsと公開派生public-derivedの2bucketともprivate。
- SQL private_family.sql実行、17チェック成功。トランザクションで合成Auth rowsとJWT claims/rolesを模擬、終了時rollback。実Authトークン試験の代替ではない。
- private-image Edge Functionを検証プロジェクトへ配置。関数でAuth.getUserによる本人認証→本人権限のRPC→そのpathだけserver側storage取得→返却直前の権限再確認。no-store、signed/public URLを返さない。
- Legacy anon-keyを受け付ける旧JWT gateway checkはOFF。代わりに関数内でAuthサーバーのgetUserを毎回使用し、未認証/匿名Authユーザー/偽トークンを拒否。テスト匿名401・偽Bearer401・匿名RPC401を実HTTPで確認。記録supabase-anonymous-probes.json。
- 公開接続設定のみ.local/supabase-public.jsonに保存。Git除外、mode0600。秘密鍵はiPhoneに持たせない。

証拠：supabase-policy-17.png / supabase-policy-result.txt。SQL editorの仮想入力欄fillが追記になることを発見、実行前キャンセルしてselect-all/pasteで試験内容だけへ置換。誤った二重migrationは実行しなかった。

上記は初回配置時点の記録。以下で実Auth/画像/退出/削除workerを追加検証した。Edge Functionの配置は本サービス正式公開ではない。公開運用・App Store準備未完了。

## 実認証・合成画像 E2E の実施
- server用の既存キーを値非表示で.local/supabase-server.json（0600）へ保持。新規キー/権限を生成していない。iPhoneへ渡していない。
- Admin Auth APIで合成試験専用3Identityを作成。ランダム資格、example.invalid、email送信なし。Petごとのアカウントではない。資格は.localのみ。
- verify_supabase_family.py：実passwordログイン/getUser、A/B/C権限、単回招待、実JPEGupload/gateway、直接/匿名/署名付きURLの拒否、提供者同意/退出/撤回/削除の39チェック成功。supabase-family-e2e.json。
- Simulator testRealCloudFamilyLoginUploadAndDelete：実ログイン/取得/表示/削除成功（30.804s）。初回はMac workspaceをRunnerから直接読もうとしてopenで停止。初回を中断し、RunnerのDocumentsに合成資格だけを0600で配置して解決。初回停止もログを残し、成功に数えない。
- private-image画像は検証UIでjpegDataへ再符号化。選んだ実原写真そのままの保管/品質保持と公開加工は引き続き未完了。
- deletion_worker migration、server専用batch/ackを適用。手動process_deletion_outboxで合成画像2件処理/failed0。一般owner/family403・anon401でworker API拒否。自動worker/全経路・本退会は未完了。
- Release unsigned Simulator build成功。公開用接続設定は未提供のためReleaseで検証サーバーへ接続しない。

## 追加検証と実装
- migration003の家族一覧/匿名Auth guest制限までSQL19チェック成功、supabase-policy-19.png。
- 家族一覧追加時点の全XCTest13件（単体10/UI3）成功、skip0、runtime warning0。ios-cloud-full-summary.json。
- CloudUploadQueueで最大30枚/20MB各・合計100MB、ログイン中の失敗分だけ再試行。同一UUID/同一JPEGを保持し成功分を再送しない。完了画像データをキューから解放。logoutで未送信を破棄し進行中の完了が復活させない。
- verify_cloud_batch.pyで実Auth/合成JPEG30枚の保存・取得・同一予約再試行・削除、125チェック成功。通信断後の再送を模擬した既存オブジェクトはHTTP400/error Duplicate。nativeは400/409のDuplicateだけ許容し、その後finish_photoで本人の予約と実storage存在を再確認。権限拒否は許容しない。
- 写真を背景時に隠しキャッシュを破棄、foregroundで権限を再確認。logout/画面移動中の古い画像応答が再表示を復活させないgenerationチェック。ディスク画像キャッシュなし。
- migration004を適用、本人の提供写真と3用途同意のみ返すprovided_photos RPC。原写真path/Pet私的プロフィール/他提供者を返さない。iPhoneに取消専用の管理画面を追加。
- verify_provider_consents.py：退出後アルバム/画像拒否、本人同意一覧、3用途撤回、再同意拒否、他人/未認証への情報拒否、削除後一覧非表示、25チェック成功。nativeの複数人撤回操作自体は未検証。
- キュー/同意画面追加後XCTest14件（単体13+実cloud UI1）成功、skip0。関連する2単体は部分失敗後のID維持、30枚上限/日付/他Pet/ログアウト中断を検証。もう1単体はDuplicateと権限エラーの区別。既存native cloud UIは実Auth/合成イラスト保存/画像表示/削除を再確認。
- 途中のテスト指定がクラス名を含まずUI0件になった実行は、単体13件のみの成功としてios-cloud-batch-finalに記録。修正後ios-cloud-batch-uiでUI1件、ios-provider-finalで単体13+UI1件の実行を確認。
- 本番への自動配信OFFだが別GitHub repositoryの接続が表示される。本人に意図を確認中。接続変更なし。

残り：本Apple/Google/メール登録とメール配送、年齢/同意/guest引継ぎ、実機、native複数人招待/解除/撤回、クラウド内容重複/終了後キュー復元、原写真品質、全サービス削除/自動worker、クラウドSNS/運営/最終QA。T-01〜69の完了を宣言しない。
