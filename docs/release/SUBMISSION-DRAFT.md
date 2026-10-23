# MEFRION ストア準備原稿（未提出）

2026-10-22更新。App Store Connectにアプリレコードとバージョン1.0の下書きを作成し、署名付きビルド1をアップロード済み。App Reviewへの提出と一般公開は未実行。未検証機能の提供を宣言する原稿ではない。

- アプリ名: MEFRION
- App Store Connectサブタイトル: 犬猫との毎日を、もっとかわいく
- サポート連絡先: nextedovation@gmail.com
- サポートURL候補: https://mefrion-support.toshiki1108.chatgpt.site/
- プライバシーポリシーURL候補: https://mefrion-support.toshiki1108.chatgpt.site/privacy.html
- 利用規約URL候補: https://mefrion-support.toshiki1108.chatgpt.site/terms.html
- 公開文書は本番の処理地域・保持期限・運営主体の法的表示を確認してから正式発効する。
- 運営表示名: MEFRION（本人が正式名称として申告。Apple Developer契約名義との照合は未実施）
- App Store Connect設定: iPhoneのみ、18歳以上、無料、広告なし。承認後は手動リリース。
- アイコン: プロジェクト独自のM/肉球マーク、1024px RGB。正式採用後はストア画像とアプリの表示を揃える。

## 説明の下書き

MEFRIONは、ペットの毎日を写真と一緒に記録するアプリです。家族のアルバムに思い出を残し、成長や記念日を振り返れます。公開を選んだ投稿は、おすすめやフォロー中の画面から楽しめます。

家族内の写真は初期非公開。公開投稿、Twins参加、外部共有は個別に確認します。通報、ブロック、公開同意の撤回、アカウント削除の手続きを用意しています。

Twinsの説明とスクリーンショットは、正式な許諾写真で品質確認を終えてから確定する。血縁・同一個体・健康状態を判定する旨や、根拠のない類似パーセントは記載しない。

## 配布前の確認

実Apple/Google/メール認証・復旧、メールとサポート導線、MFAと運営処理、APNs、実HTTPS共有、削除期限とバックアップ復旧、実機権限/VoiceOver/実写真性能、全受け入れ項目、正式素材/用途許諾を確認する。

PrivacyInfo.xcprivacyはUserDefaults/AppStorageのCA92.1と非追跡を追加した。App Store Connectにはメールアドレス、ユーザーID、写真/動画、その他のユーザーコンテンツ、検索履歴、製品の操作の収集と用途・関連付けを下書き入力した。プライバシーポリシーURLと正式公開は未設定。本番の処理、ログ、委託先と照合して確定する。manifestの追加や下書き入力だけで申告/プライバシー審査を完了と扱わない。

Releaseは独立した本番Supabaseの公開URLとpublishable keyだけを同梱する。Apple DeveloperのBundle ID `com.mefrion.app` を登録し、バージョン1.0.0・ビルド1の署名付きArchive、IPAの書き出し、App Store Connectへのアップロードに成功した。Apple側で「提出準備完了」となり、バージョン1.0に紐付けて保存済み。現在の本番環境はメール配信・投稿処理・参考写真・バックアップ等の運用条件を満たしていないため、Archiveやアップロードの成功を配布可能の証明とはしない。審査用アカウントは本番環境確定後に合成データで作成し、私有写真や運営権限を渡さない。

公式根拠:
https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest
https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype
