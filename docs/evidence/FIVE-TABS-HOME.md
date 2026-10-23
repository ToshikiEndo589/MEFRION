# 5タブとホームの更新 — 2026-10-10

利用者の参考画像と指示に合わせ、下部をホーム・アルバム・投稿・そっくり・マイページに整理。中央投稿は円形の＋。ホームの大きなロゴ・サブコピー・検証リンクを外し、中央に18ptのMEFRION、右上に検索と通知を配置した。

左おすすめが初期選択、右フォロー中。ホームは大きな写真の縦フィード。検索、カテゴリ、公開Pet候補は右上の検索へ移動。クラウドの投稿詳細、更新と続きの読込を保持した。アルバムはPet一覧から既存の非公開アルバムへ移動し、未認証時はログイン入口を表示する。

## 実行した確認

Xcodeの署名付きiPhone 17 / iOS 27 Simulatorで最新ソースのビルドとUIテスト3件が成功（失敗0）。

- `testFiveTabsCompactHomeAndSearch`: 5タブの順序、中央の小さい名称、左右フィード、検索への移動、アルバム・投稿・Twins・マイページへの移動。
- `testCloudFiveTabsAndSearchEntry`: 通常クラウド画面の同じ構成、ホームから検索、ゲストのアルバム/認証入口。
- `testOnboardingDefaultRecommendationAndSearchNotifications`: 導入、初期おすすめ、検索と通知の既存導線。

[試験集計](five-tabs-verified-summary.json) / [赤字化済みログ](five-tabs-verified.log)

[ホーム画面](five-tabs-screens/Five-tabs-compact-home.png) / [通常クラウドホーム](five-tabs-screens/Five-tabs-cloud-home.png) / [クラウド検索](five-tabs-screens/Five-tabs-cloud-search.png) / [アルバム入口](five-tabs-screens/Five-tabs-cloud-album.png)

ホームの投稿画像は所有する開発用イラスト。クラウドのゲスト画面は公開投稿0件の状態。今回のゲストUI試験は認証済み家族アルバム全機能の再試験ではない。実機、App Store申請、保留情報に依存する機能の完了を示さない。
