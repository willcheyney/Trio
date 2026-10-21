import Foundation
import Testing

@testable import Trio

@Suite("Trio Alerts: GlucoseAlertCoordinator breach/retract") struct GlucoseAlertCoordinatorTests {
    @Test("low breaches at or below threshold 70") func lowBreach() {
        #expect(GlucoseAlertCoordinator.breached(type: .low, latestMgDL: 70, thresholdMgDL: 70))
        #expect(!GlucoseAlertCoordinator.breached(type: .low, latestMgDL: 71, thresholdMgDL: 70))
    }

    @Test("low retracts only at threshold + margin (70 + 5)") func lowRetract() {
        #expect(!GlucoseAlertCoordinator.shouldRetract(
            type: .low, latestMgDL: 74, thresholdMgDL: 70, recoveryMarginMgDL: 5
        ))
        #expect(GlucoseAlertCoordinator.shouldRetract(
            type: .low, latestMgDL: 75, thresholdMgDL: 70, recoveryMarginMgDL: 5
        ))
    }

    @Test("urgentLow breaches at or below threshold 54") func urgentLowBreach() {
        #expect(GlucoseAlertCoordinator.breached(type: .urgentLow, latestMgDL: 54, thresholdMgDL: 54))
        #expect(!GlucoseAlertCoordinator.breached(type: .urgentLow, latestMgDL: 55, thresholdMgDL: 54))
    }

    @Test("high breaches at or above threshold 270") func highBreach() {
        #expect(GlucoseAlertCoordinator.breached(type: .high, latestMgDL: 270, thresholdMgDL: 270))
        #expect(!GlucoseAlertCoordinator.breached(type: .high, latestMgDL: 269, thresholdMgDL: 270))
    }

    @Test("high retracts only at threshold - margin (270 - 5)") func highRetract() {
        #expect(!GlucoseAlertCoordinator.shouldRetract(
            type: .high, latestMgDL: 266, thresholdMgDL: 270, recoveryMarginMgDL: 5
        ))
        #expect(GlucoseAlertCoordinator.shouldRetract(
            type: .high, latestMgDL: 265, thresholdMgDL: 270, recoveryMarginMgDL: 5
        ))
    }

    @Test("type priority order: urgentLow < low < forecastedLow < high < carbsRequired") func priorityOrder() {
        #expect(GlucoseAlertType.urgentLow.priority == 0)
        #expect(GlucoseAlertType.low.priority == 1)
        #expect(GlucoseAlertType.forecastedLow.priority == 2)
        #expect(GlucoseAlertType.high.priority == 3)
        #expect(GlucoseAlertType.carbsRequired.priority == 4)
        #expect(GlucoseAlertType.urgentLow.priority < GlucoseAlertType.low.priority)
    }

    @Test("shouldRetract uses the default 5 mg/dL margin when omitted") func defaultMarginWiring() {
        #expect(GlucoseAlertCoordinator.shouldRetract(type: .low, latestMgDL: 75, thresholdMgDL: 70))
        #expect(!GlucoseAlertCoordinator.shouldRetract(type: .low, latestMgDL: 74, thresholdMgDL: 70))
    }

    // MARK: - Carbs Required predicates (mg/dL-based gates are no-ops)

    /// Carbs Required is determination-driven (`evaluateCarbsRequired(_:)`),
    /// not reading-driven. The shared mg/dL `breached` predicate must never
    /// return true for it, regardless of value / threshold combination.
    @Test("carbsRequired never breaches via the mg/dL predicate") func carbsRequiredNeverBreaches() {
        #expect(!GlucoseAlertCoordinator.breached(type: .carbsRequired, latestMgDL: 0, thresholdMgDL: 0))
        #expect(!GlucoseAlertCoordinator.breached(type: .carbsRequired, latestMgDL: 200, thresholdMgDL: 10))
        #expect(!GlucoseAlertCoordinator.breached(type: .carbsRequired, latestMgDL: 10, thresholdMgDL: 200))
    }

    @Test("carbsRequired never retracts via the mg/dL predicate") func carbsRequiredNeverRetractsViaMgDL() {
        #expect(!GlucoseAlertCoordinator.shouldRetract(
            type: .carbsRequired, latestMgDL: 100, thresholdMgDL: 10, recoveryMarginMgDL: 5
        ))
        #expect(!GlucoseAlertCoordinator.shouldRetract(
            type: .carbsRequired, latestMgDL: 0, thresholdMgDL: 50, recoveryMarginMgDL: 5
        ))
    }
}

