import SwiftUI

struct AccountRetirementView:View {
    @ObservedObject private var client=CloudFamilyClient.shared
    @EnvironmentObject private var store:PrototypeStore
    @AppStorage("MEFRIONRetirementReceipt") private var retirementReceipt=""
    @State private var confirmed=false
    @State private var eraseLocal=false
    @State private var key=UUID()
    @State private var accepted=false
    @State private var targetUser:String?
    @State private var localFailure:String?
    var body:some View {
        Form {
            Text("アカウントを削除すると、投稿・コメント・家族アルバムへのアクセスを停止し、保存した写真やログイン情報を削除します。この操作は取り消せません。")
            Text("家族のほかの人が管理するPetは削除されません。写真とログイン情報は通常24時間以内に削除します。完了すると、この端末でアプリを開いた時にお知らせします。24時間を超えた場合は mefrion@mefrion.com にご連絡ください。").font(.footnote).foregroundStyle(.secondary)
            if accepted {Label("退会を受け付け、ログアウトしました",systemImage:"checkmark.shield");Text("公開表示とアクセスは停止しました。削除完了はこの端末にお知らせします。アプリを閉じても、次に開いた時に確認できます。") } else {
                if targetUser == nil {Text("アカウントを削除するにはログインしてください。")}
                Toggle("削除すると元に戻せないことを確認しました",isOn:$confirmed).accessibilityIdentifier("retirement-confirm")
                Toggle("この端末のゲスト記録も削除する",isOn:$eraseLocal)
                Button("退会・削除を申し込む",role:.destructive) {Task {await client.perform {guard let targetUser else {return};try await client.retireAccount(key:key,expectedUser:targetUser);retirementReceipt=key.uuidString;accepted=true;if eraseLocal {do {try store.erasePrivateState()} catch {localFailure="端末内削除に失敗しました。再試行してください。"}}}}}.disabled(client.busy || !confirmed || targetUser==nil || client.currentUserID != targetUser).accessibilityIdentifier("account-retirement-submit")
                if let error=client.error {Text(error).foregroundStyle(.red)}
            }
            if let localFailure {Text(localFailure).foregroundStyle(.red);Button("端末内削除を再試行") {do {try store.erasePrivateState();self.localFailure=nil} catch {}}}
            if client.busy {ProgressView()}
        }.navigationTitle("退会・データ削除").scrollContentBackground(.hidden).background(Theme.background)
        .task {await client.restore();if targetUser==nil {targetUser=client.currentUserID}}
        .protectWhenInactive()
    }
}
