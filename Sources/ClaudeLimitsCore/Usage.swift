import Foundation

/// One limit window, e.g. the 5-hour session or the weekly limit.
public struct UsageWindow: Decodable, Equatable, Sendable {
    /// Percent used, 0...100.
    public let utilization: Double?
    public let resetsAt: Date?

    public init(utilization: Double?, resetsAt: Date?) {
        self.utilization = utilization
        self.resetsAt = resetsAt
    }

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        utilization = try? c.decodeIfPresent(Double.self, forKey: .utilization)
        let raw = try? c.decodeIfPresent(String.self, forKey: .resetsAt)
        resetsAt = raw.flatMap(parseISODate)
    }
}

/// Response of GET https://api.anthropic.com/api/oauth/usage (unofficial; every field optional).
public struct UsageResponse: Decodable, Equatable, Sendable {
    public let fiveHour: UsageWindow?
    public let sevenDay: UsageWindow?
    public let sevenDayOpus: UsageWindow?
    public let sevenDaySonnet: UsageWindow?

    public init(fiveHour: UsageWindow?, sevenDay: UsageWindow?,
                sevenDayOpus: UsageWindow? = nil, sevenDaySonnet: UsageWindow? = nil) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.sevenDayOpus = sevenDayOpus
        self.sevenDaySonnet = sevenDaySonnet
    }

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fiveHour = try? c.decodeIfPresent(UsageWindow.self, forKey: .fiveHour)
        sevenDay = try? c.decodeIfPresent(UsageWindow.self, forKey: .sevenDay)
        sevenDayOpus = try? c.decodeIfPresent(UsageWindow.self, forKey: .sevenDayOpus)
        sevenDaySonnet = try? c.decodeIfPresent(UsageWindow.self, forKey: .sevenDaySonnet)
    }

    public static func decode(_ data: Data) throws -> UsageResponse {
        try JSONDecoder().decode(UsageResponse.self, from: data)
    }
}

/// Parses ISO 8601 with any number of fractional digits (the API sends microseconds,
/// which ISO8601DateFormatter does not accept), with or without a timezone suffix.
public func parseISODate(_ string: String) -> Date? {
    var s = string.trimmingCharacters(in: .whitespaces)
    if let r = s.range(of: #"\.\d+"#, options: .regularExpression) {
        s.removeSubrange(r)
    }
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    if let d = f.date(from: s) { return d }
    return f.date(from: s + "Z")
}

/// Claude Code's login stored in the macOS keychain.
public struct OAuthCredentials: Equatable, Sendable {
    public let accessToken: String
    public let expiresAt: Date?

    public init(accessToken: String, expiresAt: Date?) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
    }

    public func isExpired(now: Date) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= now
    }

    /// Parses `{"claudeAiOauth":{"accessToken":"...","expiresAt":1730000000000,...}}`.
    public static func parse(_ data: Data) -> OAuthCredentials? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else { return nil }
        var expires: Date?
        if let ms = oauth["expiresAt"] as? Double {
            expires = Date(timeIntervalSince1970: ms / 1000)
        }
        return OAuthCredentials(accessToken: token, expiresAt: expires)
    }
}
