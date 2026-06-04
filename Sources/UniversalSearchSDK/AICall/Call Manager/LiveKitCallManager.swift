//
//  LiveKitCallManager.swift
//  MintoakBase
//
//  Created by Rajan Patel on 23/12/25.
//  Copyright © 2025 Chaitanya Soni. All rights reserved.
//

import LiveKit
import AVFoundation
import UIKit

// MARK: - Notification Names (avoids raw-string typos)
extension NSNotification.Name {
    static let liveKitCallConnectionChanged = NSNotification.Name("liveKitCallConnectionChanged")
    static let liveKitScreenShareStateChanged = NSNotification.Name("liveKitScreenShareStateChanged")
    static let liveKitMuteStateChanged = NSNotification.Name("liveKitMuteStateChanged")
}

public enum LiveKitCallState: Sendable {
    case connected
    case reconnecting
    case disconnected
    case idle
}

@MainActor
final class LiveKitCallManager: NSObject {

    static let shared = LiveKitCallManager()

    weak var delegate: LiveKitCallStateDelegate?
    private(set) var room: Room

    private(set) var currentCallState: LiveKitCallState = .idle
    var wasInCall: Bool = false

    private(set) var callStartTime: Date?
    var chatConversationId: String?
    private(set) var callDuration: TimeInterval = 0
    private(set) var isMuted: Bool = false {
        didSet {
            NotificationCenter.default.post(
                name: .liveKitMuteStateChanged,
                object: nil,
                userInfo: ["isMuted": self.isMuted]
            )
            SmartBarWebViewManager.shared.sendLivekitEvent(eventName: self.isMuted ? "CALL_MUTE" : "CALL_UNMUTE")
        }
    }

    private(set) var isCallConnected: Bool = false {
        didSet {
            NotificationCenter.default.post(
                name: .liveKitCallConnectionChanged,
                object: nil,
                userInfo: ["isConnected": self.isCallConnected]
            )
        }
    }

    private(set) var isScreenShared: Bool = false {
        didSet {
            NotificationCenter.default.post(
                name: .liveKitScreenShareStateChanged,
                object: nil,
                userInfo: ["isScreenShared": self.isScreenShared]
            )
        }
    }

    private override init() {
        room = Room()
        super.init()
        room.add(delegate: self)
        setupAudioSession()
        observeAppLifecycle()
    }

    func connect(token: String) async throws {
        guard !isCallConnected else {
            #if DEBUG
            print("[LiveKitCallManager] connect() skipped — already connected")
            #endif
            return
        }

        try await room.connect(
            url: Constant.liveKitServerUrl,
            token: token
        )

        // Ensure audio session is configured for mic capture before enabling
        configureAudioSessionForMic()

        do {
            try await room.localParticipant.setMicrophone(enabled: true)
        } catch {
            #if DEBUG
            print("[LiveKitCallManager] Mic enable failed:", error)
            #endif
            // Mark as muted since mic couldn't be enabled
            isMuted = true
        }
    }

    func connectScreen(token: String) async throws {
        guard !isCallConnected else {
            #if DEBUG
            print("[LiveKitCallManager] connectScreen() skipped — already connected")
            #endif
            return
        }

        try await room.connect(
            url: Constant.liveKitServerUrl,
            token: token
        )

        // Ensure audio session is configured for mic capture before enabling
        configureAudioSessionForMic()

        do {
            try await room.localParticipant.setMicrophone(enabled: true)
        } catch {
            #if DEBUG
            print("[LiveKitCallManager] Mic enable failed:", error)
            #endif
            isMuted = true
        }
        do {
            try await room.localParticipant.setScreenShare(enabled: true)
            isScreenShared = true
        } catch {
            #if DEBUG
            print("[LiveKitCallManager] Screen share enable failed (non-fatal):", error)
            #endif
        }
    }

    func disconnect() async {
        stopCallTimer()
        // Reset mute/screenshare state so next call starts fresh
        isMuted = false
        isScreenShared = false
        await room.disconnect()
    }

    private func setupAudioSession() {
        configureAudioSessionForMic()
    }

