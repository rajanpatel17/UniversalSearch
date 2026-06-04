//
//  SmartBarWebViewManager.swift
//  UniversalSearchSDK
//
//  Created by Rajan Patel on 27/05/26.
//

import Foundation
import WebKit
import AVFoundation
import Speech

// MARK: - Weak Message Handler Proxy
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?
    init(delegate: WKScriptMessageHandler) { self.delegate = delegate }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(controller, didReceive: message)
    }
}

// MARK: - Voice Bridge
class SmartBarVoiceBridge: NSObject {
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    var onResult: ((String, Bool) -> Void)?
    var onError: ((String) -> Void)?
    override init() {
        super.init()
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-IN"))
        requestAuthorization()
    }
    private func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                switch status {
                case .authorized: print("[SmartBar Voice] Speech recognition authorized")
                case .denied: self?.onError?("Speech recognition denied")
                case .restricted: self?.onError?("Speech recognition restricted")
                case .notDetermined: self?.onError?("Speech recognition not determined")
                @unknown default: break
                }
            }
        }
    }
    func startRecognition() {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            onError?("Speech recognition not available")
            return
        }
        stopRecognition()
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let request = recognitionRequest else {
                onError?("Could not create recognition request")
                return
            }
            request.shouldReportPartialResults = true
            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                request.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()
            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self = self else { return }
                if let result = result {
                    let transcript = result.bestTranscription.formattedString
                    let isFinal = result.isFinal
                    DispatchQueue.main.async { self.onResult?(transcript, isFinal) }
                    if isFinal { self.stopRecognition() }
                }
                if let error = error {
                    DispatchQueue.main.async { self.onError?(error.localizedDescription) }
                    self.stopRecognition()
                }
            }
        } catch { onError?(error.localizedDescription) }
    }
    
    func stopRecognition() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

// MARK: - Haptic Bridge
class SmartBarHapticBridge {
    private let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let notificationGenerator = UINotificationFeedbackGenerator()
    init() {
        lightGenerator.prepare()
        mediumGenerator.prepare()
        notificationGenerator.prepare()
    }
    func light() { lightGenerator.impactOccurred() }
    func medium() { mediumGenerator.impactOccurred() }
    func success() { notificationGenerator.notificationOccurred(.success) }
    func error() { notificationGenerator.notificationOccurred(.error) }
}

// MARK: - SmartBarWebViewManager
public final class SmartBarWebViewManager: NSObject {
    
    public static let shared = SmartBarWebViewManager()
    
    public var webView: WKWebView?
    public var activeViewController: SmartBarWebViewController?
    private(set) var lastWebViewRequestCreatedNewWebView = false
    private var hasRequestedInitialLoad = false
    private(set) var hasLoadedContent = false
    private let voiceBridge = SmartBarVoiceBridge()
    private let hapticBridge = SmartBarHapticBridge()
    private static let sharedProcessPool = WKProcessPool()
    
    public var onDeepLink: ((String) -> Void)?
    public var onCallAction: (([String: Any]) -> Void)?
    public var onNavigationAction: (([String: Any]) -> Void)?
    public var onAnalyticsAction: ((String, [String: Any]) -> Void)?
    
    private override init() {
        super.init()
        setupBridges()
    }
    
