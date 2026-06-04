//
//  UIView.swift
//  BaseAppMulti
//
//  Created by Chaitanya Soni on 12/07/20.
//  Copyright © 2020 Chaitanya Soni. All rights reserved.
//

import Foundation
import UIKit

@available(iOS 11.0, *)
public extension UIView {
	
    func addTopBorder(with color: UIColor?, andWidth borderWidth: CGFloat) {
        let border = UIView()
        border.backgroundColor = color
        border.autoresizingMask = [.flexibleWidth, .flexibleBottomMargin]
        border.frame = CGRect(x: 0, y: 0, width: frame.size.width, height: borderWidth)
        addSubview(border)
    }
    
    func setFixBorders(cornerRadius: CGFloat, borderWidth: CGFloat, borderColor: UIColor, sides: CACornerMask) {
        
        self.layer.masksToBounds = true
        self.layer.cornerRadius = cornerRadius
        self.layer.borderWidth = borderWidth
        self.layer.borderColor = borderColor.cgColor
        self.layer.maskedCorners = sides
    }
    
    func setBorder(cornerRadius: CGFloat, borderWidth: CGFloat, borderColor: UIColor) {
        self.layer.masksToBounds = true
        self.layer.cornerRadius = cornerRadius
        self.layer.borderWidth = borderWidth
        self.layer.borderColor = borderColor.cgColor
    }
    
    func setCornerRadius(radius: CGFloat) {
        self.layer.cornerRadius = radius;
        self.layer.masksToBounds = true
    }
    
    func removeDoubleBorderLayers() {
        self.layer.sublayers?.removeAll(where: { $0.name == "doubleBorder1" })
        self.layer.sublayers?.removeAll(where: { $0.name == "doubleBorder2" })
    }
    
    func addDoubleBorder(outerColor: UIColor, innerColor: UIColor, outerBorderWidth: CGFloat, innerBorderWidth: CGFloat, cornerRadius: CGFloat) {
        // Outer border layer using the view's full bounds.
        let outerLayer = CAShapeLayer()
        outerLayer.name = "doubleBorder1"
        outerLayer.frame = self.bounds
        outerLayer.path = UIBezierPath(roundedRect: self.bounds, cornerRadius: cornerRadius).cgPath
        outerLayer.strokeColor = outerColor.cgColor
        outerLayer.fillColor = UIColor.clear.cgColor
        outerLayer.lineWidth = outerBorderWidth
        self.layer.addSublayer(outerLayer)
        
        // Calculate an inset for the inner border equal to the outer border's width.
        let insetRect = self.bounds.insetBy(dx: outerBorderWidth, dy: outerBorderWidth)
        // Adjust the corner radius for the inner border so it follows the inset path.
        let adjustedCornerRadius = max(0, cornerRadius - outerBorderWidth)
        
        // Inner border layer.
        let innerLayer = CAShapeLayer()
        innerLayer.frame = self.bounds
        innerLayer.name = "doubleBorder2"
        innerLayer.path = UIBezierPath(roundedRect: insetRect, cornerRadius: adjustedCornerRadius).cgPath
        innerLayer.strokeColor = innerColor.cgColor
        innerLayer.fillColor = UIColor.clear.cgColor
        innerLayer.lineWidth = innerBorderWidth
        self.layer.addSublayer(innerLayer)
    }
    
    func makeCircular() {
        
        self.layer.cornerRadius = self.frame.height / 2;
        self.layer.masksToBounds = true
    }
    
	// Using a function since `var image` might conflict with an existing variable
	// (like on `UIImageView`)
    func asImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        return renderer.image { rendererContext in
            layer.render(in: rendererContext.cgContext)
        }
    }
    
    func snapshot(scrollView: UIScrollView) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(scrollView.contentSize, false, UIScreen.main.scale)
        layer.render(in: UIGraphicsGetCurrentContext()!)
        let savedContentOffset = scrollView.contentOffset
        let savedFrame = frame
        
        scrollView.contentOffset = CGPoint.zero
        frame = CGRect(x: 0, y: 0, width: scrollView.contentSize.width, height: scrollView.contentSize.height)
        
        layer.render(in: UIGraphicsGetCurrentContext()!)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        
        scrollView.contentOffset = savedContentOffset
        frame = savedFrame
        
        UIGraphicsEndImageContext()
        
        return image
    }

}

extension UIScrollView {
    func updateContentSize() {
        var contentRect = CGRect.zero
        for view in self.subviews {
            contentRect = contentRect.union(view.frame)
        }
        self.contentSize = contentRect.size
    }
}

