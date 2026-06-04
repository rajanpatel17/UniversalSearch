//
//  AudioWaveformView.swift
//  MintoakBase
//
//  Created by Rajan Patel on 16/12/25.
//

import UIKit

/// Helper class for waveform bars to ensure gradient and shadows are always correctly sized.
private final class WaveformBar: UIView {
    private let gradientLayer = CAGradientLayer()
    
    init(primaryColor: UIColor, secondaryColor: UIColor) {
        super.init(frame: .zero)
        backgroundColor = .clear
        
        gradientLayer.colors = [primaryColor.cgColor, secondaryColor.cgColor]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 1)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 0)
        gradientLayer.cornerRadius = 2
        layer.addSublayer(gradientLayer)
        
        // Vibrant Neon Glow
        layer.shadowColor = primaryColor.cgColor
        layer.shadowRadius = 6
        layer.shadowOpacity = 1.0
        layer.shadowOffset = .zero
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: bounds.width/2).cgPath
    }
}

/// Weak proxy to break the CADisplayLink → target retain cycle.
private final class DisplayLinkProxy {
    weak var target: AudioWaveformView?
    init(_ target: AudioWaveformView) { self.target = target }
    @objc func onDisplayLink(_ link: CADisplayLink) {
        guard let target else { link.invalidate(); return }
        target.handleDisplayLink()
    }
}

final class AudioWaveformView: UIView {

    // MARK: - Configuration
    private let barCount = 6
    private let barWidth: CGFloat = 4
    private let barSpacing: CGFloat = 8
    
    // Precise Colors from HTML: #1978e5 and #60a5fa
    private let primaryBlue = UIColor(red: 0.098, green: 0.471, blue: 0.898, alpha: 1.0) 
    private let lightBlue = UIColor(red: 0.376, green: 0.647, blue: 0.980, alpha: 1.0)

    // MARK: - UI Components
    private var rippleLayers: [CAShapeLayer] = []
    
    private lazy var glassContainer: UIVisualEffectView = {
        let blur = UIBlurEffect(style: .systemThinMaterialLight)
        let v = UIVisualEffectView(effect: blur)
        v.layer.cornerRadius = 80
        v.clipsToBounds = true
        v.layer.borderWidth = 2.0
        v.layer.borderColor = UIColor.white.withAlphaComponent(0.5).cgColor
        
        // Blue Glassy Tint Overlay
        let tint = UIView()
        tint.backgroundColor = primaryBlue.withAlphaComponent(0.15)
        tint.translatesAutoresizingMaskIntoConstraints = false
        v.contentView.addSubview(tint)
        NSLayoutConstraint.activate([
            tint.topAnchor.constraint(equalTo: v.contentView.topAnchor),
            tint.bottomAnchor.constraint(equalTo: v.contentView.bottomAnchor),
            tint.leadingAnchor.constraint(equalTo: v.contentView.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: v.contentView.trailingAnchor)
        ])
        
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    /// The primary "Neon Shadow" background layer
    private lazy var glowView: UIView = {
        let v = UIView()
        v.backgroundColor = primaryBlue.withAlphaComponent(0.1) // Subtle center fill
        v.layer.cornerRadius = 80
        v.layer.shadowColor = primaryBlue.cgColor
        v.layer.shadowOpacity = 0.8
        v.layer.shadowRadius = 40
        v.layer.shadowOffset = .zero
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private var bars: [WaveformBar] = []
    private var barHeightConstraints: [NSLayoutConstraint] = []
    
    // MARK: - State
    private var displayLink: CADisplayLink?
    private var displayLinkProxy: DisplayLinkProxy?
    private var animationStartTime: CFTimeInterval = 0
    private var currentAudioLevel: Float = 0
    private var smoothedLevel: Float = 0
    private var isActive = false

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
        return CGSize(width: 320, height: 320)
    }

    // MARK: - Setup
    private func setup() {
        backgroundColor = .clear
        
        setupRipples()
        
        addSubview(glowView)
        addSubview(glassContainer)
        
        NSLayoutConstraint.activate([
            glassContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            glassContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            glassContainer.widthAnchor.constraint(equalToConstant: 160),
            glassContainer.heightAnchor.constraint(equalToConstant: 160),
            
            glowView.centerXAnchor.constraint(equalTo: centerXAnchor),
            glowView.centerYAnchor.constraint(equalTo: centerYAnchor),
            glowView.widthAnchor.constraint(equalToConstant: 160),
            glowView.heightAnchor.constraint(equalToConstant: 160),
        ])
        
        setupWaveform()
        startGlowAnimation()
    }

    private func setupRipples() {
        for i in 0..<3 {
            let ripple = CAShapeLayer()
            let path = UIBezierPath(ovalIn: CGRect(x: -80, y: -80, width: 160, height: 160))
            ripple.path = path.cgPath
            ripple.fillColor = UIColor.clear.cgColor
            ripple.strokeColor = primaryBlue.withAlphaComponent(0.6).cgColor
            ripple.lineWidth = 2.5
            ripple.opacity = 0
            
            // Neon glow for ripple
            ripple.shadowColor = primaryBlue.cgColor
            ripple.shadowRadius = 15
            ripple.shadowOpacity = 0.7
            ripple.shadowOffset = .zero
            
            layer.addSublayer(ripple)
            rippleLayers.append(ripple)
            
            addRippleAnimation(to: ripple, delay: Double(i) * 1.0)
        }
    }

    private func addRippleAnimation(to ripple: CAShapeLayer, delay: TimeInterval) {
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.8
        scale.toValue = 2.6
        
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [0, 0.6, 0]
        opacity.keyTimes = [0, 0.4, 1]
        
        let group = CAAnimationGroup()
        group.animations = [scale, opacity]
        group.duration = 3.0
        group.repeatCount = .infinity
        group.beginTime = CACurrentMediaTime() + delay
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0, 0.2, 0.8, 1)
        
        ripple.add(group, forKey: "ripple")
    }