    public func getWebView(initialSearchValue: String = "") -> WKWebView {
        if let existing = webView {
            lastWebViewRequestCreatedNewWebView = false
            if !initialSearchValue.isEmpty {
                sendInitialValue(initialSearchValue)
            }
            return existing
        }
        
        let config = WKWebViewConfiguration()
        config.processPool = Self.sharedProcessPool
        config.websiteDataStore = .default()
        let contentController = WKUserContentController()

        let proxy = WeakScriptMessageHandler(delegate: self)
        contentController.add(proxy, name: "voice")
        contentController.add(proxy, name: "haptic")
        contentController.add(proxy, name: "deeplink")
        contentController.add(proxy, name: "analytics")
        contentController.add(proxy, name: "navigation")
        contentController.add(proxy, name: "call")
        contentController.add(proxy, name: "livekit")

        let bridgeScript = WKUserScript(
            source: SmartBarWebViewManager.bridgeJavaScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        contentController.addUserScript(bridgeScript)

        injectSessionData(to: contentController)

        if !initialSearchValue.isEmpty {
            let initScript = WKUserScript(
                source: "window.SmartBarInitialValue = '\(initialSearchValue.escapedForJS)';",
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
            contentController.addUserScript(initScript)
        }

        config.userContentController = contentController
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        #if DEBUG
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        #endif

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .white
        
        self.webView = webView
        lastWebViewRequestCreatedNewWebView = true
        hasRequestedInitialLoad = false
        hasLoadedContent = false
        return webView
    }
    
    public func loadContent() {
        guard let webView = webView else { return }
        var request = URLRequest(url: webViewURL)
        request.cachePolicy = .useProtocolCachePolicy
        hasRequestedInitialLoad = true
        webView.load(request)
    }

    @MainActor
    func markContentLoadRequested() {
        hasRequestedInitialLoad = true
    }

    @MainActor
    func markContentLoadSucceeded() {
        hasLoadedContent = true
    }

    @MainActor
    func markContentLoadFailed(for webView: WKWebView) {
        guard self.webView === webView else { return }
        if webView.backForwardList.currentItem == nil {
            hasLoadedContent = false
            hasRequestedInitialLoad = false
        }
    }

    @MainActor var shouldLoadContentForCurrentWebView: Bool {
        guard let webView else { return false }
        
        // If a call is connected, we should NEVER reload the content as it would disconnect the call state in WebView
        if LiveKitCallManager.shared.isCallConnected {
            return false
        }
        
        if lastWebViewRequestCreatedNewWebView || !hasRequestedInitialLoad {
            return true
        }
        if webView.isLoading {
            return false
        }
        if hasLoadedContent && webView.backForwardList.currentItem != nil {
            return false
        }
        return webView.url == nil || webView.backForwardList.currentItem == nil
    }

    @discardableResult
    @MainActor
    func clearCachedWebViewIfAllowed() -> Bool {
        guard !LiveKitCallManager.shared.isCallConnected else {
            return false
        }

        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        webView?.removeFromSuperview()
        webView = nil
        activeViewController = nil
        lastWebViewRequestCreatedNewWebView = false
        hasRequestedInitialLoad = false
        hasLoadedContent = false
        return true
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
    
    private func injectSessionData(to contentController: WKUserContentController) {
        if let sessionDataJSON = try? JSONSerialization.data(withJSONObject: sessionData, options: []),
           let sessionDataString = String(data: sessionDataJSON, encoding: .utf8) {
            let sessionScript = WKUserScript(
                source: "window.SmartBarSession = \(sessionDataString);",
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
            contentController.addUserScript(sessionScript)
        }
    }
    
    public func sendSessionDataToJS() {
        if let sessionDataJSON = try? JSONSerialization.data(withJSONObject: sessionData, options: []),
           let sessionDataString = String(data: sessionDataJSON, encoding: .utf8) {
            let script = """
            window.SmartBarSession = \(sessionDataString);
            window.SmartBarBridge?.onSessionUpdate?.(\(sessionDataString));
            """
            sendToJS(script)
        }
    }
    
    public func sendInitialValue(_ value: String) {
        let script = "window.SmartBarBridge?.setInitialValue?.('\(value.escapedForJS)');"
        sendToJS(script)
    }

    private func sendToJS(_ script: String) {
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(script) { _, error in
                if let error = error {
                    print("[SmartBarWebViewManager] JS Error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    @MainActor public func sendLivekitEvent(
        eventName: String,
        roomId: String? = nil,
        data: Any? = nil
    ) {

        var payload: [String: Any] = [
            "type": "LIVEKIT_EVENT",
            "event": eventName
        ]

        // Add roomId only for CALL_CONNECTED
        if eventName == "CALL_CONNECTED",
           let roomId = roomId {
            payload["conversationId"] = roomId
            payload["duration"] = LiveKitCallManager.shared.formattedDuration()
        }

        if eventName == "CALL_DISCONNECTED",
           let roomId = roomId {
            payload["conversationId"] = roomId
        }

        // Optional data payload
        if let data = data {
            payload["data"] = data
        }

        guard let jsonData = try? JSONSerialization.data(
            withJSONObject: payload,
            options: []
        ),
        let jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }

        let js = """
        (function() {
            var eventPayload = \(jsonString);
            window.postMessage(eventPayload, '*');
            window.dispatchEvent(
                new CustomEvent('LivekitEvent', {
                    detail: eventPayload
                })
            );
        })();
        """

        #if DEBUG
        print("[SmartBarWebViewManager] Injecting Livekit event into WebView: \(eventName)")
        #endif

        sendToJS(js)
    }
    
    private var webViewURL: URL {
        var components = URLComponents(string: Constant.smartBarWebViewURL)!
        var queryItems: [URLQueryItem] = []
        let sessionData = UniversalSearchManager.shared.sessionData ?? UniversalSearchManager.shared.delegate?.getSessionData()
        
        if let data = sessionData {
            if !data.sessionId.isEmpty { queryItems.append(URLQueryItem(name: "sessionId", value: data.sessionId)) }
            if !data.loginId.isEmpty { queryItems.append(URLQueryItem(name: "loginId", value: data.loginId)) }
            if !data.userRole.isEmpty { queryItems.append(URLQueryItem(name: "userRole", value: data.userRole)) }
        }

        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        return components.url!
    }

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
    
    public func stopVoiceRecognition() {
        voiceBridge.stopRecognition()
    }
    
    public func startVoiceRecognition() {
        checkMicrophonePermission()
    }
    
    private func checkMicrophonePermission() {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            voiceBridge.startRecognition()
        case .denied:
            break
        case .undetermined:
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.voiceBridge.startRecognition()
                    }
                }
            }
        @unknown default:
            voiceBridge.startRecognition()
        }
    }
}

// MARK: - WKScriptMessageHandler

extension SmartBarWebViewManager: WKScriptMessageHandler {
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
            onCallAction?(body)
        case "livekit":
            if let eventName = body["event"] as? String {
                let data = body["data"]
                NotificationCenter.default.post(
                    name: NSNotification.Name("SmartBarLivekitEvent"),
                    object: nil,
                    userInfo: ["event": eventName, "data": data ?? [:]]
                )
            }
        default:
            break
        }
    }