@available(iOS 11.0, *)
public extension UIView {
    ///superview is anchored to subview, eg superview.anchor(top: subview.topAnchor)
    func anchor(top: NSLayoutYAxisAnchor?, leading: NSLayoutXAxisAnchor?, bottom: NSLayoutYAxisAnchor?, trailing: NSLayoutXAxisAnchor?, padding: UIEdgeInsets = .zero, size: CGSize = .zero) {
        //translate the view's autoresizing mask into Auto Layout constraints
        translatesAutoresizingMaskIntoConstraints = false

        if let top = top {
            topAnchor.constraint(equalTo: top, constant: padding.top).isActive = true
        }

        if let leading = leading {
            leadingAnchor.constraint(equalTo: leading, constant: padding.left).isActive = true
        }

        if let bottom = bottom {
            bottomAnchor.constraint(equalTo: bottom, constant: -padding.bottom).isActive = true
        }

        if let trailing = trailing {
            trailingAnchor.constraint(equalTo: trailing, constant: -padding.right).isActive = true
        }

        if size.width != 0 {
            widthAnchor.constraint(equalToConstant: size.width).isActive = true
        }

        if size.height != 0 {
            heightAnchor.constraint(equalToConstant: size.height).isActive = true
        }
    }
}

@available(iOS 11.0, *)
public extension UIView {
    
    func setNavigationBarShadow() {
        self.backgroundColor = .white
        self.clipsToBounds = true
        self.layer.masksToBounds = false
        self.layer.shadowRadius = 1
        self.layer.shadowOpacity = 0.2
        self.layer.shadowOffset = CGSize(width: 0, height: 1)
        self.layer.shadowColor = UIColor.black.cgColor
    }
	func constraintsForAnchoringTo(boundsOf superView: UIView) -> [NSLayoutConstraint] {
        return [
            self.topAnchor.constraint(equalTo: superView.safeAreaLayoutGuide.topAnchor),
            self.leftAnchor.constraint(equalTo: superView.safeAreaLayoutGuide.leftAnchor),
            self.bottomAnchor.constraint(equalTo: superView.safeAreaLayoutGuide.bottomAnchor),
            self.rightAnchor.constraint(equalTo: superView.safeAreaLayoutGuide.rightAnchor)
        ]
    }
    
    func asCircle() {
        self.layer.cornerRadius = self.frame.width / 2;
        self.layer.masksToBounds = true
    }
    
    func dropShadow(color: UIColor = UIColor.black, offset: CGSize = CGSize(width: 1, height: 1), scale: Bool = true) {
      layer.masksToBounds = false
      layer.shadowColor = color.cgColor
      layer.shadowOpacity = 0.5
      layer.shadowOffset = CGSize(width: -1, height: 1)
      layer.shadowRadius = 1

      layer.shadowPath = UIBezierPath(rect: bounds).cgPath
      layer.shouldRasterize = true
      layer.rasterizationScale = scale ? UIScreen.main.scale : 1
    }
    func dropShadow(color: UIColor = UIColor.black, offset: CGSize = CGSize(width: 1, height: 1), opacity: Float = 2, radius: CGFloat = 0.8, cornerRadius: CGFloat) {
        let shadowLayer = CAShapeLayer()
        shadowLayer.path = UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius).cgPath
        shadowLayer.fillColor = UIColor.white.cgColor

        shadowLayer.shadowColor = color.cgColor
        shadowLayer.shadowPath = shadowLayer.path
        shadowLayer.shadowOffset = offset
        shadowLayer.shadowOpacity = opacity
        shadowLayer.shadowRadius = radius

        layer.insertSublayer(shadowLayer, at: 0)
    }
    func curvedviewShadow(cornerRadius: CGFloat = 8){
        self.clipsToBounds = false
        self.layer.masksToBounds = false
        
        self.layer.cornerRadius = cornerRadius
        self.layer.shadowOpacity = 0.35
        self.layer.shadowOffset = CGSize(width: 0.0, height: 0.0)
        self.layer.shadowRadius = 3.0
        self.layer.shadowColor = UIColor.gray.cgColor
        self.layer.maskedCorners = [.layerMaxXMaxYCorner, .layerMinXMaxYCorner,
                                    .layerMinXMinYCorner, .layerMaxXMinYCorner]
    }
}

@available(iOS 11.0, *)
public extension UIView {
	
    func shake(){
        let animation = CABasicAnimation(keyPath: "position")
        animation.duration = 0.07
        animation.repeatCount = 3
        animation.autoreverses = true
        animation.fromValue = NSValue(cgPoint: CGPoint(x: self.center.x - 10, y: self.center.y))
        animation.toValue = NSValue(cgPoint: CGPoint(x: self.center.x + 10, y: self.center.y))
        self.layer.add(animation, forKey: "position")
    }
	
