# Phase 1 / 2026-10-08 JST
前提：Phase0のSimulatorゲート未完了。ユーザーは0/1作業を明示しており、独立ロジック・試作ソースだけを先行。Phase1完了とは宣言しない。

実装：非公開Pet作成、Swift PhotosPicker選択/EXIF日付候補/年・月・日・不明確認/縮小メモリ画像/重複候補/再保存防止/編集削除、時系列/2枚の非公開比較、Twins fixture結果/不足/写真不良/障害/評価と外部費用0計測。
API参照実装：SQLite metadata、部分失敗再送、request key競合検出、写真削除で私的比較card cascade、privateアクセスdeny、公開API不提供。
Web試験用画面：Pet作成、テストイラスト記録、2枚比較、Twins状態と評価。運営10Petはread-only demo一覧のみ。

実行コマンド：Codex bundled Pythonの `-m unittest discover -s tests -v`。
第2回：17件全成功（0.585秒）。第3回：HTTP追加後24件全成功（3.155秒）。
カバー：T-02/03/04/05/06/08/09/17/19/20/23/45/47/48/49/51/54/60/65の一部ローカルロジックのみ。各Tの本来のE2E合格とは扱わない。
SQLite再open保持確認、actor A/B/C/運営によるprivate deny、日付/重複/再送/限界/同意なし外部API404を検証。
実行：`scripts/check_repository.py` 成功、`scripts/sync_tokens.py` 成功、`scripts/verify_ios.py` はexit2未検証。

ブラウザで実操作：ローカルhome10Pet表示、写真0枚の非公開Pet作成、2026-10を追加→2020を後追加→2020が先頭、2枚比較非公開保存、Twins fixture主1/補助2表示。
一度Web locatorのexact label選択が失敗したが、DOMの既存idを使って再実行成功。製品コード不具合と断定していない。
画像：web-home.png / web-comparison.png。これらはiPhone画面ではない。

未完了：iOS build/XCTest/Simulator実画面、切り抜き調整/比較画像出力、Pet全任意項目/編集、実Twins検出/画像類似検索と主観品質、server実写真、本認証/家族/公開/通知/全経路削除。
iOSはメモリ保存、APIはfixture metadata保存、両者未接続。SwiftをPythonテストで検証したとは言わない。
費用：外部課金0、検索fixtureは実処理原価の評価資料ではない。
承認：本サービス契約/写真許諾/保持期限は待ち。XcodeSDK規約は本人操作待ち。
次：Xcode初回設定後0/1検証・修正、そのゲート後Phase2本認証/安全保存/家族、Phase3公開SNS/共有。

追加検証 2026-10-08T22:31:56.669568+09:00：30枚中1枚失敗→失敗分のみ再送→30件/重複なし、8並行HTTP再送で写真1件のみを確認。Python26件全成功（4.680秒）。Swift日付入力にASCII形式検査を追加（+020/全角を拒否）、Swift側は未実行。

Xcode27.0/SDK27.0導入後の更新：署名なしSimulator向けアプリbuild成功、XCTest/UIテストを含むbuild-for-testing成功。まだruntime未取得で実行していない。
Swift側：2枚比較の9:16固定枠、拡大/上下crop位置を家族内cardに保持、去年の今日候補（確定日だけ）、Vision feature-print端末内比較（revision1/同一と重複除外/暫定品質閾値）を追加。API/Webはfixtureのまま。
Web手動追加：候補不足・処理失敗・写真不良をそれぞれ確認、operatorの10Pet一覧読み取り確認。画面PNGを保存。
前段の「切り抜き未実装」「Swift build未実行」は当時の履歴で、現在は切り抜きソース/ビルドがある。画像書き出し/外部公開は未実装。

実行更新：最初のSimulator実行は単体5成功/1失敗（Vision Code9）、UI実行時にruntime停止。サービス再起動＋対応CPU明示後はUI1成功（59.245秒）、単体は5成功/1失敗。スクリーンショット4枚をios-screensへexportし目視確認。このUI試験のTwinsはエラー時の表示/破棄までで、類似検索成功証明ではない。revision2・暫定閾値1.2への変更を再検証中。ios-tests-first-failure.log / ios-tests-cpu-revision1-failure.log / ios-cpu-revision1-summary.jsonに失敗を保存。

最終試作ゲート：2026-10-08 23:00、Swift単体7/UI1件全成功（ios-phase01-final.xcresult）。revision2で実特徴抽出成功、同一画素のsource除外と小画像拒否を追加。runtime warningのnegative frameを修正、参考UIホーム後の再試験も単体7/UI1全成功（ios-reference-home.xcresult）。画像類似の主観品質や実犬猫検出は未検証。Phase1はMock境界を明記した体験試作としてゲート確認。
