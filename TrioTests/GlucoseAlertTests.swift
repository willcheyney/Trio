import Foundation
import Testing

@testable import Trio

@Suite("Trio Alerts: GlucoseAlert") struct GlucoseAlertTests {
    // MARK: - Group A: shouldEvaluate

    @Test("urgentLow evaluates even when isEnabled is false") func urgentLowDisabledStillEvaluates() {
        var a = GlucoseAlert(type: .urgentLow)
        a.isEnabled = false
        #expect(a.shouldEvaluate == true)
    }

    @Test("urgentLow evaluates when isEnabled is true") func urgentLowEnabledEvaluates() {
        var a = GlucoseAlert(type: .urgentLow)
        a.isEnabled = true
        #expect(a.shouldEvaluate == true)
    }

    @Test("low does not evaluate when disabled") func lowDisabledDoesNotEvaluate() {
        var a = GlucoseAlert(type: .low)
        a.isEnabled = false
        #expect(a.shouldEvaluate == false)
    }

    @Test("low evaluates when enabled") func lowEnabledEvaluates() {
        var a = GlucoseAlert(type: .low)
        a.isEnabled = true
        #expect(a.shouldEvaluate == true)
    }

    @Test("high does not evaluate when disabled") func highDisabledDoesNotEvaluate() {
        var a = GlucoseAlert(type: .high)
        a.isEnabled = false
        #expect(a.shouldEvaluate == false)
    }

    @Test("high evaluates when enabled") func highEnabledEvaluates() {
        var a = GlucoseAlert(type: .high)
        a.isEnabled = true
        #expect(a.shouldEvaluate == true)
    }

    @Test("forecastedLow does not evaluate when disabled") func forecastedLowDisabledDoesNotEvaluate() {
        var a = GlucoseAlert(type: .forecastedLow)
        a.isEnabled = false
        #expect(a.shouldEvaluate == false)
    }

    @Test("forecastedLow evaluates when enabled") func forecastedLowEnabledEvaluates() {
        var a = GlucoseAlert(type: .forecastedLow)
        a.isEnabled = true
        #expect(a.shouldEvaluate == true)
    }

    @Test("carbsRequired does not evaluate when disabled") func carbsRequiredDisabledDoesNotEvaluate() {
        var a = GlucoseAlert(type: .carbsRequired)
        a.isEnabled = false
        #expect(a.shouldEvaluate == false)
    }

    @Test("carbsRequired evaluates when enabled") func carbsRequiredEnabledEvaluates() {
        var a = GlucoseAlert(type: .carbsRequired)
        a.isEnabled = true
        #expect(a.shouldEvaluate == true)
    }

    // MARK: - Group A.5: type metadata

    @Test("carbsRequired defaults: threshold 10 g, bloop.caf, no override") func carbsRequiredDefaults() {
        let a = GlucoseAlert(type: .carbsRequired)
        #expect(a.thresholdMgDL == 10)
        #expect(a.soundFilename == "bloop.caf")
        #expect(a.overridesSilenceAndDND == false)
    }

    @Test("isReadingDriven: true for low family + high, false for forecast + carbs") func isReadingDriven() {
        #expect(GlucoseAlertType.urgentLow.isReadingDriven)
        #expect(GlucoseAlertType.low.isReadingDriven)
        #expect(GlucoseAlertType.high.isReadingDriven)
        #expect(!GlucoseAlertType.forecastedLow.isReadingDriven)
        #expect(!GlucoseAlertType.carbsRequired.isReadingDriven)
    }

    // MARK: - Group B: decoder defaults

    @Test("Omitted isEnabled defaults to true") func decodeOmittedIsEnabledDefaultsTrue() throws {
        let json = """
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "type": "low",
            "name": "Low Glucose",
            "thresholdMgDL": 72
        }
        """
        let decoded = try JSONDecoder().decode(GlucoseAlert.self, from: Data(json.utf8))
        #expect(decoded.isEnabled == true)
    }

    @Test("urgentLow with isEnabled false decodes false but still evaluates") func decodeUrgentLowDisabledStillEvaluates() throws {
        let json = """
        {
            "id": "22222222-2222-2222-2222-222222222222",
            "type": "urgentLow",
            "name": "Urgent Low Glucose",
            "isEnabled": false,
            "thresholdMgDL": 54
        }
        """
        let decoded = try JSONDecoder().decode(GlucoseAlert.self, from: Data(json.utf8))
        #expect(decoded.isEnabled == false)
        #expect(decoded.shouldEvaluate == true)
    }

