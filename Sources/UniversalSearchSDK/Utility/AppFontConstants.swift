//
//  AppFontConstants.swift
//  MintoakBase
//
//  Created by Rajan Patel on 16/04/25.
//

import UIKit

enum AppFontFamily {
    case system
    case inter
}

enum AppFontWeight {
    case light
    case regular
    case medium
    case semiBold
    case bold
    case black
    case italic

    func fontName(for family: AppFontFamily) -> String? {
        switch (family, self) {
        case (.system, _):
            return nil // No font name for system fonts
        
        case (.inter, .light): return "Inter-Light"
        case (.inter, .regular): return "Inter-Regular"
        case (.inter, .medium): return "Inter-Medium"
        case (.inter, .semiBold): return "Inter-SemiBold"
        case (.inter, .bold): return "Inter-Bold"
        case (.inter, .black): return "Inter-Black"
        case (.inter, .italic): return "Inter-Italic"
        }
    }
}

struct AppFonts {
    
    static var currentFamily: AppFontFamily = .inter /// Change this globally to use different font family
    
    static func font(_ weight: AppFontWeight, size: CGFloat) -> UIFont {
        if currentFamily == .system {
            return UIFont.systemFont(ofSize: size, weight: systemWeight(for: weight))
        }
        guard let fontName = weight.fontName(for: currentFamily),
              let customFont = UIFont(name: fontName, size: size) else {
            return UIFont.systemFont(ofSize: size, weight: systemWeight(for: weight))
        }
        return customFont
    }

    
    // MARK: - Shortcut Methods
    static func FONT_REGULAR(_ family: AppFontFamily? = nil, size: CGFloat) -> UIFont {
        return font(.regular, size: size, family: family)
    }
    
    static func FONT_MEDIUM(_ family: AppFontFamily? = nil, size: CGFloat) -> UIFont {
        return font(.medium, size: size, family: family)
    }
    
    static func FONT_SEMIBOLD(_ family: AppFontFamily? = nil, size: CGFloat) -> UIFont {
        return font(.semiBold, size: size, family: family)
    }
    
    static func FONT_BOLD(_ family: AppFontFamily? = nil, size: CGFloat) -> UIFont {
        return font(.bold, size: size, family: family)
    }
    
    static func FONT_LIGHT(_ family: AppFontFamily? = nil, size: CGFloat) -> UIFont {
        return font(.light, size: size, family: family)
    }
    
    static func FONT_ITALIC(_ family: AppFontFamily? = nil, size: CGFloat) -> UIFont {
        return font(.italic, size: size, family: family)
    }
    
    // MARK: - Private Helpers
    private static func font(_ weight: AppFontWeight, size: CGFloat, family: AppFontFamily?) -> UIFont {
        let selectedFamily = family ?? currentFamily
        if selectedFamily == .system {
            return UIFont.systemFont(ofSize: size, weight: systemWeight(for: weight))
        }
        guard let fontName = weight.fontName(for: selectedFamily),
              let customFont = UIFont(name: fontName, size: size) else {
            return UIFont.systemFont(ofSize: size, weight: systemWeight(for: weight))
        }
        return customFont
    }

    private static func systemWeight(for weight: AppFontWeight) -> UIFont.Weight {
        switch weight {
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semiBold: return .semibold
        case .bold: return .bold
        case .black: return .black
        case .italic: return .regular
        }
    }
    
}
