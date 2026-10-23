# MEFRION

iPhone向けの非公開成長アルバムを中心とするアプリ。Phase 0・1の体験試作を検証し、Phase 2・3のローカル機能と無料クラウド検証環境を実装中です。公開準備は未完了です。
仕様・全ID計画は[CODEX_START_HERE.md](CODEX_START_HERE.md)、実施結果は[PROGRESS.md](PROGRESS.md)を参照。

## ローカルAPIと動作確認用Web
Python 3.12以降。画像処理の安全性テストにPillow 13.0.0を使います。先に `python3 -m pip install -r requirements.txt` を実行してください。

```sh
python3 -m unittest discover -s tests -v
python3 scripts/check_repository.py
python3 -m backend.server
```

ブラウザで `http://127.0.0.1:8765` を開く。Pet作成、所有イラストの非公開記録、時系列、2枚比較、Twinsのfixture状態を確認できる。
`/admin` は編集/承認/配信の固定テスト権限で一括作成・権利確認・下書き・予約・停止・監査を検証するローカル管理画面。`/shared/{id}` は明示同意を確認する共有カードのローカルWeb。
Macにpython3がなければCodexの依存ランタイムを使用（この作業で実行済み）：

```sh
/Users/toshiki/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -m unittest discover -s tests -v
/Users/toshiki/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 scripts/check_repository.py
/Users/toshiki/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -m backend.server
```

`.env.example` は設定例。自動読み込みはしない。必要時はシェルでMEFRION_PORT等をexportする。`.env`と`.local/`はGit除外。
**固定demo sessionは本認証ではありません。loopback専用で本番モード起動は拒否します。実写真・個人情報をAPIに投入しないでください。**
APIは所有テストassetの参照のみ受け付け、実写真アップロード未対応。SQLiteのPet/写真metadata/cardは`.local/mefrion.sqlite3`に保存されます。
通常iPhone導線は承認済みSupabase検証環境へ接続します。ローカルWeb/APIと端末内ギャラリーは別の試作用です。家族写真の非公開アップロード・削除は合成アカウントでiPhone検証済みです。実認証・運営・常時処理を含む残件は [P0作業結果](docs/evidence/P0-WORK-STATUS.md) を参照してください。API試験合格をiOS試験の代替にしません。

## iPhoneアプリ
XcodeとiOS Simulatorが必要。プロジェクトに外部SDK・パッケージ依存はありません。
`ios/MEFRION.xcodeproj` をXcodeで開き、MEFRION schemeとiPhone Simulatorを選択してRun。
仮Bundle IDは `dev.local.mefrion.prototype`。正式ID/署名/Apple提出は承認後。

```sh
python3 scripts/verify_ios.py
```

full Xcode未設定ならexit 2と「未検証」を返す。準備済みならローカルad hoc署名でSimulator buildとオフライン単体/UI試験を実行します。Keychain検証には署名が必要です。既定では10件のクラウド試験対象を除外し、クラウド合格とは扱いません。`--cloud-integration` は予約済み合成アカウントの専用fixtureを事前配置した場合のみ使用します。CIは今回実行していません。

承認済み検証環境の公開接続設定は `python3 scripts/configure_development_client.py` で作成します。読み元は保護された `.local/supabase-public.json`、出力はGit除外の `ios/MEFRION/DevelopmentPublicConfiguration.json` です。サーバー秘密鍵はアプリへ含めません。Releaseは[本番公開設定の手順](docs/operations/PRODUCTION-IOS-CONFIG.md)に従い、別プロジェクトのURLと公開鍵を設定するまでビルドできません。
Simulatorで確認する操作：5タブ（ホーム・アルバム・投稿・そっくり・マイページ） → 投稿 → Pet作成 → テストイラストまたはPhotosPicker → 日付確認 → 家族内保存 → マイページ → アルバム → 2枚選択 → 比較 → Twinsの結果/不足/写真不良/障害。

## デザイン変更

```sh
python3 scripts/sync_tokens.py
python3 scripts/sync_policy.py
```

`design/tokens/tokens.json`が配色の基準。参考画像は`design/reference/`へ。署名とReleaseの設定を保護するため、Xcodeプロジェクトはチェックイン済みの`ios/MEFRION.xcodeproj`を編集して維持します。旧生成スクリプトは既存プロジェクトを上書きしません。
テストイラスト再生成のみPillowが必要（Codexの同梱runtimeで実行済み）：`python3 scripts/generate_assets.py`。

## 境界
検証環境の家族保存、SNS公開・同意撤回、通報/block、合成アカウントの退会連動は実装・対象試験済みです。Apple/Google・実メールの本認証、人間の退会処理の運用、常時worker、実運営体制、本共有Web、Twins公開品質、正式署名・公開は未完成です。機能全件の完了ではありません。
Phase 2・3へ進める依頼を受領済み。前段階のiPhone検証を終え、外部契約等の必要な承認がそろった範囲で続ける。
Supabase Freeの検証環境作成はユーザー承認後に実施。費用増・本番公開・Apple申請・本番削除は実行していない。

Swift側Twinsは端末内Visionによる所有デモ画像との特徴比較を試作。Web/API側は固定fixture検索です。公開品質/犬猫検出は未検証です。暫定上限はconfig/prototype.json、ネイティブ生成はscripts/sync_policy.py。設定だけが存在し未実装のクォータもあるので、実施状態はPROGRESSを参照してください。

### P2品質検証（2026-10-10）

[P2作業記録](docs/evidence/P2-WORK-STATUS.md) / [69項目の部分証拠と不足](docs/evidence/P2-ACCEPTANCE-MATRIX.md) / [実機・復旧・試用計画](docs/operations/P2-VERIFICATION-PLAN.md)。P2全件合格は未宣言。オフラインCI相当の再現は `python scripts/verify_ios.py --device <Simulator UDID> --result-bundle .local/<new-name>.xcresult`。クラウドfixture/useCloud依存の試験は除外され、実認証/本番の合格を示さない。ローカル測定は `python scripts/benchmark_p2.py`。証拠の対応/集計は `python scripts/summarize_p2_evidence.py`。最新の監査・Twins操作2件と大型3件、署名なしRelease構成のビルドは成功。実機・正式環境は未検証。

### 2026-10-11 現在の開発状態

SwiftUIのiPhoneアプリ。Debugの開発署名、本人iPhoneへのインストールとXcode起動は実施済み。問い合わせ先は設定画面と規約/プライバシーの公開前案から参照可能。Apple/Googleの利用者認証、通知、本番運用と申請準備の完了を意味しない。最新の検証はdocs/evidence/CURRENT-INFORMATION-20261011.mdを参照。
