import SwiftUI
import WidgetKit

// MARK: - Timeline Entry

struct TrioWatchComplicationEntry: TimelineEntry {
    let date: Date
    /// Latest glucose as the watch app displays it, e.g. "6.7"; nil before the first reading arrives.
    let glucose: String?
    /// Raw trend of the latest reading, e.g. "Flat" or "FortyFiveUp".
    let trend: String?
    /// Change from the previous reading as the watch app displays it, e.g. "+0.1".
    let delta: String?
    /// Trio's glucose colour for the latest reading, as a hex string.
    let colorHex: String?
    let readingDate: Date?

    /// A reading older than this is shown as stale.
    static let staleAfter: TimeInterval = 15 * 60
    /// A reading older than this is not shown at all.
    static let expiredAfter: TimeInterval = 60 * 60

    var age: TimeInterval? { readingDate.map { max(0, date.timeIntervalSince($0)) } }
    var isStale: Bool { (age ?? .infinity) >= Self.staleAfter }

    var glucoseText: String {
        guard let glucose, let age, age < Self.expiredAfter else { return "--" }
        return glucose
    }

    var ageText: String {
        guard let age else { return "" }
        let minutes = Int(age / 60)
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h"
    }

    var deltaText: String {
        guard !isStale, let delta, delta != "--" else { return "" }
        return delta
    }

    /// Colour of the trend dot: Trio's glucose colour, grey when there is none.
    var dotColor: Color {
        guard let colorHex, !colorHex.isEmpty else { return .gray }
        var rgb: UInt64 = 0
        Scanner(string: colorHex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&rgb)
        return Color(
            red: Double((rgb & 0xFF0000) >> 16) / 255,
            green: Double((rgb & 0x00FF00) >> 8) / 255,
            blue: Double(rgb & 0x0000FF) / 255
        )
    }

    /// Position of the trend dot around the right side of the ring: 0° at 3 o'clock, -90° at 12.
    var trendAngle: Double? {
        guard !isStale else { return nil }
        switch trend {
        case "TripleUp",
             "DoubleUp",
             "SingleUp": return -90
        case "FortyFiveUp": return -45
        case "Flat": return 0
        case "FortyFiveDown": return 45
        case "TripleDown",
             "DoubleDown",
             "SingleDown": return 90
        default: return nil
        }
    }
}

// MARK: - Provider

