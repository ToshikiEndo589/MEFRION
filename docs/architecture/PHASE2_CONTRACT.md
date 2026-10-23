# Phase 2着手前の接続契約（設計のみ・未実装）

Phase1のSimulator検証後に開始する。Apple/Google/メールを固定demo bearerで代替して完了としない。
管理された認証候補：Supabase Auth。使用前に事業者の契約/リージョン/保持条件/予算を確認する。既存検証projectが提供されれば資格の実在を確認して設定する。未提供時に外部アカウントや有料resourceを勝手に作らない。

## 認証
- OAuthはAuthorization Code+PKCE+state/nonce。Apple/Googleのid token検証を管理サービス側とAPI側で分担し、issuer/audience/expiry/JWKS/失効を検証。
- メールはmanaged OTP/magic link。自社DBにpasswordを持たず、token/OTPをアクセスログや分析に入れない。
- DBのAccountは認証providerの安定subjectとの対応、表示名、active/suspended/deleting/deleted。
- SessionはKeychain、移行中の写真とTwins結果は端末保護領域で目的限定。復帰先は許可済み画面enumであり任意URLにredirectしない。
- ゲスト公開閲覧からfollow/save/comment/invite承認直前に認証、完了/取消/失敗で元画面復帰。
-運営operatorは一般userと分離、MFA、editor/approver/publisher。rolesはserverが保持し、client指定を信じない。

## private保存と再送
写真ごとにrequest key、提供者、Pet、撮影精度、private original key。upload sessionに認証主体/ファイル上限/期限を結び、成功分commit、失敗分だけretry。
file typeはmagic bytesとdecoderで検証、画像を再encodeした公開派生のみ使用、EXIFは撮影時刻必要分以外を捨てる。原本取得は管理者/提供者の認可後に限る。
同意はphotoId+providerId+用途+version+時刻+撤回。保存同意は外部公開同意ではない。
private配信は認証gatewayが**毎回DB権限と失効versionを再検査**し、object直URLや長時間の署名URLを返さない。Cache-Control:no-store。家族写真を公開bucketへ置かない。

## 家族招待
管理者のみ発行。256bitランダムtokenはDBにhashで保存、7日・1回承認を暫定設定。Pet/範囲の説明後に認証主体がaccept。
invitation行をtransaction lockして単回消費。キャンセル/再発行/期限切れ/二重並行承認を試験。
家族は招待Petだけ閲覧・追加、自分提供の写真だけ編集/削除。公開/公開Pet変更/招待発行は禁止。管理者も提供者同意なしで公開不可。
退出/解除commit後は全private API/画像gateway拒否。提供済み写真の扱いと削除依頼を別導線で説明。clientの家庭画像は再認可なしのoffline cache表示をしない。

## 実装するAPI
- session validation / private account / Pet create/edit/list
- upload sessions / finalize / failed items retry / private image gateway / photo edit/delete/export
- invitations create/preview/accept/revoke / memberships list/remove/leave
- provider media consent grant/revoke
- app notifications and family frequency (off/immediate/batched)

## Phase2ゲート
A=管理者/B=家族/C=無関係。実tokenを用いてT-01/05/10〜16/21/23/39/41/42/47/48をAPI+画像URL+iPhoneで検証。
Apple/Google/メールは外部callbackを含む実認証。admin roleでprivate albumを任意閲覧できない。再送/並行承認/解除後アクセス/同意撤回を確認。
資格/外部設定が無い場合は実行不能と報告し、実認証の成功を捏造しない。
