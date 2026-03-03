import AuthenticationServices
import Capacitor

@objc(AppleSignInPlugin)
public class AppleSignInPlugin: CAPPlugin, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {

    @objc func authorize(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.email, .fullName]
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            self.bridge?.saveCall(call)
            controller.performRequests()
        }
    }

    public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        return self.bridge?.webView?.window ?? UIWindow()
    }

    public func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let cred = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
        let token = String(data: cred.identityToken ?? Data(), encoding: .utf8) ?? ""
        let result: [String: Any] = [
            "identityToken": token,
            "user": cred.user,
            "givenName": cred.fullName?.givenName ?? "",
            "familyName": cred.fullName?.familyName ?? ""
        ]
        self.bridge?.savedCalls.values.first?.resolve(result)
    }

    public func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        self.bridge?.savedCalls.values.first?.reject("Sign in failed", nil, error)
    }
}
