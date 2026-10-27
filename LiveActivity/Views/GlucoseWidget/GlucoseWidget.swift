import AppIntents
import Charts
import SwiftUI
import WidgetKit

/// Home screen, lock screen and StandBy widget showing the latest glucose reading and the last hour.
///
/// Trio shares its readings through `GlucoseWidgetSnapshot` and reloads this widget when they change.
/// WidgetKit limits how often that happens in the background, so every view shows the reading's age
/// and greys the reading out once it is stale.
struct GlucoseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: GlucoseWidgetSnapshot.kind, provider: GlucoseWidgetProvider()) { entry in
            GlucoseWidgetView(entry: entry)
                .widgetURL(URL(string: "Trio://"))
        }
        .configurationDisplayName("Trio Glucose")
        .description("Your latest glucose reading and the last hour.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct GlucoseWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: GlucoseWidgetSnapshot?
}

struct GlucoseWidgetProvider: TimelineProvider {
    func placeholder(in _: Context) -> GlucoseWidgetEntry {
        GlucoseWidgetEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (GlucoseWidgetEntry) -> Void) {
        let snapshot = GlucoseWidgetSnapshot.load() ?? (context.isPreview ? .preview : nil)
        completion(GlucoseWidgetEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<GlucoseWidgetEntry>) -> Void) {
        let snapshot = GlucoseWidgetSnapshot.load()
        let now = Date.now

        // One entry per minute keeps the reading's age current without using up WidgetKit's reload budget.
        // Trio reloads the timeline when new readings arrive; .atEnd is the fallback if it can't.
        let start = snapshot?.readings.first?.date ?? now
        let elapsedMinutes = max(0, Int(now.timeIntervalSince(start) / 60))
        let entries = [GlucoseWidgetEntry(date: now, snapshot: snapshot)] + (1 ... 30).map {
            GlucoseWidgetEntry(date: start.addingTimeInterval(Double(elapsedMinutes + $0) * 60), snapshot: snapshot)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

/// Reloads the widget from the readings Trio has most recently shared.
struct RefreshGlucoseWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Glucose"
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult {
        // WidgetKit reloads the widget's timeline after an interactive intent finishes.
        .result()
    }
}

/// Display values for one timeline entry.
private struct GlucoseWidgetDisplay {
    /// A reading older than this is shown as stale.
    static let staleAfter: TimeInterval = 15 * 60
    /// A reading older than this is not shown at all.
    static let expiredAfter: TimeInterval = 60 * 60

    let snapshot: GlucoseWidgetSnapshot
    let latest: GlucoseWidgetSnapshot.Reading
    let date: Date

    init?(entry: GlucoseWidgetEntry) {
        guard let snapshot = entry.snapshot, let latest = snapshot.readings.first else { return nil }
        self.snapshot = snapshot
        self.latest = latest
        date = entry.date
    }

    var isMgdL: Bool { snapshot.unit == GlucoseUnits.mgdL.rawValue }
    var age: TimeInterval { max(0, date.timeIntervalSince(latest.date)) }
    var isStale: Bool { age >= Self.staleAfter }
    var isExpired: Bool { age >= Self.expiredAfter }

    var glucose: String {
        isExpired ? "--" : format(latest.glucose)
    }

    var direction: String {
        isStale ? "" : snapshot.direction ?? ""
    }

    /// Change from the previous reading, with its sign.
    var delta: String {
        guard !isStale, snapshot.readings.count > 1 else { return "" }
        let previous = snapshot.readings[1].glucose
        let change = isMgdL ? Decimal(latest.glucose - previous) : latest.glucose.asMmolL - previous.asMmolL
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = isMgdL ? 0 : 1
        formatter.maximumFractionDigits = isMgdL ? 0 : 1
        formatter.positivePrefix = formatter.plusSign
        return formatter.string(from: change as NSDecimalNumber) ?? ""
    }

    var ageText: String {
        let minutes = Int(age / 60)
        if minutes < 1 { return "now" }
        if minutes < 60 { return "\(minutes)m ago" }
        return "\(minutes / 60)h ago"
    }

    /// Colour of the reading: the static Trio colours for low and high, primary in range.
    var glucoseColor: Color {
        if isStale { return .secondary }
        if Decimal(latest.glucose) <= snapshot.low { return .staticLow }
        if Decimal(latest.glucose) >= snapshot.high { return .staticHigh }
        return .primary
    }

    /// Whether the latest reading is between the low and high limits.
    var isInRange: Bool {
        Decimal(latest.glucose) > snapshot.low && Decimal(latest.glucose) < snapshot.high
    }

    /// Readings from the last hour, converted to the display unit, oldest first.
    var chartPoints: [(date: Date, value: Double)] {
        let start = date.addingTimeInterval(-60 * 60)
        return snapshot.readings.filter { $0.date >= start }.reversed().map { ($0.date, displayValue($0.glucose)) }
    }

    var lowLine: Double { displayValue(snapshot.low) }
    var highLine: Double { displayValue(snapshot.high) }

    func displayValue(_ mgdL: Int) -> Double {
        displayValue(Decimal(mgdL))
    }

    func displayValue(_ mgdL: Decimal) -> Double {
        NSDecimalNumber(decimal: isMgdL ? mgdL : mgdL.asMmolL).doubleValue
    }

    private func format(_ mgdL: Int) -> String {
        isMgdL ? "\(mgdL)" : mgdL.formattedAsMmolL
    }
}

struct GlucoseWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GlucoseWidgetEntry

    var body: some View {
        Group {
            if let display = GlucoseWidgetDisplay(entry: entry) {
                switch family {
                case .accessoryInline:
                    inline(display)
                case .accessoryCircular:
                    circular(display)
                case .accessoryRectangular:
                    rectangular(display)
                default:
                    small(display)
                }
            } else {
                noData
            }
        }
        .containerBackground(.background, for: .widget)
    }

    private var noData: some View {
        VStack(spacing: 2) {
            Text("--").font(.title2.weight(.semibold))
            if family != .accessoryCircular, family != .accessoryInline {
                Text("Open Trio").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func inline(_ display: GlucoseWidgetDisplay) -> some View {
        Text(
            [display.glucose, display.direction, display.delta].filter { !$0.isEmpty }.joined(separator: " ") + " · " + display
                .ageText
        )
    }

    private func circular(_ display: GlucoseWidgetDisplay) -> some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: -2) {
                Text(display.glucose)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(display.isStale ? .secondary : .primary)
                Text(display.isStale ? display.ageText : display.direction)
                    .font(.system(size: display.isStale ? 10 : 14, weight: .semibold))
                    .minimumScaleFactor(0.5)
            }
            .padding(4)
        }
    }

    private func rectangular(_ display: GlucoseWidgetDisplay) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 2) {
                    Text(display.glucose)
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(display.isStale ? .secondary : .primary)
                    Text(display.direction)
                        .font(.system(size: 16, weight: .semibold))
                }
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                Text(display.delta.isEmpty ? display.ageText : "\(display.delta) · \(display.ageText)")
                    .font(.caption2)
                    .lineLimit(1)
            }
            .layoutPriority(1)
            GlucoseWidgetChart(display: display, showsArea: false)
        }
    }

    private func small(_ display: GlucoseWidgetDisplay) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center, spacing: 3) {
                        Text(display.glucose)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(display.glucoseColor)
                        Text(display.direction)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(display.glucoseColor)
                    }
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    Text(display.delta.isEmpty ? display.ageText : "\(display.delta) · \(display.ageText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button(intent: RefreshGlucoseWidgetIntent()) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 30, height: 22)
                        .background(Capsule().fill(Color.primary.opacity(0.16)))
                }
                .buttonStyle(.plain)
            }
            GlucoseWidgetChart(display: display, showsArea: true)
        }
    }
}