    private func handleVoiceMessage(_ body: [String: Any]) {
        guard let action = body["action"] as? String else { return }
        switch action {
        case "start":
            startVoiceRecognition()
        case "stop":
            stopVoiceRecognition()
        default:
            break
        }
    }

    private func handleHapticMessage(_ body: [String: Any]) {
        guard let type = body["type"] as? String else { return }
        switch type {
        case "light": hapticBridge.light()
        case "medium": hapticBridge.medium()
        case "success": hapticBridge.success()
        case "error": hapticBridge.error()
        default: break
        }
    }

    private func handleDeepLinkMessage(_ body: [String: Any]) {
        if let action = body["action"] as? String, action == "downloadFile" {
            onNavigationAction?(body)
            return
        }
        guard let urlString = body["url"] as? String else { return }
        onDeepLink?(urlString)
    }

    private func handleNavigationMessage(_ body: [String: Any]) {
        onNavigationAction?(body)
    }

    private func handleAnalyticsMessage(_ body: [String: Any]) {
        guard let name = body["name"] as? String else { return }
        let params = body["params"] as? [String: Any] ?? [:]
        onAnalyticsAction?(name, params)
    }
}

// MARK: - WKNavigationDelegate

extension SmartBarWebViewManager: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        markContentLoadSucceeded()
    }
    
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        markContentLoadFailed(for: webView)
        print("[SmartBarWebViewManager] WebView navigation failed: \(error.localizedDescription)")
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        markContentLoadFailed(for: webView)
        print("[SmartBarWebViewManager] WebView provisional navigation failed: \(error.localizedDescription)")
    }
}

