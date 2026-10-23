# アルバムの思い出機能（2026-10-21）

- アルバム上部に「あの頃と今」「しぐさ図鑑」の入口を置いた。既存の写真一覧はその下に残す。
- 「あの頃と今」は同じPetの古い写真と新しい写真を初期表示し、候補の中からVisionの画像特徴で見た目が近い組み合わせを選ぶ。候補が選べない場合も手動で2枚を変えられる。家族内の既存カードRPCへワンタップで保存する。
- 「しぐさ図鑑」は6種類。写真をタップして追加・解除でき、タグは家族内の非公開テーブルに保存する。自動判定ではなく、利用者がしぐさを選ぶ。
- SQL: `supabase/migrations/202610210001_album_gestures.sql`。Supabase `MEFRION-development` のSQL Editorに同等のSQLを実行し、成功を確認。保存クエリ名は `2026-10-21｜しぐさ図鑑（非公開タグ）`。`has_table_privilege` / `has_function_privilege` の確認で、直接テーブルSELECT不可、認証済みRPC可、匿名RPC不可を確認。
- iOS Simulator (MEFRION iPhone 17) で `testAlbumThenNowAndGestureAtlas` と `testAlbumPullToRefreshKeepsExistingPhotosVisible` が成功。最後の変更後にDebugシミュレータビルドも成功。
- 画面: `album-feature-entrance-20261021.png`、`album-then-now-20261021.png`、`album-gesture-atlas-20261021.png`。
- 実機は接続状態が `unavailable` のため、この作業中はインストール・実機操作確認を行っていない。
