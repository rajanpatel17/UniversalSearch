//
//  CallActivityAttributes.swift
//  MintoakBase
//
//  ActivityAttributes for the Live Activity shown in the Dynamic Island
//  during an active LiveKit call.
//
//  NOTE: This file has target membership in BOTH the main app (HDFC) and
//  the CallActivityWidget extension. Do NOT create a separate copy.
//

#if canImport(ActivityKit)
import ActivityKit
import Foundation

struct CallActivityAttributes: ActivityAttributes {
    /// The date the call started — used for the auto-updating timer.
    var callStartDate: Date

    /// Dynamic state updated while the activity is live.
    struct ContentState: Codable, Hashable {
        var isScreenSharing: Bool
    }
}
#endif