// MARK: - JS Bridge Code

extension SmartBarWebViewManager {
    private static let bridgeJavaScript = """
    window.SmartBarBridge = {
        isNative: true,
        platform: 'ios',
        getSession: function() { return window.SmartBarSession || {}; },
        getSessionId: function() { return (window.SmartBarSession && window.SmartBarSession.sessionId) || ''; },
        getLoginId: function() { return (window.SmartBarSession && window.SmartBarSession.loginId) || ''; },
        getUserRole: function() { return (window.SmartBarSession && window.SmartBarSession.userRole) || ''; },
        getUserName: function() { return (window.SmartBarSession && window.SmartBarSession.userName) || ''; },
        refreshSession: function() { window.webkit.messageHandlers.navigation.postMessage({ action: 'getSession' }); },
        onSessionUpdate: null,
        startVoiceRecognition: function() { window.webkit.messageHandlers.voice.postMessage({ action: 'start' }); },
        stopVoiceRecognition: function() { window.webkit.messageHandlers.voice.postMessage({ action: 'stop' }); },
        onSpeechResult: null,
        onSpeechError: null,
        hapticLight: function() { window.webkit.messageHandlers.haptic.postMessage({ type: 'light' }); },
        hapticMedium: function() { window.webkit.messageHandlers.haptic.postMessage({ type: 'medium' }); },
        hapticSuccess: function() { window.webkit.messageHandlers.haptic.postMessage({ type: 'success' }); },
        hapticError: function() { window.webkit.messageHandlers.haptic.postMessage({ type: 'error' }); },
        openDeepLink: function(url) { window.webkit.messageHandlers.deeplink.postMessage({ url: url }); },
        downloadFile: function(url, fileName) { window.webkit.messageHandlers.deeplink.postMessage({ action: 'downloadFile', url: url, fileName: fileName || 'Report' }); },
        goBack: function() { window.webkit.messageHandlers.navigation.postMessage({ action: 'back' }); },
        navigateTo: function(screen, params) { window.webkit.messageHandlers.navigation.postMessage({ action: 'navigate', screen: screen, params: params || {} }); },
        logEvent: function(name, params) { window.webkit.messageHandlers.analytics.postMessage({ name: name, params: params || {} }); },
        setInitialValue: function(value) { window.dispatchEvent(new CustomEvent('SmartBarSetInitialValue', { detail: { value: value } })); },
        startCall: function() { window.webkit.messageHandlers.call.postMessage({ action: 'start' }); },
        endCall: function() { window.webkit.messageHandlers.call.postMessage({ action: 'end' }); },
        toggleMute: function() { window.webkit.messageHandlers.call.postMessage({ action: 'toggleMute' }); },
        toggleScreenShare: function() { window.webkit.messageHandlers.call.postMessage({ action: 'toggleScreenShare' }); },
        onCallStateChange: null,
        onMuteChange: null,
        onScreenShareChange: null,
        sendLivekitEvent: function(eventName, data) { window.webkit.messageHandlers.livekit.postMessage({ event: eventName, data: data }); },
        chatConversationId: '5c4c63ca-303b-4270-a519-8f5e65eb1a61',
        initCall: function() {
            var payload = { type: 'INITCALL', chatConversationId: '5c4c63ca-303b-4270-a519-8f5e65eb1a61' };
            window.postMessage(payload, '*');
            window.dispatchEvent(new CustomEvent('InitCallEvent', { detail: payload }));
        }
    };

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

    window.dispatchEvent(new CustomEvent('SmartBarBridgeReady'));

    // Dispatch INITCALL event immediately
    try {
        var initCallPayload = {
            "type": "INITCALL",
            "chatConversationId": "5c4c63ca-303b-4270-a519-8f5e65eb1a61"
        };
        window.postMessage(initCallPayload, '*');
        window.dispatchEvent(new CustomEvent('InitCallEvent', { detail: initCallPayload }));
    } catch(e) {}
    """
}

// MARK: - Helper Extensions

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
