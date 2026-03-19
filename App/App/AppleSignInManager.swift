import AuthenticationServices
import UIKit

class AppleSignInManager: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {

    var onSuccess: ((String, String, String) -> Void)?
    var onError: ((String) -> Void)?

    func signIn(presentingViewController: UIViewController, onSuccess: @escaping (String, String, String) -> Void, onError: @escaping (String) -> Void) {
        self.onSuccess = onSuccess
        self.onError = onError

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first as? UIWindowScene
        let window = windowScene?.windows.first(where: { $0.isKeyWindow }) ?? windowScene?.windows.first ?? UIWindow()
        return window
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let token = String(data: tokenData, encoding: .utf8) else {
            onError?("Failed to get identity token")
            return
        }
        let user = credential.user
        let email = credential.email ?? ""
        onSuccess?(token, user, email)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let nsError = error as NSError
        // User cancelled is not a real error
        if nsError.code == ASAuthorizationError.canceled.rawValue {
            onError?("cancelled")
            return
        }
        onError?(error.localizedDescription)
    }
}
