> 2026-10-23: 本番と実機環境の常時処理はクラウドへ移行。現在の手順は [PRODUCTION-CLOUD-RUNBOOK.md](PRODUCTION-CLOUD-RUNBOOK.md) を参照。以下のMacワーカー手順は過去の開発用です。

# ローカル運用と将来の復旧
モックは127.0.0.1限定、MEFRION_ENV=local以外は起動拒否。外部公開・トンネル・本番データ投入禁止。
.local/にSQLiteが置かれる。テストは一時DBを使う。リセットはサーバー停止後、自分の開発用.local/のみを対象に手動で行う。本番削除コマンドはない。
本番：privileged backup権限を日常operatorと分離、暗号化/期限/復元後tombstone再適用を検証してから再開。異常時は公開gateway停止、失効deny継続、権利切れ予約停止。実装と演習は未完了。
ライセンス：自作Swift/Python/HTML/描画素材、Python標準PSF、SQLite public domain。Pillow（HPND等）は開発素材生成のみに使用。外部SDK未導入、採用時lockとライセンス棚卸し必須。

## 2026-10-11 開発環境の定期処理

LaunchAgent dev.local.mefrion.development-workersを登録済み。60秒間隔、Mac稼働中のみ。healthは依存完備Pythonでscripts/check_development_worker.pyを実行。解除は同じPythonでscripts/install_development_worker.py remove。退会は本人の再認証と明示確認を経てSQL台帳に入った依頼だけを処理する。受付時にアクセスと公開を停止し、Mac稼働中のworkerが写真ファイルとAuthを削除して完了を記録する。ログには件数だけを保持。Mac停止中は最終削除が進まないため、常時クラウド運用、保存期限の強制、実バックアップ/復元の合格ではない。公開共有の配備手順はdeploy/share/README.mdを参照。
