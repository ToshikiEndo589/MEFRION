import AuthenticationServices
import UIKit

@MainActor final class OAuthBrowserFlow:NSObject,ASWebAuthenticationPresentationContextProviding {
    private var session:ASWebAuthenticationSession?
    private let window:UIWindow
    private init(window:UIWindow) {self.window=window}
    func presentationAnchor(for session:ASWebAuthenticationSession)->ASPresentationAnchor {window}
    static func authenticate(_ url:URL) async throws->URL {
        guard let window=UIApplication.shared.connectedScenes.compactMap({$0 as? UIWindowScene}).flatMap(\.windows).first(where:{$0.isKeyWindow}) else {throw CocoaError(.userCancelled)}
        let flow=OAuthBrowserFlow(window:window)
        return try await withCheckedThrowingContinuation { continuation in
            flow.session=ASWebAuthenticationSession(url:url,callbackURLScheme:"mefrion") {callback,error in
                Task {@MainActor in
                    flow.session=nil
                    if let callback {continuation.resume(returning:callback)} else {continuation.resume(throwing:error ?? CocoaError(.userCancelled))}
                }
            }
            flow.session?.presentationContextProvider=flow
            flow.session?.prefersEphemeralWebBrowserSession=true
            if flow.session?.start() != true {flow.session=nil;continuation.resume(throwing:CocoaError(.userCancelled))}
        }
    }
}
