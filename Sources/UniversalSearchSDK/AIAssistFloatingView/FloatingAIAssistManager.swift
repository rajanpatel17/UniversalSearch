//
//  FloatingAIAssistManager.swift
//  MintoakBase
//
//  Created by Rajan Patel on 02/12/25.
//

import UIKit
import SpotLightSDK

final class FloatingAIAssistManager {

    static let shared = FloatingAIAssistManager()

    private init() {
        // # When AI Call Integrate
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(callConnectionChanged(_:)),
            name: .liveKitCallConnectionChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenShareStateChanged(_:)),
            name: .liveKitScreenShareStateChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEndCall),
            name: .floatingEndCallTapped,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenShare),
            name: .floatingScreenShareTapped,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleChatTapped),
            name: .floatingChatTapped,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAIAssistTapped),
            name: .AIAssistTapped,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    public var floatingView: FloatingAIAssistView?
    private var isTogglingScreenShare = false
    private var coachmarkManager: SpotLightManager?
    private var durationTimer: Timer?
    private let voiceBridge = SmartBarVoiceBridge()

    func show() {
        guard let window = UIApplication.shared.keyWindow else { return }
        if floatingView != nil { return }

        let view = FloatingAIAssistView(frame: .zero)
        view.translatesAutoresizingMaskIntoConstraints = false
        floatingView = view
        window.addSubview(view)

        NSLayoutConstraint.activate([
            view.trailingAnchor.constraint(equalTo: window.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: window.safeAreaLayoutGuide.bottomAnchor, constant: -80),
            view.heightAnchor.constraint(equalToConstant: 44)
        ])

        // Sync call state — the view may have been recreated while a call is active
        // When start Live Kit call Integration then un comment following line
        Task { @MainActor in
            let mgr = LiveKitCallManager.shared
            if mgr.isCallConnected {
                view.updateCallActive(true)
                view.updateCallConnected(true)
                view.updateScreenShareUI(isSharing: mgr.isScreenShared)
                self.startDurationTimer()
            } else {
                // Start auto-collapse so the button shrinks to icon-only after 3s
                view.startAutoCollapseTimer()
            }
        }

        /// If above spotlight code is uncomment code then comment following line
        view.startAutoCollapseTimer()
    }

    func hide() {
        floatingView?.removeFromSuperview()
        floatingView = nil
    }

    func floatStartTimer() {
        floatingView?.startAutoCollapseTimer()
    }

    func updateCallState(isActive: Bool) {
        floatingView?.updateCallActive(isActive)
    }

    // MARK: - Spotlight

    @MainActor
    func showSpotlightIfNeeded() {
        guard UserDefaults.standard.SpotlightAIAssistViewed != true else { return }
        guard let targetView = floatingView else { return }
        guard let activityVC = topMostViewController() else { return }

        let target = CoachmarkTarget(
            targetView: targetView,
            title: CMText(
                text: "Ask Vyapar anything!",
                color: .black,
                bgColor: .clear,
                font: AppFonts.FONT_SEMIBOLD(size: 14)
            ),
            description: CMText(
                text: "Find answers, raise requests, or get instant help in one place.",
                color: UIColor.lightGrayTxtColor,
                bgColor: .clear,
                font: AppFonts.FONT_MEDIUM(size: 12)
            ),
            shape: .rect,
            paddingDp: 8,
            leftBarFillColor: UIColor.themeBlueColor,
            nextButtonMode: .text(CMText(text: "Got it", color: .white, bgColor: .themeBlueColor, font: AppFonts.FONT_MEDIUM(size: 12))),
            previousButtonMode: .image(tint: .themeBlueColor),
            showAnimation: false,
            needBorder: true,
            leftBarShow: true,
            borders: [
                .init(width: 2, color: .darkGray, priority: 0),
                .init(width: 1, color: .white, priority: 1)
            ],
            showBottomButtonStack: false
        )

        coachmarkManager = SpotLightManager(activity: activityVC, listener: self)
        coachmarkManager?.showCoachmarks(targetList: [target])
    }

    // MARK: - AI Assist tap handler

    @objc func handleAIAssistTapped() {
        print("AI Assist tapped!")

//        AnalyticsUtilites.triggerAnalyticsEvent(event: "us_icon_clicked", screenName: "bizview", identifier: "bizview", element: "universal_search", action1: "click", action2: "", myBundle: ["type": "Acknowledgement"])

        Task { @MainActor in
            // If a LiveKit call is active, navigate to the call screen or SmartBar
            if LiveKitCallManager.shared.isCallConnected {
                if let nav = self.topMostNavigationController() {
                    // Check if SmartBarWebViewController is already in stack
                    if let existingVC = nav.viewControllers.first(where: { $0 is SmartBarWebViewController }) {
                        nav.popToViewController(existingVC, animated: true)
                        return
                    }
                }
                
                // If we have a cached activeViewController, reuse it!
                if let cachedVC = SmartBarWebViewManager.shared.activeViewController {
                    self.safeShow(cachedVC)
                } else {
                    let vc = SmartBarWebViewController.instantiate(selectedValue: "")
                    self.safeShow(vc)
                }
            } else {
                // No active call — navigate to SmartBar with a fresh webView
                SmartBarWebViewManager.shared.clearCachedWebViewIfAllowed()
                let vc = SmartBarWebViewController.instantiate(selectedValue: "")
                self.safeShow(vc)
            }
        }
    }

    @MainActor
    private func safeShow(_ vc: UIViewController) {
        if let nav = self.topMostNavigationController() {
            nav.pushViewController(vc, animated: true)
        } else if let topVC = self.topMostViewController() {
            vc.modalPresentationStyle = .fullScreen
            topVC.present(vc, animated: true)
        }
    }

    @MainActor
    private func topMostViewController() -> UIViewController? {
        guard let window = UIApplication.shared.keyWindow else { return nil }
        var topController: UIViewController? = window.rootViewController
        while let presented = topController?.presentedViewController {
            topController = presented
        }
        return topController
    }

    @MainActor
    private func topMostNavigationController() -> UINavigationController? {
        let topVC = topMostViewController()
        if let nav = topVC as? UINavigationController {
            return nav
        }
        if let nav = topVC?.navigationController {
            return nav
        }
        return nil
    }

    @MainActor @objc private func callConnectionChanged(_ notification: Notification) {
        guard let isConnected = notification.userInfo?["isConnected"] as? Bool else { return }
        floatingView?.updateCallActive(isConnected)
        floatingView?.updateCallConnected(isConnected)
        
        if isConnected {
            startDurationTimer()
        } else {
            stopDurationTimer()
        }
    }

    @MainActor private func startDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let duration = LiveKitCallManager.shared.formattedDuration()
            self.floatingView?.updateCallDuration(duration)
        }
        // Run immediately
        let duration = LiveKitCallManager.shared.formattedDuration()
        floatingView?.updateCallDuration(duration)
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    @objc private func screenShareStateChanged(_ notification: Notification) {
        guard let isSharing = notification.userInfo?["isScreenShared"] as? Bool else { return }
        floatingView?.updateScreenShareUI(isSharing: isSharing)
    }

    // # When AI Call Integrate
    @MainActor @objc private func handleEndCall() {
        callEnd()
    }

    @MainActor
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
        topMostViewController()?.present(alert, animated: true)
    }

    func endCall() {
        Task {
            await LiveKitCallManager.shared.setScreenShare(false)
            await LiveKitCallManager.shared.disconnect()
        }
    }
    
    @objc private func handleScreenShare() {
        guard !isTogglingScreenShare else { return }
        isTogglingScreenShare = true
        Task {
            await LiveKitCallManager.shared.toggleScreenShare()
            isTogglingScreenShare = false
        }
    }

    @objc private func handleChatTapped() {
        Task { @MainActor in
            if LiveKitCallManager.shared.isCallConnected {
                if let nav = self.topMostNavigationController() {
                    if let existingVC = nav.viewControllers.first(where: { $0 is SmartBarWebViewController }) {
                        nav.popToViewController(existingVC, animated: true)
                        return
                    }
                }
                
                if let cachedVC = SmartBarWebViewManager.shared.activeViewController {
                    self.safeShow(cachedVC)
                } else {
                    let vc = SmartBarWebViewController.instantiate(selectedValue: "")
                    self.safeShow(vc)
                }
                return
            }
            
            if let nav = self.topMostNavigationController() {
                if let existingVC = nav.viewControllers.first(where: { $0 is SmartBarWebViewController }) {
                    nav.popToViewController(existingVC, animated: true)
                    return
                }
            }
            SmartBarWebViewManager.shared.clearCachedWebViewIfAllowed()
            let vc = SmartBarWebViewController.instantiate(selectedValue: "")
            self.safeShow(vc)
        }
    }
}

// MARK: - SpotLightListener

extension FloatingAIAssistManager: SpotLightListener {

    func onCoachmarkClosed(index: Int) {
        UserDefaults.standard.SpotlightAIAssistViewed = true
        floatingView?.startAutoCollapseTimer()
    }

    func onCoachmarkNextClicked(index: Int, isLastIndex: Bool) {
        if isLastIndex {
            UserDefaults.standard.SpotlightAIAssistViewed = true
        }
    }

    func onCoachmarkBackClicked(index: Int) {
        // Single-step coachmark — back is not applicable
    }
}
