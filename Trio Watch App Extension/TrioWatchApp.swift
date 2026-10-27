import SwiftUI
import UserNotifications
import WatchKit

@main struct TrioWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase

    /// Background refresh that fetches the latest reading from the phone for the complication.
    private static let complicationRefresh = "complicationRefresh"

    init() {
        WatchNotificationHandler.shared.configure()
        // Activate WatchConnectivity at launch, including background launches for the complication.
        _ = WatchState.shared
    }

    /// Asks watchOS to wake the app in about 15 minutes. With the complication on the active face, watchOS
    /// allows up to four of these an hour. Only call this once the app has launched: during `init` SwiftUI has not
    /// yet set up background task handling, and watchOS terminates the app.
    private static func scheduleComplicationRefresh() {
        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: Date().addingTimeInterval(15 * 60),
            userInfo: complicationRefresh as NSString
        ) { error in
            if let error {
                Task { await WatchLogger.shared.log("⌚️ Could not schedule complication refresh: \(error)") }
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            TrioMainWatchView()
                .onAppear { Self.scheduleComplicationRefresh() }
        }
        .onChange(of: scenePhase) { _, newScenePhase in
            if newScenePhase == .background {
                Self.scheduleComplicationRefresh()
                Task {
                    await WatchLogger.shared.flushPersistedLogs()
                }
            }
        }
        .backgroundTask(.watchConnectivity) {
            await WatchState.shared.waitForPendingContent()
        }
        .backgroundTask(.appRefresh(Self.complicationRefresh)) {
            await WatchState.shared.refreshFromPhone()
            await MainActor.run { Self.scheduleComplicationRefresh() }
        }
    }
}
