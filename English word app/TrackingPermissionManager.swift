//
//  TrackingPermissionManager.swift
//  English word app
//
//  Created by Codex on 2026/06/15.
//

import Foundation

#if os(iOS) && canImport(AppTrackingTransparency)
import AppTrackingTransparency
#endif

@MainActor
enum TrackingPermissionManager {
    static func requestIfNeeded() async {
#if os(iOS) && canImport(AppTrackingTransparency)
        guard #available(iOS 14.0, *) else {
            return
        }

        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else {
            return
        }

        _ = await ATTrackingManager.requestTrackingAuthorization()
#endif
    }
}
