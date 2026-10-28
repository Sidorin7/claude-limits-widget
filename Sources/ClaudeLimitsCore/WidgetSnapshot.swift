import Foundation

/// What the app hands to the desktop widget after each "Обновить". The widget never fetches.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    /// "<TEAM_ID>.com.ivansidorin.claudelimits"; build.sh fills it in from the signing certificate.
    public static var appGroup: String? {
        Bundle.main.object(forInfoDictionaryKey: "ClaudeLimitsAppGroup") as? String
    }
    public static let fileName = "widget-snapshot.json"
    public static let widgetKind = "ClaudeLimitsWidget"
    public static let refreshURL = URL(string: "claudelimits://refresh")!

    public var fiveHour: Double?
    public var sevenDay: Double?
    public var fiveHourResetsAt: Date?
    public var updatedAt: Date?
    /// The last request failed, so the numbers may be outdated.
    public var isStale: Bool

    public init(fiveHour: Double? = nil, sevenDay: Double? = nil, fiveHourResetsAt: Date? = nil,
                updatedAt: Date? = nil, isStale: Bool = false) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.fiveHourResetsAt = fiveHourResetsAt
        self.updatedAt = updatedAt
        self.isStale = isStale
    }

    public init(usage: UsageResponse?, updatedAt: Date?, isStale: Bool) {
        self.init(fiveHour: usage?.fiveHour?.utilization,
                  sevenDay: usage?.sevenDay?.utilization,
                  fiveHourResetsAt: usage?.fiveHour?.resetsAt,
                  updatedAt: updatedAt,
                  isStale: isStale)
    }

    /// The line under the rings: "сброс через 2ч 14м", "сессия сброшена" once the time passed.
    public func resetText(now: Date) -> String {
        guard let reset = fiveHourResetsAt else { return updatedAt == nil ? "нажмите ↻" : "" }
        return reset > now ? "сброс \(Fmt.until(reset, now: now))" : "сессия сброшена"
    }

    /// Moments at which `resetText` changes, so the widget can redraw the countdown
    /// without any requests. Capped to keep the timeline small.
    public func countdownDates(now: Date, limit: Int = 400) -> [Date] {
        var dates = [now]
        guard let reset = fiveHourResetsAt, reset > now else { return dates }
        // `Fmt.until` truncates whole minutes, so the text changes just after each
        // "reset minus N minutes" boundary.
        let left = reset.timeIntervalSince(now)
        var t = reset.addingTimeInterval(-floor(left / 60) * 60 + 1)
        if t <= now { t += 60 }
        while t <= reset + 1 && dates.count < limit {
            // The last step is the reset itself, when the text becomes "сессия сброшена".
            dates.append(min(t, reset))
            t += 60
        }
        return dates
    }

    public func encoded() throws -> Data {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return try e.encode(self)
    }

    public static func decode(_ data: Data) throws -> WidgetSnapshot {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return try d.decode(WidgetSnapshot.self, from: data)
    }

    /// The file in the shared app group container, readable by both the app and the widget.
    public static var fileURL: URL? {
        guard let appGroup else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(fileName)
    }

    public static func load() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? decode(data)
    }

    public func save() throws {
        guard let url = Self.fileURL else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoded().write(to: url, options: .atomic)
    }
}
