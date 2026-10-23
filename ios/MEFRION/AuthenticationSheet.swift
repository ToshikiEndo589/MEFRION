import SwiftUI

/// The presenting screen retains its input in memory; no photo or credential is
/// encoded into an authentication URL or persisted for continuation.
struct AuthenticationSheet:View {
    @ObservedObject var client:CloudFamilyClient
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        NavigationStack {
            CloudFamilyView().safeAreaInset(edge:.top) {
                Text("ログイン後は元の画面へ戻ります。入力写真と結果はこの起動中だけ保持します。取消では元の画面へ戻り、アプリ終了では未保存の入力を破棄します。公開やフォローは戻った画面で改めて確認します。")
                    .font(.caption).padding(12).background(Theme.background)
            }.toolbar {ToolbarItem(placement:.cancellationAction) {Button("認証を取り消して戻る") {dismiss()}.accessibilityIdentifier("auth-resume-cancel")}}
        }.onChange(of:client.busy) {_,busy in if !busy && client.authenticated {dismiss()}}.protectWhenInactive()
    }
}
