# Pexels素材の事前収集

2026-10-11、利用者がPexelsの明示許可を取得済みと回答したため、MEFRION用のローカル素材収集を実施する。許可の根拠は会話中の利用者の申告であり、Pexelsの許可書自体をこちらで確認したという意味ではない。

## 保管形式

保管先は `.local/pexels-pets/`。Git管理・iOSアプリの同梱対象から除外する。APIキーは環境変数から収集プロセスに渡し、ファイル・出典台帳・アプリには記録しない。

- `images/<Pexels ID>.jpg`：RGB、長辺最大1,024px、縦横比維持、EXIF除去。
- `thumbnails/<Pexels ID>.jpg`：長辺最大320px。
- `records/<Pexels ID>.json`：出典ページ、撮影者、クレジット、取得時刻、取得URL、SHA-256、画像サイズ、検索語、確認状態。
- `manifest.jsonl` / `manifest.csv`：画像全体の一覧。Pexels IDと正規化前のJPEGエンコードに依存しない画素ハッシュで重複を除外。
- `<species>-assets.csv`：検索語に基づく仮分類一覧。種別を確認したことを表すものではない。
- `index.html` / `review/page-*.html`：100件ずつ閲覧できるオフラインの確認ページ。出典リンク付き。
- `contact-sheet.jpg`：仮分類ごとに分散抽出した写真の一覧。
- `dog-cat-portrait-candidates.csv`：説明文に顔・ポートレート等がある犬猫の確認候補。画像の品質保証ではない。
- `review-hints.jsonl`：説明文からの人物・手等の確認フラグ。
- `visual-review-notes.json`：目視したサンプルと検索分類の誤りの記録。
- `seed-01-06-photo-drafts.json`：目視サンプルから選んだ犬猫6枚の写真下書き。公開承認false、運営セレクトと出典の表示案。
- `permission.json`：利用者による許可取得済みの申告。
- `summary.json` / `verification.json`：取得件数・失敗・ファイル全件検証の結果。
- `responses/`：再開時のAPI応答キャッシュ。

## 収集・検証コマンド

PythonとPillowが必要。APIキーを環境変数 `PEXELS_API_KEY` に用意する。許可記録が存在し、`operator_confirmed_explicit_permission` がtrueの場合のみ動作する。

```sh
python3 scripts/collect_pexels_assets.py --permission-record .local/pexels-permission.json --target 6000 --request-budget 130
python3 scripts/prepare_pexels_catalog.py
python3 -m unittest discover -s tests -p test_pexels_intake.py -v
```

API検索は1ページ80件。検索リクエスト数の上限を設け、401・403・429で停止する。APIキーを別ホストに転送しないためリダイレクトを拒否する。写真取得は限定並列。途中の画像・応答を保持して再開可能。

## MEFRIONへの投入時

この収集は素材在庫の準備であり、通常投稿・公開Pet・Twins候補への自動登録は行わない。既存データ、家族写真、ユーザー投稿を変更しない。

1. ギャラリーで動物の種類、人物・商標等の写り込み、顔の見え方を確認する。
2. 取得済み許可の利用範囲と個別写真の条件を照合し、必要な権利証跡を運営台帳に残す。
3. SEED用には運営コンテンツであることと撮影者のクレジットを明示する。ストック写真を実ユーザーの飼育記録に見せかけない。同一個体・犬種・年齢・性別・撮影地は推定で埋めない。
4. 運営管理画面の画像登録と画像ごとの権利確認、投稿下書き・承認の既存手順を使う。素材CSVをPet一括作成CSVに直接読み込まない。
5. Twinsの評価に使う場合、種類・顔の領域・似ている組み合わせ等の正解ラベルを別途作る。写真件数の充足は類似検索の精度検証完了を意味しない。画像ごとの実在するPetの本人性は不明。

## 確認した公式情報

- [Pexels利用条件](https://www.pexels.com/terms-of-service/)：大量・体系的なコピーには明示許可が必要。
- [API利用条件の公式説明](https://help.pexels.com/hc/en-us/articles/900005880463-What-are-the-Terms-and-Conditions)：AIの開発・評価用の大量収集にも明示許可が必要。
- [API仕様](https://www.pexels.com/api/documentation/)：デフォルト200リクエスト/時、20,000リクエスト/月、1ページ最大80件。

実績件数は収集終了後の証拠記録を参照する。

## 犬・猫限定への更新（2026-10-11）

利用者の追加指示により、現在の素材一覧・画像フォルダ・CSV・ギャラリー・ZIPは犬猫の候補のみとする。`collect_pexels_assets.py` の検索語も犬猫だけに限定し、`filter_pexels_dog_cat.py` の判定を収集前に適用する。

既存6,311件から、犬猫以外の検索分類1,058件と説明文で犬猫と確認できない/他動物の記述がある32件を除外。現在5,221件（犬3,073、猫2,148）。説明文による保守的な除外のため、犬猫を他動物にたとえた記述なども除外する場合がある。全件の画像認識・目視による確認は未実施。

元の素材と旧ZIPは `.local/pexels-before-dog-cat-filter/` に別保管し、現在の配布ZIPには含めない。APIキーを再利用せずローカル処理のみで整理。`filter-report.json` に結果を保持する。
