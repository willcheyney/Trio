import Foundation

/// The latest glucose readings Trio shares with its home screen, lock screen and StandBy widget.
///
/// Trio saves a snapshot to the App Group defaults whenever a reading arrives, and the widget extension
/// loads it when WidgetKit asks for a timeline. This file is compiled into both targets.
struct GlucoseWidgetSnapshot: Codable, Equatable {
    struct Reading: Codable, Equatable {
        let date: Date
        /// Glucose in mg/dL, as Trio stores it.
        let glucose: Int
    }

    /// Readings from the last few hours, newest first.
    let readings: [Reading]
    /// Trend arrow of the newest reading, e.g. "→".
    let direction: String?
    /// "mg/dL" or "mmol/L".
    let unit: String
    /// The user's low and high glucose limits, in mg/dL.
    let low: Decimal
    let high: Decimal

    /// WidgetKit kind of the glucose widget, used to reload its timelines.
    static let kind = "TrioGlucoseWidget"

    private static let defaultsKey = "glucoseWidgetSnapshot"

    private static var defaults: UserDefaults? {
        guard let suiteName = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String else { return nil }
        return UserDefaults(suiteName: suiteName)
    }

    static func load() -> GlucoseWidgetSnapshot? {
        guard let data = defaults?.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(GlucoseWidgetSnapshot.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        Self.defaults?.set(data, forKey: Self.defaultsKey)
    }
}
