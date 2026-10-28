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
        if displayValue(latest.glucose) < lowLine { return .staticLow }
        if displayValue(latest.glucose) > highLine { return .staticHigh }
        return .primary
    }

    /// Whether the latest reading, as displayed, is within the widget's limits.
    var isInRange: Bool {
        (lowLine ... highLine).contains(displayValue(latest.glucose))
    }

    /// Readings from the last hour, converted to the display unit, oldest first.
    var chartPoints: [(date: Date, value: Double)] {
        let start = date.addingTimeInterval(-60 * 60)
        return snapshot.readings.filter { $0.date >= start }.reversed().map { ($0.date, displayValue($0.glucose)) }
    }

    var lowLine: Double { isMgdL ? GlucoseWidgetSnapshot.lowLimitMgdL : GlucoseWidgetSnapshot.lowLimitMmolL }
    var highLine: Double { isMgdL ? GlucoseWidgetSnapshot.highLimitMgdL : GlucoseWidgetSnapshot.highLimitMmolL }

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
    @Environment(\.widgetRenderingMode) private var renderingMode
    /// False in StandBy, where the widget sits beside the clock without its background.
    @Environment(\.showsWidgetContainerBackground) private var showsBackground
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
                    .font(.system(size: 20, weight: .semibold))
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
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: -2) {
                HStack(alignment: .center, spacing: 2) {
                    Text(display.glucose)
                        .font(.system(size: 44, weight: .regular))
                        .foregroundStyle(display.isStale ? .secondary : .primary)
                    Text(display.direction)
                        .font(.system(size: 26, weight: .semibold))
                }
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                Text(display.delta.isEmpty ? display.ageText : "\(display.delta) · \(display.ageText)")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .frame(maxHeight: .infinity)
            .layoutPriority(1)
            GlucoseWidgetChart(display: display, showsArea: false)
        }
    }

    /// StandBy's night mode tints the widget red and sets brightness from each colour's lightness, so colours and
    /// greys come out dimmer than the clock. There the reading is white, as bright as the clock, even when stale.
    private func readingColor(_ display: GlucoseWidgetDisplay) -> Color {
        renderingMode == .vibrant ? .white : display.glucoseColor
    }

    private func small(_ display: GlucoseWidgetDisplay) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center, spacing: 3) {
                        Text(display.glucose)
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(readingColor(display))
                        Text(display.direction)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(readingColor(display))
                    }
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    // The line box leaves about 7pt above the digits; pull them up so the top margin matches the left.
                    .padding(.top, -7)
                    Text(display.delta.isEmpty ? display.ageText : "\(display.delta) · \(display.ageText)")
                        .font(.caption)
                        .foregroundStyle(
                            renderingMode == .vibrant ? AnyShapeStyle(Color.white.opacity(0.8)) : AnyShapeStyle(.secondary)
                        )
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button(intent: RefreshGlucoseWidgetIntent()) {
                    // Fixed icon size, so StandBy's larger text settings can't overflow the button.
                    Image(systemName: "arrow.clockwise")
                        .resizable()
                        .fontWeight(.semibold)
                        .scaledToFit()
                        .frame(width: 11, height: 11)
                        .foregroundStyle(.primary)
                        .frame(width: 30, height: 22)
                        .background(Capsule().fill(Color.primary.opacity(0.16)))
                }
                .buttonStyle(.plain)
            }
            GlucoseWidgetChart(display: display, showsArea: true)
        }
        // In StandBy, inset the top and bottom to line up with the clock beside it.
        .padding(.vertical, showsBackground ? 0 : 6)
    }
}

