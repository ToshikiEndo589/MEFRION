# 外部アカウント・費用案（2026-10-08確認、契約なし）

Stripe Directoryを先に調査したがCLI/Homebrewなし。stripe.directoryはWeb readerで形式エラー、Pythonによるread-only取得でセットアップ文書のみ確認。検索・プロビジョニングは未実施。外部候補は公式サイトを代替調査した暫定案。

| アカウント | 用途 | 必要時期/承認 |
|---|---|---|
| Apple Account + Xcode | Simulator・開発 | Phase0検証。Xcode未導入。導入承認済み。Xcode27配置とSDK同意完了、Simulator取得中 |
| Apple Developer / App Store Connect | Sign in with Apple、APNs、TestFlight、署名、申請 | Phase2/6。契約/権限/署名/送信は承認 |
| Google Cloud OAuth client | Google認証 | Phase2、利用者所有projectとcallback設定。未作成 |
| Supabase候補 | PostgreSQL/Auth/private Storage | Phase2、リージョン/契約/保持条件/課金を承認後のみ |
| メール配送サービス（未選定） | 認証・通知メール | Phase2、sender domainと秘密鍵。追加契約は承認 |
| Web/APIホスト（未選定） | API/管理/共有Web | Phase3、先に見積もりと保護設定レビュー |
| GitHub等（未接続） | private repo/CI | 任意。ローカルGitのみ作成 |
| ドメイン（未選定） | 共有・サポート・認証callback | 購入/公開前承認 |

ローカルPhase0/1外部追加課金 **0円**（端末/電力/既存サブスクリプションは除く）。外部AI呼び出し0、クラウドresource0。
Apple Developerは公式年99 USDまたは現地通貨。[公式](https://developer.apple.com/help/account/membership/program-enrollment)。加入時の日本円・税・料金を再確認。
Supabase Proは公式基本25 USD/月、追加compute/転送等で変動。[公式料金](https://supabase.com/pricing) / [billing](https://supabase.com/docs/guides/platform/billing-on-supabase)。無料枠は試作候補で本番運用の保証なし。

以下は業者見積もりでなく、試用30人・各1GB上限・公開派生数GB・月転送50GB・Twins150回/日を仮定した**予算枠**。円換算は実勢為替ではなく150円/USDの計算仮定。作業人件費・権利素材購入・法務は別途。

| 費目 | 月予算枠（円） | 根拠/未確定 |
|---|---:|---|
| DB/認証/画像保存 | 3,750〜8,000 | 25USD基本+環境分離/超過の余裕。保持容量30GB仮定 |
| API/worker/Web | 0〜6,000 | ホスト未選定、常設GPUなし |
| 画像転送/派生 | 0〜3,000 | 転送量の実測待ち、バンドル二重計上を避ける |
| メール/プッシュ | 0〜2,000 | APNs資格/メール契約待ち |
| Twins処理 | 0〜5,000 | CPU/オンデバイス優先、品質と計算時間未測定 |
| ログ/監視/backup | 0〜3,000 | 自由文/写真なし、復旧試験と保持期限待ち |
| 予備 | 5,000 | 原価超過余裕 |
| 合計計画枠 | 8,750〜32,000 | 上限保証なし。Apple年費/ドメイン/人件費別 |

本番予算は未承認。PDFの月5万円・35,000円警告は暫定値。警告だけでは請求停止不可なのでクォータ・レート制限・worker停止をPhase4で実装。既存写真の自動削除で節約しない。
