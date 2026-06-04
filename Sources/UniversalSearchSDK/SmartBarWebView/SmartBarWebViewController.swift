//
//  SmartBarWebViewController.swift
//  HDFC Bank SmartHub Vyapar
//
//  Created by Rajan Patel on 27/05/26.
//

import UIKit
import WebKit
import Speech
import AVFoundation
import LiveKit

// MARK: - Weak Message Handler Proxy
// Breaks the retain cycle: WKUserContentController → proxy (weak→ VC) instead of → VC directly

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(controller, didReceive: message)
    }
}

// MARK: - SmartBarWebViewController

public class SmartBarWebViewController: UIViewController {

    // Shared process pool ensures localStorage persists across VC instances
    private static let sharedProcessPool = WKProcessPool()

    // MARK: - Static Factory Method

    public static func instantiate(selectedValue: String = "") -> SmartBarWebViewController {
        let vc = SmartBarWebViewController()
        vc.initialSearchValue = selectedValue
        return vc
    }

    // MARK: - Properties

    var webView: WKWebView!
    private let voiceBridge = SmartBarVoiceBridge()
    private let hapticBridge = SmartBarHapticBridge()
    private let viewModel = AICallViewModel()
    var userQuery: String = ""

    var initialSearchValue: String = ""
    var isDashboard: Bool = false
    private var currentRoomName: String?

    // Call (native AICallView handles all UI/controls)

    /// URL with session parameters for the SmartBar web app
    private var webViewURL: URL {
        var components = URLComponents(string: Constant.smartBarWebViewURL)!

        // Add session data as query parameters
        var queryItems: [URLQueryItem] = []

        let sessionData = UniversalSearchManager.shared.sessionData ?? UniversalSearchManager.shared.delegate?.getSessionData()
        
        if let data = sessionData {
            if !data.sessionId.isEmpty {
                queryItems.append(URLQueryItem(name: "sessionId", value: data.sessionId))
            }
            if !data.loginId.isEmpty {
                queryItems.append(URLQueryItem(name: "loginId", value: data.loginId))
            }
            if !data.userRole.isEmpty {
                queryItems.append(URLQueryItem(name: "userRole", value: data.userRole))
            }
        }

        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        return components.url!
    }

    /// Session data dictionary for JavaScript injection
    private var sessionData: [String: Any] {
        guard let data = UniversalSearchManager.shared.sessionData ?? UniversalSearchManager.shared.delegate?.getSessionData() else { return [:] }
        return [
            "sessionId": data.sessionId,
            "loginId": data.loginId,
            "userName": data.userName,
            "userRole": data.userRole,
            "fcmToken": data.fcmToken,
            "tid": data.tid,
            "storeCount": data.storeCount,
            "isChainOwner": data.isChainOwner
        ]
    }
    
    private func setupViewModel() {
        viewModel.onTokenSuccess = { [weak self] token, roomName, isScreenShared in
            self?.connectToLiveKit(token: token, roomName: roomName, isScreenShared: isScreenShared)
        }

        viewModel.onAgentConnected = { roomName in
            #if DEBUG
            print("Agent connected to room:", roomName)
            #endif
        }

        viewModel.onError = { [weak self] message in
            self?.showAlert(message: message)
        }
    }

    // MARK: - UI Components
  