    /// Ensures the audio session is set to .playAndRecord so microphone capture works.
    /// Safe to call multiple times — idempotent.
    private func configureAudioSessionForMic() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.allowBluetooth, .defaultToSpeaker]
            )
            try session.setActive(true)
        } catch {
            #if DEBUG
            print("[LiveKitCallManager] Audio session configuration failed:", error)
            #endif
        }
    }

    private func observeAppLifecycle() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    /// Tracks whether screen share was active before entering background
    private var wasScreenSharedBeforeBackground = false

    @objc private func appDidEnterBackground() {
        guard isCallConnected, isScreenShared else { return }
        wasScreenSharedBeforeBackground = true
        // Pause screen share in background
        Task { await applyScreenShareState(forceDisable: true) }
    }

    @objc private func appWillEnterForeground() {
        guard isCallConnected, wasScreenSharedBeforeBackground else { return }
        wasScreenSharedBeforeBackground = false
        // Resume screen share when returning to foreground
        Task { await applyScreenShareState() }
    }

    func startCallTimerIfNeeded() {
        if callStartTime == nil {
            callStartTime = Date()
        }
    }

    func stopCallTimer() {
        guard let start = callStartTime else { return }
        callDuration = Date().timeIntervalSince(start)
        callStartTime = nil
    }

    func formattedDuration() -> String {
        let currentDuration: TimeInterval
        if let start = callStartTime {
            currentDuration = Date().timeIntervalSince(start)
        } else {
            currentDuration = callDuration
        }
        
        let seconds = Int(currentDuration)
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    // MARK: - Audio Level

    func remoteAudioLevel() -> Float {
        room.remoteParticipants.values.first?.audioLevel ?? 0.0
    }

    // MARK: - Mute / Unmute
    func toggleMute() async {
        isMuted.toggle()
        await applyMicState()
    }

    func setMuted(_ muted: Bool) async {
        isMuted = muted
        await applyMicState()
    }

    private func applyMicState() async {
        guard room.connectionState == .connected else { return }

        // Ensure audio session is properly configured before mic operations
        configureAudioSessionForMic()

        do {
            try await room.localParticipant.setMicrophone(
                enabled: !isMuted
            )
        } catch {
            #if DEBUG
            print("[LiveKitCallManager] applyMicState failed (isMuted=\(isMuted)):", error)
            #endif
            // Revert state so UI stays in sync with LiveKit
            isMuted.toggle()
        }
    }

    // MARK: - Screen Share

    func toggleScreenShare() async {
        isScreenShared.toggle()
        await applyScreenShareState()
    }

    func setScreenShare(_ enabled: Bool) async {
        isScreenShared = enabled
        await applyScreenShareState()
    }

    private func applyScreenShareState(forceDisable: Bool = false) async {
        guard room.connectionState == .connected else { return }

        let desired = forceDisable ? false : isScreenShared
        do {
            try await room.localParticipant.setScreenShare(
                enabled: desired
            )
        } catch {
            #if DEBUG
            print("[LiveKitCallManager] setScreenShare(\(desired)) failed (non-fatal):", error)
            #endif
            // Don't revert state — the broadcast extension (LKSampleHandler) may be
            // handling screen capture independently. The LiveKit in-app capture
            // failing is expected on simulator or when using the broadcast approach.
        }
    }

}

extension LiveKitCallManager: RoomDelegate {

    nonisolated func room(
        _ room: Room,
        didUpdateConnectionState connectionState: ConnectionState,
        from oldConnectionState: ConnectionState
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch connectionState {

            case .connecting:
                self.delegate?.onCallConnecting()

            case .connected:
                self.currentCallState = .connected
                self.wasInCall = true
                await self.applyMicState()
                await self.applyScreenShareState()
                self.isCallConnected = true
                self.delegate?.onCallConnected()
                self.startCallTimerIfNeeded()
                SmartBarWebViewManager.shared.sendLivekitEvent(eventName: "CALL_CONNECTED", roomId: self.chatConversationId)

            case .reconnecting:
                self.currentCallState = .reconnecting
                self.delegate?.onCallReconnecting()
                SmartBarWebViewManager.shared.sendLivekitEvent(eventName: "CALL_RECONNECT")

            case .disconnecting:
                SmartBarWebViewManager.shared.sendLivekitEvent(eventName: "CALL_DISCONNECTED", roomId: self.chatConversationId)
                
            case .disconnected:
                if oldConnectionState == .reconnecting {
                    InstaQrAlertViewControllerViewController.showAlert(titleString: "Call ended due to a network issue. Please try again.", isWarning: false)
                }
                self.currentCallState = .disconnected
                self.stopCallTimer()
                self.isCallConnected = false
                self.delegate?.onCallDisconnected()
                SmartBarWebViewManager.shared.sendLivekitEvent(eventName: "CALL_DISCONNECTED", roomId: self.chatConversationId)

            default:
                break
            }
        }
    }

    nonisolated func room(
        _ room: Room,
        didStartReconnectWithMode mode: ReconnectMode
    ) {
        Task { @MainActor in
            #if DEBUG
            print("[LiveKitCallManager] didStartReconnectWithMode: \(mode)")
            #endif
            SmartBarWebViewManager.shared.sendLivekitEvent(eventName: "CALL_RECONNECT")
        }
    }
}
