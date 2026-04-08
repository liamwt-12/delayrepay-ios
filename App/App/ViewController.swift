import UIKit
import WebKit
import SafariServices
import AuthenticationServices

class ViewController: UIViewController {

    // MARK: - Properties

    private var webView: WKWebView!
    private let storeKitManager = StoreKitManager()
    private let appleSignInManager = AppleSignInManager()
    private var offlineView: OfflineViewController?
    private var isWebViewReady = false
    private var pendingCallbacks: [String] = []
    private let refreshControl = UIRefreshControl()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(hex: "#FAFAFA")
        
        setupWebView()
        setupPullToRefresh()
        observeNotifications()
        observeNetwork()
        loadApp()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .darkContent
    }

    // MARK: - WebView Setup

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()

        // Inject bridge at document start — before any web JS runs
        let bridge = WKUserScript(
            source: bridgeJavaScript(),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        contentController.addUserScript(bridge)
        contentController.add(self, name: "delayrepay")

        config.userContentController = contentController
        config.allowsInlineMediaPlayback = true

        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.navigationDelegate = self
        webView.scrollView.contentInsetAdjustmentBehavior = .always
        webView.isOpaque = false
        webView.backgroundColor = UIColor(hex: "#FAFAFA")
        webView.scrollView.backgroundColor = UIColor(hex: "#FAFAFA")

        view.addSubview(webView)
    }

    private func setupPullToRefresh() {
        refreshControl.tintColor = UIColor(hex: "#111111")
        refreshControl.addTarget(self, action: #selector(pullToRefresh), for: .valueChanged)
        webView.scrollView.refreshControl = refreshControl
    }

    // MARK: - Loading

    private func loadApp() {
        guard let url = URL(string: "https://delayrepay.uk") else { return }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        webView.load(request)
    }

    @objc private func pullToRefresh() {
        webView.reload()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.refreshControl.endRefreshing()
        }
    }

    // MARK: - Observers

    private func observeNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePushToken(_:)),
            name: .pushTokenReceived,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePushTapped(_:)),
            name: .pushNotificationTapped,
            object: nil
        )
    }

    private func observeNetwork() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(networkChanged(_:)),
            name: .networkStatusChanged,
            object: nil
        )
    }

    // MARK: - Network Status / Offline View

    @objc private func networkChanged(_ notification: Foundation.Notification) {
        guard let isConnected = notification.object as? Bool else { return }
        DispatchQueue.main.async { [weak self] in
            if isConnected {
                self?.hideOfflineView()
                // If WebView failed to load, retry now
                if self?.webView.url == nil {
                    self?.loadApp()
                }
            }
        }
    }

    private func showOfflineView() {
        guard offlineView == nil else { return }
        let offline = OfflineViewController()
        offline.onRetry = { [weak self] in
            self?.loadApp()
        }
        offline.view.frame = view.bounds
        offline.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addChild(offline)
        view.addSubview(offline.view)
        offline.didMove(toParent: self)
        offlineView = offline
    }

    private func hideOfflineView() {
        guard let offline = offlineView else { return }
        offline.willMove(toParent: nil)
        offline.view.removeFromSuperview()
        offline.removeFromParent()
        offlineView = nil
    }

    // MARK: - JS Bridge Callbacks (JSON-serialized)

    /// Send a JSON-serialized callback to the WebView. If the page isn't ready yet, queue it.
    private func sendCallback(_ payload: [String: Any]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            print("[BRIDGE] Failed to serialize callback: \(payload)")
            return
        }

        let js = "window.nativeCallback(\(jsonString))"

        if isWebViewReady {
            webView.evaluateJavaScript(js) { _, error in
                if let error = error {
                    print("[BRIDGE] JS eval error: \(error.localizedDescription)")
                }
            }
        } else {
            pendingCallbacks.append(js)
        }
    }

    /// Flush any callbacks that were queued before the WebView was ready
    private func flushPendingCallbacks() {
        let queued = pendingCallbacks
        pendingCallbacks.removeAll()
        for js in queued {
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        // Also deliver any cold-launch notification payload
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate,
           let payload = appDelegate.pendingNotificationPayload {
            appDelegate.pendingNotificationPayload = nil
            deliverNotificationToWeb(payload)
        }
    }

    // MARK: - Push Notification Handlers

    @objc private func handlePushToken(_ notification: Foundation.Notification) {
        guard let token = notification.object as? String else { return }
        sendCallback(["action": "pushToken", "token": token])
    }

    @objc private func handlePushTapped(_ notification: Foundation.Notification) {
        guard let userInfo = notification.object as? [AnyHashable: Any] else { return }
        deliverNotificationToWeb(userInfo)
    }

    private func deliverNotificationToWeb(_ userInfo: [AnyHashable: Any]) {
        let type = userInfo["type"] as? String ?? ""
        let trainTime = userInfo["train_time"] as? String ?? ""
        let status = userInfo["status"] as? String ?? ""
        let tappedAction = userInfo["tappedAction"] as? String ?? ""

        sendCallback([
            "action": "pushTapped",
            "notification": [
                "data": [
                    "type": type,
                    "trainTime": trainTime,
                    "status": status,
                    "tappedAction": tappedAction
                ]
            ]
        ])
    }

    // MARK: - Native Share Sheet

    private func shareReferral(code: String, amount: String) {
        let shareText: String
        if !amount.isEmpty && amount != "0" {
            shareText = "I use this app to catch train delays I'd normally miss — it's already found me \(amount). Try it free: https://delayrepay.uk/r/\(code)"
        } else {
            shareText = "I use this app to catch train delays and claim compensation automatically. Try it free: https://delayrepay.uk/r/\(code)"
        }

        let activityVC = UIActivityViewController(
            activityItems: [shareText],
            applicationActivities: nil
        )

        // iPad requires sourceView
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }

        present(activityVC, animated: true) { [weak self] in
            self?.sendCallback(["action": "shareResult", "success": true])
        }
    }
}

