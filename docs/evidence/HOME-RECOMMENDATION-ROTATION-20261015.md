# ホーム「おすすめ」の再読み込み時の入れ替え（2026-10-15）

## 実装

- ホームタブの再タップと下方向への引っ張り更新で「おすすめ」を再取得し、投稿の並びを更新する。
- サーバーの `mefrion_feed_page` で公開可否、期限、ブロックを判定した最大50件を候補にする。端末内の直近上位12件の表示回数が少ない投稿を先にし、同条件では新しい投稿を優先する。犬と猫は可能な範囲で交互に配置する。
- 通常の画面復帰やバックグラウンド再検証では並びを維持し、新着投稿があれば先頭に出す。「フォロー中」は従来どおり時系列表示する。
- 再読み込み後の先頭12枚の写真を優先して取得する。ページングにはサーバーから受け取った時系列カーソルを使い、端末内の並び替えと切り離す。
- 表示回数はアプリ内の一時メモリだけに保持し、アプリ終了後には引き継がない。投稿数が少ない場合、次の再読み込みで先頭が必ず変わる保証はない。

## 実際に実行した確認

- Simulator Debugビルド成功（`.local/feed-rotation-build.log`）。
- iOS単体テスト `testRecommendedFeedRefreshPromotesUnseenPostsWithoutDuplicates` 成功。50件からの再並び替えで上位12件が前回と重ならず、重複がなく、犬猫が交互になることを検証した。
- 隔離UIテスト `testHomeTabReselectScrollsToTopAndRefreshesFeed` 成功。ホームタブを再タップした際に先頭へ戻り、先頭投稿が変わることを確認した（`.local/feed-rotation-test.log`）。
- 開発Supabaseの実投稿50件を使うUIテスト `testLiveRecommendedReloadShowsDifferentTopPost` と `testLiveCloudHomeScrollKeepsItsPosition` が2件成功・失敗0・skip0（`.local/feed-rotation-live-test-2.log`）。初回の環境変数設定ではこの2件がskipとなったため、Simulatorにフラグを設定して再実行した結果を正式な確認として扱う。
- 50件の投稿情報RPCをMacから3回測定し、205.9 / 191.8 / 221.0 ms、中央値205.9 ms。写真描画時間や実iPhoneでの体感速度はこの測定に含まない。
- 署名付きiPhone Debugビルド成功（`.local/feed-rotation-device-build.log`）。接続中のiPhone `00008140-001A74A22E90401C` に上書きインストールし、`devicectl` から起動成功。

## 未確認・制限

- 実iPhoneで人が見て先頭の入れ替えや体感速度を確認する操作は今回行っていない。端末へのインストールとプロセス起動まで確認済み。
- 関連するフィード索引マイグレーション `202610150047_feed_paging_indexes.sql` はサーバー未適用。今回の並び替えにSQL変更は不要。
- 検証用50投稿は期限付きであり、恒久的な本番配信ではない。
