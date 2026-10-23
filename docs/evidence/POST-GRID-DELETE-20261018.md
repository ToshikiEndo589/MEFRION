# 自分の投稿グリッドと削除（2026-10-18）

## 変更

- 自分の投稿一覧を写真中心の3列・正方形グリッドへ変更。タイルの写真を開くと大きな写真と投稿内容を見られる。
- タイル右上または詳細から削除できる。削除確認には、公開投稿と公開用画像を停止する一方、家族アルバムの元写真は残ることを明示した。
- 既存の本人限定停止APIを使い、停止済み投稿を一覧から除外。公開準備中の投稿は本人に限り、非公開の元写真IDを返し、別途本人認証付きの画像ゲートウェイで再認可して表示する。元写真の保存パスは返さない。
- マイページに戻ったときは直近投稿の状態を再取得する。

## 実行した検証

- `supabase/migrations/202610180051_my_publication_grid_and_delete.sql` を開発Supabaseへ適用。適用後、合成試験アカウントの停止済み投稿は一覧に返らないことをHTTPで確認。
- `.venv/bin/python scripts/verify_my_publication_grid.py` の13項目成功。合成写真の登録、本人限定プレビュー、匿名拒否、投稿停止、停止後の一覧除外、元写真の保持を実環境で確認。結果は `docs/evidence/my-publication-grid-e2e.json`。合成写真は最後に削除した。
- iPhone 17e Simulatorで `testQuickPostHasOneDirectPathAndRequiresExplicitConsent` 1件成功。合成画像で投稿し、3列グリッドのタイル表示、削除確認、削除後の消失、元写真の後処理まで確認。結果は `/tmp/mefrion-post-grid-delete-20261018.xcresult`、撮影画像は `docs/evidence/post-grid-simulator.png`。
- 最終コードのiPhone 16向け署名付きDebugビルド成功。接続中のiPhoneへ上書きインストールし、CoreDeviceから起動成功。

## 未確認

- 実際の利用者写真を使った実機での削除操作。
- 一覧は現在、新しい順に最大50投稿まで取得する。50件を超える投稿のページ追加は未実装。

## 追加変更: 写真をさらに大きく表示

- 要望に合わせて投稿一覧を3列から2列へ変更。正方形タイルの一辺は約1.5倍、表示面積は約2.25倍になり、1画面にはおおむね6〜8枚が入る。削除ボタンと拡大表示は維持。
- 同じ合成投稿から削除までのSimulator UIテスト1件に再成功（`/tmp/mefrion-post-grid-two-column-20261018.xcresult`）。画面は `docs/evidence/post-grid-two-column-simulator.png` で目視確認。
- 最終版のiPhone 16向け署名付きビルド成功。接続中の実機に上書きインストール・起動成功。本人写真での画面目視は未確認。
