import Foundation

public enum Fmt {
    public static func percent(_ u: Double?) -> String {
        guard let u else { return "—" }
        return "\(Int(u.rounded()))%"
    }

    /// "через 2ч 14м", "через 14м", "через 3д 4ч", "скоро".
    public static func until(_ date: Date, now: Date) -> String {
        let total = Int(date.timeIntervalSince(now))
        guard total >= 60 else { return "скоро" }
        let days = total / 86_400
        let hours = (total % 86_400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return "через \(days)д \(hours)ч" }
        if hours > 0 { return "через \(hours)ч \(minutes)м" }
        return "через \(minutes)м"
    }

    /// "чт 10:00", or "сегодня 10:00" / "завтра 10:00".
    public static func dayTime(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let time = DateFormatter()
        time.locale = Locale(identifier: "ru_RU")
        time.timeZone = calendar.timeZone
        time.dateFormat = "HH:mm"
        if calendar.isDate(date, inSameDayAs: now) { return "сегодня " + time.string(from: date) }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "завтра " + time.string(from: date)
        }
        time.dateFormat = "EE HH:mm"
        return time.string(from: date).lowercased(with: time.locale)
    }

    /// "только что", "5 мин назад", "2 ч назад".
    public static func ago(_ date: Date, now: Date) -> String {
        let s = Int(now.timeIntervalSince(date))
        if s < 60 { return "только что" }
        if s < 3600 { return "\(s / 60) мин назад" }
        return "\(s / 3600) ч назад"
    }

    public static func clock(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
