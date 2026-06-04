//
//  AICallView.swift
//  HDFC Bank SmartHub Vyapar
//
//  Created by Rajan Patel on 16/12/25.
//

import UIKit
import LiveKit
import AVFoundation
import SDWebImage
import ReplayKit

protocol LiveKitCallStateDelegate: AnyObject {
    func onCallConnecting()
    func onCallConnected()
    func onCallDisconnected()
    func onCallReconnecting()
}

// SampleHandler is defined in the ScreenShareExtension target (LKSampleHandler subclass).
// Do NOT duplicate it here — the extension target handles screen capture forwarding.

/// Weak proxy to break CADisplayLink → AICallView retain cycle.
private final class AudioPollProxy {
    weak var target: AICallView?
    init(_ target: AICallView) { self.target = target }
    @objc func onDisplayLink(_ link: CADisplayLink) {
        guard let target else { link.invalidate(); return }
        target.handleAudioPoll()
    }
}

class AICallView: UIViewController, XIBed {

    // MARK: - Factory

    static func instantiate(selectedValue: String) -> AICallView {
        let vc = AICallView.instantiate()
        vc.userQuery = selectedValue
        return vc
    }

    // MARK: - Outlets

    @IBOutlet weak var navContainer: UIView!
    @IBOutlet weak var lblNavTitle: UILabel!
    @IBOutlet weak var btnMute: UIButton!
    @IBOutlet weak var btnEndCall: UIButton!
    @IBOutlet weak var imgLoader: UIImageView! {
        didSet {
            imgLoader.contentMode = .scaleAspectFit
        }
    }
    @IBOutlet weak var btnScreenShare: UIButton!

    // MARK: - Properties

    private let viewModel = AICallViewModel()
    var userQuery: String = ""
    private var currentRoomName: String?

    private var screenShareTrack: LocalVideoTrack?
    private var broadcastPicker: RPSystemBroadcastPickerView?
    /// When true, skips auto-starting a new call (used when navigating to an already-active call)
    var isRejoiningActiveCall: Bool = false

    // MARK: - Callback to send call info back
    var onCallEnded: ((_ durationText: String, _ endTimeText: String) -> Void)?

    // MARK: - Gradient Blob Background

    private let brandBlue = UIColor(red: 0.10, green: 0.47, blue: 0.90, alpha: 1.0)

    private var blobBlueLayer: CAGradientLayer?
    private var blobPurpleLayer: CAGradientLayer?
    private var blobPrimaryLayer: CAGradientLayer?

    private lazy var particlesView: BackgroundParticlesView = {
        let v = BackgroundParticlesView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.alpha = 0.6
        return v
    }()

    // MARK: - Waveform (replaces GlassSphereView)

    private lazy var waveformView: AudioWaveformView = {
        let wv = AudioWaveformView()
        wv.translatesAutoresizingMaskIntoConstraints = false
        wv.alpha = 0
        wv.isHidden = true
        return wv
    }()

    // MARK: - Status Labels (above waveform)

    private lazy var connectedLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "CONNECTED"
        label.font = AppFonts.FONT_BOLD(size: 11)
        label.textColor = brandBlue
        label.textAlignment = .center
        label.alpha = 0

        // Letter spacing
        let attributedString = NSMutableAttributedString(string: "CONNECTED")
        attributedString.addAttribute(.kern, value: 3.0, range: NSRange(location: 0, length: attributedString.length))
        attributedString.addAttribute(.font, value: AppFonts.FONT_BOLD(size: 11) as Any, range: NSRange(location: 0, length: attributedString.length))
        attributedString.addAttribute(.foregroundColor, value: brandBlue, range: NSRange(location: 0, length: attributedString.length))
        label.attributedText = attributedString

