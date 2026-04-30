import Foundation

struct UsageSnapshot: Decodable, Equatable, Sendable {
    /// 5-hour rolling window. Whole field may be `null` from the API.
    let fiveHour: UsageWindow?

    /// 7-day rolling window. Whole field may be `null` from the API.
    let sevenDay: UsageWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}
