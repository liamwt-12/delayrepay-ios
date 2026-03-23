import AuthenticationServices
import UIKit

/// Handles Sign in with Apple authentication flow.
class AppleSignInManager: NSObject {

    private var onSuccess: ((String, String, String) -> Void)?
    private var onError: ((String) -> Void)?

    func signIn(
        presentingViewController: UIViewController,
        onSuccess: @escaping (String, String, String) -> Void,
        onError: @escaping (String) -> Void
    ) {
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
}

// MARK: - ASAuthorizationControllerDelegate

extension AppleSignInManager: ASAuthorizationControllerDelegate {

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            onError?("Unexpected credential type")
            cleanup()
            return
        }

        guard let tokenData = credential.identityToken,
              let token = String(data: tokenData, encoding: .utf8) else {
            onError?("Failed to decode identity token")
            cleanup()
            return
        }

        let user = credential.user
        let email = credential.email ?? ""

        onSuccess?(token, user, email)
        cleanup()
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        let nsError = error as NSError

        if nsError.domain == ASAuthorizationError.errorDomain {
            switch ASAuthorizationError.Code(rawValue: nsError.code) {
            case .canceled:
                onError?("cancelled")
            case .failed:
                onError?("Sign in failed. Please try again.")
            case .invalidResponse:
                onError?("Invalid response from Apple. Please try again.")
            case .notHandled:
                onError?("Sign in request was not handled.")
            case .notInteractive:
                onError?("Sign in requires interaction.")
            case .unknown:
                onError?("An unknown error occurred. Please try again.")
            default:
                onError?(error.localizedDescription)
            }
        } else {
            onError?(error.localizedDescription)
        }

        cleanup()
    }

    private func cleanup() {
        onSuccess = nil
        onError = nil
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AppleSignInManager: ASAuthorizationControllerPresentationContextProviding {

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        if let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
           let window = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first {
            return window
        }
        return UIWindow()
    }
}
