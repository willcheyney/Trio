import SwiftUI
import WidgetKit

// MARK: - Timeline Entry

struct TrioWatchComplicationEntry: TimelineEntry {
    let date: Date
    /// Latest glucose as the watch app displays it, e.g. "6.7"; nil before the first reading arrives.
    let glucose: String?
    /// Raw trend of the latest reading, e.g. "Flat" or "FortyFiveUp".
    let trend: String?
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

    /// Angle of the trend arrow around the right side of the complication: 0° at 3 o'clock, -90° at 12.
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
        TrioWatchComplicationEntry(date: Date(), glucose: "6.7", trend: "Flat", readingDate: Date())
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
            return TrioWatchComplicationEntry(date: date, glucose: nil, trend: nil, readingDate: nil)
        }
        let timestamp = defaults.double(forKey: "complication.date")
        return TrioWatchComplicationEntry(
            date: date,
            glucose: glucose,
            trend: defaults.string(forKey: "complication.trend"),
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
                .font(.title3.weight(.semibold))
                .foregroundStyle(entry.isStale ? .secondary : .primary)
                .widgetCurvesContent()
                .widgetLabel {
                    Text(entry.ageText.isEmpty ? "Trio" : "\(entry.ageText) ago")
                }
                .widgetBackground(backgroundView: Color.clear)
        }
    }
#endif

/// Circular Complication: the reading in the centre, its age underneath, and the trend arrow
/// travelling around the right-hand edge.
struct TrioAccessoryCircularView: View {
    var entry: TrioWatchComplicationProvider.Entry

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let circleDiameter = size * 0.74
            let arrowWidth = size * 0.09
            let accent: Color = entry.isStale ? .gray : .green

            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: circleDiameter, height: circleDiameter)

                Text(entry.glucoseText)
                    .font(.system(size: size * 0.3, weight: .bold))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(entry.isStale ? .secondary : .primary)
                    .frame(width: circleDiameter * 0.9)

                Text(entry.ageText)
                    .font(.system(size: size * 0.16, weight: .semibold))
                    .foregroundStyle(accent)
                    .offset(y: size * 0.21)
                    .widgetAccentable()

                if let angle = entry.trendAngle {
                    TrendArrow()
                        .fill(accent)
                        .frame(width: arrowWidth, height: arrowWidth * 1.3)
                        // Sit just outside the circle, then swing round its centre to the trend's position.
                        .offset(x: circleDiameter / 2 + size * 0.03 + arrowWidth / 2)
                        .rotationEffect(.degrees(angle))
                        .widgetAccentable()
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .widgetBackground(backgroundView: Color.clear)
    }
}

/// Triangle pointing right, rotated with its position around the complication.
private struct TrendArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
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