struct TrioWatchComplicationProvider: TimelineProvider {
    func placeholder(in _: Context) -> TrioWatchComplicationEntry {
        TrioWatchComplicationEntry(
            date: Date(),
            glucose: "6.7",
            trend: "Flat",
            delta: "+0.1",
            colorHex: "#4CD964",
            readingDate: Date()
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TrioWatchComplicationEntry) -> Void) {
        let entry = loadEntry(at: Date())
        completion(context.isPreview && entry.glucose == nil ? placeholder(in: context) : entry)
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<TrioWatchComplicationEntry>) -> Void) {
        let now = Date()
        let latest = loadEntry(at: now)

        // One entry per minute keeps the reading's age current without using up WidgetKit's reload budget.
        // The watch app reloads the timeline when a new reading arrives; .atEnd is the fallback.
        let start = latest.readingDate ?? now
        let elapsedMinutes = max(0, Int(now.timeIntervalSince(start) / 60))
        let entries = [latest] + (1 ... 30).map {
            loadEntry(at: start.addingTimeInterval(Double(elapsedMinutes + $0) * 60))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    /// Reads the latest reading the watch app shared through the App Group.
    private func loadEntry(at date: Date) -> TrioWatchComplicationEntry {
        guard let suiteName = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String,
              let defaults = UserDefaults(suiteName: suiteName),
              let glucose = defaults.string(forKey: "complication.glucose")
        else {
            return TrioWatchComplicationEntry(date: date, glucose: nil, trend: nil, delta: nil, colorHex: nil, readingDate: nil)
        }
        let timestamp = defaults.double(forKey: "complication.date")
        return TrioWatchComplicationEntry(
            date: date,
            glucose: glucose,
            trend: defaults.string(forKey: "complication.trend"),
            delta: defaults.string(forKey: "complication.delta"),
            colorHex: defaults.string(forKey: "complication.color"),
            readingDate: timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
        )
    }
}

// MARK: - Views

//// Displayed View Wrapper
struct TrioWatchComplicationEntryView: View {
    @Environment(\.widgetFamily) private var widgetFamily

    var entry: TrioWatchComplicationEntry

    var body: some View {
        switch widgetFamily {
        case .accessoryCircular:
            TrioAccessoryCircularView(entry: entry)
        #if os(watchOS)
            case .accessoryCorner:
                TrioAccessoryCornerView(entry: entry)
        #endif
        default:
            Image("ComplicationIcon")
                .widgetAccentable()
                .widgetBackground(backgroundView: Color.clear)
        }
    }
}

#if os(watchOS)
    /// Corner Complication
    struct TrioAccessoryCornerView: View {
        var entry: TrioWatchComplicationProvider.Entry

        var body: some View {
            Text(entry.glucoseText)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(entry.isStale ? .secondary : .primary)
                .widgetCurvesContent()
                .widgetLabel {
                    Text(entry.ageText.isEmpty ? "Trio" : "\(entry.ageText) ago")
                }
                .widgetBackground(backgroundView: Color.clear)
        }
    }
#endif

/// Circular Complication: a ring the size of the system's ring complications, with the reading's age,
/// value and change inside, and a dot in Trio's glucose colour that moves round the right of the ring
/// to show the trend. Proportions follow the Trio designs, drawn at 50 pt.
struct TrioAccessoryCircularView: View {
    var entry: TrioWatchComplicationProvider.Entry

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let ringWidth = size * 0.1073
            let dotDiameter = size * 0.13
            let dotOutline = size * 0.028
            // As in Apple's gauge complications, the ring sits just inside the edge so the dot, which is wider than
            // the ring, can be centred on it without watchOS clipping its outline at the complication's edge.
            let ringInset = dotDiameter / 2 + dotOutline / 2
            let ringColor = entry.isStale ? Color.gray : entry.dotColor

            ZStack {
                Circle()
                    .inset(by: ringInset)
                    .stroke(ringColor.opacity(0.22), lineWidth: ringWidth)

                Text(entry.ageText)
                    .font(.system(size: size * 0.14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .offset(y: -size * 0.236)

                Text(entry.glucoseText)
                    .font(.system(size: size * 0.36, weight: .medium, design: .rounded))
                    .tracking(-size * 0.0144)
                    .foregroundStyle(entry.isStale ? Color.gray : Color(red: 0xF2 / 255, green: 0xF2 / 255, blue: 0xF2 / 255))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .frame(width: size * 0.74)

                Text(entry.deltaText)
                    .font(.system(size: size * 0.14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .offset(y: size * 0.264)

                if let angle = entry.trendAngle {
                    Circle()
                        .fill(entry.dotColor)
                        .overlay(Circle().stroke(Color.black, lineWidth: dotOutline))
                        .frame(width: dotDiameter, height: dotDiameter)
                        // Centre the dot on the ring, then swing it round to the trend's position.
                        .offset(x: size / 2 - ringInset)
                        .rotationEffect(.degrees(angle))
                        .widgetAccentable()
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .widgetBackground(backgroundView: Color.clear)
    }
}

// MARK: - Widget Configuration

@main struct TrioWatchComplication: Widget {
    let kind: String = "TrioWatchComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TrioWatchComplicationProvider()) { entry in
            TrioWatchComplicationEntryView(entry: entry)
        }
        .configurationDisplayName("Trio")
        .description("Your latest glucose reading, its age and trend")
        .supportedFamilies(supportedFamilies)
    }

    private var supportedFamilies: [WidgetFamily] {
        #if os(watchOS)
            return [.accessoryCorner, .accessoryCircular]
        #else
            return [.accessoryCircular]
        #endif
    }
}

extension View {
    func widgetBackground(backgroundView: some View) -> some View {
        if #available(watchOS 10.0, iOSApplicationExtension 17.0, iOS 17.0, *) {
            return containerBackground(for: .widget) {
                backgroundView
            }
        } else {
            return background(backgroundView)
        }
    }
}
