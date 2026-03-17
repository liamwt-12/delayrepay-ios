import UIKit
import WebKit
import SafariServices

class ViewController: UIViewController, WKNavigationDelegate, WKScriptMessageHandler {

    var webView: WKWebView!
    let storeKitManager = StoreKitManager()
    let appleSignInManager = AppleSignInManager()

    override func viewDidLoad() {
        super.viewDidLoad()

        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()

        let bridgeScript = WKUserScript(source: bridgeJS(), injectionTime: .atDocumentStart, forMainFrameOnly: false)
        contentController.addUserScript(bridgeScript)
        contentController.add(self, name: "delayrepay")

        config.userContentController = contentController
        config.allowsInlineMediaPlayback = true

        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.navigationDelegate = self
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        view.addSubview(webView)

        NotificationCenter.default.addObserver(self, selector: #selector(pushTokenReceived(_:)), name: NSNotification.Name("PushTokenReceived"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(pushNotificationTapped(_:)), name: NSNotification.Name("PushNotificationTapped"), object: nil)

        load()
    }

    func load() {
        let url = URL(string: "https://delayrepay.uk")!
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        webView.load(request)
    }

    func bridgeJS() -> String {
        return """
        window.__isNativeApp = true;
        window.__nativePlatform = 'ios';

        window.Capacitor = {
            getPlatform: function() { return 'ios'; },
            isNativePlatform: function() { return true; },
            Plugins: {
                StoreKitPlugin: {
                    getProducts: function(opts) {
                        return new Promise(function(resolve, reject) {
                            window.__storeResolve = resolve;
                            window.__storeReject = reject;
                            window.webkit.messageHandlers.delayrepay.postMessage({action:'getProducts'});
                        });
                    },
                    purchase: function(opts) {
                        return new Promise(function(resolve, reject) {
                            window.__purchaseResolve = resolve;
                            window.__purchaseReject = reject;
                            window.webkit.messageHandlers.delayrepay.postMessage({action:'purchase', productId: opts.productId});
                        });
                    },
                    restorePurchases: function() {
                        return new Promise(function(resolve, reject) {
                            window.__restoreResolve = resolve;
                            window.__restoreReject = reject;
                            window.webkit.messageHandlers.delayrepay.postMessage({action:'restorePurchases'});
                        });
                    }
                },
                AppleSignInPlugin: {
                    signIn: function() {
                        return new Promise(function(resolve, reject) {
                            window.__appleSignInResolve = resolve;
                            window.__appleSignInReject = reject;
                            window.webkit.messageHandlers.delayrepay.postMessage({action:'appleSignIn'});
                        });
                    }
                },
                PushNotifications: {
                    checkPermissions: function() {
                        return new Promise(function(resolve) {
                            window.__pushPermResolve = resolve;
                            window.webkit.messageHandlers.delayrepay.postMessage({action:'checkPushPermissions'});
                        });
                    },
                    register: function() {
                        return new Promise(function(resolve) {
                            window.webkit.messageHandlers.delayrepay.postMessage({action:'registerPush'});
                            resolve();
                        });
                    },
                    addListener: function(event, callback) {
                        window.__pushListeners = window.__pushListeners || {};
                        window.__pushListeners[event] = callback;
                        return { remove: function() {} };
                    }
                }
            }
        };

        window.nativeCallback = function(data) {
            switch(data.action) {
                case 'getProductsResult':
                    if(data.success && window.__storeResolve) window.__storeResolve({products: data.products});
                    else if(window.__storeReject) window.__storeReject(data.error || 'Failed');
                    break;
                case 'purchaseResult':
                    if(data.success && window.__purchaseResolve) window.__purchaseResolve({transactionId: data.transactionId, productId: data.productId});
                    else if(window.__purchaseReject) window.__purchaseReject(data.error || 'Failed');
                    break;
                case 'restoreResult':
                    if(data.success && window.__restoreResolve) window.__restoreResolve({transactionId: data.transactionId, productId: data.productId});
                    else if(window.__restoreReject) window.__restoreReject(data.error || 'No purchases');
                    break;
                case 'appleSignInResult':
                    if(data.success && window.__appleSignInResolve) window.__appleSignInResolve({identityToken: data.identityToken, user: data.user, email: data.email});
                    else if(window.__appleSignInReject) window.__appleSignInReject(data.error || 'Failed');
                    break;
                case 'pushPermissions':
                    if(window.__pushPermResolve) window.__pushPermResolve({receive: data.status});
                    break;
                case 'pushToken':
                    var listeners = window.__pushListeners || {};
                    if(listeners['registration']) listeners['registration']({value: data.token});
                    break;
                case 'pushReceived':
                    var listeners = window.__pushListeners || {};
                    if(listeners['pushNotificationReceived']) listeners['pushNotificationReceived'](data.notification);
                    break;
                case 'pushTapped':
                    var listeners = window.__pushListeners || {};
                    if(listeners['pushNotificationActionPerformed']) listeners['pushNotificationActionPerformed']({notification: data.notification});
                    break;
            }
        };
        """
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }

        switch action {
        case "getProducts":
            storeKitManager.getProducts { [weak self] products in
                if let data = try? JSONSerialization.data(withJSONObject: products),
                   let json = String(data: data, encoding: .utf8) {
                    let js = "window.nativeCallback({action:'getProductsResult', success:true, products:\(json)})"
                    self?.webView.evaluateJavaScript(js, completionHandler: nil)
                }
            } onError: { [weak self] error in
                let js = "window.nativeCallback({action:'getProductsResult', success:false, error:'\(error)'})"
                self?.webView.evaluateJavaScript(js, completionHandler: nil)
            }

        case "purchase":
            guard let productId = body["productId"] as? String else { return }
            storeKitManager.purchase(productId: productId) { [weak self] transactionId, pid in
                let js = "window.nativeCallback({action:'purchaseResult', success:true, transactionId:'\(transactionId)', productId:'\(pid)'})"
                self?.webView.evaluateJavaScript(js, completionHandler: nil)
            } onError: { [weak self] error in
                let js = "window.nativeCallback({action:'purchaseResult', success:false, error:'\(error)'})"
                self?.webView.evaluateJavaScript(js, completionHandler: nil)
            }

        case "restorePurchases":
            storeKitManager.restore { [weak self] transactionId, productId in
                let js = "window.nativeCallback({action:'restoreResult', success:true, transactionId:'\(transactionId)', productId:'\(productId)'})"
                self?.webView.evaluateJavaScript(js, completionHandler: nil)
            } onError: { [weak self] error in
                let js = "window.nativeCallback({action:'restoreResult', success:false, error:'\(error)'})"
                self?.webView.evaluateJavaScript(js, completionHandler: nil)
            }

        case "appleSignIn":
            appleSignInManager.signIn(presentingViewController: self) { [weak self] identityToken, user, email in
                let safeToken = identityToken.replacingOccurrences(of: "'", with: "\\'")
                let js = "window.nativeCallback({action:'appleSignInResult', success:true, identityToken:'\(safeToken)', user:'\(user)', email:'\(email)'})"
                self?.webView.evaluateJavaScript(js, completionHandler: nil)
            } onError: { [weak self] error in
                let js = "window.nativeCallback({action:'appleSignInResult', success:false, error:'\(error)'})"
                self?.webView.evaluateJavaScript(js, completionHandler: nil)
            }

        case "checkPushPermissions":
            UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
                let status = settings.authorizationStatus == .authorized ? "granted" : "denied"
                DispatchQueue.main.async {
                    let js = "window.nativeCallback({action:'pushPermissions', status:'\(status)'})"
                    self?.webView.evaluateJavaScript(js, completionHandler: nil)
                }
            }

        case "registerPush":
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                if granted {
                    DispatchQueue.main.async {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                }
            }

        default:
            break
        }
    }

    @objc func pushTokenReceived(_ notification: Foundation.Notification) {
        guard let token = notification.object as? String else { return }
        let js = "window.nativeCallback({action:'pushToken', token:'\(token)'})"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    @objc func pushNotificationTapped(_ notification: Foundation.Notification) {
        guard let userInfo = notification.object as? [AnyHashable: Any] else { return }
        let type = userInfo["type"] as? String ?? ""
        let js = "window.nativeCallback({action:'pushTapped', notification:{data:{type:'\(type)'}}})"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url {
            let host = url.host ?? ""
            if host.contains("delayrepay.uk") || host.contains("supabase.co") || host.contains("stripe.com") || host.contains("google.com") || host.contains("googleapis.com") {
                decisionHandler(.allow)
                return
            }
            if navigationAction.navigationType == .linkActivated {
                let safari = SFSafariViewController(url: url)
                present(safari, animated: true)
                decisionHandler(.cancel)
                return
            }
        }
        decisionHandler(.allow)
    }
}
