# MEFRION App Store提出準備の現在地（2026-10-21更新）

2026-10-21追記: [サポート](https://mefrion-support.toshiki1108.chatgpt.site/)、[プライバシー](https://mefrion-support.toshiki1108.chatgpt.site/privacy)、[利用規約](https://mefrion-support.toshiki1108.chatgpt.site/terms)を公開し、アプリの「プライバシーと同意」から開けるようにした。いずれも現在の検証状況を説明する公開準備中の文書であり、保持期限・本番委託先情報の確認前に正式発効したとは扱わない。独立本番Supabase「MEFRION-production」をFreeプランの東京リージョンに作成し、56件のSQLマイグレーションを適用・差分0件を確認した。Release用の公開接続設定をローカルに置き、Simulator Releaseビルドは成功。5つのEdge Functionsを配備し、未認証/存在しないIDへの401/404応答を確認した。実データを用いた関数試験、Auth/メール、クラウド常時処理、バックアップ・復元、本番接続の実機試験は未完了。

2026-10-15追記: Releaseのクラウド接続停止を解除し、独立した本番Supabaseの公開設定を検証して同梱する方式へ変更した。開発用URL・鍵のRelease混入、設定欠落、開発用Bundle IDでのArchiveをビルド時に拒否する。10月21日に本番設定とDBを作成したが、配布用ビルド・申請の条件はまだ満たしていない。手順は[PRODUCTION-IOS-CONFIG.md](../operations/PRODUCTION-IOS-CONFIG.md)。

同日、開発環境の公開フィードは0件。以前の20件は期限付き検証投稿であり、本番初期コンテンツではない。投稿0件のホームには説明と投稿導線を追加した。実データでのスクロール・画像速度の再試験は、権利承認済みの投稿が配信されるまで未実施。投稿なしの試験を成功として数えない。

提出・TestFlight配布・正式公開は未実施。本人から運営名称「MEFRION」、実機版品質確認「OK」を受領。Apple/Googleの本人設定は、本人がMacを使える時に行う。2026-10-13に本人が初期投稿方針を修正し、そっくり用の取得済み犬猫写真で初回100件・日次30件を希望した。

Appleの[開発者名の規則](https://developer.apple.com/help/app-store-connect/create-an-app-record/set-your-developer-name/)では、個人登録のApp Store販売者名は本人の法的氏名、組織登録では条件を満たす商号を設定できる。アプリ名・運営ブランドMEFRIONという回答から、Apple側の販売者名までMEFRIONになるとは断定しない。

## 今回完了

- 以前の生成画像6件のSEED投稿案を撤回し、誤使用防止のためパッケージを `.local/withdrawn-seed-artifacts/` に退避。公開・サーバー登録はもともと未実施。
- そっくり用犬猫索引の写真から、初回100件・日次30件×365日（合計11,050件）の重複しないローカル計画を `release/stock-seed-plan/` に作成。撮影者、出典、SHA-256を保持。投稿承認や自動公開は未実施。
- 運営主体の本人申告名称を法務・ストア案へ反映。Apple Developer契約上の個人/事業者名との一致は未確認で、法的身元の確認完了とは記載しない。
- 10月13日時点ではXcodeのRelease SimulatorとiPhone向けReleaseビルドが成功した。ログは `../evidence/appstore-release-simulator-20261013.log` と `../evidence/appstore-release-no-dev-config-20261013.log`。当時のiPhone向け生成物55,120,599 bytes、iOS 17以上、Privacy manifest・CoreMLモデル・モデルライセンスを確認。全参考写真は同梱しない。10月15日にReleaseのコンパイル時通信停止を解除し、本番設定を必須にした。配布署名/アーカイブ/本番クラウド接続は未確認。詳細 `../evidence/appstore-release-audit-20261013.json`。

## 提出までのゲート

| 順位 | 完了条件 | 現在の状態 / 次の担当 |
|---|---|---|
| 1 | 公開用バックエンド、共有HTTPSホスト、プライバシー/サポートURL、監視・削除worker・バックアップ復旧 | 公開URLは設置・HTTP表示確認済み。本番Supabase作成と56件のSQL移行は完了。5つのEdge Functions配備は完了。Auth/メール、実データ試験、常時処理・監視・バックアップ復元は未完了 |
| 2 | Apple/Googleの実認証とメール確認・復旧、運営本人のAuth/MFA | 未完了。本人のMac上でのサインインや資格入力後に接続・試験を完了 |
| 3 | そっくり用Pexels写真の個別確認、権利記録、初回100件・日次30件の運営投稿登録と常時配信 | ローカル計画のみ完了。運営本人のMFA権限、許可証跡確認、画像ごとの承認、常時workerが必要。未公開 |
| 4 | 正式な取扱主体、発効日、委託先/処理地域/保持期限を実態に合わせた規約・プライバシー確定 | 公開URLと案内文は設置済み。Apple Developer契約名義、本番処理地域・削除/保持期限の実証、発効日を反映して確定する必要あり |
| 5 | 配布用Bundle ID・Entitlements/APNs・Releaseクラウド設定・署名付きArchive・TestFlight実機回帰 | Release公開設定の検証と混入防止を実装。本番公開設定をローカルに作り、Simulator Releaseビルド成功。配布ID、署名付きArchive、本番接続・実機試験は未完了 |
| 6 | 投稿/通報/ブロック/削除/同意/家族非公開/通知/通信断を公開環境で総合確認 | 機能と限定試験はあるが公開環境全体の合格は未宣言。本人の「品質OK」は実機版の主観確認として記録 |
| 7 | App Store Connectのアプリ情報、年齢区分、データ申告、スクリーンショット、審査用アカウント | 原稿案あり。実画面素材/公開URL/審査アカウント未作成 |

AppleはiOSアプリに公開可能なプライバシーポリシーURLとデータ取扱い申告を求める。投稿型アプリには不適切投稿の防止、通報・対応、ブロック、連絡先が必要。審査では必要なメタデータ、ビルド、デモログイン情報を提出する。現在のSDK最低条件はXcode 26以降。根拠: [App Privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy)、[App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)、[Complete Review](https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review)、[Submit App](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app)、[SDK requirements](https://developer.apple.com/news/upcoming-requirements/?id=04282026a)。

## 本人がMacを使える時に必要な操作

1. Apple Developer/App Store Connectの契約名義・Team権限を確認し、Sign in with AppleのApp ID/Service IDと戻り先を設定する。パスワード・秘密鍵をチャットへ送らない。
2. Google CloudのOAuth同意画面とクライアントを本人のアカウントで設定する。秘密値は承認済みの管理画面へ本人が入力する。
3. MEFRION運営アカウントを本人が登録しMFAを有効化する。本人確認後に期限付き運営権限を付与し、取得済み犬猫写真を個別確認・承認する。

ユーザーが「品質OK」と答えた事実は記録するが、未実施の正式Release・複数利用者の家族共有・実認証・APNs・バックアップ復元の試験を合格済みにしない。
