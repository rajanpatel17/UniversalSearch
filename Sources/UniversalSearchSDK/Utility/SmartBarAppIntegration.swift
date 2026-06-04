//
//  DateUtility.swift
//  MintoakBase
//
//  Created by Rajan Patel on 10/12/25.
//

import Foundation
import UIKit

// MARK: - SmartBar Configuration

/// Global configuration for SmartBar
struct SmartBarConfiguration {
    /// Enable/disable SmartBar suggestions
    static var isEnabled: Bool = true
    
    /// Minimum characters to trigger suggestions
    static var minQueryLength: Int = 2
    
    /// Debounce delay in seconds
    static var debounceDelay: TimeInterval = 0.15
    
    /// Maximum suggestions to show
    static var maxSuggestions: Int = 5
}

// MARK: - SmartBar App Integration

/// Utility class for integrating SmartBar into the app lifecycle
class SmartBarAppIntegration {
    
    // MARK: - Singleton
    
    static let shared = SmartBarAppIntegration()
    
    // MARK: - Properties
    
    private var isInitialized = false
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Initialize SmartBar on app launch
    /// Call this in AppDelegate.application(_:didFinishLaunchingWithOptions:)
    func initialize() {
        guard !isInitialized else { return }
        
        // Pre-warm the bridge
        _ = SmartBarBridge.shared
        
        isInitialized = true
        print("[SmartBar] Initialized successfully")
    }
    
    /// Handle app entering background
    func handleDidEnterBackground() {
        // Cache cleanup if needed
    }
    
    /// Handle app becoming active
    func handleDidBecomeActive() {
        // Refresh cache if needed
    }
    
    /// Handle memory warning
    func handleMemoryWarning() {
        // Clear caches on memory pressure
        print("[SmartBar] Memory warning - clearing caches")
    }
    
    // MARK: - Debug Helpers
    
    /// Test intent detection
    func testIntentDetection(_ query: String) {
        #if DEBUG
        print("[SmartBar] Testing query: '\(query)'")
        let suggestions = SmartBarBridge.shared.getSuggestionsSync(for: query)
        
        if suggestions.isEmpty {
            print("[SmartBar] No suggestions found")
        } else {
            for (index, suggestion) in suggestions.enumerated() {
                print("[SmartBar] \(index + 1). '\(suggestion.intentId)' (score: \(String(format: "%.2f", suggestion.score)))")
                print("         Icon: \(suggestion.icon)")
                print("         Text: \(suggestion.text)")
            }
        }
        #endif
    }
    
    /// Print supported intents
    func printSupportedIntents() {
        #if DEBUG
        print("[SmartBar] Supported intents:")
        let categories: [IntentCategory] = [.settlement, .sales, .transactions, .collect, .reports, .help]
        for category in categories {
            print("  - \(category.displayName)")
        }
        #endif
    }
}

// MARK: - UIViewController Extension

extension UIViewController {
    
    /// Check if SmartBar is enabled
    var isSmartBarEnabled: Bool {
        return SmartBarConfiguration.isEnabled
    }
}
