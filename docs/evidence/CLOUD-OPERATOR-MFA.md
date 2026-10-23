# クラウド運営のMFA境界（2026-10-09）

migration014を承認済みFree検証環境へ実際に適用。DB内の運営権限（編集・承認・通報審査・管理）と有効状態、署名検証済みAuth JWTのaal2、有効なTOTP factorを毎回確認する。通報一覧と対応記録は通報審査／管理担当のみ。権限行を共有ロックして、取消との競合を直列化する。サービス用の既存RPCと、人間のAuth用RPCを分離する。人間の運営操作はAuthの実UIDを内部監査に記録し、サービス操作を架空の人間として扱わない。

権限付与テスト用RPCはservice専用かつ、test_onlyメタデータを持つmefrion-test-*@example.invalidアカウントだけに限定する。人間のアカウントへの権限付与には使えない。実担当者の登録／初期bootstrapは未実装・未承認。

実行したテスト：scripts/verify_operator_mfa.pyで28チェック成功（supabase-operator-mfa-e2e.json）。実際に合成担当のパスワードログイン、TOTP登録・challenge・verifyを実行。権限だけ／未検証MFA拒否、通報審査担当+aal2許可、編集担当+aal2拒否、正確な再送、変更した再送の拒否、権限取消後の拒否、TOTP解除後の古いaal2拒否を確認した。最後に担当権限を無効化し、テストfactorを解除した。人間のMFAは変更していない。

Web管理画面は/admin/cloud。公開接続キーのみ取得し、サービスキーをブラウザーへ渡さない。JWTはメモリだけに保持、明示ログアウト・ページ破棄で削除、セッション切れは再ログインする。HTML差し込みはtextContentで行う。CSPの接続先は承認済み検証プロジェクトだけ。ログイン、MFA、合成通報9件・異議の一覧表示をブラウザーで実操作確認した。判断記録時のwindow.confirmがCodex内ブラウザーの制御を止めたため、ユーザーにキャンセル操作を依頼し、アプリ内の確認画面へ修正した。修正版での対応記録・ログアウトの実操作はまだ未確認。JS構文確認とPython59テストは成功。

未完了：修正版Webの最後の実操作確認、実担当者のMFA登録と権限bootstrap、担当割当／期限／再審査、緊急体制、管理者向け監査閲覧、クラウドSEED一括編集／承認／配信。既存のローカルSEED管理画面とクラウド通報審査は現時点で別の接続である。本番運営準備完了とはしない。

参照（2026-10-09確認）：https://supabase.com/docs/guides/auth/auth-mfa/totp 、https://supabase.com/docs/reference/javascript/auth-mfa-enroll 。TOTPは無料で利用可能。factor一覧・challenge・verify／解除のREST経路はSupabase公式auth-js実装を参照。Auth側のfactor状態のDB構造は公式authのMFA migrationを確認した。
