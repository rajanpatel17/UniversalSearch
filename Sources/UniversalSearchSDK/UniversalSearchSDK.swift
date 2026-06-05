//
//  UniversalSearchSDK.swift
//  UniversalSearchSDK
//
//  Created by Rajan Patel on 25/03/26.
//

import Foundation
import UIKit

public struct UniversalSearchSessionData {
    public let sessionId: String
    public let loginId: String
    public let userName: String
    public let userRole: String
    public let fcmToken: String
    public let tid: String
    public let storeCount: Int
    public let isChainOwner: Bool
    
    public init(sessionId: String, loginId: String, userName: String, userRole: String, fcmToken: String, tid: String, storeCount: Int, isChainOwner: Bool) {
        self.sessionId = sessionId
        self.loginId = loginId
        self.userName = userName
        self.userRole = userRole
        self.fcmToken = fcmToken
        self.tid = tid
        self.storeCount = storeCount
        self.isChainOwner = isChainOwner
    }
}

public protocol UniversalSearchDelegate: AnyObject {
    /// Provide current session data for Universal Search
    func getSessionData() -> UniversalSearchSessionData?
    
    /// Handle Analytics events fired from Universal Search
    func logEvent(eventName: String, params: [String: String])
    
    /// Let the host app handle internal deep links that are specific to the host application
    func handleDeepLink(_ urlString: String)
    
    /// Let the host app open transaction details
    func openTransactionDetail(transactionId: String)
    
    /// Let the host app fetch an API response since ServiceAPI is tied to the main project
    func getServiceTemplatesAndDashboard(completion: @escaping (Any?, Any?) -> Void)
    
    /// Let the host app open a view controller or handle a user role modification screen
    func handleUserAccessList(mobile: String)
    
    /// Fetch all TIDs for the user to be used in some logic handled internally or by the host app
    func getAllTids() -> [String]
    
    /// Gets TID/MID name dict mapping
    func getTidMidNameDict() -> [String: String]
    
    /// Let the host app start the deeplink coordinator
    func startDeeplinkCoordinator()
}

public extension UniversalSearchDelegate {
    func getSessionData() -> UniversalSearchSessionData? { return nil }
    func logEvent(eventName: String, params: [String: String]) {}
    func handleDeepLink(_ urlString: String) {}
    func openTransactionDetail(transactionId: String) {}
    func getServiceTemplatesAndDashboard(completion: @escaping (Any?, Any?) -> Void) { completion(nil, nil) }
    func handleUserAccessList(mobile: String) {}
    func getAllTids() -> [String] { return [] }
    func getTidMidNameDict() -> [String: String] { return [:] }
    func startDeeplinkCoordinator() {}
}

public final class UniversalSearchManager {
    public static let shared = UniversalSearchManager()
    
    public static var bundle: Bundle {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle(for: UniversalSearchManager.self)
        #endif
    }
    
    public weak var delegate: UniversalSearchDelegate?
    public private(set) var sessionData: UniversalSearchSessionData?
    
    private init() {}
    
    /// Sets the session data for Universal Search
    public func setSessionData(_ data: UniversalSearchSessionData) {
        self.sessionData = data
    }
    
    /// Convinence method to setup session data
    public func setupSession(sessionId: String, loginId: String, userName: String, userRole: String, fcmToken: String, tid: String, storeCount: Int) {
        let data = UniversalSearchSessionData(
            sessionId: sessionId,
            loginId: loginId,
            userName: userName,
            userRole: userRole,
            fcmToken: fcmToken,
            tid: tid,
            storeCount: storeCount,
            isChainOwner: storeCount > 1
        )
        self.setSessionData(data)
    }
    
    /// Exposes a way to show the floating AI assist view
    public func showFloatingAIAssist() {
        // FloatingAIAssistManager.shared.show() will be called internally once imported
        FloatingAIAssistManager.shared.show()
    }
    
    /// Exposes a way to hide the floating AI assist view
    public func hideFloatingAIAssist() {
        // FloatingAIAssistManager.shared.hide() will be called internally once imported
        FloatingAIAssistManager.shared.hide()
    }
    
    public func expandAIAssist() {
        // FloatingAIAssistManager.shared.expandView() will be called internally once imported
        FloatingAIAssistManager.shared.floatingView?.expandView()
    }
    
    public func openSmartBarWebViewWithDeepLink() {
        // FloatingAIAssistManager.shared.handleAIAssistTapped() will be called internally open open SmartBarWebView With DeepLink
        FloatingAIAssistManager.shared.handleAIAssistTapped()
    }
    
    @MainActor public func spotlightAIAssistViewed() {
        FloatingAIAssistManager.shared.showSpotlightIfNeeded()
    }
    
    /// Clears the session, ends any active LiveKit calls, and cleans up resources.
    /// Should be called when the user logouts or the session expires.
    @MainActor public func callEndAIAssist() {
        self.sessionData = nil
        self.hideFloatingAIAssist()
        Task {
            await LiveKitCallManager.shared.disconnect()
            SmartBarWebViewManager.shared.clearCachedWebViewIfAllowed()
        }
    }

}
