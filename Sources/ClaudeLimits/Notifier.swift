import ClaudeLimitsCore
import Foundation
import UserNotifications

/// Sends "80% / 95% used" notifications, once per threshold per limit window.
@MainActor
final class Notifier {
    private let defaultsKey = "thresholdRecords"
    private var tracker: ThresholdTracker

    init() {
        let data = UserDefaults.standard.data(forKey: defaultsKey)
        let records = data.flatMap { try? JSONDecoder().decode([String: ThresholdTracker.Record].self, from: $0) }
        tracker = ThresholdTracker(records: records ?? [:])
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func process(_ usage: UsageResponse) {
        let windows: [(id: String, title: String, window: UsageWindow?)] = [
            ("five_hour", "Сессия (5 ч)", usage.fiveHour),
            ("seven_day", "Недельный лимит", usage.sevenDay),
            ("seven_day_opus", "Недельный лимит Opus", usage.sevenDayOpus),
            ("seven_day_sonnet", "Недельный лимит Sonnet", usage.sevenDaySonnet),
        ]
        for w in windows {
            guard let window = w.window,
                  let hit = tracker.check(window: w.id, utilization: window.utilization, resetsAt: window.resetsAt)
            else { continue }
            send(title: "Claude: \(w.title) — \(Fmt.percent(window.utilization))",
                 body: window.resetsAt.map { "Сброс \(Fmt.dayTime($0, now: Date()))" } ?? "Использовано больше \(hit)%")
        }
        if let data = try? JSONEncoder().encode(tracker.records) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private func send(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
