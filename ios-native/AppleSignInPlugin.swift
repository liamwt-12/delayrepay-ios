import Capacitor
import AuthenticationServices

@objc(AppleSignInPlugin)
public class AppleSignInPlugin: CAPPlugin, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    
    private var savedCall: CAPPluginCall?
    
    @objc func signIn(_ call: CAPPluginCall) {
        self.savedCall = call
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }
    
    public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        return UIApplication.shared.windows.first!
    }
    
    public func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
            let result: [String: Any] = [
                "identityToken": String(data: credential.identityToken ?? Data(), encoding: .utf8) ?? "",
                "user": credential.user,
                "email": credential.email ?? "",
                "givenName": credential.fullName?.givenName ?? "",
                "familyName": credential.fullName?.familyName ?? ""
            ]
            self.savedCall?.resolve(result)
            self.savedCall = nil
        }
    }
    
    public func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        self.savedCall?.reject("Sign in failed", nil, error)
        self.savedCall = nil
    }
}