        return label
    }()

    private lazy var assistantLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "AI ASSISTANT"
        label.font = AppFonts.FONT_BOLD(size: 26)
        label.textColor = .textColorDark
        label.textAlignment = .center
        label.alpha = 0
        return label
    }()

    // MARK: - Glass Timer Panel

    private lazy var timerPanelBlur: UIVisualEffectView = {
        let blur = UIBlurEffect(style: .systemThinMaterial)
        let v = UIVisualEffectView(effect: blur)
        v.translatesAutoresizingMaskIntoConstraints = false
        v.layer.cornerRadius = 26
        v.clipsToBounds = true
        v.layer.borderWidth = 1
        v.layer.borderColor = UIColor.white.withAlphaComponent(0.3).cgColor
        v.alpha = 0
        return v
    }()

    private lazy var timerLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "00 : 00"
        label.font = UIFont.monospacedDigitSystemFont(ofSize: 22, weight: .medium)
        label.textColor = .textColorDark
        label.textAlignment = .center
        return label
    }()

    // MARK: - Glass Controls Panel

    private lazy var controlsPanelBlur: UIVisualEffectView = {
        let blur = UIBlurEffect(style: .systemThinMaterial)
        let v = UIVisualEffectView(effect: blur)
        v.translatesAutoresizingMaskIntoConstraints = false
        v.layer.cornerRadius = 28
        v.clipsToBounds = true
        v.layer.borderWidth = 1
        v.layer.borderColor = UIColor.white.withAlphaComponent(0.2).cgColor
        return v
    }()

    // MARK: - Status Label (for connecting/reconnecting text)

    private lazy var statusLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = AppFonts.FONT_MEDIUM(size: 15)
        label.textColor = .secondaryFontColor
        label.textAlignment = .center
        label.alpha = 0
        return label
    }()

    // MARK: - Animation & Timer Properties

    private var audioDisplayLink: CADisplayLink?
    private var audioPollProxy: AudioPollProxy?
    private var statusTimer: Timer?
    private var ellipsisTimer: Timer?
    private var ellipsisDotCount = 0
    private var pulseLayer: CAShapeLayer?
    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
    private let notificationFeedback = UINotificationFeedbackGenerator()

    deinit {
        audioDisplayLink?.invalidate()
        statusTimer?.invalidate()
        ellipsisTimer?.invalidate()
        pulseLayer?.removeFromSuperlayer()
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        LiveKitCallManager.shared.delegate = self
        self.loadSearchHistoryFromUserDefaults()
        self.setupViewModel()
        self.setupUI()
        self.setUpLanguage()
        setupScreenSharePicker()
        setupGlassSphereAndStatus()
        setupGlassTimerPanel()
        setupGlassControlsPanel()
        if isRejoiningActiveCall && LiveKitCallManager.shared.isCallConnected {
            showConnectedState()
            btnMute.isEnabled = true
        } else {
            self.btnCallClicked()
        }
        FloatingAIAssistManager.shared.hide()
        animateControlsEntry()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if LiveKitCallManager.shared.isCallConnected {
            showConnectedState()
        }

        updateMuteButtonUI(
            isMuted: LiveKitCallManager.shared.isMuted
        )

        updateShareButtonUI(
            isScreenShared: LiveKitCallManager.shared.isScreenShared
        )

        runAfterTime(1.0) {
            FloatingAIAssistManager.shared.hide()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let pulse = pulseLayer, let loaderParent = imgLoader.superview {
            pulse.position = loaderParent.convert(imgLoader.center, from: imgLoader.superview)
        }
    }

    // MARK: - UI Setup

    func setupUI() {
        // Light background with gradient blobs
        view.backgroundColor = UIColor(red: 0.965, green: 0.969, blue: 0.973, alpha: 1.0) // #F6F7F8

        navContainer.backgroundColor = .clear
        navContainer.setNavigationBarShadow()
        lblNavTitle.configureLabel(color: .textColorDark, font: AppFonts.FONT_SEMIBOLD(size: 16))
        
        let bundle = Bundle(for: AICallView.self)
        let unmutedImage = UIImage(named: "icn_unmute", in: bundle, compatibleWith: nil)?.withRenderingMode(.alwaysOriginal)
        self.btnMute.setImage(unmutedImage, for: .normal)
        self.btnScreenShare.setImage(UIImage(named: "ic_screenshare", in: bundle, compatibleWith: nil), for: .normal)

        setupGradientBlobs()
        setupControls()
    }

    private func setupGradientBlobs() {
        let w = UIScreen.main.bounds.width
        let h = UIScreen.main.bounds.height

        // Background Particles
        view.insertSubview(particlesView, at: 0)
        NSLayoutConstraint.activate([
            particlesView.topAnchor.constraint(equalTo: view.topAnchor),
            particlesView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            particlesView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            particlesView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        // Blue blob — top-left, 380pt radial (matches SwiftUI reference)
        let blue = CAGradientLayer()
        blue.type = .radial
        blue.colors = [UIColor.blue.withAlphaComponent(0.12).cgColor, UIColor.clear.cgColor]
        blue.locations = [0, 1]
        blue.startPoint = CGPoint(x: 0.5, y: 0.5)
        blue.endPoint = CGPoint(x: 1.0, y: 1.0)
        blue.frame = CGRect(x: -w * 0.35, y: -h * 0.15, width: 380, height: 380)
        view.layer.insertSublayer(blue, at: 0)
        blobBlueLayer = blue

        // Purple blob — bottom-right, 320pt radial
        let purple = CAGradientLayer()
        purple.type = .radial
        purple.colors = [UIColor.purple.withAlphaComponent(0.12).cgColor, UIColor.clear.cgColor]
        purple.locations = [0, 1]
        purple.startPoint = CGPoint(x: 0.5, y: 0.5)
        purple.endPoint = CGPoint(x: 1.0, y: 1.0)
        purple.frame = CGRect(x: w * 0.3, y: h * 0.58, width: 320, height: 320)
        view.layer.insertSublayer(purple, at: 0)
        blobPurpleLayer = purple

        // Primary blue blob — center-left, 260pt radial
        let primary = CAGradientLayer()
        primary.type = .radial
        primary.colors = [brandBlue.withAlphaComponent(0.10).cgColor, UIColor.clear.cgColor]
        primary.locations = [0, 1]
        primary.startPoint = CGPoint(x: 0.5, y: 0.5)
        primary.endPoint = CGPoint(x: 1.0, y: 1.0)
        primary.frame = CGRect(x: -w * 0.15, y: h * 0.35, width: 260, height: 260)
        view.layer.insertSublayer(primary, at: 0)
        blobPrimaryLayer = primary

        // Gentle scale pulse animation on all blobs
        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 1.0
        pulse.toValue = 1.15
        pulse.duration = 3.0
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        for layer in [blue, purple, primary] {
            let copy = pulse.copy() as! CABasicAnimation
            copy.beginTime = CACurrentMediaTime() + Double.random(in: 0...1.5)
            layer.add(copy, forKey: "blobPulse")
        }
    }

    /// Rebuild controls layout: Mute (left) | End Call (center pill) | Screen Share (right)
    private func setupControls() {
        guard let controlsContainer = btnEndCall.superview else { return }

        let muteBtn = btnMute!
        let endBtn = btnEndCall!
        let shareBtn = btnScreenShare!

        // Remove buttons from old XIB stack view
        if let stackView = muteBtn.superview as? UIStackView {
            muteBtn.removeFromSuperview()
            shareBtn.removeFromSuperview()
            stackView.removeFromSuperview()
        }

        // Deactivate ALL old XIB constraints from the controls container
        let oldContainerConstraints = controlsContainer.constraints.filter {
            $0.firstItem === endBtn || $0.secondItem === endBtn ||
            $0.firstItem === muteBtn || $0.secondItem === muteBtn ||
            $0.firstItem === shareBtn || $0.secondItem === shareBtn
        }
        NSLayoutConstraint.deactivate(oldContainerConstraints)

        // Deactivate old size constraints on the buttons themselves
        for btn in [muteBtn, endBtn, shareBtn] {
            NSLayoutConstraint.deactivate(btn.constraints.filter {
                $0.firstAttribute == .height || $0.firstAttribute == .width
            })
        }

        // Override XIB height (84pt) to fit 60pt button + 16pt top/bottom padding
        for constraint in controlsContainer.constraints {
            if constraint.firstAttribute == .height && constraint.firstItem === controlsContainer {
                constraint.constant = 92
            }
        }

        controlsContainer.addSubview(muteBtn)
        controlsContainer.addSubview(endBtn)
        controlsContainer.addSubview(shareBtn)

        self.btnMute = muteBtn
        self.btnEndCall = endBtn
        self.btnScreenShare = shareBtn

        // Style mute button — starts unmuted (mic live) with blue background + white icon
        muteBtn.backgroundColor = UIColor.activeButtonColor
        muteBtn.tintColor = .white
        muteBtn.layer.cornerRadius = 16
        muteBtn.clipsToBounds = true

        // Style share button — same as mute
        shareBtn.backgroundColor = UIColor(red: 0.90, green: 0.91, blue: 0.93, alpha: 1.0)
        shareBtn.layer.cornerRadius = 16
        shareBtn.clipsToBounds = true
        shareBtn.isHidden = true // Temporarily hidden

        // Style end call button — red pill with shadow
        endBtn.configureButton(
            title: "End Call", titleColor: .white,
            font: AppFonts.FONT_SEMIBOLD(size: 16),
            bgColor: UIColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1.0) // #FF3B30
        )
        endBtn.setCornerRadius(radius: 16)
        endBtn.layer.shadowColor = UIColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1.0).cgColor
        endBtn.layer.shadowOpacity = 0.4
        endBtn.layer.shadowRadius = 12
        endBtn.layer.shadowOffset = CGSize(width: 0, height: 4)
        endBtn.layer.masksToBounds = false
        endBtn.imageEdgeInsets = .zero
        endBtn.titleEdgeInsets = .zero

        if let icon = UIImage(named: "ic_endcall")?.withRenderingMode(.alwaysTemplate) {
            endBtn.setImage(icon, for: .normal)
        }
        endBtn.tintColor = .white
        let spacing: CGFloat = 10
        endBtn.imageEdgeInsets = UIEdgeInsets(top: 0, left: -spacing / 2, bottom: 0, right: spacing / 2)
        endBtn.titleEdgeInsets = UIEdgeInsets(top: 0, left: spacing / 2, bottom: 0, right: -spacing / 2)

        // Constraints for Mute and End Call centered as a group
        let buttonsSpacing: CGFloat = 20
        NSLayoutConstraint.activate([
            endBtn.centerXAnchor.constraint(equalTo: controlsContainer.centerXAnchor, constant: (56 + buttonsSpacing) / 2),
            endBtn.centerYAnchor.constraint(equalTo: controlsContainer.centerYAnchor),
            endBtn.heightAnchor.constraint(equalToConstant: 60),
            endBtn.widthAnchor.constraint(equalToConstant: 170),

            muteBtn.trailingAnchor.constraint(equalTo: endBtn.leadingAnchor, constant: -buttonsSpacing),
            muteBtn.centerYAnchor.constraint(equalTo: controlsContainer.centerYAnchor),
            muteBtn.widthAnchor.constraint(equalToConstant: 56),
            muteBtn.heightAnchor.constraint(equalToConstant: 56),
        ])
    }

    fileprivate func setUpLanguage() {
        lblNavTitle.text = "AI Call"
    }

    private func setupScreenSharePicker() {
        let picker = RPSystemBroadcastPickerView(frame: .zero)
        picker.preferredExtension = "com.mintoak.hdfc.ScreenShareExtension"
        picker.showsMicrophoneButton = false
        picker.isHidden = true

        view.addSubview(picker)
        self.broadcastPicker = picker
    }

    private func setupGlassSphereAndStatus() {
        guard let loaderParent = imgLoader.superview else { return }

        loaderParent.addSubview(connectedLabel)
        loaderParent.addSubview(assistantLabel)
        loaderParent.addSubview(waveformView)
        loaderParent.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            // Waveform centered
            waveformView.centerXAnchor.constraint(equalTo: loaderParent.centerXAnchor),
            waveformView.centerYAnchor.constraint(equalTo: loaderParent.centerYAnchor),
            waveformView.widthAnchor.constraint(equalToConstant: 320),
            waveformView.heightAnchor.constraint(equalToConstant: 320),

            // Connected label above assistant label
            connectedLabel.centerXAnchor.constraint(equalTo: loaderParent.centerXAnchor),
            connectedLabel.bottomAnchor.constraint(equalTo: assistantLabel.topAnchor, constant: -8),

            // Assistant label above the waveform
            assistantLabel.centerXAnchor.constraint(equalTo: loaderParent.centerXAnchor),
            assistantLabel.bottomAnchor.constraint(equalTo: waveformView.topAnchor, constant: -40),

            // Status label (connecting text) below waveform
            statusLabel.centerXAnchor.constraint(equalTo: loaderParent.centerXAnchor),
            statusLabel.topAnchor.constraint(equalTo: waveformView.bottomAnchor, constant: -16),
        ])
    }

    private func setupGlassTimerPanel() {
        guard let loaderParent = imgLoader.superview else { return }

        loaderParent.addSubview(timerPanelBlur)
        timerPanelBlur.contentView.addSubview(timerLabel)

        NSLayoutConstraint.activate([
            timerPanelBlur.centerXAnchor.constraint(equalTo: loaderParent.centerXAnchor),
            timerPanelBlur.topAnchor.constraint(equalTo: waveformView.bottomAnchor, constant: 40),
            timerPanelBlur.heightAnchor.constraint(equalToConstant: 52),
            timerPanelBlur.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),

            timerLabel.leadingAnchor.constraint(equalTo: timerPanelBlur.contentView.leadingAnchor, constant: 24),
            timerLabel.trailingAnchor.constraint(equalTo: timerPanelBlur.contentView.trailingAnchor, constant: -24),
            timerLabel.centerYAnchor.constraint(equalTo: timerPanelBlur.contentView.centerYAnchor),
        ])
    }

    private func setupGlassControlsPanel() {
        guard let controlsContainer = btnEndCall.superview else { return }

        // Insert glass panel behind the buttons with horizontal insets
        controlsContainer.insertSubview(controlsPanelBlur, at: 0)
        controlsPanelBlur.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            controlsPanelBlur.leadingAnchor.constraint(equalTo: controlsContainer.leadingAnchor, constant: 24),
            controlsPanelBlur.trailingAnchor.constraint(equalTo: controlsContainer.trailingAnchor, constant: -24),
            controlsPanelBlur.topAnchor.constraint(equalTo: controlsContainer.topAnchor),
            controlsPanelBlur.bottomAnchor.constraint(equalTo: controlsContainer.bottomAnchor),
        ])

        // Shadow on the container (blur view has clipsToBounds=true)
        controlsContainer.layer.shadowColor = UIColor.black.cgColor
        controlsContainer.layer.shadowOpacity = 0.06
        controlsContainer.layer.shadowRadius = 10
        controlsContainer.layer.shadowOffset = CGSize(width: 0, height: -2)
        controlsContainer.layer.masksToBounds = false
    }

    private func animateControlsEntry() {
        guard let controlsContainer = btnEndCall.superview else { return }
        controlsContainer.transform = CGAffineTransform(translationX: 0, y: 60)
        controlsContainer.alpha = 0
        UIView.animate(withDuration: 0.5, delay: 0.3, usingSpringWithDamping: 0.75,
                       initialSpringVelocity: 0.6, options: [.curveEaseOut]) {
            controlsContainer.transform = .identity
            controlsContainer.alpha = 1
        }
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

    func btnCallClicked() {
        showConnectingState()

        // Disable LiveKit's automatic audio session management so we control it
        AudioManager.shared.audioSession.isAutomaticConfigurationEnabled = false

        // Configure audio session for voice call AFTER disabling auto-config,
        // ensuring LiveKit doesn't override it back to .playback
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
            print("[AICallView] Audio session setup failed:", error)
            #endif
        }

        session.requestRecordPermission { [weak self] granted in
            guard let self else { return }
            if granted {
                DispatchQueue.main.async {
                    self.viewModel.getToken(name: UniversalSearchManager.shared.sessionData?.userName ?? "")
                }
            } else {
                DispatchQueue.main.async {
                    self.stopAllAnimations()
                    self.showSettingsAlert(message: "Microphone permission is required for AI Call. Please enable it in Settings.")
                }
            }
        }
    }

    private func showSettingsAlert(message: String) {
        let alert = UIAlertController(
            title: "Permission Required",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Settings", style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })
        present(alert, animated: true)
    }

    private func formattedEndTime() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: Date())
    }

    // MARK: - State Transitions

    private func showConnectingState() {
        // Hide waveform during connecting
        waveformView.isHidden = true
        waveformView.alpha = 0
        waveformView.stopAnimation()
        stopAudioPolling()

        // Hide timer panel
        timerPanelBlur.alpha = 0
        connectedLabel.alpha = 0

        // Show loader GIF
        UIView.transition(with: imgLoader, duration: 0.25, options: .transitionCrossDissolve) {
            guard let url = Bundle.main.url(forResource: "ic_connecting", withExtension: "gif") else { return }
            self.imgLoader.sd_setImage(with: url)
        }
        imgLoader.isHidden = false
        imgLoader.alpha = 1

        UIView.animate(withDuration: 0.3) { self.assistantLabel.alpha = 1 }

        startPulseAnimation()
        showStatusText("Connecting", animated: true)
        startEllipsisTimer()
    }

    private func showConnectedState() {
        stopPulseAnimation()
        stopEllipsisTimer()

        // Hide loader
        UIView.animate(withDuration: 0.3) {
            self.imgLoader.alpha = 0
        } completion: { _ in
            self.imgLoader.isHidden = true
            self.imgLoader.sd_cancelCurrentImageLoad()
            self.imgLoader.image = nil
        }

        // Hide connecting status text
        UIView.animate(withDuration: 0.2) { self.statusLabel.alpha = 0 }

        // Show "CONNECTED" + "AI ASSISTANT" labels
        UIView.animate(withDuration: 0.4, delay: 0.1) {
            self.connectedLabel.alpha = 1
            self.assistantLabel.alpha = 1
        }

        // Show waveform with spring animation
        waveformView.isHidden = false
        waveformView.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
        UIView.animate(withDuration: 0.6, delay: 0.15, usingSpringWithDamping: 0.75,
                       initialSpringVelocity: 0.6, options: []) {
            self.waveformView.alpha = 1
            self.waveformView.transform = .identity
        }
        waveformView.startIdleAnimation()
        startAudioPolling()

        // Show timer panel with slide-up
        timerPanelBlur.transform = CGAffineTransform(translationX: 0, y: 20)
        UIView.animate(withDuration: 0.5, delay: 0.3, usingSpringWithDamping: 0.75,
                       initialSpringVelocity: 0.6) {
            self.timerPanelBlur.alpha = 1
            self.timerPanelBlur.transform = .identity
        }
        startCallTimerDisplay()

        // Timer panel subtle pulse
        startTimerPulse()

        notificationFeedback.notificationOccurred(.success)
    }

    private func showReconnectingState() {
        stopAudioPolling()
        stopCallTimerDisplay()
        stopTimerPulse()
        waveformView.stopAnimation()

        // Hide waveform
        UIView.animate(withDuration: 0.2) {
            self.waveformView.alpha = 0
            self.timerPanelBlur.alpha = 0
            self.connectedLabel.alpha = 0
        } completion: { _ in
            self.waveformView.isHidden = true
        }

        // Show loader
        imgLoader.isHidden = false
        UIView.transition(with: imgLoader, duration: 0.25, options: .transitionCrossDissolve) {
            guard let url = Bundle.main.url(forResource: "ic_connecting", withExtension: "gif") else { return }
            self.imgLoader.sd_setImage(with: url)
        }
        UIView.animate(withDuration: 0.2) { self.imgLoader.alpha = 1 }
        UIView.animate(withDuration: 0.3) { self.assistantLabel.alpha = 1 }

        startPulseAnimation()
        showStatusText("Reconnecting", animated: true)
        startEllipsisTimer()
    }

    private func stopAllAnimations() {
        stopPulseAnimation()
        stopEllipsisTimer()
        stopAudioPolling()
        stopCallTimerDisplay()
        stopTimerPulse()
        waveformView.stopAnimation()
        imgLoader.sd_cancelCurrentImageLoad()
        imgLoader.image = nil

        UIView.animate(withDuration: 0.2) {
            self.statusLabel.alpha = 0
            self.waveformView.alpha = 0
            self.assistantLabel.alpha = 0
            self.connectedLabel.alpha = 0
            self.timerPanelBlur.alpha = 0
        }
    }

    // MARK: - Pulse Ring Animation

    private func startPulseAnimation() {
        stopPulseAnimation()
        guard let loaderParent = imgLoader.superview else { return }

        let ringRadius: CGFloat = 55
        let path = UIBezierPath(arcCenter: .zero, radius: ringRadius,
                                startAngle: 0, endAngle: .pi * 2, clockwise: true)

        let layer = CAShapeLayer()
        layer.path = path.cgPath
        layer.fillColor = UIColor.clear.cgColor
        layer.strokeColor = brandBlue.withAlphaComponent(0.3).cgColor
        layer.lineWidth = 3
        layer.position = loaderParent.convert(imgLoader.center, from: imgLoader.superview)
        loaderParent.layer.insertSublayer(layer, below: imgLoader.layer)

        let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
        scaleAnim.fromValue = 1.0
        scaleAnim.toValue = 1.6

        let opacityAnim = CABasicAnimation(keyPath: "opacity")
        opacityAnim.fromValue = 0.6
        opacityAnim.toValue = 0.0

        let group = CAAnimationGroup()
        group.animations = [scaleAnim, opacityAnim]
        group.duration = 1.4
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(group, forKey: "pulse")
        pulseLayer = layer
    }

    private func stopPulseAnimation() {
        pulseLayer?.removeAllAnimations()
        pulseLayer?.removeFromSuperlayer()
        pulseLayer = nil
    }

    // MARK: - Timer Panel Pulse

    private func startTimerPulse() {
        UIView.animate(withDuration: 2.0, delay: 0,
                       options: [.autoreverse, .repeat, .curveEaseInOut]) {
            self.timerPanelBlur.transform = CGAffineTransform(scaleX: 1.02, y: 1.02)
        }
    }

    private func stopTimerPulse() {
        timerPanelBlur.layer.removeAllAnimations()
        timerPanelBlur.transform = .identity
    }

    // MARK: - Status Label & Timers

    private func showStatusText(_ text: String, animated: Bool) {
        statusLabel.text = text
        if animated {
            UIView.animate(withDuration: 0.25) { self.statusLabel.alpha = 1 }
        } else {
            statusLabel.alpha = 1
        }
    }

    private func startEllipsisTimer() {
        stopEllipsisTimer()
        ellipsisDotCount = 0
        let baseText = statusLabel.text?.replacingOccurrences(of: ".", with: "") ?? "Connecting"
        ellipsisTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.ellipsisDotCount = (self.ellipsisDotCount + 1) % 4
            let dots = String(repeating: ".", count: self.ellipsisDotCount)
            self.statusLabel.text = "\(baseText)\(dots)"
        }
    }

    private func stopEllipsisTimer() {
        ellipsisTimer?.invalidate()
        ellipsisTimer = nil
    }

    private func startCallTimerDisplay() {
        stopEllipsisTimer()
        updateTimerText()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateTimerText()
        }
    }

    private func stopCallTimerDisplay() {
        statusTimer?.invalidate()
        statusTimer = nil
    }

    private func updateTimerText() {
        guard let startTime = LiveKitCallManager.shared.callStartTime else {
            timerLabel.text = "00 : 00"
            return
        }
        let elapsed = Int(Date().timeIntervalSince(startTime))
        let minutes = (elapsed % 3600) / 60
        let seconds = elapsed % 60
        timerLabel.text = String(format: "%02d : %02d", minutes, seconds)
    }

    // MARK: - Audio Level Polling (via weak proxy to avoid retain cycle)

    private func startAudioPolling() {
        guard audioDisplayLink == nil else { return }
        let proxy = AudioPollProxy(self)
        audioPollProxy = proxy
        let link = CADisplayLink(target: proxy, selector: #selector(AudioPollProxy.onDisplayLink(_:)))
        if #available(iOS 15.0, *) {
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        }
        link.add(to: .current, forMode: .common)
        audioDisplayLink = link
    }

    private func stopAudioPolling() {
        audioDisplayLink?.invalidate()
        audioDisplayLink = nil
        audioPollProxy = nil
    }

    /// Called by AudioPollProxy — must be fileprivate for proxy access.
    fileprivate func handleAudioPoll() {
        let level = LiveKitCallManager.shared.remoteAudioLevel()
        waveformView.updateAudioLevel(level)
        particlesView.updateAudioLevel(level)
        
        // Background blob reaction logic
        let l = CGFloat(level)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        // Blob opacity: subtly brighter when speaking
        let opacityMultiplier = Float(1.0 + l * 0.8)
        blobBlueLayer?.opacity = opacityMultiplier
        blobPurpleLayer?.opacity = opacityMultiplier
        blobPrimaryLayer?.opacity = opacityMultiplier
        
        // Blob animation speed: faster pulse when speaking
        let blobSpeed = Float(1.0 + l * 2.0)
        for blob in [blobBlueLayer, blobPurpleLayer, blobPrimaryLayer] {
            guard let blob = blob else { continue }
            blob.timeOffset = blob.convertTime(CACurrentMediaTime(), from: nil)
            blob.beginTime = CACurrentMediaTime()
            blob.speed = blobSpeed
        }
        
        CATransaction.commit()
    }

    // MARK: - Button Actions
    @IBAction func backButtonAction(_ sender: UIButton) {
        if let nav = navigationController {
            nav.popToRootViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }

    @IBAction func btnMuteUnmuteClicked(_ sender: Any) {
        impactFeedback.impactOccurred()
        btnMute.isEnabled = false
        Task { [weak self] in
            await LiveKitCallManager.shared.toggleMute()

            await MainActor.run {
                self?.updateMuteButtonUI(
                    isMuted: LiveKitCallManager.shared.isMuted
                )
                self?.btnMute.isEnabled = true
            }
        }
    }

    @IBAction func btnScreenShareClicked(_ sender: Any) {

        if LiveKitCallManager.shared.isScreenShared {
            showStopScreenShareAlert()
            return
        }

        impactFeedback.impactOccurred()

        // Show system broadcast picker — user must confirm to start capture.
        // The ScreenShareExtension (LKSampleHandler) handles publishing frames.
        requestScreenSharePermission()

        // Update state after triggering the picker
        Task { [weak self] in
            await LiveKitCallManager.shared.setScreenShare(true)

            await MainActor.run {
                self?.updateShareButtonUI(
                    isScreenShared: LiveKitCallManager.shared.isScreenShared
                )
            }
        }
    }

    private func showStopScreenShareAlert() {
        let alert = UIAlertController(
            title: "Stop Screen Sharing?",
            message: "Are you sure you want to stop screen sharing?",
            preferredStyle: .alert
        )

        alert.addAction(
            UIAlertAction(title: "Cancel", style: .cancel)
        )

        alert.addAction(
            UIAlertAction(title: "Yes", style: .destructive) { [weak self] _ in
                // Trigger the broadcast picker to stop the broadcast
                self?.requestScreenSharePermission()

                Task { [weak self] in
                    await LiveKitCallManager.shared.setScreenShare(false)

                    await MainActor.run {
                        self?.updateShareButtonUI(
                            isScreenShared: LiveKitCallManager.shared.isScreenShared
                        )
                    }
                }
            }
        )

        present(alert, animated: true)
    }

    private func requestScreenSharePermission() {
        guard let picker = broadcastPicker else { return }

        for subview in picker.subviews {
            if let button = subview as? UIButton {
                button.sendActions(for: .touchUpInside)
                break
            }
        }
    }

    private func updateMuteButtonUI(isMuted: Bool) {
        let imageName = isMuted ? "ic_mute" : "icn_unmute"
        animateButtonImageChange(btnMute, imageName: imageName)

        UIView.animate(withDuration: 0.25) {
            if isMuted {
                // Muted: gray background, dark icon
                self.btnMute.backgroundColor = UIColor(red: 0.90, green: 0.91, blue: 0.93, alpha: 1.0)
                self.btnMute.tintColor = UIColor(red: 0.30, green: 0.31, blue: 0.33, alpha: 1.0)
            } else {
                // Unmuted (mic live): blue background, white icon
                self.btnMute.backgroundColor = UIColor.activeButtonColor
                self.btnMute.tintColor = .white
            }
        }
    }

    private func updateShareButtonUI(isScreenShared: Bool) {
        let imageName = isScreenShared ? "ic_stopscreenshare" : "ic_screenshare"
        animateButtonImageChange(btnScreenShare, imageName: imageName)
    }

    private func animateButtonImageChange(_ button: UIButton, imageName: String) {
        UIView.animate(withDuration: 0.1, animations: {
            button.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        }) { _ in
            let image = UIImage(named: imageName, in: #bundle, compatibleWith: nil)?.withRenderingMode(.alwaysOriginal)
            button.setImage(image, for: .normal)
            UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.6,
                           initialSpringVelocity: 0.5, options: []) {
                button.transform = .identity
            }
        }
    }


    @IBAction func btnEndCallClicked(_ sender: Any) {
        impactFeedback.impactOccurred()
        let alert = UIAlertController(
            title: "End Call?",
            message: "Are you sure you want to end the call?",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "End", style: .destructive) { [weak self] _ in
            self?.endCall()
        })
        present(alert, animated: true)
    }

    func endCall() {
        UIView.animate(withDuration: 0.2) {
            self.btnEndCall.alpha = 0.5
            self.btnMute.alpha = 0.5
            self.btnScreenShare.alpha = 0.5
        }
        btnEndCall.isEnabled = false
        btnMute.isEnabled = false
        btnScreenShare.isEnabled = false

        Task {
            await LiveKitCallManager.shared.setScreenShare(false)
            await LiveKitCallManager.shared.disconnect()
        }
    }

    private func closeCallScreen() {
        if let nav = navigationController {
            nav.popToRootViewController(animated: true)
        } else {
            dismiss(animated: true)
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

    func callConnectRoomWithScreenSharing(token: String) {
        Task {
            do {
                try await LiveKitCallManager.shared.connectScreen(token: token)
            } catch {
                await MainActor.run { showAlert(message: "Unable to connect call") }
            }
        }
    }

}

//MARK: Extension: Connect to Live Kit Method
extension AICallView {

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
            self.callConnectRoomWithScreenSharing(token: token)
        } else {
            self.callConnectRoom(token: token)
        }
    }

}

