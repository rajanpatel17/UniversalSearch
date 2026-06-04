//
//  GlassSphereView.swift
//  HDFC Bank SmartHub Vyapar
//
//  Created by Rajan Patel on 27/05/26.
//

import UIKit

protocol GlassSphereAudioDelegate: AnyObject {
    func glassSphere(_ sphere: GlassSphereView, didUpdateSmoothedLevel level: Float)
}

/// Weak proxy to break the CADisplayLink -> target retain cycle.
private final class SphereDisplayLinkProxy {
    weak var target: GlassSphereView?
    init(_ target: GlassSphereView) { self.target = target }
    @objc func onDisplayLink(_ link: CADisplayLink) {
        guard let target else { link.invalidate(); return }
        target.handleDisplayLink()
    }
}

final class GlassSphereView: UIView {

    // MARK: - Configuration

    private let sphereSize: CGFloat = 250
    private let brandBlue = UIColor(red: 0.10, green: 0.47, blue: 0.90, alpha: 1.0)

    // MARK: - State

    private var displayLink: CADisplayLink?
    private var displayLinkProxy: SphereDisplayLinkProxy?
    private var animationStartTime: CFTimeInterval = 0
    private var currentAudioLevel: Float = 0
    private var smoothedLevel: Float = 0
    private var isActive = false
    private var isConnectingMode = false
    weak var audioDelegate: GlassSphereAudioDelegate?

    // MARK: - Outer Glow