    @Test("high with optional fields omitted uses type defaults") func decodeHighDefaults() throws {
        let json = """
        {
            "id": "33333333-3333-3333-3333-333333333333",
            "type": "high",
            "name": "High Glucose",
            "thresholdMgDL": 270
        }
        """
        let decoded = try JSONDecoder().decode(GlucoseAlert.self, from: Data(json.utf8))
        #expect(decoded.soundFilename == GlucoseAlertType.high.defaultSoundFilename)
        #expect(decoded.playsSound == true)
        #expect(decoded.overridesSilenceAndDND == false)
        #expect(decoded.activeOption == .always)
        #expect(decoded.snoozedUntil == nil)
        #expect(decoded.isEnabled == true)
    }

    @Test("urgentLow with overridesSilenceAndDND omitted uses type defaults") func decodeUrgentLowOverrideDefault() throws {
        let json = """
        {
            "id": "44444444-4444-4444-4444-444444444444",
            "type": "urgentLow",
            "name": "Urgent Low Glucose",
            "thresholdMgDL": 54
        }
        """
        let decoded = try JSONDecoder().decode(GlucoseAlert.self, from: Data(json.utf8))
        #expect(decoded.overridesSilenceAndDND == true)
        #expect(decoded.soundFilename == GlucoseAlertType.urgentLow.defaultSoundFilename)
    }

    // MARK: - Group C: round-trip

    @Test("Fully-populated value survives encode/decode round-trip") func roundTrip() throws {
        var original = GlucoseAlert(type: .low)
        original.name = "Custom Low Alarm"
        original.isEnabled = false
        original.thresholdMgDL = 65
        original.soundFilename = "custom_sound.caf"
        original.playsSound = false
        original.overridesSilenceAndDND = true
        original.activeOption = .night
        original.snoozedUntil = Date(timeIntervalSinceReferenceDate: 1_000_000)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GlucoseAlert.self, from: data)
        #expect(decoded == original)
    }
}

@Suite("Trio Alerts: GlucoseAlert CGM-style chime settings") struct GlucoseAlertChimeSettingsTests {
    @Test("New alarms default to continuous with a 5-minute chime interval") func defaultsOff() {
        for type in GlucoseAlertType.allCases {
            let a = GlucoseAlert(type: type)
            #expect(a.soundBehavior == .continuous)
            #expect(a.chimeRepeatInterval == .fiveMinutes)
            #expect(!a.usesChime)
        }
    }

    @Test("Alarms saved before the chime option decode as continuous") func legacyDecodesContinuous() throws {
        let legacy = """
        {"id":"\(UUID().uuidString)","type":"low","name":"Low","isEnabled":true,"thresholdMgDL":72,
         "soundFilename":"trill.caf","playsSound":true,"overridesSilenceAndDND":true,"activeOption":"always"}
        """
        let a = try JSONDecoder().decode(GlucoseAlert.self, from: Data(legacy.utf8))
        #expect(a.soundBehavior == .continuous)
        #expect(a.chimeRepeatInterval == .fiveMinutes)
        #expect(a.overridesSilenceAndDND)
    }

    @Test("Chime settings round-trip through Codable") func roundTrip() throws {
        var a = GlucoseAlert(type: .urgentLow)
        a.soundBehavior = .chime
        a.chimeRepeatInterval = .fifteenMinutes
        let decoded = try JSONDecoder().decode(GlucoseAlert.self, from: JSONEncoder().encode(a))
        #expect(decoded == a)
        #expect(decoded.usesChime)
    }

    @Test("Every glucose alarm type honours chime mode") func chimeOnAllTypes() {
        for type in GlucoseAlertType.allCases {
            var a = GlucoseAlert(type: type)
            a.soundBehavior = .chime
            #expect(a.usesChime)
        }
    }

    @Test("Chime intervals are exactly 5, 10 and 15 minutes") func intervals() {
        #expect(GlucoseAlertChimeInterval.allCases.map(\.timeInterval) == [300, 600, 900])
    }
}
