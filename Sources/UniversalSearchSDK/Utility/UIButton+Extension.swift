//
//  UIButton+Extension.swift
//  MintoakBase
//
//  Created by Rajan Patel on 08/01/26.
//

import UIKit

extension UIButton {
  func setBackgroundColor(_ color: UIColor, forState controlState: UIControl.State) {
    let colorImage = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { _ in
      color.setFill()
      UIBezierPath(rect: CGRect(x: 0, y: 0, width: 1, height: 1)).fill()
    }
    setBackgroundImage(colorImage, for: controlState)
  }
}

@available(iOS 11.0, *)
extension CACornerMask {
    public static var topLeft: CACornerMask     = .layerMinXMinYCorner//{ get }
    public static var topRight: CACornerMask    = .layerMaxXMinYCorner //{ get }
    public static var bottomLeft: CACornerMask  = .layerMinXMaxYCorner //{ get }
    public static var bottomRight: CACornerMask = .layerMaxXMaxYCorner //{ get }
}

extension UserDefaults {

    // MARK: - SmartBar Filter Context (passed via deeplink sb_* query params)

    var smartBarFilterTids: [String]? {
        get {
            UserDefaults.standard.array(forKey: "smartBarFilterTids") as? [String]
        } set {
            UserDefaults.standard.set(newValue, forKey: "smartBarFilterTids")
        }
    }

    var smartBarFilterDate: String? {
        get {
            UserDefaults.standard.string(forKey: "smartBarFilterDate")
        } set {
            UserDefaults.standard.set(newValue, forKey: "smartBarFilterDate")
        }
    }

    var smartBarFilterStartDate: String? {
        get {
            UserDefaults.standard.string(forKey: "smartBarFilterStartDate")
        } set {
            UserDefaults.standard.set(newValue, forKey: "smartBarFilterStartDate")
        }
    }

    var smartBarFilterEndDate: String? {
        get {
            UserDefaults.standard.string(forKey: "smartBarFilterEndDate")
        } set {
            UserDefaults.standard.set(newValue, forKey: "smartBarFilterEndDate")
        }
    }

    func clearSmartBarFilter() {
        smartBarFilterTids = nil
        smartBarFilterDate = nil
        smartBarFilterStartDate = nil
        smartBarFilterEndDate = nil
    }
    
    var SpotlightAIAssistViewed: Bool? {
        get {
            UserDefaults.standard.bool(forKey: "SpotlightAIAssistViewed")
        } set {
            UserDefaults.standard.set(newValue, forKey: "SpotlightAIAssistViewed")
        }
    }
    
}

extension UIButton {
    func underline() {
        guard let title = self.titleLabel else { return }
        guard let tittleText = title.text else { return }
        let attributedString = NSMutableAttributedString(string: (tittleText))
        attributedString.addAttribute(NSAttributedString.Key.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: (tittleText.count)))
        self.setAttributedTitle(attributedString, for: .normal)
    }
}

public extension UIButton {
    func configureButton(title: String?, titleColor: UIColor, font: UIFont, bgColor: UIColor) {
        if let t = title {
            self.setTitle(t, for: .normal)
        }
        self.backgroundColor = bgColor
        self.setTitleColor(titleColor, for: .normal)
        self.titleLabel?.font = font
    }
}