/// Line chart of the last hour, with the low and high limits as dashed lines.
private struct GlucoseWidgetChart: View {
    let display: GlucoseWidgetDisplay
    let showsArea: Bool

    var body: some View {
        let points = display.chartPoints
        let values = points.map(\.value) + [display.lowLine, display.highLine]
        let lowerBound = (values.min() ?? 0) * 0.9
        let upperBound = (values.max() ?? 0) * 1.05

        // The whole chart is green while the latest reading is in range, red when it is outside the limits.
        let chartColor: Color = display.isInRange ? .green : .red

        Chart {
            RuleMark(y: .value("High", display.highLine))
                .foregroundStyle(.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            RuleMark(y: .value("Low", display.lowLine))
                .foregroundStyle(.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

            ForEach(points, id: \.date) { point in
                if showsArea {
                    AreaMark(
                        x: .value("Time", point.date),
                        yStart: .value("Floor", lowerBound),
                        yEnd: .value("Glucose", point.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [chartColor.opacity(0.4), chartColor.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.monotone)
                }
                LineMark(x: .value("Time", point.date), y: .value("Glucose", point.value))
                    .foregroundStyle(chartColor)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
        }
        .chartXScale(domain: display.date.addingTimeInterval(-60 * 60) ... display.date)
        .chartYScale(domain: lowerBound ... upperBound)
        .chartXAxis(.hidden)
        .chartYAxis {
            if showsArea {
                AxisMarks(position: .trailing, values: [display.lowLine, display.highLine]) { value in
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(display.isMgdL ? "\(Int(number))" : String(format: "%.1f", number))
                                .font(.system(size: 8))
                        }
                    }
                }
            }
        }
        .widgetAccentable()
    }
}

extension GlucoseWidgetSnapshot {
    /// Sample data for the widget gallery.
    static var preview: GlucoseWidgetSnapshot {
        let values = [112, 115, 120, 126, 131, 133, 130, 126, 121, 118, 117, 119, 120]
        let now = Date.now
        return GlucoseWidgetSnapshot(
            readings: values.reversed().enumerated().map {
                Reading(date: now.addingTimeInterval(Double(-$0.offset) * 5 * 60), glucose: $0.element)
            },
            direction: "→",
            unit: GlucoseUnits.mmolL.rawValue,
            low: 70,
            high: 180
        )
    }
}

#Preview("Small", as: .systemSmall) {
    GlucoseWidget()
} timeline: {
    GlucoseWidgetEntry(date: .now, snapshot: .preview)
    GlucoseWidgetEntry(date: .now.addingTimeInterval(20 * 60), snapshot: .preview)
    GlucoseWidgetEntry(date: .now, snapshot: nil)
}

#Preview("Lock screen", as: .accessoryRectangular) {
    GlucoseWidget()
} timeline: {
    GlucoseWidgetEntry(date: .now, snapshot: .preview)
}
