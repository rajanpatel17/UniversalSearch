//
//  DateUtility.swift
//  MintoakBase
//
//  Created by Rajan Patel on 10/12/25.
//

import UIKit

// MARK: - Localizable Stub
extension String {
    func localize() -> String {
        return NSLocalizedString(self, comment: "")
    }
}

// MARK: - SpotLightSDK Stubs
public protocol SpotLightListener: AnyObject {
    func onCoachmarkClosed(index: Int)
    func onCoachmarkNextClicked(index: Int, isLastIndex: Bool)
    func onCoachmarkBackClicked(index: Int)
}

public enum CoachmarkNextButtonMode {
    case text(CMText)
}

public enum CoachmarkPreviousButtonMode {
    case image(tint: UIColor)
}

public enum CoachmarkShape {
    case rect
}

public struct CMText {
    public let text: String
    public let color: UIColor
    public let bgColor: UIColor
    public let font: UIFont
    
    public init(text: String, color: UIColor, bgColor: UIColor, font: UIFont) {
        self.text = text
        self.color = color
        self.bgColor = bgColor
        self.font = font
    }
}

public struct BorderConfig {
    public let width: CGFloat
    public let color: UIColor
    public let priority: Int
    
    public init(width: CGFloat, color: UIColor, priority: Int) {
        self.width = width
        self.color = color
        self.priority = priority
    }
}

public struct CoachmarkTarget {
    public let targetView: UIView
    public let title: CMText
    public let description: CMText
    public let shape: CoachmarkShape
    public let paddingDp: CGFloat
    public let leftBarFillColor: UIColor
    public let nextButtonMode: CoachmarkNextButtonMode
    public let previousButtonMode: CoachmarkPreviousButtonMode
    public let showAnimation: Bool
    public let needBorder: Bool
    public let leftBarShow: Bool
    public let borders: [BorderConfig]
    public let showBottomButtonStack: Bool
    
    public init(targetView: UIView, title: CMText, description: CMText, shape: CoachmarkShape, paddingDp: CGFloat, leftBarFillColor: UIColor, nextButtonMode: CoachmarkNextButtonMode, previousButtonMode: CoachmarkPreviousButtonMode, showAnimation: Bool, needBorder: Bool, leftBarShow: Bool, borders: [BorderConfig], showBottomButtonStack: Bool) {
        self.targetView = targetView
        self.title = title
        self.description = description
        self.shape = shape
        self.paddingDp = paddingDp
        self.leftBarFillColor = leftBarFillColor
        self.nextButtonMode = nextButtonMode
        self.previousButtonMode = previousButtonMode
        self.showAnimation = showAnimation
        self.needBorder = needBorder
        self.leftBarShow = leftBarShow
        self.borders = borders
        self.showBottomButtonStack = showBottomButtonStack
    }
}

public class SpotLightManager {
    public init(activity: UIViewController, listener: SpotLightListener?) {}
    public func showCoachmarks(targetList: [CoachmarkTarget]) {}
}
