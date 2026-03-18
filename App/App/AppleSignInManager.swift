import AuthenticationServices
import UIKit

class AppleSignInManager: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {

    var onSuccess: ((String, String, String) -> Void)?
    var onError: ((String) -> Void)?
    weak var presentingViewController: UIViewController?

    func signIn(presentingViewController: UIViewController, onSuccess: @escaping (String, String, String) -> Void, onError: @escaping (String) -> Void) {
        self.presentingViewController = presentingViewController
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
        return presentingViewController?.view.window ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }.first ?? UIWindow()
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
        onError?(error.localizedDescription)
    }
}
