# テスト素材台帳
全10枚はscripts/generate_assets.pyの独自描画。Web収集なし。実在写真ではない。用途は開発専用、demo_only。本番投入禁止。Twins品質評価には使用不可。

2026-10-11: design/mefrion-icon.svgとAppIcon.appiconset/AppIcon.pngは、プロジェクト内の単純なM字・楕円・色の幾何描画から作成した独自アイコン。実写真・第三者キャラクター・参考画像のロゴは使用していない。1024px RGB、アルファなし。最終デザインは変更可能。

2026-10-11: 利用者がPexelsの明示許可を取得済みと申告したため、別のローカル素材在庫 `.local/pexels-pets/` に写真6,311件の主一覧を作成。各写真に撮影者・出典・ライセンスURL・申告の記録を保持する。許可書自体の確認、全件の内容確認、本番公開、Twins正解ラベルの作成は完了扱いにしない。iOS同梱の独自描画10枚は変更していない。実績docs/evidence/PEXELS-COLLECTION-20261011.md。

同日追加指示：現在の主一覧と配布ZIPは犬猫候補5,221件のみ。除外元の素材/旧ZIPは別バックアップに保管し、現行素材配布には含めない。検索分類と説明文での絞り込みであり全件目視済みとはしない。docs/evidence/PEXELS-DOG-CAT-FILTER-20261011.md。

同日Twins実装：Visionで犬猫の認識/特徴を確認した4,412枚をDebugアプリの参考索引として同梱。ユーザーの許可取得済み申告を記録し、各写真の撮影者・HTTPS出典・demoOnlyを保持。元の独自描画10枚と一般Petプロフィールは保持。Pexels写真を個体/飼い主/品種の正解データとして扱わない。全件目視・許諾書・本番掲載確認は未済。撤回は索引再生成とアプリ更新で対応する。docs/evidence/TWINS-REFERENCE-IMPLEMENTATION-20261011.md。

2026-10-11追加: 本人が今回のPexels APIキー再利用を許可。犬猫検索の取得18,306枚、Vision採用14,915枚、掲載終了の開発試験1枚を除き参考検索候補14,914枚を既存Free Supabaseに格納。写真はdemoOnlyと撮影者/出典付き、実Pet/飼い主の架空登録なし。全件目視/許諾書の確認は未了。原本・出典manifest・不採用情報は.localに保管し、キーは保存しない。詳細docs/evidence/TWINS-SERVER-MIGRATION-20261011.md。

2026-10-12: facebook/dinov2-small（Apache-2.0、revision ed25f3a31f01632728cabb09d1542f84ab7b0056）をCoreML FP16へ変換。出典・変更点・ライセンス全文をios/MEFRION/ModelNotices.txtに保持し、アプリ設定から閲覧可能。モデルハッシュはdocs/evidence/resemblance-model.json。写真の許諾状況とは別に管理。新索引掲載中14,906件、写真の追加取得なし。

2026-10-13訂正: 本人が初期投稿の素材をそっくり用の取得済み犬猫写真に指定したため、生成画像6枚の投稿案は撤回し、公開用パッケージを `.local/withdrawn-seed-artifacts/` に退避。サーバー登録・配信は未実施。そっくり用索引から初回100件と日次30件×365日のローカル計画を `release/stock-seed-plan/` に作成したが、各写真の目視と掲載権利・許可書確認は未了。これを承認済み素材とみなさない。