    private lazy var outerGlowView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = .clear
        return v
    }()
    private var outerGlowGradient: CAGradientLayer?

    // MARK: - Glass Sphere Container

    private lazy var sphereContainer: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.layer.cornerRadius = sphereSize / 2
        v.clipsToBounds = true
        v.backgroundColor = .clear
        return v
    }()
    private var sphereBgGradient: CAGradientLayer?

    // MARK: - Shine

    private var shineGradientLayer: CAGradientLayer?

    private lazy var shineView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = .clear
        v.layer.cornerRadius = 16
        v.clipsToBounds = true
        v.transform = CGAffineTransform(rotationAngle: -.pi / 4)
        v.layer.shadowColor = UIColor.white.cgColor
        v.layer.shadowOpacity = 0.4
        v.layer.shadowRadius = 6
        v.layer.shadowOffset = .zero

        let g = CAGradientLayer()
        g.colors = [
            UIColor.white.withAlphaComponent(0.35).cgColor,
            UIColor.clear.cgColor,
        ]
        g.startPoint = CGPoint(x: 0, y: 0)
        g.endPoint = CGPoint(x: 1, y: 1)
        v.layer.addSublayer(g)
        self.shineGradientLayer = g
        return v
    }()

    // MARK: - Aurora Aura Layers

    private var aura1Layer = CAGradientLayer()
    private var aura2Layer = CAGradientLayer()
    private var aura3Layer = CAGradientLayer()
    private var auraCoreLayer = CAGradientLayer()

    private lazy var aura1View: UIView = {
        let v = UIView(); v.translatesAutoresizingMaskIntoConstraints = false; return v
    }()
    private lazy var aura2View: UIView = {
        let v = UIView(); v.translatesAutoresizingMaskIntoConstraints = false; return v
    }()
    private lazy var aura3View: UIView = {
        let v = UIView(); v.translatesAutoresizingMaskIntoConstraints = false; return v
    }()
    private lazy var auraCoreView: UIView = {
        let v = UIView(); v.translatesAutoresizingMaskIntoConstraints = false; return v
    }()

    // MARK: - Glass Border

    private var borderGradientLayer: CAGradientLayer?

    // MARK: - Bottom Tint

    private lazy var bottomTintView: UIView = {
        let v = UIView(); v.translatesAutoresizingMaskIntoConstraints = false
        v.isUserInteractionEnabled = false; return v
    }()
    private var bottomTintGradient: CAGradientLayer?

    // MARK: - Particles

    private var particleLayers: [CAShapeLayer] = []

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: 280, height: 280)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Force nested subview layout so aura view bounds are resolved
        // (aura views are grandchildren — inside sphereContainer)
        sphereContainer.layoutIfNeeded()
        updateLayerFrames()
    }

    // MARK: - Setup

    private func setup() {
        backgroundColor = .clear

        addSubview(outerGlowView)
        addSubview(sphereContainer)

        sphereContainer.addSubview(aura1View)
        sphereContainer.addSubview(aura2View)
        sphereContainer.addSubview(aura3View)
        sphereContainer.addSubview(auraCoreView)
        sphereContainer.addSubview(bottomTintView)
        sphereContainer.addSubview(shineView)

        NSLayoutConstraint.activate([
            outerGlowView.centerXAnchor.constraint(equalTo: centerXAnchor),
            outerGlowView.centerYAnchor.constraint(equalTo: centerYAnchor),
            outerGlowView.widthAnchor.constraint(equalToConstant: 270),
            outerGlowView.heightAnchor.constraint(equalToConstant: 270),

            sphereContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            sphereContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            sphereContainer.widthAnchor.constraint(equalToConstant: sphereSize),
            sphereContainer.heightAnchor.constraint(equalToConstant: sphereSize),

            // Aura 1 — 240×240 (20% larger for soft edge = simulated blur)
            aura1View.widthAnchor.constraint(equalToConstant: 240),
            aura1View.heightAnchor.constraint(equalToConstant: 240),
            aura1View.centerXAnchor.constraint(equalTo: sphereContainer.centerXAnchor, constant: -25),
            aura1View.centerYAnchor.constraint(equalTo: sphereContainer.centerYAnchor, constant: -25),

            // Aura 2 — 220×220 (20% larger for soft edge)
            aura2View.widthAnchor.constraint(equalToConstant: 220),
            aura2View.heightAnchor.constraint(equalToConstant: 220),
            aura2View.centerXAnchor.constraint(equalTo: sphereContainer.centerXAnchor, constant: 30),
            aura2View.centerYAnchor.constraint(equalTo: sphereContainer.centerYAnchor, constant: 30),

            // Aura 3 — 180×180 (20% larger for soft edge)
            aura3View.widthAnchor.constraint(equalToConstant: 180),
            aura3View.heightAnchor.constraint(equalToConstant: 180),
            aura3View.centerXAnchor.constraint(equalTo: sphereContainer.centerXAnchor),
            aura3View.centerYAnchor.constraint(equalTo: sphereContainer.centerYAnchor),

            // Core — 120×120 (20% larger for soft edge)
            auraCoreView.widthAnchor.constraint(equalToConstant: 120),
            auraCoreView.heightAnchor.constraint(equalToConstant: 120),
            auraCoreView.centerXAnchor.constraint(equalTo: sphereContainer.centerXAnchor),
            auraCoreView.centerYAnchor.constraint(equalTo: sphereContainer.centerYAnchor),

            // Bottom tint — 120pt from bottom
            bottomTintView.leadingAnchor.constraint(equalTo: sphereContainer.leadingAnchor),
            bottomTintView.trailingAnchor.constraint(equalTo: sphereContainer.trailingAnchor),
            bottomTintView.bottomAnchor.constraint(equalTo: sphereContainer.bottomAnchor),
            bottomTintView.heightAnchor.constraint(equalToConstant: 120),

            // Shine — top-left
            shineView.topAnchor.constraint(equalTo: sphereContainer.topAnchor, constant: 20),
            shineView.leadingAnchor.constraint(equalTo: sphereContainer.leadingAnchor, constant: 35),
            shineView.widthAnchor.constraint(equalToConstant: 80),
            shineView.heightAnchor.constraint(equalToConstant: 40),
        ])

        setupOuterGlow()
        setupSphereBackground()
        setupAuraGradients()
        setupAuraBlendMode()
        setupGlassBorder()
        setupBottomTint()
        setupParticles()
        setupShadows()

        // Set initial gradient frames immediately (auto layout hasn't run yet)
        updateLayerFrames()
    }

    // MARK: - Outer Glow (radial gradient for soft diffused light)

    private func setupOuterGlow() {
        let g = CAGradientLayer()
        g.type = .radial
        g.colors = [
            brandBlue.withAlphaComponent(0.18).cgColor,
            brandBlue.withAlphaComponent(0.08).cgColor,
            UIColor.clear.cgColor,
        ]
        g.locations = [0, 0.55, 1]
        g.startPoint = CGPoint(x: 0.5, y: 0.5)
        g.endPoint = CGPoint(x: 1.0, y: 1.0)
        outerGlowView.layer.addSublayer(g)
        outerGlowGradient = g
    }

    // MARK: - Sphere Background (minimal tint — aurora colors must dominate)

    private func setupSphereBackground() {
        let g = CAGradientLayer()
        g.colors = [
            UIColor.white.withAlphaComponent(0.15).cgColor,
            UIColor.white.withAlphaComponent(0.05).cgColor,
        ]
        g.startPoint = CGPoint(x: 0, y: 0)
        g.endPoint = CGPoint(x: 1, y: 1)
        sphereContainer.layer.insertSublayer(g, at: 0)
        sphereBgGradient = g
    }

    // MARK: - Aura Gradients (vivid, concentrated — must be clearly visible on light bg)

    private func setupAuraGradients() {
        // Aura 1 — vivid blue with soft-edge falloff (simulates blur(radius:12))
        aura1Layer.type = .radial
        aura1Layer.colors = [
            UIColor(red: 0.10, green: 0.47, blue: 0.90, alpha: 1.0).cgColor,
            UIColor(red: 0.10, green: 0.47, blue: 0.90, alpha: 0.80).cgColor,
            UIColor(red: 0.10, green: 0.47, blue: 0.90, alpha: 0.40).cgColor,
            UIColor(red: 0.10, green: 0.47, blue: 0.90, alpha: 0.12).cgColor,
            UIColor(red: 0.10, green: 0.47, blue: 0.90, alpha: 0.04).cgColor,
            UIColor.clear.cgColor,
        ]
        aura1Layer.locations = [0, 0.20, 0.45, 0.65, 0.85, 1]
        aura1Layer.startPoint = CGPoint(x: 0.5, y: 0.5)
        aura1Layer.endPoint = CGPoint(x: 1.0, y: 1.0)
        aura1View.layer.addSublayer(aura1Layer)

        // Aura 2 — vivid purple with soft-edge falloff
        aura2Layer.type = .radial
        aura2Layer.colors = [
            UIColor(red: 0.55, green: 0.36, blue: 0.96, alpha: 1.0).cgColor,
            UIColor(red: 0.55, green: 0.36, blue: 0.96, alpha: 0.75).cgColor,
            UIColor(red: 0.55, green: 0.36, blue: 0.96, alpha: 0.35).cgColor,
            UIColor(red: 0.55, green: 0.36, blue: 0.96, alpha: 0.10).cgColor,
            UIColor(red: 0.55, green: 0.36, blue: 0.96, alpha: 0.03).cgColor,
            UIColor.clear.cgColor,
        ]
        aura2Layer.locations = [0, 0.20, 0.45, 0.65, 0.85, 1]
        aura2Layer.startPoint = CGPoint(x: 0.5, y: 0.5)
        aura2Layer.endPoint = CGPoint(x: 1.0, y: 1.0)
        aura2View.layer.addSublayer(aura2Layer)

        // Aura 3 — rich blue fill with soft edge
        aura3Layer.type = .radial
        aura3Layer.colors = [
            UIColor(red: 0.23, green: 0.51, blue: 0.96, alpha: 0.85).cgColor,
            UIColor(red: 0.23, green: 0.51, blue: 0.96, alpha: 0.55).cgColor,
            UIColor(red: 0.23, green: 0.51, blue: 0.96, alpha: 0.18).cgColor,
            UIColor(red: 0.23, green: 0.51, blue: 0.96, alpha: 0.04).cgColor,
            UIColor.clear.cgColor,
        ]
        aura3Layer.locations = [0, 0.30, 0.55, 0.80, 1]
        aura3Layer.startPoint = CGPoint(x: 0.5, y: 0.5)
        aura3Layer.endPoint = CGPoint(x: 1.0, y: 1.0)
        aura3View.layer.addSublayer(aura3Layer)

        // Core — bright white center with soft blue glow
        auraCoreLayer.type = .radial
        auraCoreLayer.colors = [
            UIColor.white.withAlphaComponent(1.0).cgColor,
            UIColor.white.withAlphaComponent(0.65).cgColor,
            brandBlue.withAlphaComponent(0.40).cgColor,
            brandBlue.withAlphaComponent(0.08).cgColor,
            UIColor.clear.cgColor,
        ]
        auraCoreLayer.locations = [0, 0.15, 0.40, 0.70, 1]
        auraCoreLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        auraCoreLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        auraCoreView.layer.addSublayer(auraCoreLayer)
    }

    // MARK: - Aura Blend Mode
    // Note: SwiftUI .blendMode(.screen) washes out on light backgrounds in UIKit's
    // compositingFilter. Using normal compositing with transparent sphere background
    // lets the vivid aura colors show through naturally.
    private func setupAuraBlendMode() {
        // No compositing filter needed — aura colors show through the transparent sphere bg
    }

    // MARK: - Glass Border

    private func setupGlassBorder() {
        let borderMask = CAShapeLayer()
        borderMask.path = UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: sphereSize, height: sphereSize)).cgPath
        borderMask.fillColor = nil
        borderMask.strokeColor = UIColor.white.cgColor
        borderMask.lineWidth = 1.0

        let gradient = CAGradientLayer()
        gradient.colors = [
            UIColor.white.withAlphaComponent(0.4).cgColor,
            UIColor.white.withAlphaComponent(0.1).cgColor,
        ]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        gradient.mask = borderMask
        sphereContainer.layer.addSublayer(gradient)
        borderGradientLayer = gradient
    }

    // MARK: - Bottom Tint

    private func setupBottomTint() {
        let g = CAGradientLayer()
        g.colors = [
            UIColor.clear.cgColor,
            brandBlue.withAlphaComponent(0.15).cgColor,
        ]
        g.startPoint = CGPoint(x: 0.5, y: 0)
        g.endPoint = CGPoint(x: 0.5, y: 1)
        bottomTintView.layer.addSublayer(g)
        bottomTintGradient = g
    }

    // MARK: - Particles

    private func setupParticles() {
        let configs: [(CGPoint, CGFloat, TimeInterval)] = [
            (CGPoint(x: 0.50, y: 0.04), 1.5, 8),
            (CGPoint(x: 0.14, y: 0.27), 1.0, 11),
            (CGPoint(x: 0.82, y: 0.71), 2.0, 10),
            (CGPoint(x: 0.75, y: 0.18), 1.0, 12),
            (CGPoint(x: 0.21, y: 0.79), 1.5, 9),
            (CGPoint(x: 0.89, y: 0.46), 1.0, 13),
        ]

        for (relPos, size, dur) in configs {
            let p = CAShapeLayer()
            p.path = UIBezierPath(ovalIn: CGRect(x: -size/2, y: -size/2, width: size, height: size)).cgPath
            p.fillColor = UIColor.white.cgColor
            p.shadowColor = UIColor.white.cgColor
            p.shadowRadius = 2
            p.shadowOpacity = 0.8
            p.shadowOffset = .zero
            p.opacity = 0
            p.position = CGPoint(x: 280 * relPos.x, y: 280 * relPos.y)
            layer.addSublayer(p)
            particleLayers.append(p)
            addParticleAnimation(to: p, duration: dur)
        }
    }

    private func addParticleAnimation(to particle: CAShapeLayer, duration: TimeInterval) {
        let start = particle.position
        let dx = CGFloat.random(in: -15...15)
        let dy = CGFloat.random(in: -25...(-5))

        let posAnim = CAKeyframeAnimation(keyPath: "position")
        posAnim.values = [
            NSValue(cgPoint: start),
            NSValue(cgPoint: CGPoint(x: start.x + dx * 0.4, y: start.y + dy * 0.4)),
            NSValue(cgPoint: CGPoint(x: start.x + dx * 0.8, y: start.y + dy * 0.8)),
            NSValue(cgPoint: CGPoint(x: start.x + dx, y: start.y + dy)),
        ]
        posAnim.keyTimes = [0, 0.3, 0.7, 1]

        let opacityAnim = CAKeyframeAnimation(keyPath: "opacity")
        opacityAnim.values = [0.0, 0.5, 0.5, 0.0]
        opacityAnim.keyTimes = [0, 0.15, 0.80, 1]

        let group = CAAnimationGroup()
        group.animations = [posAnim, opacityAnim]
        group.duration = duration
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .linear)
        group.beginTime = CACurrentMediaTime() + Double.random(in: 0...3)
        particle.add(group, forKey: "particleFloat")
    }

    // MARK: - Shadows

    private func setupShadows() {
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.10
        layer.shadowRadius = 30
        layer.shadowOffset = CGSize(width: 0, height: 15)
    }

    // MARK: - Layout

    private func updateLayerFrames() {
        outerGlowGradient?.frame = outerGlowView.bounds.isEmpty
            ? CGRect(x: 0, y: 0, width: 270, height: 270) : outerGlowView.bounds
        sphereBgGradient?.frame = CGRect(x: 0, y: 0, width: sphereSize, height: sphereSize)
        borderGradientLayer?.frame = CGRect(x: 0, y: 0, width: sphereSize, height: sphereSize)

        // Use known constraint sizes as fallback if bounds aren't resolved yet
        aura1Layer.frame = aura1View.bounds.isEmpty
            ? CGRect(x: 0, y: 0, width: 240, height: 240) : aura1View.bounds
        aura2Layer.frame = aura2View.bounds.isEmpty
            ? CGRect(x: 0, y: 0, width: 220, height: 220) : aura2View.bounds
        aura3Layer.frame = aura3View.bounds.isEmpty
            ? CGRect(x: 0, y: 0, width: 180, height: 180) : aura3View.bounds
        auraCoreLayer.frame = auraCoreView.bounds.isEmpty
            ? CGRect(x: 0, y: 0, width: 120, height: 120) : auraCoreView.bounds
        bottomTintGradient?.frame = bottomTintView.bounds.isEmpty
            ? CGRect(x: 0, y: 0, width: sphereSize, height: 120) : bottomTintView.bounds
        shineGradientLayer?.frame = shineView.bounds.isEmpty
            ? CGRect(x: 0, y: 0, width: 80, height: 40) : shineView.bounds
    }

    // MARK: - Public API

    func updateAudioLevel(_ level: Float) {
        currentAudioLevel = level
    }

    func startIdleAnimation() {
        guard displayLink == nil else { return }
        isActive = true
        animationStartTime = CACurrentMediaTime()

        let proxy = SphereDisplayLinkProxy(self)
        displayLinkProxy = proxy
        let link = CADisplayLink(target: proxy, selector: #selector(SphereDisplayLinkProxy.onDisplayLink(_:)))
        if #available(iOS 15.0, *) {
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        }
        link.add(to: .current, forMode: .common)
        displayLink = link

        startAuroraAnimations()
        startFloatAnimation()
    }

    func stopAnimation() {
        isActive = false
        displayLink?.invalidate()
        displayLink = nil
        displayLinkProxy = nil

        sphereContainer.layer.removeAnimation(forKey: "float")
        outerGlowView.layer.removeAnimation(forKey: "float")
        aura1View.layer.removeAnimation(forKey: "auroraSpin")
        aura2View.layer.removeAnimation(forKey: "auroraSpinReverse")
        aura3View.layer.removeAnimation(forKey: "blobPulse")
        outerGlowView.layer.removeAnimation(forKey: "connectingPulse")

        // Reset aurora speed to default
        for v in [aura1View, aura2View] {
            v.layer.speed = 1.0
        }
    }

    func showConnectingMode() {
        isConnectingMode = true

        aura1View.layer.removeAnimation(forKey: "auroraSpin")
        aura2View.layer.removeAnimation(forKey: "auroraSpinReverse")

        let fastSpin = CABasicAnimation(keyPath: "transform.rotation.z")
        fastSpin.fromValue = 0
        fastSpin.toValue = CGFloat.pi * 2
        fastSpin.duration = 4
        fastSpin.repeatCount = .infinity
        aura1View.layer.add(fastSpin, forKey: "auroraSpin")

        let fastReverse = CABasicAnimation(keyPath: "transform.rotation.z")
        fastReverse.fromValue = CGFloat.pi * 2
        fastReverse.toValue = 0
        fastReverse.duration = 6
        fastReverse.repeatCount = .infinity
        aura2View.layer.add(fastReverse, forKey: "auroraSpinReverse")

        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.8
        pulse.toValue = 1.0
        pulse.duration = 1.0
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        outerGlowView.layer.add(pulse, forKey: "connectingPulse")
    }

    func showConnectedMode() {
        isConnectingMode = false
        outerGlowView.layer.removeAnimation(forKey: "connectingPulse")
        startAuroraAnimations()
    }

    // MARK: - Animations

    private func startFloatAnimation() {
        let float = CABasicAnimation(keyPath: "transform.translation.y")
        float.fromValue = 0
        float.toValue = -10
        float.duration = 3
        float.autoreverses = true
        float.repeatCount = .infinity
        float.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        sphereContainer.layer.add(float, forKey: "float")

        let gFloat = CABasicAnimation(keyPath: "transform.translation.y")
        gFloat.fromValue = 0
        gFloat.toValue = -8
        gFloat.duration = 3.5
        gFloat.autoreverses = true
        gFloat.repeatCount = .infinity
        gFloat.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        outerGlowView.layer.add(gFloat, forKey: "float")
    }

    private func startAuroraAnimations() {
        aura1View.layer.removeAnimation(forKey: "auroraSpin")
        aura2View.layer.removeAnimation(forKey: "auroraSpinReverse")
        aura3View.layer.removeAnimation(forKey: "blobPulse")

        let spin1 = CABasicAnimation(keyPath: "transform.rotation.z")
        spin1.fromValue = 0
        spin1.toValue = CGFloat.pi * 2
        spin1.duration = 8
        spin1.repeatCount = .infinity
        spin1.timingFunction = CAMediaTimingFunction(name: .linear)
        aura1View.layer.add(spin1, forKey: "auroraSpin")

        let spin2 = CABasicAnimation(keyPath: "transform.rotation.z")
        spin2.fromValue = CGFloat.pi * 2
        spin2.toValue = 0
        spin2.duration = 12
        spin2.repeatCount = .infinity
        spin2.timingFunction = CAMediaTimingFunction(name: .linear)
        aura2View.layer.add(spin2, forKey: "auroraSpinReverse")

        let scale3 = CABasicAnimation(keyPath: "transform.scale")
        scale3.fromValue = 1.0
        scale3.toValue = 1.15
        scale3.duration = 4
        scale3.autoreverses = true
        scale3.repeatCount = .infinity
        scale3.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        aura3View.layer.add(scale3, forKey: "blobPulse")

        // Core opacity is now driven by handleDisplayLink() (sine-wave idle pulse +
        // audio-reactive alpha). No CAAnimation here — it would override .alpha changes.
    }

    // MARK: - Aurora Speed Helper

    /// Adjusts aura rotation speed without visual jumps.
    /// Uses the layer.timeOffset/beginTime pattern to maintain continuity.
    private func setAuraSpeed(_ newSpeed: Float) {
        for auraView in [aura1View, aura2View] {
            let layer = auraView.layer
            layer.timeOffset = layer.convertTime(CACurrentMediaTime(), from: nil)
            layer.beginTime = CACurrentMediaTime()
            layer.speed = newSpeed
        }
    }

    // MARK: - Audio-Reactive (via proxy)
    //
    // Driven by remoteAudioLevel (0.0–1.0) at 60 fps via dual-rate
    // attack/release smoothing. No binary threshold — all effects use
    // continuous interpolation and naturally settle to idle as level → 0.

    fileprivate func handleDisplayLink() {
        // Dual-rate smoothing: fast attack for snappy onset, slow release for natural decay
        let isAttack = currentAudioLevel > smoothedLevel
        let smoothing: Float = isAttack ? 0.45 : 0.08
        smoothedLevel += (currentAudioLevel - smoothedLevel) * smoothing

        let level = CGFloat(max(smoothedLevel, 0.0))

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // 1. Core — scale pulse (idle=1.0, full=1.7×)
        let coreScale = 1.0 + level * 0.70
        auraCoreView.transform = CGAffineTransform(scaleX: coreScale, y: coreScale)

        // 2. Core opacity — sine-wave idle pulse that cross-fades into audio-driven alpha
        let t = CACurrentMediaTime() - animationStartTime
        let sine = CGFloat(sin(t * .pi))          // period ≈ 2s
        let idlePulse = 0.55 + sine * 0.20        // range: 0.35..0.75
        let audioAlpha = 0.6 + level * 0.4        // range: 0.6..1.0
        let blend = min(level / 0.05, 1.0)        // 0→1 as level crosses 0.05
        auraCoreView.alpha = idlePulse * (1.0 - blend) + audioAlpha * blend

        // 3. Sphere breathing (idle=1.0, full=1.12×)
        let sphereScale = 1.0 + level * 0.12
        sphereContainer.transform = CGAffineTransform(scaleX: sphereScale, y: sphereScale)

        // 4. Outer glow — expand and brighten
        let glowScale = 1.0 + level * 0.30
        outerGlowView.transform = CGAffineTransform(scaleX: glowScale, y: glowScale)
        if !isConnectingMode {
            outerGlowView.alpha = 0.5 + level * 0.5
        }

        // 5. Aura layers — alpha brightening
        aura1View.alpha = 0.7 + level * 0.3
        aura2View.alpha = 0.7 + level * 0.3
        aura3View.alpha = 0.6 + level * 0.4

        // 6. Aurora speed modulation (idle=1×, full=2.5×)
        let targetSpeed = Float(1.0 + level * 1.5)
        setAuraSpeed(targetSpeed)

        // 7. Shine — glass highlight
        shineView.alpha = 0.3 + level * 0.7

        // 8. Particles — glow intensity, spread, and scale
        let particleShadow = Float(0.4 + level * 0.6)
        let particleGlow = 2.0 + level * 4.0
        let particleScale = 1.0 + level * 0.8
        for p in particleLayers {
            p.shadowOpacity = particleShadow
            p.shadowRadius = particleGlow
            p.transform = CATransform3DMakeScale(particleScale, particleScale, 1.0)
        }

        // 9. Border glow — smooth from invisible to visible
        let borderAlpha = level * 0.40
        sphereContainer.layer.borderColor = UIColor.white.withAlphaComponent(borderAlpha).cgColor

        CATransaction.commit()

        // Notify delegate (for background blob reaction)
        audioDelegate?.glassSphere(self, didUpdateSmoothedLevel: smoothedLevel)
    }

    // MARK: - Cleanup

    deinit {
        displayLink?.invalidate()
    }
}
