import SwiftUI

/// The presenting screen retains its input in memory; no photo or credential is
/// encoded into an authentication URL or persisted for continuation.
struct AuthenticationSheet:View {
    @ObservedObject var client:CloudFamilyClient
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        NavigationStack {
            EmailAccountView(client:client)
                .toolbar {ToolbarItem(placement:.cancellationAction) {Button("戻る") {dismiss()}.accessibilityIdentifier("auth-resume-cancel")}}
        }.onChange(of:client.busy) {_,busy in if !busy && client.authenticated {dismiss()}}.protectWhenInactive()
    }
}
