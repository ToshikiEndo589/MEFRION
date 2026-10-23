# 投稿ごとのPet名と品種：2026-10-16

## 変更

- 開発Supabaseの公開中50投稿を、投稿・写真・権利記録のIDを保ったまま、50件の独立したPetプロフィールへ移行。犬猫それぞれに名前を付け、出典で品種を確認できる26件のみ品種を保存。残り24件は空欄。
- iOSの新規メール登録で最初の犬・猫の名前、種別、品種を入力。飼い主名の入力欄は外し、最初のPet名をコメント用の表示名にも使用。品種が分からない場合は明示して空欄登録できる。追加のPet作成とローカルアルバムのPet作成でも同様。投稿見出しと公開プロフィールにはPet名を使用。
- メール確認待ちの最初のPet情報は端末内Keychainに保持し、確認後のログイン時にコメント用表示名とPet作成を再試行する。Apple/Googleなどで後から最初のPetを作る場合も、Pet名をコメント用表示名に設定する。実メール到達の検証はまだ行っていない。
- 将来の11,050件の未承認配信計画も写真ごとのPetプロフィールに変更。権利確認・本番公開は別途必要。

## 実行結果

- Supabase SQL Editorで `release/stock-seed-plan/stock-50-individual-pets.sql` を実行。移行前に公開投稿50件、フォロー0件、対応する元写真50件、他の未完了ジョブ0件を確認。移行後のSQL結果は `posts=50, named_pets=50, breeds_shown=26, breeds_hidden=24`。
- 投稿・写真の移行後、空になった旧2コレクションプロフィールを `release/stock-seed-plan/stock-50-retire-collections.sql` で無効化。SQL結果は `visible_collections=0, active_collections=0`。匿名フィードは引き続き50件、旧名義の検索は各0件。
- 匿名 `mefrion_feed_page` がHTTP 200で50件を返し、異なるPet ID・名前を各50件確認。「推定」「未確認」を含む品種表示は0件。
- 代表2件の匿名公開プロフィールAPIで、フィードと同じPet名・品種を確認。テスト用アカウントで新Pet「きなこ丸」をフォローし、「フォロー中」に投稿が現れることを確認してからフォロー解除。
- iOS Simulator実データUI `testLiveManagedPostShowsPetNameAndOnlyKnownBreed` と登録条件単体テストが成功。登録画面UI `testSignupExplainsRequirementsAndConfirmsPassword`、ローカルPet作成を含む `testFourTabsPrivateAlbumComparisonAndTwinsStates` も成功。
- 最後のコメント用表示名の補完変更後、iOS Simulator Debugビルド成功。
- Pythonの投稿移行/計画テスト3件成功。計画再生成後 `queue=11050, profiles=11050, unique_keys=11050` を確認。
- Simulatorのおすすめ画面で「いちご／ペルシャ」が写真とともに表示されることをスクリーンショット `docs/evidence/individual-pet-feed-20261016.png` で目視確認。

## 未確認

- Apple/Google認証から初回Pet登録までの通し操作、一般利用者宛ての実メール配信と確認後のPet自動作成は未検証。
- 実iPhoneはCoreDeviceで `unavailable` のため、この変更の上書きインストール・実機目視は未実施。
- 移行対象50投稿の権利期間は既存の検証用期限のままで、恒久的な本番初期投稿ではない。
