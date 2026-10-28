import Foundation

/// Decides when a request to the usage endpoint is allowed, so we never hammer it.
public struct FetchPolicy: Equatable, Sendable {
    public static let minGap: TimeInterval = 60
    public static let rateLimitBase: TimeInterval = 15 * 60
    public static let rateLimitCap: TimeInterval = 60 * 60
    public static let networkBase: TimeInterval = 60
    public static let networkCap: TimeInterval = 15 * 60

    public private(set) var lastAttempt: Date?
    public private(set) var lastSuccess: Date?
    /// Set after 429 or network errors: no requests before this moment.
    public private(set) var blockedUntil: Date?
    public private(set) var rateLimitStrikes = 0
    public private(set) var networkStrikes = 0
    /// Token that got a 401; we don't retry until the keychain holds a different one.
    public private(set) var rejectedToken: String?

    public init() {}

    /// The "Обновить" menu item. Requests happen only on this manual action.
    public func canFetch(now: Date) -> Bool {
        nextAllowed(now: now) == nil
    }

    /// When the next request is allowed, or nil if it is allowed right now.
    public func nextAllowed(now: Date) -> Date? {
        var next: Date?
        if let blockedUntil, now < blockedUntil { next = blockedUntil }
        if let lastAttempt {
            let gapEnd = lastAttempt.addingTimeInterval(Self.minGap)
            if now < gapEnd { next = max(next ?? gapEnd, gapEnd) }
        }
        return next
    }

    /// The token was already rejected, so asking again would only be another 401.
    public func isRejected(token: String) -> Bool {
        token == rejectedToken
    }

    public mutating func recordAttempt(now: Date) {
        lastAttempt = now
    }

    public mutating func recordSuccess(now: Date) {
        lastSuccess = now
        blockedUntil = nil
        rateLimitStrikes = 0
        networkStrikes = 0
        rejectedToken = nil
    }

    public mutating func recordRateLimit(now: Date, retryAfter: TimeInterval?) {
        rateLimitStrikes += 1
        let backoff = min(Self.rateLimitBase * pow(2, Double(rateLimitStrikes - 1)), Self.rateLimitCap)
        let delay = retryAfter.map { max($0, Self.minGap) } ?? backoff
        blockedUntil = now.addingTimeInterval(delay)
    }

    public mutating func recordNetworkError(now: Date) {
        networkStrikes += 1
        let delay = min(Self.networkBase * pow(2, Double(networkStrikes - 1)), Self.networkCap)
        blockedUntil = now.addingTimeInterval(delay)
    }

    public mutating func recordAuthRejected(token: String) {
        rejectedToken = token
    }
}
