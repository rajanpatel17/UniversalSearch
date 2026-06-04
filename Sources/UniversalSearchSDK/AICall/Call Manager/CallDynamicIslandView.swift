//
//  CallDynamicIslandView.swift
//  MintoakBase
//
//  Manages the Live Activity shown in the Dynamic Island during an active
//  LiveKit call. Uses Apple's ActivityKit for native Dynamic Island integration.
//

#if canImport(ActivityKit)
import ActivityKit
import Foundation

@available(iOS 16.2, *)
@MainActor
final class CallDynamicIslandManager {

    static let shared = CallDynamicIslandManager()

    private init() {
        #if DEBUG
        let authInfo = ActivityAuthorizationInfo()
        print("[CallDynamicIsland] Manager initialized")
        print("[CallDynamicIsland] Activities enabled: \(authInfo.areActivitiesEnabled)")
        print("[CallDynamicIsland] Frequent push enabled: \(authInfo.frequentPushesEnabled)")
        #endif

        endAllStaleActivities()
        observeCallState()
    }

    private var currentActivity: Activity<CallActivityAttributes>?
    private var observers: [NSObjectProtocol] = []

    // MARK: - Observe LiveKit state

    private func observeCallState() {
        // # When AI Call Integrate
        let connObs = NotificationCenter.default.addObserver(
            forName: .liveKitCallConnectionChanged,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let connected = notification.userInfo?["isConnected"] as? Bool ?? false
            #if DEBUG
            print("[CallDynamicIsland] Connection notification — isConnected: \(connected)")
            #endif
            if connected {
                self.startActivity()
            } else {
                self.endActivity()
            }
        }
        observers.append(connObs)

        let shareObs = NotificationCenter.default.addObserver(
            forName: .liveKitScreenShareStateChanged,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let isShared = notification.userInfo?["isScreenShared"] as? Bool ?? false
            #if DEBUG
            print("[CallDynamicIsland] Screen share notification — isScreenShared: \(isShared)")
            #endif
            self.updateScreenShare(isShared)
        }
        observers.append(shareObs)
    }

    // MARK: - Activity Lifecycle

    func startActivity() {
        guard currentActivity == nil else {
            #if DEBUG
            if let id = currentActivity?.id {
                print("[CallDynamicIsland] startActivity skipped — activity exists: \(id)")
            }
            #endif
            return
        }

        let authInfo = ActivityAuthorizationInfo()
        guard authInfo.areActivitiesEnabled else {
            #if DEBUG
            print("[CallDynamicIsland] Live Activities NOT enabled by user")
            #endif
            return
        }

        let attributes = CallActivityAttributes(callStartDate: Date())
        let initialState = CallActivityAttributes.ContentState(isScreenSharing: false)

        do {
            let activity = try Activity<CallActivityAttributes>.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: nil
            )
            currentActivity = activity
            #if DEBUG
            print("[CallDynamicIsland] Started Live Activity: \(activity.id)")
            #endif
        } catch {
            #if DEBUG
            print("[CallDynamicIsland] Failed to start Live Activity: \(error)")
            #endif
        }
    }

    func endActivity() {
        guard let activity = currentActivity else { return }
        currentActivity = nil

        let finalState = CallActivityAttributes.ContentState(isScreenSharing: false)

        Task {
            await activity.end(
                .init(state: finalState, staleDate: nil),
                dismissalPolicy: .immediate
            )
            #if DEBUG
            print("[CallDynamicIsland] Ended Live Activity: \(activity.id)")
            #endif
        }
    }

    func updateScreenShare(_ isSharing: Bool) {
        guard let activity = currentActivity else { return }

        let updatedState = CallActivityAttributes.ContentState(isScreenSharing: isSharing)

        Task {
            await activity.update(.init(state: updatedState, staleDate: nil))
            #if DEBUG
            print("[CallDynamicIsland] Updated screen share state: \(isSharing)")
            #endif
        }
    }

    // MARK: - Cleanup

    private func endAllStaleActivities() {
        let existingActivities = Activity<CallActivityAttributes>.activities
        #if DEBUG
        print("[CallDynamicIsland] Found \(existingActivities.count) existing activities at launch")
        #endif
        for activity in existingActivities {
            let state = CallActivityAttributes.ContentState(isScreenSharing: false)
            Task {
                await activity.end(
                    .init(state: state, staleDate: nil),
                    dismissalPolicy: .immediate
                )
            }
        }
    }
}
#endif
