//
//  Constant.swift
//  MintoakBase
//
//  Created by Rajan Patel on 10/12/25.
//

import Foundation
import UIKit
import Security

// MARK: - Constants

struct Constant {

    /// Base URL for the SmartBar web app
    #if DEBUG
    static let baseWebViewURL = "https://uat-universal-ui-hbank.mintoak.com"
    #else
    // For production, use bundled HTML or CDN
    static let baseWebViewURL = "https://uat-universal-ui-hbank.mintoak.com"
    #endif

    /// WebView URL with dev/prod split (mirrors BaseUrl.smartBarWebViewURL without host-app dependency)
    #if DEBUG
    static let smartBarWebViewURL = "https://dev-universal-ui-hbank.mintoak.com"
    #else
    static let smartBarWebViewURL = "https://uat-universal-ui-hbank.mintoak.com"
    #endif

    /// baseUrl of Dify environment
    #if DEBUG
    static let baseUrl = "https://dev-vagent-hbank.mintoak.com/api/"
    static let liveKitServerUrl = "wss://dev-livekit-public.mintoak.com"
    #else
    static let baseUrl = "https://vagent-hbank.mintoak.com/api/"
    static let liveKitServerUrl = "wss://livekit-public.mintoak.com"
    #endif

    /// Authorization Token — loaded from Keychain at runtime.
    /// Call `Constant.configure(authToken:)` during app launch with a server-provided token.
    private(set) static var authToken: String = {
        // Attempt to load from Keychain first
        if let stored = KeychainHelper.load(key: "com.abcmerchant.authToken") {
            return "Bearer \(stored)"
        }
        #if DEBUG
        // Fallback for DEBUG only — remove before production release
        return "Bearer app-YoptcfqddVcHrfrElv1T7G9p"
        #else
        return ""
        #endif
    }()

    /// Configure auth token at runtime (e.g. from server config or login response)
    static func configure(authToken token: String) {
        authToken = "Bearer \(token)"
        KeychainHelper.save(key: "com.abcmerchant.authToken", value: token)
    }

    /// Agent Name
    static let agentName = "Sarvam-HDFC" //"HDFC-Bank-Service-Agent"
    
    /// Get API End Points
    static let getConversationbyId = "v1/messages"

    /// Post  API End Points
    static let intent = "v1/dify/universal-search/intent"
    static let chatMessage = "v1/dify/universal-search/chat"

    /// Deep Link screen name to internal URL mapping
    static let ScreenRoutes: [String: String] = [
        "settlement": "hdfc://mintoak.com/TransactionFragment/fragment/2",
        "transactions": "hdfc://mintoak.com/PaymentsFragment/fragment/0/TransactionsViewMoreActivity/activity",
        "reports": "hdfc://mintoak.com/ProfileFragment/fragment/4/ReportListActivity/activity",
        "help": "hdfc://mintoak.com/ServicePopUp/fragment/4",
        "support": "hdfc://mintoak.com/ServicePopUp/fragment/4",
        "qrcode": "hdfc://mintoak.com/PaymentsFragment/fragment/0/?type=c&paymentModeId=2",
        "qr": "hdfc://mintoak.com/PaymentsFragment/fragment/0/?type=c&paymentModeId=2",
        "team": "hdfc://mintoak.com/ProfileFragment/fragment/4/StaffManagement/activity",
        "staff": "hdfc://mintoak.com/ProfileFragment/fragment/4/StaffManagement/activity",
        "settings": "hdfc://mintoak.com/ProfileFragment/fragment/4/SettingsActivity/activity",
        "sales": "hdfc://mintoak.com/ThreeSixtyViewFragment/fragment/1",
        "dashboard": "hdfc://mintoak.com/ThreeSixtyViewFragment/fragment/1",
        "payments": "hdfc://mintoak.com/PaymentsFragment/fragment/0",
        "loan": "hdfc://mintoak.com/LendingDashboard/activity",
        "lending": "hdfc://mintoak.com/LendingDashboard/activity",
        "paymentlink": "hdfc://mintoak.com/PaymentsFragment/fragment/0/?type=c&paymentModeId=4",
        "pay_link": "hdfc://mintoak.com/PaymentsFragment/fragment/0/?type=c&paymentModeId=4",
        "tapphone": "hdfc://mintoak.com/PaymentsFragment/fragment/0/?type=c&paymentModeId=7",
        "tap_phone": "hdfc://mintoak.com/PaymentsFragment/fragment/0/?type=c&paymentModeId=7"
    ]
}

enum SearchType: String, Codable {
    case thinking
    case sectionHeader
    case content
    case settlement
    case customView
    case faq
    case voiceCall
    case deeplink
    case report
    case action1
    case ordernRequest
    case users
    case helpnsupport
    case genUI
    case pieChart
    case barGraph
    case transactionPerformance
    case recentTransactions
    case orderRequestsCard
    case unknown
}

enum UniversalSearchStorage {
    static let historyKey = "universal_search_history"
}

public extension NSNotification.Name {

    static let AIAssistTapped = Notification.Name("AIAssistTapped")
    static let floatingEndCallTapped = Notification.Name("floatingEndCallTapped")
    static let floatingScreenShareTapped = Notification.Name("floatingScreenShareTapped")
    static let floatingChatTapped = Notification.Name("floatingChatTapped")    
}

// MARK: - Keychain Helper (used by Constant for secure token storage)

private enum KeychainHelper {

    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        _ = SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        _ = SecItemAdd(attributes as CFDictionary, nil)
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        _ = SecItemDelete(query as CFDictionary)
    }
}
