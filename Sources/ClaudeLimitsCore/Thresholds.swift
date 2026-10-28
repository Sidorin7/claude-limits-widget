import Foundation

public enum Level: Equatable, Sendable {
    case normal, warning, critical

    public static func of(_ utilization: Double?) -> Level {
        guard let u = utilization else { return .normal }
        if u >= 95 { return .critical }
        if u >= 80 { return .warning }
        return .normal
    }
}

/// Remembers which thresholds were already announced for each window, so each one fires
/// once per window. A new `resetsAt` means a fresh window and starts over.
public struct ThresholdTracker: Sendable {
    public static let thresholds = [80, 95]

    public struct Record: Codable, Equatable, Sendable {
        public var resetsAt: Date?
        public var notified: Int
    }

    public private(set) var records: [String: Record]

    public init(records: [String: Record] = [:]) {
        self.records = records
    }

    /// Returns the threshold to announce now (the highest newly crossed one), or nil.
    public mutating func check(window: String, utilization: Double?, resetsAt: Date?) -> Int? {
        guard let u = utilization else { return nil }
        var rec = records[window] ?? Record(resetsAt: resetsAt, notified: 0)
        if !sameWindow(rec.resetsAt, resetsAt) {
            rec = Record(resetsAt: resetsAt, notified: 0)
        }
        let crossed = Self.thresholds.filter { Double($0) <= u }.max() ?? 0
        defer { records[window] = rec }
        guard crossed > rec.notified else { return nil }
        rec.notified = crossed
        return crossed
    }

    /// The server's reset time can drift by a few seconds between responses.
    private func sameWindow(_ a: Date?, _ b: Date?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (a?, b?): return abs(a.timeIntervalSince(b)) < 5 * 60
        default: return false
        }
    }
}