    private func setupWaveform() {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.alignment = .center
        stackView.spacing = barSpacing
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        glassContainer.contentView.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: glassContainer.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: glassContainer.centerYAnchor),
            stackView.heightAnchor.constraint(equalToConstant: 100)
        ])
        
        for _ in 0..<barCount {
            let bar = WaveformBar(primaryColor: primaryBlue, secondaryColor: lightBlue)
            stackView.addArrangedSubview(bar)
            bars.append(bar)
            
            let h = bar.heightAnchor.constraint(equalToConstant: 14)
            h.isActive = true
            barHeightConstraints.append(h)
            
            NSLayoutConstraint.activate([
                bar.widthAnchor.constraint(equalToConstant: barWidth)
            ])
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        for ripple in rippleLayers {
            ripple.position = center
        }
    }

    private func startGlowAnimation() {
        // Continuous subtle pulse logic for when idle
        let pulse = CABasicAnimation(keyPath: "shadowRadius")
        pulse.fromValue = 25
        pulse.toValue = 45
        pulse.duration = 2.5
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        glowView.layer.add(pulse, forKey: "pulseGlow")
    }

    // MARK: - Public API
    func updateAudioLevel(_ level: Float) {
        currentAudioLevel = level
    }

    func startIdleAnimation() {
        guard displayLink == nil else { return }
        isActive = true
        animationStartTime = CACurrentMediaTime()
        let proxy = DisplayLinkProxy(self)
        displayLinkProxy = proxy
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.onDisplayLink(_:)))
        if #available(iOS 15.0, *) {
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        }
        link.add(to: .current, forMode: .common)
        displayLink = link
    }

    func stopAnimation() {
        isActive = false
        displayLink?.invalidate()
        displayLink = nil
        displayLinkProxy = nil

        UIView.animate(withDuration: 0.3) {
            for constraint in self.barHeightConstraints {
                constraint.constant = 14
            }
            self.layoutIfNeeded()
        }
    }

    // MARK: - Animation Loop
    fileprivate func handleDisplayLink() {
        let elapsed = CACurrentMediaTime() - animationStartTime
        
        let isAttack = currentAudioLevel > smoothedLevel
        let smoothingFactor: Float = isAttack ? 0.4 : 0.15
        smoothedLevel += (currentAudioLevel - smoothedLevel) * smoothingFactor
        
        let level = CGFloat(smoothedLevel)
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        // 1. Waveform Bars Update
        for (i, constraint) in barHeightConstraints.enumerated() {
            let phase = Double(i) * 0.4
            let idleHeight = 14 + 16 * CGFloat(0.5 + 0.5 * sin(elapsed * 4.0 + phase))
            let audioHeight = 14 + 76 * level * CGFloat.random(in: 0.8...1.2)
            constraint.constant = max(idleHeight, audioHeight)
        }
        
        // 2. Neon Background Glow Reactivity (Matches HTML shadow intensity)
        let glowRadius = 30 + level * 50 // Expand radius up to 80
        let glowOpacity = 0.6 + level * 0.4 // Brighten up to 1.0
        glowView.layer.shadowRadius = glowRadius
        glowView.layer.shadowOpacity = Float(glowOpacity)
        
        // 3. Scale Pulse
        let scale = 1.0 + level * 0.15
        glowView.transform = CGAffineTransform(scaleX: scale, y: scale)
        glassContainer.transform = CGAffineTransform(scaleX: scale, y: scale)
        
        // 4. Ripple intensity boost
        let rippleAlpha = 0.5 + level * 0.5
        for ripple in rippleLayers {
            ripple.shadowOpacity = Float(rippleAlpha * 0.7)
        }
        
        CATransaction.commit()
        layoutIfNeeded()
    }

    deinit {
        displayLink?.invalidate()
    }
}

