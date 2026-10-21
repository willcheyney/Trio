import Foundation

/// A single configurable glucose alarm. Multiple entries of the same type are
/// allowed — e.g. a Low alarm `active: .day` at 80 mg/dL plus a second Low
/// `active: .night` at 70 mg/dL.
struct GlucoseAlert: Identifiable, Codable, Equatable {
    var id: UUID
    var type: GlucoseAlertType
    var name: String
    var isEnabled: Bool
    var thresholdMgDL: Decimal
    var soundFilename: String
    /// When false, the alarm fires the banner / notification but no sound.
    /// iOS still drives haptics from the interruption level.
    var playsSound: Bool
    /// When true, this alarm bypasses Focus Mode / silent switch
    /// modes. Maps to `Alert.InterruptionLevel.critical` and triggers the
    /// in-process `CriticalAlertAudioPlayer` fallback for builds without the
    /// Critical Alerts entitlement.
    var overridesSilenceAndDND: Bool
    var activeOption: ActiveOption
    /// Opt-in CGM-style behaviour for low / urgent-low: one short chime per
    /// alert, re-issued every `chimeRepeatInterval` while the episode is still
    /// low and unacknowledged, instead of a sound that loops until
    /// acknowledged. Ignored for other types (`usesChime`).
    var soundBehavior: GlucoseAlertSoundBehavior
    var chimeRepeatInterval: GlucoseAlertChimeInterval
    /// Per-alarm snooze. Distinct from the global mute on `AlertMuter`.
    var snoozedUntil: Date?

    init(type: GlucoseAlertType) {
        id = UUID()
        self.type = type
        name = type.displayName
        isEnabled = true
        thresholdMgDL = type.defaultThresholdMgDL
        soundFilename = type.defaultSoundFilename
        playsSound = true
        overridesSilenceAndDND = type.defaultOverridesSilenceAndDND
        activeOption = .always
        soundBehavior = .continuous
        chimeRepeatInterval = .fiveMinutes
        snoozedUntil = nil
    }

    /// True when this alarm should use the CGM-style chime pathway. Only the
    /// reading-driven low family supports it.
    var usesChime: Bool {
        soundBehavior == .chime && type.supportsChime
    }

    /// Whether the coordinator should fire this alarm when a reading breaches.
    /// Urgent-low is the safety floor — the editor hides the Enabled toggle so
    /// the user can't accidentally turn it off, and stored `isEnabled = false`
    /// from a prior install is ignored here.
    var shouldEvaluate: Bool {
        type == .urgentLow || isEnabled
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case name
        case isEnabled
        case thresholdMgDL
        case soundFilename
        case playsSound
        case overridesSilenceAndDND
        case activeOption
        case soundBehavior
        case chimeRepeatInterval
        case snoozedUntil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        type = try container.decode(GlucoseAlertType.self, forKey: .type)
        name = try container.decode(String.self, forKey: .name)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        thresholdMgDL = try container.decode(Decimal.self, forKey: .thresholdMgDL)
        soundFilename = try container.decodeIfPresent(String.self, forKey: .soundFilename) ?? type.defaultSoundFilename
        playsSound = try container.decodeIfPresent(Bool.self, forKey: .playsSound) ?? true
        overridesSilenceAndDND = try container.decodeIfPresent(
            Bool.self,
            forKey: .overridesSilenceAndDND
        ) ?? type.defaultOverridesSilenceAndDND
        activeOption = try container.decodeIfPresent(ActiveOption.self, forKey: .activeOption) ?? .always
        // Absent on alarms saved before this option existed — keep them on
        // today's continuous behaviour.
        soundBehavior = try container.decodeIfPresent(
            GlucoseAlertSoundBehavior.self,
            forKey: .soundBehavior
        ) ?? .continuous
        chimeRepeatInterval = try container.decodeIfPresent(
            GlucoseAlertChimeInterval.self,
            forKey: .chimeRepeatInterval
        ) ?? .fiveMinutes
        snoozedUntil = try container.decodeIfPresent(Date.self, forKey: .snoozedUntil)
    }
}

/// How a low / urgent-low alarm sounds.
enum GlucoseAlertSoundBehavior: String, Codable, CaseIterable, Identifiable, DayNightDisplayable {
    /// Existing behaviour: sound loops until acknowledged.
    case continuous
    /// One short chime, repeated at `GlucoseAlertChimeInterval`.
    case chime

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .continuous: return String(localized: "Continuous")
        case .chime: return String(localized: "CGM-style Chime")
        }
    }
}

/// Re-chime cadence while a CGM-style alarm stays low and unacknowledged.
/// Raw value is minutes.
enum GlucoseAlertChimeInterval: Int, Codable, CaseIterable, Identifiable, DayNightDisplayable {
    case fiveMinutes = 5
    case tenMinutes = 10
    case fifteenMinutes = 15

    var id: Int { rawValue }

    var timeInterval: TimeInterval { TimeInterval(rawValue * 60) }

    var displayName: String {
        String(format: String(localized: "Every %d min"), rawValue)
    }
}
