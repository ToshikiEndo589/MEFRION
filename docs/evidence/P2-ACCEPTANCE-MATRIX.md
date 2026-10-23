# P2受け入れ照合 — 69項目

2026-10-10。全件 `not_verified` は本番条件を含む受け入れ全体の状態。部分試験の成功を全件E2E成功へ読み替えない。

| ID | シナリオ | 部分証拠・範囲 | 残件 |
|---|---|---|---|
| T-01 | 新規ユーザーがアルバム入口から登録元の導線へ戻りPet作成できる | [p01-final-integrated-summary.json](p01-final-integrated-summary.json) — 登録・非公開作成・日付のSimulator/合成API証拠 | 実認証と実iPhoneでの入口復帰・編集 |
| T-02 | 写真0枚でPet作成 保存できる。公開はされない | [p01-final-integrated-summary.json](p01-final-integrated-summary.json) — 登録・非公開作成・日付のSimulator/合成API証拠 | 実認証と実iPhoneでの入口復帰・編集 |
| T-03 | 日付の古い写真を後から追加 撮影日順に挿入される | [p01-final-integrated-summary.json](p01-final-integrated-summary.json) — 登録・非公開作成・日付のSimulator/合成API証拠 | 実認証と実iPhoneでの入口復帰・編集 |
| T-04 | 撮影日が不明な写真を追加 推測せず不明のまま保存 | [p01-final-integrated-summary.json](p01-final-integrated-summary.json) — 登録・非公開作成・日付のSimulator/合成API証拠 | 実認証と実iPhoneでの入口復帰・編集 |
| T-05 | 30枚のうち一部アップロード失敗成功分を保持し失敗分だけ再送 | [ios-cloud-batch-final-summary.json](ios-cloud-batch-final-summary.json) — 部分再送/重複/容量の合成試験 | 実写真30枚・通信断・端末容量不足 |
| T-06 | 同じ写真を再追加 重複候補を案内し決定は本人 | [ios-cloud-batch-final-summary.json](ios-cloud-batch-final-summary.json) — 部分再送/重複/容量の合成試験 | 実写真30枚・通信断・端末容量不足 |
| T-07 | Petの節目を記録 年齢不明でも記録可能 | [p1-cards-paging-server.json](p1-cards-paging-server.json) — 節目/比較/用途認可の実API部分証拠 | 実iPhone写真保存/共有と権限 |
| T-08 | 2枚の比較カードを作成 日付・切り抜きを確認し家族内保存 | [p1-cards-paging-server.json](p1-cards-paging-server.json) — 節目/比較/用途認可の実API部分証拠 | 実iPhone写真保存/共有と権限 |
| T-09 | 非公開2枚からカードを外部公開しよう とする 明示確認と同意確認なしでは失敗 | [p1-cards-paging-server.json](p1-cards-paging-server.json) — 節目/比較/用途認可の実API部分証拠 | 実iPhone写真保存/共有と権限 |
| T-10 | 管理者が家族を招待 7日内の1回承認で有効、再利用不可 | [p01-family-concurrency.json](p01-family-concurrency.json) — 家族権限/競合の実API部分証拠 | 正式招待HTTPSリンクと複数実iPhone |
| T-11 | 招待を取り消す 取り消しURLでは写真が見えない | [p01-family-concurrency.json](p01-family-concurrency.json) — 家族権限/競合の実API部分証拠 | 正式招待HTTPSリンクと複数実iPhone |
| T-12 | 家族が写真を追加 家族内にのみ出現、外部には出ない | [p01-family-concurrency.json](p01-family-concurrency.json) — 家族権限/競合の実API部分証拠 | 正式招待HTTPSリンクと複数実iPhone |
| T-13 | 家族が他人の写真を編集 権限拒否、元画像は不変 | [p01-family-concurrency.json](p01-family-concurrency.json) — 家族権限/競合の実API部分証拠 | 正式招待HTTPSリンクと複数実iPhone |
| T-14 | 家族提供写真を管理者が勝手に公開同意がなければAPIでも拒否 | [p01-family-concurrency.json](p01-family-concurrency.json) — 家族権限/競合の実API部分証拠 | 正式招待HTTPSリンクと複数実iPhone |
| T-15 | 提供者が公開許可を与え管理者が投稿指定された公開写真だけ表示 | [p01-family-concurrency.json](p01-family-concurrency.json) — 家族権限/競合の実API部分証拠 | 正式招待HTTPSリンクと複数実iPhone |
| T-16 | 家族が退出・解除 直後から画像URL・APIアクセス不可 | [p01-family-concurrency.json](p01-family-concurrency.json) — 家族権限/競合の実API部分証拠 | 正式招待HTTPSリンクと複数実iPhone |
| T-17 | Twinsゲスト初回検索 登録せず結果閲覧、候補は最大3 | [p1-twins-shares-server.json](p1-twins-shares-server.json) — デモ/候補/失効/共有の部分証拠 | 許諾実写真の独立品質評価と実認証復帰 |
| T-18 | Twins画像が不鮮明 写真の問題として再選択を案内 | [p1-twins-shares-server.json](p1-twins-shares-server.json) — デモ/候補/失効/共有の部分証拠 | 許諾実写真の独立品質評価と実認証復帰 |
| T-19 | Twins候補不足 検索エラーではなく不足と表示 | [p1-twins-shares-server.json](p1-twins-shares-server.json) — デモ/候補/失効/共有の部分証拠 | 許諾実写真の独立品質評価と実認証復帰 |
| T-20 | Twins検索処理が失敗 同じ画像の再試行、二重課金・処理抑制 | [p1-twins-shares-server.json](p1-twins-shares-server.json) — デモ/候補/失効/共有の部分証拠 | 許諾実写真の独立品質評価と実認証復帰 |
| T-21 | Twins結果からログインしフォロー元結果・対象Petを復元しフォロー完了 | [p1-twins-shares-server.json](p1-twins-shares-server.json) — デモ/候補/失効/共有の部分証拠 | 許諾実写真の独立品質評価と実認証復帰 |
| T-22 | Twins候補の許可を取り消す 新規候補除外、過去共有画面で相手をマ スク | [p1-twins-shares-server.json](p1-twins-shares-server.json) — デモ/候補/失効/共有の部分証拠 | 許諾実写真の独立品質評価と実認証復帰 |
| T-23 | 未ログインで非公開PetのURLへアクセス情報・画像・存在の不要な露出なし | [p01-final-integrated-summary.json](p01-final-integrated-summary.json) — 認可/投稿/反応/撤回の部分証拠 | 全対象の実機E2E対応 |
| T-24 | 投稿タブを開く 「アルバムに残す」が初期選択 | [p01-final-integrated-summary.json](p01-final-integrated-summary.json) — 認可/投稿/反応/撤回の部分証拠 | 全対象の実機E2E対応 |
| T-25 | 5枚の公開写真を選ぶ 最大4枚の制約を説明 | [p01-final-integrated-summary.json](p01-final-integrated-summary.json) — 認可/投稿/反応/撤回の部分証拠 | 全対象の実機E2E対応 |
| T-26 | 公開本文を501文字入力 500文字の制約が明確で、安全に修正可 能 | [p01-final-integrated-summary.json](p01-final-integrated-summary.json) — 認可/投稿/反応/撤回の部分証拠 | 全対象の実機E2E対応 |
| T-27 | 同じ投稿に2回いいね 二重カウントせず状態が切り替わる | [p01-final-integrated-summary.json](p01-final-integrated-summary.json) — 認可/投稿/反応/撤回の部分証拠 | 全対象の実機E2E対応 |
| T-28 | コメント返信を入れ子で増やす 返信1階層までの制約を維持 | [p01-final-integrated-summary.json](p01-final-integrated-summary.json) — 認可/投稿/反応/撤回の部分証拠 | 全対象の実機E2E対応 |
| T-29 | 発言名義として他人のPet IDを指定サーバー側で拒否 | [p01-final-integrated-summary.json](p01-final-integrated-summary.json) — 認可/投稿/反応/撤回の部分証拠 | 全対象の実機E2E対応 |
| T-30 | Petの公開を停止 検索・ホーム・公開プロフィールから除 外 | [p01-final-integrated-summary.json](p01-final-integrated-summary.json) — 認可/投稿/反応/撤回の部分証拠 | 全対象の実機E2E対応 |
| T-31 | 公開済み素材の同意を撤回 投稿・カード・キャッシュ上の露出を停 止 | [p01-final-integrated-summary.json](p01-final-integrated-summary.json) — 認可/投稿/反応/撤回の部分証拠 | 全対象の実機E2E対応 |
| T-32 | 共有URLを失効 公開終了画面を表示し元画像を出さない | [p01-share-http.json](p01-share-http.json) — 公開専用HTTPと失効の実確認 | 正式HTTPSホスト/URL/OGP/Universal Links |
| T-33 | AがBをブロック 相互の交流・表示・通知が仕様どおり停 止 | [p01-assignment-race.json](p01-assignment-race.json) — ブロック/担当/処分の部分証拠 | 人間運営MFA・正式窓口・総合シナリオ |
| T-34 | 同じ人が別Pet名義で接触を試みるブロックは全Pet名義に適用 | [p01-assignment-race.json](p01-assignment-race.json) — ブロック/担当/処分の部分証拠 | 人間運営MFA・正式窓口・総合シナリオ |
| T-35 | 不適切投稿を通報 管理画面に届き対応履歴を保存 | [p01-assignment-race.json](p01-assignment-race.json) — ブロック/担当/処分の部分証拠 | 人間運営MFA・正式窓口・総合シナリオ |
| T-36 | 権限のない人が管理APIを実行 拒否し必要な監査を記録 | [p01-assignment-race.json](p01-assignment-race.json) — ブロック/担当/処分の部分証拠 | 人間運営MFA・正式窓口・総合シナリオ |
| T-37 | 運営が投稿を非表示・アカウント停止当該表示と再投稿が正しく制限 | [p01-assignment-race.json](p01-assignment-race.json) — ブロック/担当/処分の部分証拠 | 人間運営MFA・正式窓口・総合シナリオ |
| T-38 | アカウントを退会 関連Pet・家族・公開・通知が削除計画 に従う | [p0-account-retirement-e2e.json](p0-account-retirement-e2e.json) — 合成Authで退会57条件 | 人間Auth/Apple token失効・保持/常時処理 |
| T-39 | ゲスト画像の保持期限が過ぎる 原則24時間以内の削除を自動検証 | [p1-twins-shares-server.json](p1-twins-shares-server.json) — 入力10分消去/画面終了の部分証拠 | 実機バックグラウンド/終了/期限跨ぎ |
| T-40 | バックアップを復元 取消済み公開・削除済み権限が復活しな い | 対応証拠未確定 — 対応証拠未確定（合格ではない） | 実バックアップの隔離復元・削除台帳再適用・公開再開前確認 |
| T-41 | 通信切断・復帰 破損・二重保存せず続行または再試行 | 対応証拠未確定 — 対応証拠未確定（合格ではない） | 実通信断/復帰・同時アップロード |
| T-42 | 通知を拒否したiPhoneで使う 全主要機能が使え、通知を勝手に送らな い | 対応証拠未確定 — 対応証拠未確定（合格ではない） | 実iPhoneのAPNs拒否/設定復帰 |
| T-43 | スクリーンリーダーで主要導線操作ボタンと公開状態が理解できる | [p2-accessibility-final-summary.json](p2-accessibility-final-summary.json) — ホーム/Twins自動監査（44pt/説明/切れ/コントラスト）とTwins入力・履歴削除のSimulator2件成功。VoiceOver実操作は未実施 | 実VoiceOver操作と全画面/端末サイズ |
| T-44 | iPhoneの異なる表示サイズ 主要操作に欠け・重なりがない | [p2-large-final-summary.json](p2-large-final-summary.json) — iPhone18ProMax Simulatorの5タブ・最大文字・監査3件成功。iPhone17と17eにも部分証拠あり。全画面/実端末を代用しない | 実VoiceOver操作と全画面/端末サイズ |
| T-45 | デモ用Twins候補のみでテスト デモが本番Petのように一般公開されな い | 対応証拠未確定 — 対応証拠未確定（合格ではない） | 実写真HEIC/EXIF・Releaseへの混入防止 |
| T-46 | 画像のEXIFに位置情報がある 公開配信画像には位置情報が残らない | 対応証拠未確定 — 対応証拠未確定（合格ではない） | 実写真HEIC/EXIF・Releaseへの混入防止 |
| T-47 | 利用上限へ到達 新規操作を安全に制限し既存画像は保持 | [p01-final-integrated-summary.json](p01-final-integrated-summary.json) — 写真/回数上限等の部分証拠 | 保存枠/端末容量/本番レートの実境界 |
| T-48 | 原本画像の削除 必要な派生画像・共有・索引も更新 | [p01-deletion-drain.json](p01-deletion-drain.json) — 削除workerの合成素材処理 | 常時処理/実権利データ・監視 |
| T-49 | ログ収集・分析 個人の写真・コメント本文等の不要情報 が入らない | [p01-python.log](p01-python.log) — ログを無効化/件数記録の実装と部分証拠 | 本番全ログ・委託先ログ・保持期限の検証 |
| T-50 | ストア審査用ビルドと書類を点検実施済み / 未実施 / ユーザー待ちが明確 | [P01-COMPLETION.md](P01-COMPLETION.md) — 実施/未実施の記録 | P3正式署名/審査資料 |
| T-51 | 一般投稿が0件で新規ユーザーがホーム を見る 「見つける」に運営管理Petの投稿が通 常UIで表示され、空のSNSにならない | [p1-seed-server.json](p1-seed-server.json) — 運営素材/配信の94条件・実運営画面の部分証拠 | 正式権利在庫・人間運営/実ユーザー集計・正式試用 |
| T-52 | 運営管理Petをフォローしていない状態 で「フォロー中」を見る 未フォローのPet投稿を勝手に「フォ ロー中」へ混ぜない | [p1-seed-server.json](p1-seed-server.json) — 運営素材/配信の94条件・実運営画面の部分証拠 | 正式権利在庫・人間運営/実ユーザー集計・正式試用 |
| T-53 | 運営が投稿用Petを選んで投稿を作成・ 予約・公開 Pet別の表示名義・権限・時刻に従って 配信され二重投稿されない | [p1-seed-server.json](p1-seed-server.json) — 運営素材/配信の94条件・実運営画面の部分証拠 | 正式権利在庫・人間運営/実ユーザー集計・正式試用 |
| T-54 | 権利確認のない画像で運営準備投稿を公 開しようとする 管理画面/API双方で公開を拒否し、不足 情報を示す | [p1-seed-server.json](p1-seed-server.json) — 運営素材/配信の94条件・実運営画面の部分証拠 | 正式権利在庫・人間運営/実ユーザー集計・正式試用 |
| T-55 | 運営準備投稿の公開を停止、写真権利を 撤回 ホーム、検索、共有、画像配信、キャッ シュに停止が反映 | [p1-seed-server.json](p1-seed-server.json) — 運営素材/配信の94条件・実運営画面の部分証拠 | 正式権利在庫・人間運営/実ユーザー集計・正式試用 |
| T-56 | 一般ユーザー投稿が増える 運営準備投稿の表示量を設定で下げら れ、一般投稿が発見できる | [p1-seed-server.json](p1-seed-server.json) — 運営素材/配信の94条件・実運営画面の部分証拠 | 正式権利在庫・人間運営/実ユーザー集計・正式試用 |
| T-57 | 運営準備投稿にいいね・保存・コメン ト・通報 本物のリアクションのみ記録し、通常投 稿と同じ制限と処理が働く | [p1-seed-server.json](p1-seed-server.json) — 運営素材/配信の94条件・実運営画面の部分証拠 | 正式権利在庫・人間運営/実ユーザー集計・正式試用 |
| T-58 | 本番にテスト用・無許諾の画像やTwins デモ候補を投入 公開を拒否し、運営の権利確認と内部出 典を監査できる | [p1-seed-server.json](p1-seed-server.json) — 運営素材/配信の94条件・実運営画面の部分証拠 | 正式権利在庫・人間運営/実ユーザー集計・正式試用 |
| T-59 | 同一運営準備投稿を繰り返し配信・再読 込 重複や配信回数水増し、無限スクロール の重複乱発がない | [p1-seed-server.json](p1-seed-server.json) — 運営素材/配信の94条件・実運営画面の部分証拠 | 正式権利在庫・人間運営/実ユーザー集計・正式試用 |
| T-60 | 運営管理権のないユーザーが投稿用管理 APIを利用 拒否し、変更履歴と権限を監査できる | [p1-seed-server.json](p1-seed-server.json) — 運営素材/配信の94条件・実運営画面の部分証拠 | 正式権利在庫・人間運営/実ユーザー集計・正式試用 |
| T-61 | 運営準備投稿しかない段階のユーザー行 動を分析 一般投稿と内部識別して閲覧・フォ ロー・再訪を集計できる | [p1-seed-server.json](p1-seed-server.json) — 運営素材/配信の94条件・実運営画面の部分証拠 | 正式権利在庫・人間運営/実ユーザー集計・正式試用 |
| T-62 | 10件の管理用Petプロフィールを運営画 面で一括登録 各Petへのメール・Apple・Google登録 なしに作成、重複検知、監査記録が残る | [p1-seed-server.json](p1-seed-server.json) — 運営素材/配信の94条件・実運営画面の部分証拠 | 正式権利在庫・人間運営/実ユーザー集計・正式試用 |
| T-63 | 運営担当者が1画面でPetを切り替え10件 予約投稿 正しいPet名義で公開し、ログアウト・ ログイン操作は不要 | [p1-seed-server.json](p1-seed-server.json) — 運営素材/配信の94条件・実運営画面の部分証拠 | 正式権利在庫・人間運営/実ユーザー集計・正式試用 |
| T-64 | 管理用Petの公開プロフィールを一般Pet と比較 同じレイアウト、専用の公式バッジや運 営文言を強制表示しない | [p1-seed-server.json](p1-seed-server.json) — 運営素材/配信の94条件・実運営画面の部分証拠 | 正式権利在庫・人間運営/実ユーザー集計・正式試用 |
| T-65 | 管理者APIの認証を外した一括発行を試 行 禁止し、権限のない外部ユーザーがPet 量産・予約をできない | [p1-seed-server.json](p1-seed-server.json) — 運営素材/配信の94条件・実運営画面の部分証拠 | 正式権利在庫・人間運営/実ユーザー集計・正式試用 |
| T-66 | 一般ユーザーのWAU・UGC投稿を集計管理用Petや運営投稿は混入せず、実 ユーザーだけを集計する | [p1-seed-server.json](p1-seed-server.json) — 運営素材/配信の94条件・実運営画面の部分証拠 | 正式権利在庫・人間運営/実ユーザー集計・正式試用 |
| T-67 | 実在しない飼い主の実体験・偽反応・過 去投稿の作成を試みる 業務ルールで禁止し、管理上の確認・レ ビュー対象となる | [p1-seed-server.json](p1-seed-server.json) — 運営素材/配信の94条件・実運営画面の部分証拠 | 正式権利在庫・人間運営/実ユーザー集計・正式試用 |
| T-68 | ヘルプ・規約から運営管理コンテンツの 説明を探す 利用者が確認できる説明があり、個別プ ロフィールに表記を強制しない | [p1-seed-server.json](p1-seed-server.json) — 運営素材/配信の94条件・実運営画面の部分証拠 | 正式権利在庫・人間運営/実ユーザー集計・正式試用 |
| T-69 | プロフィールを一括停止・権利撤回・一 括復旧 投稿と画像が安全に無効化され、承認の ない再公開は防止される | [p1-seed-server.json](p1-seed-server.json) — 運営素材/配信の94条件・実運営画面の部分証拠 | 正式権利在庫・人間運営/実ユーザー集計・正式試用 |
