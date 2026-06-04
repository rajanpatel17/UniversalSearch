//
//  FloatingAIAssistView.swift
//  MintoakBase
//
//  Created by Rajan Patel on 02/12/25.
//

import UIKit

final class FloatingAIAssistView: UIView {

    // MARK: - UI
    /// Outer wrapper — gradient border visible on top/left/bottom; right edge flush with screen (no right corner radius)
    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        view.layer.cornerRadius = 20
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        view.clipsToBounds = true
        return view
    }()

    /// Dark background — visible only during call mode
    private let callBackgroundView: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.darkGrayTxtColor1
        v.layer.cornerRadius = 20
        v.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        v.clipsToBounds = true
        v.alpha = 0
        return v
    }()

    private let imageView: UIImageView = {
        let bundle = UniversalSearchManager.bundle
        let img = UIImageView(image: UIImage(named: "icn_aiAssist", in: bundle, compatibleWith: nil) ?? UIImage(named: "img_aIAssist", in: bundle, compatibleWith: nil))
        img.contentMode = .scaleAspectFit
        // Prevent image from shrinking during collapse animation
        img.setContentCompressionResistancePriority(.required, for: .horizontal)
        img.setContentCompressionResistancePriority(.required, for: .vertical)
        return img
    }()

    private let askVyaparLabel: UILabel = {
        let lbl = UILabel()
        lbl.text = "Ask Vyapar"
        lbl.font = AppFonts.FONT_SEMIBOLD(size: 14)
        lbl.textColor = .textColorDark
        lbl.textAlignment = .left
        // Prevent label from forcing view wider than widthConstraint
        lbl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return lbl
    }()

    private let callIndicatorDot: UIView = {
        let dot = UIView()
        dot.backgroundColor = .systemRed
        dot.layer.cornerRadius = 6
        dot.isHidden = true
        return dot
    }()

    private let callTimerLabel: UILabel = {
        let lbl = UILabel()
        lbl.font = AppFonts.FONT_MEDIUM(size: 16)
        lbl.textColor = .white
        lbl.text = "00:00"
        lbl.isHidden = true
        return lbl
    }()

    private let phoneIconImageView: UIImageView = {
        let iv = UIImageView()
        iv.image = UIImage(systemName: "phone")?.withRenderingMode(.alwaysTemplate)
        iv.tintColor = .white
        iv.contentMode = .scaleAspectFit
        iv.isHidden = true
        return iv
    }()

    private lazy var timerStackView: UIStackView = {
        let sv = UIStackView(arrangedSubviews: [phoneIconImageView, callTimerLabel])
        sv.axis = .horizontal
        sv.spacing = 6
        sv.alignment = .center
        sv.distribution = .fill
        sv.isHidden = true
        return sv
    }()

    // MARK: - Call Control Buttons
    private lazy var endCallButton: UIButton = {
        let btn = UIButton(type: .system)
        let bundle = UniversalSearchManager.bundle
        var icon = UIImage(named: "ic_endcall", in: bundle, compatibleWith: nil)
        if icon == nil {
            icon = UIImage(systemName: "phone.down.slash.fill") ?? UIImage(systemName: "phone.down.fill")
        }
        btn.setImage(icon?.withRenderingMode(.alwaysTemplate), for: .normal)
        btn.tintColor = UIColor.endCallButtonColor
        btn.backgroundColor = UIColor.white.withAlphaComponent(0.15)
        btn.layer.cornerRadius = 10
        btn.clipsToBounds = true
        btn.isHidden = true
        btn.addTarget(self, action: #selector(endCallTapped), for: .touchUpInside)
        return btn
    }()

    private lazy var screenShareButton: UIButton = {
        let btn = UIButton(type: .system)
        let icon = UIImage(systemName: "square.and.arrow.up")
        btn.setImage(icon, for: .normal)
        btn.tintColor = .white
        btn.backgroundColor = UIColor(red: 0.11, green: 0.25, blue: 0.79, alpha: 1.0)
        btn.layer.cornerRadius = 17
        btn.isHidden = true
        btn.addTarget(self, action: #selector(screenShareTapped), for: .touchUpInside)
        return btn
    }()

    private lazy var chatButton: UIButton = {
        let btn = UIButton(type: .system)
        let icon = UIImage(systemName: "bubble.left.fill")
        btn.setImage(icon, for: .normal)
        btn.tintColor = .white
        btn.backgroundColor = UIColor(red: 0.24, green: 0.38, blue: 0.95, alpha: 1.0)
        btn.layer.cornerRadius = 17
        btn.isHidden = true
        btn.addTarget(self, action: #selector(chatTapped), for: .touchUpInside)
        return btn
    }()

    private lazy var muteUnmuteButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.layer.cornerRadius = 10
        btn.clipsToBounds = true
        btn.isHidden = true
        btn.addTarget(self, action: #selector(muteUnmuteTapped), for: .touchUpInside)
        return btn
    }()

    private let callButtonsStackView: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 10
        sv.alignment = .center
        sv.distribution = .fillEqually
        sv.isHidden = true
        return sv
    }()

    // MARK: - Properties
    private var tapGesture: UITapGestureRecognizer!
    private(set) var isCallActive = false
    private(set) var isCallConnected = false
    private(set) var isExpanded = true

    private var collapseTimer: Timer?
    private var gradientBorderLayer: CAGradientLayer?
    private var callGradientBorderLayer: CAGradientLayer?

    // Icon-only collapsed width: leading(10) + icon(24) + trailing(10)
    private let collapsedWidth: CGFloat = 44
    // Call active: icon + 2 buttons (190pt)
    private let callExpandedWidth: CGFloat = 190

    // Call connecting (2 buttons): 136pt
    private let callConnectingWidth: CGFloat = 136
    
    private var tapHandled = false

    /// Self-owned width constraint, updated when call mode changes
    private var widthConstraint: NSLayoutConstraint?
    private var buttonsLeadingConstraint: NSLayoutConstraint?

    // MARK: - Init
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
        setupGestures()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        collapseTimer?.invalidate()
    }

    // MARK: - Setup
    private func setupView() {
        backgroundColor = .clear

        addSubview(containerView)
        containerView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        // Blur background — visible only during call mode
        containerView.insertSubview(callBackgroundView, at: 0)
        callBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            callBackgroundView.topAnchor.constraint(equalTo: containerView.topAnchor),
            callBackgroundView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            callBackgroundView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            callBackgroundView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor)
        ])

        // Icon
        containerView.addSubview(imageView)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            imageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 10),
            imageView.widthAnchor.constraint(equalToConstant: 24),
            imageView.heightAnchor.constraint(equalToConstant: 24)
        ])

        // "Ask Vyapar" label
        containerView.addSubview(askVyaparLabel)
        askVyaparLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let labelTrailingConstraint = askVyaparLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12)
        labelTrailingConstraint.priority = .defaultHigh
        
        NSLayoutConstraint.activate([
            askVyaparLabel.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            askVyaparLabel.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
            labelTrailingConstraint
        ])

        // Call indicator dot (top-right of icon)
        containerView.addSubview(callIndicatorDot)
        callIndicatorDot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            callIndicatorDot.widthAnchor.constraint(equalToConstant: 12),
            callIndicatorDot.heightAnchor.constraint(equalToConstant: 12),
            callIndicatorDot.topAnchor.constraint(equalTo: imageView.topAnchor, constant: -2),
            callIndicatorDot.trailingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 2)
        ])

        // Call control views added directly to containerView
        containerView.addSubview(timerStackView)
        containerView.addSubview(muteUnmuteButton)
        containerView.addSubview(endCallButton)
        
        phoneIconImageView.translatesAutoresizingMaskIntoConstraints = false
        timerStackView.translatesAutoresizingMaskIntoConstraints = false
        muteUnmuteButton.translatesAutoresizingMaskIntoConstraints = false
        endCallButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            // Phone Icon constraint inside timerStackView
            phoneIconImageView.widthAnchor.constraint(equalToConstant: 16),
            phoneIconImageView.heightAnchor.constraint(equalToConstant: 16),

            // Mute Button: leading, centerY, size 34x34
            muteUnmuteButton.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            muteUnmuteButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 10),
            muteUnmuteButton.widthAnchor.constraint(equalToConstant: 34),
            muteUnmuteButton.heightAnchor.constraint(equalToConstant: 34),

            // Timer Stack View: center, centerY
            timerStackView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            timerStackView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),

            // End Call Button: trailing, centerY, size 34x34
            endCallButton.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            endCallButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            endCallButton.widthAnchor.constraint(equalToConstant: 34),
            endCallButton.heightAnchor.constraint(equalToConstant: 34)
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(handleMuteStateChanged(_:)), name: .liveKitMuteStateChanged, object: nil)
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        guard superview != nil else { return }
        // Install a width constraint on self once added to a parent, so call-mode can animate it
        if widthConstraint == nil {
            let w = makeWidthConstraint(callActive: false)
            widthConstraint = w
            w.isActive = true
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Keep gradient border in sync with the view's current bounds (changes during expand/collapse)
        applyGradientBorder(to: containerView, layerVar: &gradientBorderLayer)
        //applyGradientBorder(to: callBackgroundView, layerVar: &callGradientBorderLayer)
    }

    private func makeWidthConstraint(callActive: Bool) -> NSLayoutConstraint {
        if callActive {
            let width = isCallConnected ? callExpandedWidth : callConnectingWidth
            return widthAnchor.constraint(equalToConstant: width)
        } else {
            let labelWidth = askVyaparLabel.sizeThatFits(
                CGSize(width: CGFloat.greatestFiniteMagnitude, height: 44)
            ).width
            // leading-padding(10) + icon(24) + spacing(6) + label + trailing-padding(12)
            let normalWidth = 10 + 24 + 6 + ceil(labelWidth) + 12
            return widthAnchor.constraint(equalToConstant: normalWidth)
        }
    }

    private func setupGestures() {
        tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTap))
        addGestureRecognizer(tapGesture)
        
        let swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(didSwipeLeft))
        swipeLeft.direction = .left
        addGestureRecognizer(swipeLeft)
        
        // Tap gesture for timerStackView to trigger chat action
        let timerTapGesture = UITapGestureRecognizer(target: self, action: #selector(timerAreaTapped))
        timerStackView.addGestureRecognizer(timerTapGesture)
        timerStackView.isUserInteractionEnabled = true
    }
    
    @objc private func timerAreaTapped() {
        chatTapped()
    }
    
    @objc private func didSwipeLeft() {
        guard superview != nil else { return }
        isExpanded = true
        widthConstraint?.isActive = false
        let newConstraint = widthAnchor.constraint(equalToConstant: callExpandedWidth - 54)
        newConstraint.isActive = true
        widthConstraint = newConstraint

        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.4, options: [.curveEaseOut]) {
            if self.isCallActive {
                self.callBackgroundView.alpha = 1
            } else {
                self.askVyaparLabel.isHidden = false
                self.askVyaparLabel.alpha = 1
            }
            self.superview?.layoutIfNeeded()
        }
        startAutoCollapseTimer()
    }

    func updateCallActive(_ active: Bool) {
        isCallActive = active
        tapHandled = false
        callIndicatorDot.isHidden = true//!active
        
        // Hide AI icon and Ask Vyapar label in call mode
        imageView.isHidden = active
        askVyaparLabel.isHidden = active
        
        // Show/hide call control buttons
        muteUnmuteButton.isHidden = !active
        endCallButton.isHidden = !active
        
        // Other buttons should be hidden
        chatButton.isHidden = true
        screenShareButton.isHidden = true
        
        if active {
            updateMuteUI(isMuted: LiveKitCallManager.shared.isMuted)
            startPulseAnimation()
            stopAutoCollapseTimer()
            expandToCallMode()
        } else {
            // Reset to expanded state when returning from call mode
            isExpanded = true
            imageView.isHidden = false
            askVyaparLabel.isHidden = false
            askVyaparLabel.alpha = 1
            
            // Hide call UI
            muteUnmuteButton.isHidden = true
            endCallButton.isHidden = true
            timerStackView.isHidden = true
            phoneIconImageView.isHidden = true
            callTimerLabel.isHidden = true
            
            stopPulseAnimation()
            collapseFromCallMode()
            startAutoCollapseTimer()
        }
    }

    func updateCallConnected(_ connected: Bool) {
        isCallConnected = connected
        
        // Show timer and phone icon when connected
        callTimerLabel.isHidden = !connected
        phoneIconImageView.isHidden = !connected
        timerStackView.isHidden = !connected
        
        // Ensure other buttons remain hidden
        chatButton.isHidden = true
        screenShareButton.isHidden = true
        
        if isCallActive {
            expandToCallMode()
        }
    }

    func updateCallDuration(_ duration: String) {
        callTimerLabel.text = duration
    }

    private func updateButtonsLayout(showTimer: Bool) {
        // No-op in new layout
    }

    func updateScreenShareUI(isSharing: Bool) {
        let icon = UIImage(systemName: isSharing ? "square.and.arrow.up.fill" : "square.and.arrow.up")
        screenShareButton.setImage(icon, for: .normal)
        screenShareButton.backgroundColor = isSharing
            ? UIColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 1.0)
            : UIColor(red: 0.11, green: 0.25, blue: 0.79, alpha: 1.0)
    }

    // MARK: - Gradient Border

    private func applyGradientBorder(to view: UIView, layerVar: inout CAGradientLayer?) {
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        // Reuse layer if possible to prevent flickering and inefficiency
        let gradient: CAGradientLayer
        if let existing = layerVar {
            gradient = existing
        } else {
            gradient = CAGradientLayer()
            // Colors: #FFB6BA → #3D62F3 → #FFB1B6
            gradient.colors = [
                UIColor.aIGradiantBorderColor1.cgColor,
                UIColor.aIGradiantBorderColor2.cgColor,
                UIColor.aIGradiantBorderColor3.cgColor
            ]
            // Approx 118.78 deg (Right and Down)
            gradient.startPoint = CGPoint(x: 0.26, y: 0.0)
            gradient.endPoint   = CGPoint(x: 0.74, y: 1.0)
            
            let shape = CAShapeLayer()
            shape.lineWidth = 1
            shape.fillColor = UIColor.clear.cgColor
            shape.strokeColor = UIColor.black.cgColor // Mask color doesn't matter, just needs to be opaque
            gradient.mask = shape
            
            // For callBackgroundView (UIVisualEffectView), add on top of blur effect.
            // For containerView, insert at index 0 to stay behind icons/labels.
            if view === callBackgroundView {
                view.layer.addSublayer(gradient)
            } else {
                view.layer.insertSublayer(gradient, at: 0)
            }
            layerVar = gradient
        }

        gradient.frame = bounds
        
        let radius = view.layer.cornerRadius
        let path = UIBezierPath()
        
        // Inset by half line width (0.5pt) so the 1pt stroke isn't cut by clipsToBounds
        let inset: CGFloat = 0.5
        let innerRadius = max(0, radius - inset)
        
        // 3-sided border: Top, Left, Bottom. Right side remains open (flush with screen).
        // Start at top-right
        path.move(to: CGPoint(x: bounds.maxX, y: inset))
        
        // Top edge
        path.addLine(to: CGPoint(x: inset + innerRadius, y: inset))
        
        // Top-left corner (Top to Left: Counter-Clockwise in iOS)
        path.addArc(
            withCenter: CGPoint(x: inset + innerRadius, y: inset + innerRadius),
            radius: innerRadius,
            startAngle: -CGFloat.pi / 2,
            endAngle: CGFloat.pi,
            clockwise: false
        )
        
        // Left edge
        path.addLine(to: CGPoint(x: inset, y: bounds.maxY - inset - innerRadius))
        
        // Bottom-left corner (Left to Bottom: Counter-Clockwise in iOS)
        path.addArc(
            withCenter: CGPoint(x: inset + innerRadius, y: bounds.maxY - inset - innerRadius),
            radius: innerRadius,
            startAngle: CGFloat.pi,
            endAngle: CGFloat.pi / 2,
            clockwise: false
        )
        
        // Bottom edge back to right
        path.addLine(to: CGPoint(x: bounds.maxX, y: bounds.maxY - inset))

        if let shape = gradient.mask as? CAShapeLayer {
            shape.path = path.cgPath
        }
    }

    // MARK: - Call Mode Expand / Collapse

    private func expandToCallMode() {
        guard superview != nil else { return }
        widthConstraint?.isActive = false
        let newConstraint = makeWidthConstraint(callActive: true)
        newConstraint.isActive = true
        widthConstraint = newConstraint

        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.4, options: [.curveEaseOut]) {
            self.callBackgroundView.alpha = 1
            self.superview?.layoutIfNeeded()
        }
    }

    private func collapseFromCallMode() {
        guard superview != nil else { return }
        widthConstraint?.isActive = false
        let newConstraint = makeWidthConstraint(callActive: false)
        newConstraint.isActive = true
        widthConstraint = newConstraint

        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.4, options: [.curveEaseOut]) {
            self.callBackgroundView.alpha = 0
            self.superview?.layoutIfNeeded()
        }
    }

    // MARK: - Normal Mode Expand / Collapse

    func expandView() {
        guard !isExpanded, !isCallActive, superview != nil else { return }
        isExpanded = true
        askVyaparLabel.isHidden = false
        widthConstraint?.isActive = false
        let newConstraint = makeWidthConstraint(callActive: false)
        newConstraint.isActive = true
        widthConstraint = newConstraint

        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.4, options: [.curveEaseOut]) {
            self.askVyaparLabel.alpha = 1
            self.superview?.layoutIfNeeded()
        }
    }

    func collapseView() {
        guard isExpanded, !isCallActive, superview != nil else { return }
        isExpanded = false
        widthConstraint?.isActive = false
        let newConstraint = widthAnchor.constraint(equalToConstant: collapsedWidth)
        newConstraint.isActive = true
        widthConstraint = newConstraint

        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.4, options: [.curveEaseOut]) {
            self.askVyaparLabel.alpha = 0
            self.superview?.layoutIfNeeded()
        } completion: { _ in
            // Hide after animation to prevent clipping artefacts during expand
            if !self.isExpanded {
                self.askVyaparLabel.isHidden = true
            }
        }
    }

    // MARK: - Call Control Actions

    @objc private func endCallTapped() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        NotificationCenter.default.post(name: .floatingEndCallTapped, object: nil)
    }

    @objc private func muteUnmuteTapped() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            await LiveKitCallManager.shared.toggleMute()
        }
    }

    private func updateMuteUI(isMuted: Bool) {
        let imageName = isMuted ? "ic_mute" : "icn_unmute"
        let bundle = UniversalSearchManager.bundle
        let image = UIImage(named: imageName, in: bundle, compatibleWith: nil)?.withRenderingMode(.alwaysOriginal)
        muteUnmuteButton.setImage(image, for: .normal)
//        muteUnmuteButton.backgroundColor = isMuted
//            ? UIColor(red: 0.90, green: 0.91, blue: 0.93, alpha: 1.0)
//            : UIColor.activeButtonColor
    }

    @objc private func handleMuteStateChanged(_ notification: Notification) {
        if let isMuted = notification.userInfo?["isMuted"] as? Bool {
            updateMuteUI(isMuted: isMuted)
        }
    }

    @objc private func screenShareTapped() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        NotificationCenter.default.post(name: .floatingScreenShareTapped, object: nil)
    }

    @objc private func chatTapped() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        NotificationCenter.default.post(name: .floatingChatTapped, object: nil)
    }

    // MARK: - Pulse Animation
    private func startPulseAnimation() {
        callIndicatorDot.layer.removeAnimation(forKey: "pulse")
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.3
        pulse.duration = 0.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        callIndicatorDot.layer.add(pulse, forKey: "pulse")
    }

    private func stopPulseAnimation() {
        callIndicatorDot.layer.removeAnimation(forKey: "pulse")
    }

    // MARK: - Tap
    @objc private func didTap() {
        guard !tapHandled else { return }
        tapHandled = true

        // If collapsed in normal mode, expand first then navigate
        if !isExpanded && !isCallActive {
            expandView()
            startAutoCollapseTimer()
        }

        NotificationCenter.default.post(name: .AIAssistTapped, object: nil)

        // Auto-reset after a short delay to ensure it stays clickable
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.tapHandled = false
        }
    }

    // MARK: - Auto Collapse Timer
    func startAutoCollapseTimer() {
        collapseTimer?.invalidate()
        collapseTimer = nil
        collapseTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            guard let self else { return }
            if self.isCallActive {
                self.collapseFromCallMode()
            } else if UserDefaults.standard.SpotlightAIAssistViewed == true {
                // When Spotlight view integrate then uncomment this following line
                guard UserDefaults.standard.SpotlightAIAssistViewed == true else { return }
                self.collapseView()
            } else {
                self.collapseView()
            }
        }
    }

    func stopAutoCollapseTimer() {
        collapseTimer?.invalidate()
        collapseTimer = nil
    }
}