    private lazy var webViewContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .white
        return view
    }()

    private lazy var loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()

    private var webViewBottomConstraint: NSLayoutConstraint?


    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        setupWebView()
        setupBridges()
        setupLoadingIndicator()
        setupViewModel()
        SmartBarWebViewManager.shared.activeViewController = self
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        FloatingAIAssistManager.shared.hide()
        LiveKitCallManager.shared.delegate = self
        
        // Ensure shared webView delegates point to this instance
        if let sharedWebView = SmartBarWebViewManager.shared.webView {
            sharedWebView.navigationDelegate = self
            sharedWebView.uiDelegate = self
        }
        
        // Link manager closures to local handlers
        SmartBarWebViewManager.shared.onDeepLink = { [weak self] urlString in
            // Re-wrap in body dictionary to match existing handleDeepLinkMessage logic
            self?.handleDeepLinkMessage(["url": urlString])
        }
        SmartBarWebViewManager.shared.onCallAction = { [weak self] body in
            self?.handleCallMessage(body)
        }
        SmartBarWebViewManager.shared.onNavigationAction = { [weak self] body in
            if let action = body["action"] as? String, action == "downloadFile" {
                self?.handleDeepLinkMessage(body)
            } else {
                self?.handleNavigationMessage(body)
            }
        }
        SmartBarWebViewManager.shared.onAnalyticsAction = { [weak self] name, params in
            self?.handleAnalyticsMessage(["name": name, "params": params])
        }
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Clean up closures to avoid calling dismissed controller
        SmartBarWebViewManager.shared.onDeepLink = nil
        SmartBarWebViewManager.shared.onCallAction = nil
        SmartBarWebViewManager.shared.onNavigationAction = nil
        SmartBarWebViewManager.shared.onAnalyticsAction = nil
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !LiveKitCallManager.shared.isCallConnected {
            reEmitCallStateToWebView()
        }
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // voiceBridge.stopRecognition()
        FloatingAIAssistManager.shared.show()
        
        if !LiveKitCallManager.shared.isCallConnected {
            SmartBarWebViewManager.shared.activeViewController = nil
            SmartBarWebViewManager.shared.clearCachedWebViewIfAllowed()
        }
    }

    private func reEmitCallStateToWebView() {
        guard let webView = self.webView else { return }

        let eventName: String
        let conversationId = LiveKitCallManager.shared.chatConversationId
        
        switch LiveKitCallManager.shared.currentCallState {
        case .connected:
            eventName = "CALL_CONNECTED"
        case .reconnecting:
            eventName = "CALL_RECONNECT"
        case .disconnected, .idle:
            guard LiveKitCallManager.shared.wasInCall else { return }
            eventName = "CALL_DISCONNECTED"
            LiveKitCallManager.shared.wasInCall = false
        }

        var payloadDict: [String: Any] = [
            "type": "LIVEKIT_EVENT",
            "event": eventName
        ]
        
        if let cid = conversationId {
            payloadDict["conversationId"] = cid
        }
        
        if LiveKitCallManager.shared.isCallConnected {
            payloadDict["duration"] = LiveKitCallManager.shared.formattedDuration()
        }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payloadDict, options: []),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }

        let js = """
            (function() {
                var p = \(jsonString);
                window.dispatchEvent(new CustomEvent('LivekitEvent', { detail: p }));
                window.postMessage(p, '*');
            })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - Setup Methods

    deinit {
        // We no longer remove all script message handlers here as the webView is shared
    }

    private func setupWebView() {
        // Use the shared webView from SmartBarWebViewManager
        let sharedWebView = SmartBarWebViewManager.shared.getWebView(initialSearchValue: initialSearchValue)
        self.webView = sharedWebView
        
        sharedWebView.translatesAutoresizingMaskIntoConstraints = false
        sharedWebView.navigationDelegate = self
        sharedWebView.uiDelegate = self

        view.addSubview(webViewContainer)
        if let previousSuperview = sharedWebView.superview {
            let constraints = previousSuperview.constraints.filter {
                $0.firstItem === sharedWebView || $0.secondItem === sharedWebView
            }
            NSLayoutConstraint.deactivate(constraints)
            sharedWebView.removeFromSuperview()
        }
        webViewContainer.addSubview(sharedWebView)

        webViewBottomConstraint = webViewContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor)

        NSLayoutConstraint.activate([
            webViewContainer.topAnchor.constraint(equalTo: view.topAnchor),
            webViewContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webViewContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webViewBottomConstraint!,

            sharedWebView.topAnchor.constraint(equalTo: webViewContainer.topAnchor),
            sharedWebView.leadingAnchor.constraint(equalTo: webViewContainer.leadingAnchor),
            sharedWebView.trailingAnchor.constraint(equalTo: webViewContainer.trailingAnchor),
            sharedWebView.bottomAnchor.constraint(equalTo: webViewContainer.bottomAnchor)
        ])
        
        if SmartBarWebViewManager.shared.shouldLoadContentForCurrentWebView {
            loadContent()
        }
    }

    private func setupLoadingIndicator() {
        view.addSubview(loadingIndicator)
        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: webViewContainer.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: webViewContainer.centerYAnchor)
        ])
    }

    private func createButton(title: String, color: UIColor, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = AppFonts.FONT_SEMIBOLD(size: 14)
        button.backgroundColor = color
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 10
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    @objc private func initiateCallTapped() {
        sendLivekitEventToWebView(eventName: "initiateCall", data: nil)
    }

    @objc private func endCallTapped() {
        sendLivekitEventToWebView(eventName: "endCall", data: nil)
    }

    @objc private func muteCallTapped() {
        // Toggle or send specific state as needed, here we send a generic mute event
        sendLivekitEventToWebView(eventName: "muteCall", data: ["isMuted": true])
    }

    private func setupBridges() {
        voiceBridge.onResult = { [weak self] transcript, isFinal in
            let escapedTranscript = transcript.escapedForJS
            self?.sendToJS("window.SmartBarBridge?.onSpeechResult?.('\(escapedTranscript)', \(isFinal))")
        }

        voiceBridge.onError = { [weak self] error in
            let escapedError = error.escapedForJS
            self?.sendToJS("window.SmartBarBridge?.onSpeechError?.('\(escapedError)')")
        }

    }

    // MARK: - Call Bridge (delegates to native AICallView)

    private func handleCallMessage(_ body: [String: Any]) {
        guard let action = body["action"] as? String else { return }
        let conversationID = body["chat_conversation_id"] as? String
        LiveKitCallManager.shared.chatConversationId = conversationID
        
        switch action {
        case "INITCALL":
            //let vc = TermsAndConditionView.instantiate(redirectionURL: "https://www.mintoak.com/terms-and-conditions", onAgree: { [weak self] in
            self.presentNativeCallScreen()
            //}, onClose: { [weak self] in
                //self?.backButtonTapped()
            //})
            //vc.modalPresentationStyle = .overFullScreen
            //self.present(vc, animated: true)
            break
        case "start":
            //presentNativeCallScreen()
            break
        case "getState":
            reEmitCallStateToWebView()
        case "toggleMute":
            Task {
                await LiveKitCallManager.shared.toggleMute()
            }
        case "CALL_MUTE":
            Task {
                await LiveKitCallManager.shared.toggleMute()
            }
        case "CALL_UNMUTE":
            Task {
                await LiveKitCallManager.shared.toggleMute()
            }
        case "toggleScreenShare":
            Task {
                await LiveKitCallManager.shared.toggleScreenShare()
            }
        case "end":
            callEnd()
        case "CALL_DISCONNECTED":
            callEnd()
        default:
            #if DEBUG
            print("[SmartBarBridge] Call action '\(action)' ignored — handled natively by AICallView")
            #endif
            break
        }
    }
    
    func callEnd() {
        let alert = UIAlertController(
            title: "End Call?",
            message: "Are you sure you want to end the call?",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "End", style: .destructive) { [weak self] _ in
            self?.voiceBridge.stopRecognition()
            self?.endCall()
        })
        present(alert, animated: true)
    }

    func endCall() {
        Task {
            await LiveKitCallManager.shared.setScreenShare(false)
            await LiveKitCallManager.shared.disconnect()
        }
    }
    
    private func presentNativeCallScreen() {
        // Don't present another if already showing or a call is in progress
        // # When AI Call Integrate
        if navigationController?.viewControllers.contains(where: { $0 is AICallView }) == true {
            return
        }
        guard !LiveKitCallManager.shared.isCallConnected else {
            return
        }

        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            pushAICallView()
        case .denied:
            showMicrophonePermissionAlert()
        case .undetermined:
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.pushAICallView()
                    } else {
                        self?.showMicrophonePermissionAlert()
                    }
                }
            }
        @unknown default:
            break
        }
    }

    private func pushAICallView() {
        self.viewModel.getToken(name: UniversalSearchManager.shared.sessionData?.userName ?? "")
        /*let callVC = AICallView.instantiate(selectedValue: "")
        callVC.userQuery = UserDefaults.standard.string(forKey: "lastSearchText") ?? ""
        callVC.onCallEnded = { [weak self] durationText, endTimeText in
            self?.sendToJS("window.SmartBarBridge?.onCallStateChange?.('disconnected')")
        }
        navigationController?.pushViewController(callVC, animated: true)*/
    }

    private func loadContent() {
        loadingIndicator.startAnimating()

        var request = URLRequest(url: webViewURL)
        request.cachePolicy = .useProtocolCachePolicy
        SmartBarWebViewManager.shared.markContentLoadRequested()
        webView.load(request)
    }

    private func checkMicrophonePermission() {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            voiceBridge.startRecognition()
        case .denied:
            showMicrophonePermissionAlert()
        case .undetermined:
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.voiceBridge.startRecognition()
                    } else {
                        self?.showMicrophonePermissionAlert()
                    }
                }
            }
        @unknown default:
            voiceBridge.startRecognition()
        }
    }

    private func showMicrophonePermissionAlert() {
        let alert = UIAlertController(
            title: "Microphone Permission Required",
            message: "Microphone permission is required for AI Call. Please enable it in Settings.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Settings", style: .default) { _ in
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsURL)
            }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            // Just dismiss, don't exit screen
        })
        present(alert, animated: true)
    }


    // MARK: - Actions

    @objc private func backButtonTapped() {
        if let nav = navigationController {
            nav.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }
    

    // MARK: - File Download

    private func downloadReportFile(from url: URL, fileName: String) {
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }
            guard let data = data, error == nil else {
                print("[SmartBarBridge] Failed to download file: \(error?.localizedDescription ?? "Unknown error")")
                DispatchQueue.main.async {
                    self.sendToJS("window.SmartBarBridge?.onDownloadResult?.({ success: false, error: 'Download failed' })")
                }
                return
            }

            // Save file to Documents directory as .xlsx
            let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
            let filePath = "\(documentsPath)/\(fileName).xlsx"
            do {
                try data.write(to: URL(fileURLWithPath: filePath))
                UserDefaults.standard.setValue(filePath, forKey: "docpath")

                DispatchQueue.main.async {
                    let fileURL = URL(fileURLWithPath: filePath)
                    let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
                    self.present(activityVC, animated: true)

                    activityVC.completionWithItemsHandler = { _, completed, _, _ in
                        self.sendToJS("window.SmartBarBridge?.onDownloadResult?.({ success: \(completed) })")
                    }
                }
            } catch {
                print("[SmartBarBridge] Failed to save file: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.sendToJS("window.SmartBarBridge?.onDownloadResult?.({ success: false, error: 'Save failed' })")
                }
            }
        }
        task.resume()
    }

    // MARK: - JavaScript Communication

    private func sendToJS(_ script: String) {
        DispatchQueue.main.async { [weak self] in
            self?.webView.evaluateJavaScript(script) { _, error in
                if let error = error {
                    print("[SmartBarBridge] JS Error: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Bridge JavaScript

    private static let bridgeJavaScript = """
    window.SmartBarBridge = {
        // Platform detection
        isNative: true,
        platform: 'ios',

        // Session data (also available via window.SmartBarSession)
        getSession: function() {
            return window.SmartBarSession || {};
        },
        getSessionId: function() {
            return (window.SmartBarSession && window.SmartBarSession.sessionId) || '';
        },
        getLoginId: function() {
            return (window.SmartBarSession && window.SmartBarSession.loginId) || '';
        },
        getUserRole: function() {
            return (window.SmartBarSession && window.SmartBarSession.userRole) || '';
        },
        getUserName: function() {
            return (window.SmartBarSession && window.SmartBarSession.userName) || '';
        },

        // Request fresh session data from native
        refreshSession: function() {
            window.webkit.messageHandlers.navigation.postMessage({ action: 'getSession' });
        },
        onSessionUpdate: null,

        // Voice Recognition
        startVoiceRecognition: function() {
            window.webkit.messageHandlers.voice.postMessage({ action: 'start' });
        },
        stopVoiceRecognition: function() {
            window.webkit.messageHandlers.voice.postMessage({ action: 'stop' });
        },
        onSpeechResult: null,
        onSpeechError: null,

        // Haptics
        hapticLight: function() {
            window.webkit.messageHandlers.haptic.postMessage({ type: 'light' });
        },
        hapticMedium: function() {
            window.webkit.messageHandlers.haptic.postMessage({ type: 'medium' });
        },
        hapticSuccess: function() {
            window.webkit.messageHandlers.haptic.postMessage({ type: 'success' });
        },
        hapticError: function() {
            window.webkit.messageHandlers.haptic.postMessage({ type: 'error' });
        },

        // Deep Links
        openDeepLink: function(url) {
            window.webkit.messageHandlers.deeplink.postMessage({ url: url });
        },

        // File Download (report .xlsx etc.)
        downloadFile: function(url, fileName) {
            window.webkit.messageHandlers.deeplink.postMessage({ action: 'downloadFile', url: url, fileName: fileName || 'Report' });
        },

        // Navigation
        goBack: function() {
            window.webkit.messageHandlers.navigation.postMessage({ action: 'back' });
        },
        navigateTo: function(screen, params) {
            window.webkit.messageHandlers.navigation.postMessage({
                action: 'navigate',
                screen: screen,
                params: params || {}
            });
        },

        // Analytics
        logEvent: function(name, params) {
            window.webkit.messageHandlers.analytics.postMessage({ name: name, params: params || {} });
        },

        // Initial value injection from native
        setInitialValue: function(value) {
            window.dispatchEvent(new CustomEvent('SmartBarSetInitialValue', { detail: { value: value } }));
        },

        // Call
        startCall: function() {
            window.webkit.messageHandlers.call.postMessage({ action: 'start' });
        },
        endCall: function() {
            window.webkit.messageHandlers.call.postMessage({ action: 'end' });
        },
        toggleMute: function() {
            window.webkit.messageHandlers.call.postMessage({ action: 'toggleMute' });
        },
        toggleScreenShare: function() {
            window.webkit.messageHandlers.call.postMessage({ action: 'toggleScreenShare' });
        },
        onCallStateChange: null,
        onMuteChange: null,
        onScreenShareChange: null,

        // Livekit
        sendLivekitEvent: function(eventName, data) {
            window.webkit.messageHandlers.livekit.postMessage({ event: eventName, data: data });
        }
    };

    // Intercept console.log for BACK navigation
    (function() {
        var _origLog = console.log;
        console.log = function() {
            _origLog.apply(console, arguments);
            try {
                var msg = arguments[0];
                if (typeof msg === 'string') {
                    var parsed = JSON.parse(msg);
                    if (parsed && parsed.type === 'BACK') {
                        window.webkit.messageHandlers.navigation.postMessage({ action: 'back' });
                    }
                }
            } catch(e) {}
        };
    })();

    // Notify web app that bridge is ready
    window.dispatchEvent(new CustomEvent('SmartBarBridgeReady'));
    console.log('[SmartBar] Native iOS bridge initialized');
    """
}

// MARK: - WKScriptMessageHandler

extension SmartBarWebViewController: WKScriptMessageHandler {

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }

        switch message.name {
        case "voice":
            handleVoiceMessage(body)
        case "haptic":
            handleHapticMessage(body)
        case "deeplink":
            handleDeepLinkMessage(body)
        case "navigation":
            handleNavigationMessage(body)
        case "analytics":
            handleAnalyticsMessage(body)
        case "call":
            // # When AI Call Integrate
            handleCallMessage(body)
            break
        case "livekit":
            handleLivekitMessage(body)
            break
        default:
            break
        }
    }

    private func handleVoiceMessage(_ body: [String: Any]) {
        guard let action = body["action"] as? String else { return }

        switch action {
        case "start":
            checkMicrophonePermission()
        case "stop":
            voiceBridge.stopRecognition()
        default:
            break
        }
    }

    private func handleHapticMessage(_ body: [String: Any]) {
        guard let type = body["type"] as? String else { return }

        switch type {
        case "light":
            hapticBridge.light()
        case "medium":
            hapticBridge.medium()
        case "success":
            hapticBridge.success()
        case "error":
            hapticBridge.error()
        default:
            break
        }
    }

    private func handleDeepLinkMessage(_ body: [String: Any]) {
        // Handle file download action
        if let action = body["action"] as? String, action == "downloadFile",
           let urlString = body["url"] as? String,
           let fileUrl = URL(string: urlString) {
            let fileName = body["fileName"] as? String ?? "Report"
            downloadReportFile(from: fileUrl, fileName: fileName)
            return
        }

        guard let urlString = body["url"] as? String else { return }

        // Extract and store SmartBar filter params (sb_tids, sb_date, sb_start, sb_end)
        let (cleanURL, _) = extractAndStoreSmartBarFilterParams(from: urlString)

        // Handle internal deep links
        if cleanURL.hasPrefix("app://") || cleanURL.hasPrefix("smartbar://") {
            handleInternalDeepLink(cleanURL)
            return
        }
        
        // Delegate all deep links to the host app
        UniversalSearchManager.shared.delegate?.handleDeepLink(cleanURL)
        //DispatchQueue.main.async {
            //self.backButtonTapped()
        //}
    }

    /// Extract SmartBar filter query params (sb_tids, sb_date, sb_start, sb_end) from a deeplink URL,
    /// store them in UserDefaults for the destination screen, and return the cleaned URL without sb_* params.
    private func extractAndStoreSmartBarFilterParams(from urlString: String) -> (String, Bool) {
        guard var components = URLComponents(string: urlString) else {
            UserDefaults.standard.clearSmartBarFilter()
            return (urlString, false)
        }

        let queryItems = components.queryItems ?? []
        let sbItems = queryItems.filter { $0.name.hasPrefix("sb_") }

        guard !sbItems.isEmpty else {
            UserDefaults.standard.clearSmartBarFilter()
            return (urlString, false)
        }

        // Parse SmartBar filter params
        var tids: [String]?
        var date: String?
        var startDate: String?
        var endDate: String?

        for item in sbItems {
            switch item.name {
            case "sb_tids":
                tids = item.value?.components(separatedBy: ",").filter { !$0.isEmpty }
            case "sb_date":
                date = item.value
            case "sb_start":
                startDate = item.value
            case "sb_end":
                endDate = item.value
            default:
                break
            }
        }

        // Store in UserDefaults for destination screen consumption
        UserDefaults.standard.smartBarFilterTids = tids
        UserDefaults.standard.smartBarFilterDate = date
        UserDefaults.standard.smartBarFilterStartDate = startDate
        UserDefaults.standard.smartBarFilterEndDate = endDate
        // Strip sb_* params from URL so DeepLinkHelper exact matching still works
        let remainingItems = queryItems.filter { !$0.name.hasPrefix("sb_") }
        components.queryItems = remainingItems.isEmpty ? nil : remainingItems

        let cleanURL = components.string ?? urlString
        return (cleanURL, true)
    }



    private func handleNavigationMessage(_ body: [String: Any]) {
        guard let action = body["action"] as? String else { return }

        switch action {
        case "back":
            backButtonTapped()
        case "navigate":
            if let screen = body["screen"] as? String {
                let params = body["params"] as? [String: Any] ?? [:]
                //#Framework Run
                navigateToScreen(screen, params: params)
            }
        case "getSession":
            // Send fresh session data to webview
            sendSessionDataToJS()
        default:
            break
        }
    }

    private func navigateToScreen(_ screen: String, params: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            guard let link = Constant.ScreenRoutes[screen.lowercased()] else {
                print("[SmartBar] Unknown screen: \(screen)")
                return
            }

            // Immediately delegate the internal link back to the host App
            UniversalSearchManager.shared.delegate?.handleDeepLink(link)
            //self.backButtonTapped()
        }
    }
    
    private func sendSessionDataToJS() {
        if let sessionDataJSON = try? JSONSerialization.data(withJSONObject: sessionData, options: []),
           let sessionDataString = String(data: sessionDataJSON, encoding: .utf8) {
            let script = """
            window.SmartBarSession = \(sessionDataString);
            window.SmartBarBridge?.onSessionUpdate?.(\(sessionDataString));
            """
            sendToJS(script)
        }
    }

    private func handleAnalyticsMessage(_ body: [String: Any]) {
        guard let name = body["name"] as? String else { return }
        let params = body["params"] as? [String: Any] ?? [:]

        // Sanitize event name for Firebase (alphanumeric + underscores, max 40 chars)
        let sanitizedName = name
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")

        // Convert params to [String: String] for AnalyticsUtilites
        var stringParams: [String: String] = [:]
        for (key, value) in params {
            stringParams[key] = "\(value)"
        }

        UniversalSearchManager.shared.delegate?.logEvent(
            eventName: String(sanitizedName.prefix(40)),
            params: stringParams
        )
    }

    // MARK: - Livekit Bridge

    private func handleLivekitMessage(_ body: [String: Any]) {
        guard let eventName = body["event"] as? String else { return }
        let data = body["data"]

        #if DEBUG
        print("[SmartBarBridge] Livekit event received from WebView: \(eventName) with data: \(String(describing: data))")
        #endif

        // Forward to native listeners if needed
        NotificationCenter.default.post(
            name: NSNotification.Name("SmartBarLivekitEvent"),
            object: nil,
            userInfo: ["event": eventName, "data": data ?? [:]]
        )
    }

    /// Sends a Livekit event to the WebView by injecting JavaScript.
    /// This matches the Android implementation by calling window.postMessage
    /// and dispatching a 'LivekitEvent' CustomEvent.
    public func sendLivekitEventToWebView(eventName: String, data: Any?) {
        var payload: [String: Any] = [
            "type": "LIVEKIT_EVENT",
            "event": eventName
        ]
        if let data = data {
            payload["data"] = data
        }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: []),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }

        let js = """
        (function() {
            var eventPayload = \(jsonString);
            window.postMessage(eventPayload, '*');
            window.dispatchEvent(new CustomEvent('LivekitEvent', { detail: eventPayload }));
        })();
        """

        #if DEBUG
        print("[SmartBarBridge] Injecting Livekit event into WebView: \(eventName) with data: \(String(describing: data))")
        #endif

        sendToJS(js)
    }

    // MARK: - Internal Navigation

    private func handleInternalDeepLink(_ urlString: String) {
        // Parse the deep link and navigate to appropriate screen
        let cleanURL = urlString
            .replacingOccurrences(of: "app://", with: "")
            .replacingOccurrences(of: "smartbar://", with: "")

        let components = cleanURL.components(separatedBy: "/")
        guard let screen = components.first else { return }

        navigateToScreen(screen, params: [:])
    }
}

// MARK: - WKNavigationDelegate

extension SmartBarWebViewController: WKNavigationDelegate {

    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loadingIndicator.startAnimating()
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadingIndicator.stopAnimating()
        SmartBarWebViewManager.shared.markContentLoadSucceeded()

        // Send initial value to web app if provided
        if !initialSearchValue.isEmpty {
            let script = "window.SmartBarBridge?.setInitialValue?.('\(initialSearchValue.escapedForJS)');"
            sendToJS(script)
        }
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadingIndicator.stopAnimating()
        SmartBarWebViewManager.shared.markContentLoadFailed(for: webView)
        print("[SmartBar] WebView navigation failed: \(error.localizedDescription)")
        showErrorState(error)
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadingIndicator.stopAnimating()
        SmartBarWebViewManager.shared.markContentLoadFailed(for: webView)
        print("[SmartBar] WebView provisional navigation failed: \(error.localizedDescription)")
        showErrorState(error)
    }

    private func showErrorState(_ error: Error) {
        // Show error UI - could display a retry button
        let alert = UIAlertController(
            title: "Connection Error",
            message: "Unable to load SmartBar. Please check your connection and try again.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Retry", style: .default) { [weak self] _ in
            self?.loadContent()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.backButtonTapped()
        })
        present(alert, animated: true)
    }
}

// MARK: - WKUIDelegate

extension SmartBarWebViewController: WKUIDelegate {

    public func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completionHandler()
        })
        present(alert, animated: true)
    }

    public func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            completionHandler(false)
        })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completionHandler(true)
        })
        present(alert, animated: true)
    }
}


// MARK: - String Extension for JS Escaping

private extension String {
    var escapedForJS: String {
        return self
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "${", with: "\\${")
            .replacingOccurrences(of: "</script>", with: "<\\/script>")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }
}

// MARK: - SmartBarTransactionDetailVC

class SmartBarTransactionDetailVC: UIViewController {

    private let transactionId: String
    private let amount: String
    private let status: String
    private let time: String
    private let txnDescription: String
    private let paymentType: String
    private let customerName: String
    private let cardNumber: String

    init(transactionId: String, amount: String, status: String, time: String,
         description: String, paymentType: String, customerName: String, cardNumber: String) {
        self.transactionId = transactionId
        self.amount = amount
        self.status = status
        self.time = time
        self.txnDescription = description
        self.paymentType = paymentType
        self.customerName = customerName
        self.cardNumber = cardNumber
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        setupUI()
    }

    private func setupUI() {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -40)
        ])

        // Title
        let titleLabel = UILabel()
        titleLabel.text = "Transaction Details"
        titleLabel.font = AppFonts.FONT_SEMIBOLD(size: 18)
        titleLabel.textColor = UIColor.universalSearchLabelColor
        stack.addArrangedSubview(titleLabel)
        stack.setCustomSpacing(20, after: titleLabel)

        // Status badge
        let statusBadge = makeStatusBadge()
        stack.addArrangedSubview(statusBadge)
        stack.setCustomSpacing(20, after: statusBadge)

        // Amount
        let amountLabel = UILabel()
        let currencySymbol = "$"
        if let amountNum = Double(amount) {
            amountLabel.text = "\(currencySymbol) \(String(format: "%.2f", amountNum))"
        } else {
            amountLabel.text = "\(currencySymbol) \(amount)"
        }
        amountLabel.font = AppFonts.FONT_BOLD(size: 28)
        amountLabel.textColor = UIColor.universalSearchLabelColor
        amountLabel.textAlignment = .center
        stack.addArrangedSubview(amountLabel)
        stack.setCustomSpacing(24, after: amountLabel)

        // Divider
        stack.addArrangedSubview(makeDivider())
        stack.setCustomSpacing(16, after: stack.arrangedSubviews.last!)

        // Detail rows
        let rows: [(String, String)] = [
            ("Transaction ID", transactionId),
            ("Payment Type", paymentType),
            ("Date & Time", time),
            ("Customer", customerName),
            ("Card Number", cardNumber),
            ("Description", txnDescription)
        ]

        for (label, value) in rows {
            guard !value.isEmpty else { continue }
            let row = makeDetailRow(title: label, value: value)
            stack.addArrangedSubview(row)
            stack.setCustomSpacing(12, after: row)
        }

        // Close button
        stack.setCustomSpacing(24, after: stack.arrangedSubviews.last!)
        let closeBtn = UIButton(type: .system)
        closeBtn.setTitle("Done", for: .normal)
        closeBtn.titleLabel?.font = AppFonts.FONT_SEMIBOLD(size: 16)
        closeBtn.setTitleColor(.white, for: .normal)
        closeBtn.backgroundColor = UIColor.darkBlueThemeColor
        closeBtn.layer.cornerRadius = 12
        closeBtn.heightAnchor.constraint(equalToConstant: 48).isActive = true
        closeBtn.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        stack.addArrangedSubview(closeBtn)
    }

    private func makeStatusBadge() -> UIView {
        let container = UIView()
        let label = UILabel()
        label.text = status.capitalized
        label.font = AppFonts.FONT_SEMIBOLD(size: 13)
        label.textAlignment = .center

        let lowerStatus = status.lowercased()
        if lowerStatus.contains("success") || lowerStatus.contains("captured") || lowerStatus.contains("settled") {
            label.textColor = UIColor.successTextColor
            label.backgroundColor = UIColor.flexiBackgroundColor
        } else if lowerStatus.contains("fail") || lowerStatus.contains("declined") {
            label.textColor = UIColor.failedTrnstTextColor
            label.backgroundColor = UIColor.commonSdkBackColor
        } else if lowerStatus.contains("pending") || lowerStatus.contains("progress") {
            label.textColor = UIColor.inProgressTrnstTextColor
            label.backgroundColor = UIColor.btnUserPendingColor
        } else {
            label.textColor = UIColor.universalSearchTitleLabelColor
            label.backgroundColor = UIColor.textFieldBackgroundColor
        }

        label.layer.cornerRadius = 8
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.topAnchor.constraint(equalTo: container.topAnchor),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            label.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
            label.heightAnchor.constraint(equalToConstant: 28)
        ])
        return container
    }

    private func makeDetailRow(title: String, value: String) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fill

        let titleLbl = UILabel()
        titleLbl.text = title
        titleLbl.font = AppFonts.FONT_REGULAR(size: 13)
        titleLbl.textColor = UIColor.universalSearchTitleLabelColor
        titleLbl.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        let valueLbl = UILabel()
        valueLbl.text = value
        valueLbl.font = AppFonts.FONT_SEMIBOLD(size: 13)
        valueLbl.textColor = UIColor.fontColor
        valueLbl.textAlignment = .right
        valueLbl.numberOfLines = 2

        row.addArrangedSubview(titleLbl)
        row.addArrangedSubview(valueLbl)
        return row
    }

    private func makeDivider() -> UIView {
        let line = UIView()
        line.backgroundColor = UIColor.universalSearchDeviderColor
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return line
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }
}


//MARK: Extension: Connect to Live Kit Method
extension SmartBarWebViewController {

    func connectToLiveKit(token: String, roomName: String, isScreenShared: Bool = false) {
        #if DEBUG
        print("Connecting to room:", roomName)
        #endif
        self.currentRoomName = roomName

        let context = UserContext(userQuery: userQuery)
        var userContext = "{}"
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(context)
            userContext = String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            #if DEBUG
            print("UserContext encoding failed:", error)
            #endif
        }
        self.viewModel.connectAgent(name: UniversalSearchManager.shared.sessionData?.userName ?? "", roomName: roomName, userContext: userContext)
        if isScreenShared {
            //self.callConnectRoomWithScreenSharing(token: token)
        } else {
            self.callConnectRoom(token: token)
        }
    }
    
    func callConnectRoom(token: String) {
        Task {
            do {
                try await LiveKitCallManager.shared.connect(token: token)
            } catch {
                await MainActor.run {
                    //showAlert(message: "Unable to connect call")
                }
            }
        }
    }

}

//MARK: Extension: Alert show message
extension SmartBarWebViewController {

    func showAlert(title: String = "Error", message: String) {
        let alert = UIAlertController(title: title,
                                      message: message,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

//MARK: Extension: LiveKit Call State Delegate Methods
extension SmartBarWebViewController: LiveKitCallStateDelegate {

    func onCallConnecting() {
        //showConnectingState()
        //updateMuteButtonUI(
//            isMuted: LiveKitCallManager.shared.isMuted
        //)
    }

    func onCallConnected() {
        SmartBarWebViewManager.shared.sendLivekitEvent(eventName: "CALL_CONNECTED", roomId: LiveKitCallManager.shared.chatConversationId)
        //showConnectedState()

        //updateMuteButtonUI(
            //isMuted: LiveKitCallManager.shared.isMuted
        //)

        //updateShareButtonUI(
            //isScreenShared: LiveKitCallManager.shared.isScreenShared
        //)
    }

    func onCallReconnecting() {
        //showReconnectingState()
    }

    func onCallDisconnected() {
        if let roomName = currentRoomName {
            viewModel.deleteRoom(roomName: roomName)
            currentRoomName = nil
        }
        SmartBarWebViewManager.shared.sendLivekitEvent(eventName: "CALL_DISCONNECTED", roomId: LiveKitCallManager.shared.chatConversationId)
        
        if self.view.window == nil {
            SmartBarWebViewManager.shared.activeViewController = nil
            SmartBarWebViewManager.shared.clearCachedWebViewIfAllowed()
        }
//        stopAllAnimations()
//        btnMute.isEnabled = false
//        btnScreenShare.isEnabled = false
//        btnEndCall.isEnabled = false
//        notificationFeedback.notificationOccurred(.warning)
//
//        let durationText = LiveKitCallManager.shared.formattedDuration()
//        let endTimeText = formattedEndTime()
//
//        onCallEnded?(durationText, endTimeText)
//
//        closeCallScreen()
    }

}

extension SmartBarWebViewController {

    private func loadSearchHistoryFromUserDefaults() {
        guard userQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            #if DEBUG
            print("Using explicit userQuery, skipping search history load")
            #endif
            return
        }

        guard let data = UserDefaults.standard.data(
            forKey: UniversalSearchStorage.historyKey
        ) else {
            return
        }

        if let jsonString = prettyPrintedJSONString(from: data) {
            #if DEBUG
            print("Search History JSON (fallback):\n\(jsonString)")
            #endif
            userQuery = jsonString
        }

    }

    private func prettyPrintedJSONString(from data: Data) -> String? {
        do {
            let jsonObject = try JSONSerialization.jsonObject(
                with: data,
                options: []
            )
            let prettyData = try JSONSerialization.data(
                withJSONObject: jsonObject,
                options: [.prettyPrinted]
            )
            return String(data: prettyData, encoding: .utf8)
        } catch {
            #if DEBUG
            print("JSON stringify error:", error)
            #endif
            return nil
        }
    }

}