	func addDiagonalGradiant(_ colors: [UIColor]) {
        let GradientLayerName = "diagonalGradientLayer"
        
        if let oldlayer = self.layer.sublayers?.filter({$0.name == GradientLayerName}).first {
            oldlayer.removeFromSuperlayer()
        }
        
        let gradientLayer = CAGradientLayer()
		gradientLayer.colors = colors.map { $0.cgColor }
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1 )
        gradientLayer.frame = self.bounds
        gradientLayer.masksToBounds = true
        gradientLayer.cornerRadius = self.layer.cornerRadius
        gradientLayer.maskedCorners = self.layer.maskedCorners
        gradientLayer.name = GradientLayerName
        
        
        self.layer.insertSublayer(gradientLayer, at: 0)
    }
    
    func addVerticalGradiant(withColors colors: [UIColor] = []) {
        let GradientLayerName = "vgradientLayer"
        
        if let oldlayer = self.layer.sublayers?.filter({$0.name == GradientLayerName}).first {
            oldlayer.removeFromSuperlayer()
        }
        
        let gradientLayer = CAGradientLayer()
		gradientLayer.colors = colors.map { $0.cgColor }
		gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
		gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        gradientLayer.frame = self.bounds
        gradientLayer.masksToBounds = true
        gradientLayer.cornerRadius = self.layer.cornerRadius
        gradientLayer.maskedCorners = self.layer.maskedCorners
        gradientLayer.name = GradientLayerName

        
        self.layer.insertSublayer(gradientLayer, at: 0)
    }
    
    
    func addHorizontalGradiant(withColors colors: [UIColor] = []) {
        let GradientLayerName = "hgradientLayer"
        
        if let oldlayer = self.layer.sublayers?.filter({$0.name == GradientLayerName}).first {
            oldlayer.removeFromSuperlayer()
        }
        
        let gradientLayer = CAGradientLayer()
        gradientLayer.colors = colors.map { $0.cgColor }
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        gradientLayer.frame = self.bounds
        gradientLayer.masksToBounds = true
        gradientLayer.cornerRadius = self.layer.cornerRadius
        gradientLayer.maskedCorners = self.layer.maskedCorners
        gradientLayer.name = GradientLayerName

        
        self.layer.insertSublayer(gradientLayer, at: 0)
    }
    
    
    func addDashedBorder(_ color: UIColor = UIColor.black, withWidth width: CGFloat = 2, cornerRadius: CGFloat = 10, dashPattern: [NSNumber] = [8,6]) {
        
        let shapeLayer = CAShapeLayer()
        
        shapeLayer.bounds = bounds
        shapeLayer.position = CGPoint(x: bounds.width/2, y: bounds.height/2)
        shapeLayer.fillColor = nil
        shapeLayer.strokeColor = color.cgColor
        shapeLayer.lineWidth = width
        shapeLayer.lineJoin = CAShapeLayerLineJoin.round // Updated in swift 4.2
        shapeLayer.lineDashPattern = dashPattern
        shapeLayer.path = UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius).cgPath
        
        self.layer.addSublayer(shapeLayer)
    }
    
    func AddShadowToButton(cornerRadiusVal : CGFloat , shadowRadiusVal : CGFloat)  {
        
        self.layer.cornerRadius = cornerRadiusVal
        self.layer.shadowRadius = shadowRadiusVal
        self.layer.masksToBounds = true
        self.layer.shadowColor = UIColor.gray.cgColor
        self.layer.shadowOpacity = 1.0
        self.layer.shadowOffset = CGSize(width: 0.0, height: 0.0)
    }
	
}

public extension UILabel {
    func configureLabel(color: UIColor, font: UIFont) {
        self.textColor = color
        self.font = font
    }
}

extension UIViewController {
    func setupKeyboardObservers(button: UIButton, constraint: NSLayoutConstraint, initialConstant: CGFloat) {
        NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: nil) { [weak self] notification in
            self?.keyboardWillShow(notification: notification, constraint: constraint)
        }

        NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: nil) { [weak self] notification in
            self?.keyboardWillHide(notification: notification, constraint: constraint, initialConstant: initialConstant)
        }
    }

    func keyboardWillShow(notification: Notification, constraint: NSLayoutConstraint) {
        if let keyboardSize = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue {
            UIView.animate(withDuration: 0.3) { [weak self] in
                guard let strongSelf = self else { return }
                constraint.constant = keyboardSize.height
                strongSelf.view.layoutIfNeeded()
            }
        }
    }

    func keyboardWillHide(notification: Notification, constraint: NSLayoutConstraint, initialConstant: CGFloat) {
        UIView.animate(withDuration: 0.3) { [weak self] in
            guard let strongSelf = self else { return }
            constraint.constant = initialConstant
            strongSelf.view.layoutIfNeeded()
        }
    }
}