// MARK: - WKScriptMessageHandler

extension ViewController: WKScriptMessageHandler {

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }

        switch action {

        // --- WebView Ready Handshake ---
        case "nativeReady":
            isWebViewReady = true
            flushPendingCallbacks()

        // --- StoreKit ---
        case "getProducts":
            storeKitManager.getProducts { [weak self] products in
                self?.sendCallback([
                    "action": "getProductsResult",
                    "success": true,
                    "products": products
                ])
            } onError: { [weak self] error in
                self?.sendCallback([
                    "action": "getProductsResult",
                    "success": false,
                    "error": error
                ])
            }

        case "purchase":
            guard let productId = body["productId"] as? String else {
                sendCallback([
                    "action": "purchaseResult",
                    "success": false,
                    "error": "Missing productId"
                ])
                return
            }
            storeKitManager.purchase(productId: productId) { [weak self] transactionId, pid in
                self?.sendCallback([
                    "action": "purchaseResult",
                    "success": true,
                    "transactionId": transactionId,
                    "productId": pid
                ])
            } onError: { [weak self] error in
                self?.sendCallback([
                    "action": "purchaseResult",
                    "success": false,
                    "error": error
                ])
            }

        case "restorePurchases":
            storeKitManager.restore { [weak self] transactionId, productId in
                self?.sendCallback([
                    "action": "restoreResult",
                    "success": true,
                    "transactionId": transactionId,
                    "productId": productId
                ])
            } onError: { [weak self] error in
                self?.sendCallback([
                    "action": "restoreResult",
                    "success": false,
                    "error": error
                ])
            }

        // --- Apple Sign In ---
        case "appleSignIn":
            appleSignInManager.signIn(presentingViewController: self) { [weak self] token, user, email in
                self?.sendCallback([
                    "action": "appleSignInResult",
                    "success": true,
                    "identityToken": token,
                    "user": user,
                    "email": email
                ])
            } onError: { [weak self] error in
                self?.sendCallback([
                    "action": "appleSignInResult",
                    "success": false,
                    "error": error
                ])
            }

        // --- Push Notifications ---
        case "checkPushPermissions":
            UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
                let status: String
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    status = "granted"
                case .denied:
                    status = "denied"
                case .notDetermined:
                    status = "prompt"
                @unknown default:
                    status = "prompt"
                }
                DispatchQueue.main.async {
                    self?.sendCallback(["action": "pushPermissions", "status": status])
                }
            }

        case "registerPush":
            UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]
            ) { granted, error in
                DispatchQueue.main.async { [weak self] in
                    if granted {
                        UIApplication.shared.registerForRemoteNotifications()
                        self?.sendCallback(["action": "pushRegistered", "granted": true])
                    } else {
                        self?.sendCallback([
                            "action": "pushRegistered",
                            "granted": false,
                            "error": error?.localizedDescription ?? "Permission denied"
                        ])
                    }
                }
            }

        // --- Share / Referral ---
        case "shareReferral":
            let code = body["code"] as? String ?? ""
            let amount = body["amount"] as? String ?? ""
            shareReferral(code: code, amount: amount)

        // --- Haptic Feedback ---
        case "haptic":
            let style = body["style"] as? String ?? "medium"
            HapticManager.fire(style: style)

        default:
            print("[BRIDGE] Unknown action: \(action)")
        }
    }
}