/// Guards the #1428 invariant: "Use CGM App Alerts" suppression applies to
/// reading-driven alarms only. A CGM app can alarm on the current reading,
/// but it cannot compute Trio's oref forecast or carbsReq, so those alarms
/// must stay armed — which is also what the settings screen shows the user,
/// since only reading-driven types move into the "Handled by CGM App" section.
@Suite("Trio Alerts: CGM-ownership suppression scope") struct CGMOwnershipSuppressionScopeTests {
    @Test("Forecast and carbs-required alarms are not reading-driven") func determinationDrivenTypes() {
        #expect(!GlucoseAlertType.forecastedLow.isReadingDriven)
        #expect(!GlucoseAlertType.carbsRequired.isReadingDriven)
    }

    @Test("Only high/low/urgentLow are reading-driven") func readingDrivenSetIsExact() {
        let readingDriven = Set(GlucoseAlertType.allCases.filter(\.isReadingDriven))
        #expect(readingDriven == [.high, .low, .urgentLow])
    }
}

@Suite("Trio Alerts: CGM-style chime reminder cadence") struct ChimeReminderCadenceTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private let fiveMin: TimeInterval = 300

    private func due(
        after elapsed: TimeInterval,
        readingAge: TimeInterval = 0,
        lastIssued: Date? = nil,
        lastReading: Date? = nil,
        interval: TimeInterval = 300,
        acknowledged: Bool = false
    ) -> Bool {
        let now = start.addingTimeInterval(elapsed)
        return GlucoseAlertCoordinator.isChimeReminderDue(
            lastIssuedAt: lastIssued ?? start,
            lastReadingDate: lastReading ?? start,
            readingDate: now.addingTimeInterval(-readingAge),
            interval: interval,
            isAcknowledged: acknowledged,
            now: now
        )
    }

    @Test("Per-minute readings inside the interval don't re-chime") func noChimeBetweenReminders() {
        for minute in 1 ... 4 {
            #expect(!due(after: TimeInterval(minute * 60)))
        }
    }

    @Test("Reminder is due once the interval elapses") func dueAtInterval() {
        #expect(due(after: fiveMin))
        #expect(due(after: fiveMin + 60))
    }

    @Test("Reading up to 30 s early still counts; earlier does not") func toleranceWindow() {
        #expect(due(after: fiveMin - 30))
        #expect(!due(after: fiveMin - 31))
    }

    @Test("Honours 10 and 15 minute intervals") func longerIntervals() {
        #expect(!due(after: fiveMin, interval: 600))
        #expect(due(after: 600, interval: 600))
        #expect(!due(after: 600, interval: 900))
        #expect(due(after: 900, interval: 900))
    }

    @Test("Acknowledged alarm never re-chimes") func acknowledgedStops() {
        #expect(!due(after: fiveMin * 3, acknowledged: true))
    }

    @Test("No new CGM reading since the last chime means no reminder") func staleReadingNoReminder() {
        // Latest reading is the same one that drove the last chime.
        let now = start.addingTimeInterval(fiveMin * 2)
        #expect(!GlucoseAlertCoordinator.isChimeReminderDue(
            lastIssuedAt: start,
            lastReadingDate: start,
            readingDate: start,
            interval: fiveMin,
            isAcknowledged: false,
            now: now
        ))
    }

    @Test("An alarm that hasn't sounded yet is never a 'reminder'") func noHistoryNoReminder() {
        #expect(!GlucoseAlertCoordinator.isChimeReminderDue(
            lastIssuedAt: nil,
            lastReadingDate: nil,
            readingDate: start,
            interval: fiveMin,
            isAcknowledged: false,
            now: start.addingTimeInterval(fiveMin)
        ))
    }
}