//MARK: Extension: Alert show message
extension AICallView {

    func showAlert(title: String = "Error", message: String) {
        let alert = UIAlertController(title: title,
                                      message: message,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

//MARK: Extension: LiveKit Call State Delegate Methods
extension AICallView: LiveKitCallStateDelegate {

    func onCallConnecting() {
        showConnectingState()
        updateMuteButtonUI(
            isMuted: LiveKitCallManager.shared.isMuted
        )
    }

    func onCallConnected() {
        showConnectedState()

        updateMuteButtonUI(
            isMuted: LiveKitCallManager.shared.isMuted
        )

        updateShareButtonUI(
            isScreenShared: LiveKitCallManager.shared.isScreenShared
        )
    }

    func onCallReconnecting() {
        showReconnectingState()
    }

    func onCallDisconnected() {
        if let roomName = currentRoomName {
            viewModel.deleteRoom(roomName: roomName)
            currentRoomName = nil
        }
        stopAllAnimations()
        btnMute.isEnabled = false
        btnScreenShare.isEnabled = false
        btnEndCall.isEnabled = false
        notificationFeedback.notificationOccurred(.warning)

        let durationText = LiveKitCallManager.shared.formattedDuration()
        let endTimeText = formattedEndTime()

        onCallEnded?(durationText, endTimeText)

        closeCallScreen()
    }

}

extension AICallView {

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


