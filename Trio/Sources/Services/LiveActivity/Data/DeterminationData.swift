import Foundation

struct DeterminationData {
    let cob: Int
    let tdd: Decimal
    let target: Decimal
    let date: Date?
    let minForecast: [Int]
    let maxForecast: [Int]
    let forecastLines: [(type: String, values: [Int])]
    /// Eventual glucose in mg/dL, as shown on Trio's home screen.
    let eventualGlucose: Int?
}