/// Line chart of the last hour, with the low and high limits as dashed lines.
private struct GlucoseWidgetChart: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let display: GlucoseWidgetDisplay
    let showsArea: Bool

    /// StandBy's night mode turns everything red and sets brightness from lightness, so there the chart is drawn in
    /// white and the limits in lighter greys, to stay as clear as the clock.
    private var isNightMode: Bool { renderingMode == .vibrant }

    private static let lineWidth: CGFloat = 2
    private static let limitLineWidth: CGFloat = 1
    /// Approximate width of the trailing limit labels, used to estimate the plot width.
    private static let labelWidth: CGFloat = 18

    var body: some View {
        GeometryReader { geometry in
            chart(plotWidth: geometry.size.width - (showsArea ? Self.labelWidth : 0))
        }
    }

    private func chart(plotWidth: CGFloat) -> some View {
        let points = display.chartPoints
        let values = points.map(\.value) + [display.lowLine, display.highLine]
        let lowerBound = (values.min() ?? 0) * 0.9
        let upperBound = (values.max() ?? 0) * 1.05

        // The whole chart is green while the latest reading is in range, red when it is outside the limits.
        let chartColor: Color = isNightMode ? .white : display.isInRange ? .green : .red
        let areaStyle = LinearGradient(
            colors: [chartColor.opacity(0.4), chartColor.opacity(0.02)],
            startPoint: .top,
            endPoint: .bottom
        )

        // The line's round caps reach half its width past the first and last readings. Widen the x-axis by that
        // much and carry the shading out to the same place, so the line spans the full width without overhanging it.
        let readings = xDomain(points)
        let capTime = plotWidth > 0
            ? readings.upperBound.timeIntervalSince(readings.lowerBound) * Double(Self.lineWidth / 2 / plotWidth)
            : 0
        let areaPoints = extended(points, by: capTime)

        return Chart {
            if showsArea {
                ForEach(areaPoints, id: \.date) { point in
                    AreaMark(
                        x: .value("Time", point.date),
                        yStart: .value("Floor", lowerBound),
                        yEnd: .value("Glucose", point.value)
                    )
                    .foregroundStyle(areaStyle)
                    .interpolationMethod(.monotone)
                }
            }
            ForEach(points, id: \.date) { point in
                LineMark(x: .value("Time", point.date), y: .value("Glucose", point.value))
                    .foregroundStyle(chartColor)
                    .lineStyle(StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
        }
        .chartXScale(domain: readings.lowerBound.addingTimeInterval(-capTime) ... readings.upperBound.addingTimeInterval(capTime))
        .chartYScale(domain: lowerBound ... upperBound)
        .chartXAxis(.hidden)
        .chartYAxis {
            if showsArea {
                AxisMarks(position: .trailing, values: [display.lowLine, display.highLine]) { value in
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(display.isMgdL ? "\(Int(number))" : String(format: "%.1f", number))
                                .font(.system(size: 8))
                                .foregroundStyle(isNightMode ? Color.white.opacity(0.7) : Color.gray.opacity(0.6))
                        }
                    }
                }
            }
        }
        .chartBackground { proxy in
            // Drawn here rather than as rule marks, so the dashes can be sized to divide the plot width evenly.
            GeometryReader { geometry in
                if let plotFrame = proxy.plotFrame {
                    let frame = geometry[plotFrame]
                    ForEach([display.highLine, display.lowLine], id: \.self) { value in
                        if let y = proxy.position(forY: value) {
                            limitLine(width: frame.width)
                                .position(x: frame.midX, y: frame.minY + y)
                        }
                    }
                }
            }
        }
        .widgetAccentable()
    }

    /// A faint grey dashed line, kept in the background behind the glucose line, with round-ended dashes of
    /// equal length, the first and last flush with each end.
    private func limitLine(width: CGFloat) -> some View {
        let lineWidth = Self.limitLineWidth
        // An odd number of equal segments, dash first and last, each about 3 pt long.
        let dashCount = max(1, Int(((width + 3) / 6).rounded()))
        let segment = width / CGFloat(2 * dashCount - 1)
        return Path { path in
            path.move(to: CGPoint(x: lineWidth / 2, y: lineWidth / 2))
            path.addLine(to: CGPoint(x: width - lineWidth / 2, y: lineWidth / 2))
        }
        // Round caps add half the line width to each end of a dash, so shorten the dashes and lengthen the gaps by that.
        .stroke(
            isNightMode ? Color.white.opacity(0.55) : Color.gray.opacity(0.45),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: [max(0, segment - lineWidth), segment + lineWidth])
        )
        .frame(width: width, height: lineWidth)
    }

    /// The readings with a point added `time` beyond each end, continuing the line's direction, so the shading is
    /// one piece that reaches under the line's round caps while following the same curve.
    private func extended(_ points: [(date: Date, value: Double)], by time: TimeInterval) -> [(date: Date, value: Double)] {
        guard time > 0, points.count > 1 else { return points }
        let first = points[0], second = points[1]
        let last = points[points.count - 1], beforeLast = points[points.count - 2]
        let startSlope = (second.value - first.value) / second.date.timeIntervalSince(first.date)
        let endSlope = (last.value - beforeLast.value) / last.date.timeIntervalSince(beforeLast.date)
        return [(first.date.addingTimeInterval(-time), first.value - startSlope * time)] + points +
            [(last.date.addingTimeInterval(time), last.value + endSlope * time)]
    }

    /// From the oldest to the newest reading shown; the last hour when there are fewer than two.
    private func xDomain(_ points: [(date: Date, value: Double)]) -> ClosedRange<Date> {
        guard let first = points.first?.date, let last = points.last?.date, first < last else {
            return display.date.addingTimeInterval(-60 * 60) ... display.date
        }
        return first ... last
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
            unit: GlucoseUnits.mmolL.rawValue
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