// MARK: - WKNavigationDelegate

extension ViewController: WKNavigationDelegate {

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        let host = url.host ?? ""

        // Allow our domains and auth providers
        let allowedHosts = [
            "delayrepay.uk",
            "supabase.co",
            "stripe.com",
            "google.com",
            "googleapis.com",
            "accounts.google.com",
            "appleid.apple.com"
        ]

        if allowedHosts.contains(where: { host.contains($0) }) {
            decisionHandler(.allow)
            return
        }

        // External links open in Safari sheet
        if navigationAction.navigationType == .linkActivated {
            let safari = SFSafariViewController(url: url)
            safari.preferredControlTintColor = UIColor(hex: "#111111")
            present(safari, animated: true)
            decisionHandler(.cancel)
            return
        }

        // Allow everything else (iframes, XHR targets, etc.)
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
        hideOfflineView()
        UIApplication.shared.applicationIconBadgeNumber = 0
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        let nsError = error as NSError
        if nsError.code == NSURLErrorCancelled { return }

        let networkErrors = [
            NSURLErrorNotConnectedToInternet,
            NSURLErrorTimedOut,
            NSURLErrorCannotFindHost,
            NSURLErrorCannotConnectToHost,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorDNSLookupFailed
        ]

        if networkErrors.contains(nsError.code) {
            showOfflineView()
        } else {
            print("[WEBVIEW] Navigation failed: \(error.localizedDescription)")
            showOfflineView()
        }
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        let nsError = error as NSError
        if nsError.code != NSURLErrorCancelled {
            print("[WEBVIEW] Load failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Bridge JavaScript

extension ViewController {

    private func bridgeJavaScript() -> String {
        return """
        (function() {
            'use strict';

            // Signal to web app that we're running in the native iOS shell
            window.__isNativeApp = true;
            window.__nativePlatform = 'ios';

            // Promise callback registry
            var _callbacks = {};
            var _pushListeners = {};
            var _callId = 0;

            function _post(msg) {
                window.webkit.messageHandlers.delayrepay.postMessage(msg);
            }

            function _callNative(action, extraParams) {
                return new Promise(function(resolve, reject) {
                    var id = ++_callId;
                    _callbacks[action] = { resolve: resolve, reject: reject, id: id };
                    var msg = { action: action };
                    if (extraParams) {
                        for (var k in extraParams) {
                            if (extraParams.hasOwnProperty(k)) msg[k] = extraParams[k];
                        }
                    }
                    _post(msg);
                });
            }

            // Capacitor-compatible shim
            window.Capacitor = {
                getPlatform: function() { return 'ios'; },
                isNativePlatform: function() { return true; },
                Plugins: {
                    StoreKitPlugin: {
                        getProducts: function() {
                            return _callNative('getProducts');
                        },
                        purchase: function(opts) {
                            return _callNative('purchase', { productId: opts.productId });
                        },
                        restorePurchases: function() {
                            return _callNative('restorePurchases');
                        }
                    },
                    AppleSignInPlugin: {
                        authorize: function() {
                            return _callNative('appleSignIn');
                        },
                        signIn: function() {
                            return _callNative('appleSignIn');
                        }
                    },
                    PushNotifications: {
                        checkPermissions: function() {
                            return _callNative('checkPushPermissions');
                        },
                        requestPermissions: function() {
                            return _callNative('registerPush');
                        },
                        register: function() {
                            return _callNative('registerPush');
                        },
                        addListener: function(event, callback) {
                            _pushListeners[event] = callback;
                            return { remove: function() { delete _pushListeners[event]; } };
                        }
                    }
                }
            };

            // Native share sheet for referrals
            window.__nativeShare = function(code, amount) {
                _post({ action: 'shareReferral', code: code || '', amount: amount || '' });
            };

            // Native haptic feedback
            window.__nativeHaptic = function(style) {
                _post({ action: 'haptic', style: style || 'medium' });
            };

            // Capacitor.Plugins.Haptics — matches what the web app calls
            window.Capacitor.Plugins.Haptics = {
                impact: function(opts) {
                    var style = (opts && opts.style) ? opts.style.toLowerCase() : 'light';
                    _post({ action: 'haptic', style: style });
                    return Promise.resolve();
                },
                notification: function(opts) {
                    var type = (opts && opts.type) ? opts.type.toLowerCase() : 'success';
                    _post({ action: 'haptic', style: type });
                    return Promise.resolve();
                },
                selectionStart: function() { return Promise.resolve(); },
                selectionChanged: function() {
                    _post({ action: 'haptic', style: 'selection' });
                    return Promise.resolve();
                },
                selectionEnd: function() { return Promise.resolve(); }
            };

            // Callback handler — called by native Swift via evaluateJavaScript
            window.nativeCallback = function(data) {
                if (!data || !data.action) return;

                var action = data.action;
                var cb;

                switch(action) {
                    case 'getProductsResult':
                        cb = _callbacks['getProducts'];
                        if (cb) {
                            if (data.success) cb.resolve({ products: data.products });
                            else cb.reject(data.error || 'Failed to get products');
                            delete _callbacks['getProducts'];
                        }
                        break;

                    case 'purchaseResult':
                        cb = _callbacks['purchase'];
                        if (cb) {
                            if (data.success) cb.resolve({ transactionId: data.transactionId, productId: data.productId });
                            else cb.reject(data.error || 'Purchase failed');
                            delete _callbacks['purchase'];
                        }
                        break;

                    case 'restoreResult':
                        cb = _callbacks['restorePurchases'];
                        if (cb) {
                            if (data.success) cb.resolve({ transactionId: data.transactionId, productId: data.productId });
                            else cb.reject(data.error || 'No active subscription');
                            delete _callbacks['restorePurchases'];
                        }
                        break;

                    case 'appleSignInResult':
                        cb = _callbacks['appleSignIn'];
                        if (cb) {
                            if (data.success) cb.resolve({ identityToken: data.identityToken, user: data.user, email: data.email });
                            else cb.reject(data.error || 'Sign in failed');
                            delete _callbacks['appleSignIn'];
                        }
                        break;

                    case 'pushPermissions':
                        cb = _callbacks['checkPushPermissions'];
                        if (cb) {
                            cb.resolve({ receive: data.status });
                            delete _callbacks['checkPushPermissions'];
                        }
                        break;

                    case 'pushRegistered':
                        cb = _callbacks['registerPush'];
                        if (cb) {
                            cb.resolve({ granted: data.granted });
                            delete _callbacks['registerPush'];
                        }
                        break;

                    case 'pushToken':
                        if (_pushListeners['registration']) {
                            _pushListeners['registration']({ value: data.token });
                        }
                        break;

                    case 'pushReceived':
                        if (_pushListeners['pushNotificationReceived']) {
                            _pushListeners['pushNotificationReceived'](data.notification);
                        }
                        break;

                    case 'pushTapped':
                        if (_pushListeners['pushNotificationActionPerformed']) {
                            _pushListeners['pushNotificationActionPerformed']({
                                notification: data.notification
                            });
                        }
                        break;

                    case 'shareResult':
                        break;

                    // FUTURE: Live Activities hook point
                    // case 'liveActivityUpdate':
                    //     Handle ActivityKit push-to-start / push-to-update for
                    //     "My Train" status on lock screen and Dynamic Island.
                    //     Requires: ActivityKit framework, Widget extension target,
                    //     APNs push-to-start token registration.
                    //     Server sends: train time, status, platform, delay minutes.
                    //     break;
                }
            };

            // Signal to native that the page is ready to receive callbacks
            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', function() {
                    _post({ action: 'nativeReady' });
                });
            } else {
                _post({ action: 'nativeReady' });
            }
        })();
        """
    }
}

// MARK: - UIColor Hex Extension

extension UIColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
}