// MARK: - BackgroundParticlesView
final class BackgroundParticlesView: UIView {
    
    private var particleLayers: [CAShapeLayer] = []
    private var smoothedLevel: Float = 0
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupParticles()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupParticles()
    }
    
    private func setupParticles() {
        backgroundColor = .clear
        isUserInteractionEnabled = false
        
        for _ in 0..<22 {
            let size = CGFloat.random(in: 1.5...4.5)
            let particle = CAShapeLayer()
            particle.path = UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: size, height: size)).cgPath
            particle.fillColor = UIColor.white.withAlphaComponent(CGFloat.random(in: 0.2...0.6)).cgColor
            
            particle.shadowColor = UIColor.white.cgColor
            particle.shadowRadius = 2
            particle.shadowOpacity = 0.5
            particle.shadowOffset = .zero
            
            let startX = CGFloat.random(in: 0...UIScreen.main.bounds.width)
            let startY = CGFloat.random(in: 0...UIScreen.main.bounds.height)
            particle.position = CGPoint(x: startX, y: startY)
            
            layer.addSublayer(particle)
            particleLayers.append(particle)
            
            animateParticle(particle)
        }
    }
    
    private func animateParticle(_ particle: CAShapeLayer) {
        let duration = Double.random(in: 12...20)
        let delay = Double.random(in: 0...8)
        
        let float = CABasicAnimation(keyPath: "position.y")
        float.fromValue = UIScreen.main.bounds.height + 50
        float.toValue = -50
        float.duration = duration
        float.repeatCount = .infinity
        float.beginTime = CACurrentMediaTime() + delay
        
        let drift = CABasicAnimation(keyPath: "position.x")
        let currentX = particle.position.x
        drift.fromValue = currentX
        drift.toValue = currentX + CGFloat.random(in: -60...60)
        drift.duration = duration
        drift.repeatCount = .infinity
        drift.beginTime = CACurrentMediaTime() + delay
        
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [0, 1, 1, 0]
        opacity.keyTimes = [0, 0.15, 0.85, 1]
        opacity.duration = duration
        opacity.repeatCount = .infinity
        opacity.beginTime = CACurrentMediaTime() + delay
        
        particle.add(float, forKey: "float")
        particle.add(drift, forKey: "drift")
        particle.add(opacity, forKey: "opacity")
    }
    
    func updateAudioLevel(_ level: Float) {
        let isAttack = level > smoothedLevel
        let smoothingFactor: Float = isAttack ? 0.2 : 0.05
        smoothedLevel += (level - smoothedLevel) * smoothingFactor
        
        let l = CGFloat(smoothedLevel)
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        for particle in particleLayers {
            particle.opacity = Float(0.4 + l * 0.6)
            let scale = 1.0 + l * 1.5
            particle.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
            particle.speed = Float(1.0 + smoothedLevel * 2.0)
        }
        
        CATransaction.commit()
    }
}
