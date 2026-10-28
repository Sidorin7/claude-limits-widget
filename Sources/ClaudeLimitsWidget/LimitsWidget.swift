import ClaudeLimitsCore
import SwiftUI
import WidgetKit

@main
struct ClaudeLimitsWidgets: WidgetBundle {
    var body: some Widget {
        LimitsWidget()
    }
}

struct LimitsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshot.widgetKind, provider: Provider()) { entry in
            LimitsView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Claude Limits")
        .description("Сессия и недельный лимит. Обновляется только по кнопке ↻.")
        .supportedFamilies([.systemSmall])
    }
}

struct Entry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

/// Only reads what the app saved; never talks to the network.
struct Provider: TimelineProvider {
    static let sample = WidgetSnapshot(fiveHour: 42, sevenDay: 18,
                                       fiveHourResetsAt: Date().addingTimeInterval(2 * 3600 + 14 * 60),
                                       updatedAt: Date())

    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), snapshot: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        let snapshot = context.isPreview ? Self.sample : (WidgetSnapshot.load() ?? WidgetSnapshot())
        completion(Entry(date: Date(), snapshot: snapshot))
    }

    /// One entry per minute of the countdown; the app reloads the timeline after each refresh.
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let snapshot = WidgetSnapshot.load() ?? WidgetSnapshot()
        let entries = snapshot.countdownDates(now: Date()).map { Entry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .never))
    }
}

struct LimitsView: View {
    let entry: Entry

    private var snapshot: WidgetSnapshot { entry.snapshot }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("✳ Claude")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Link(destination: WidgetSnapshot.refreshURL) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 20, height: 20)
                        .background(.quaternary, in: Circle())
                }
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            HStack(spacing: 0) {
                Ring(title: "сессия", utilization: snapshot.fiveHour, isStale: snapshot.isStale)
                Spacer(minLength: 4)
                Ring(title: "неделя", utilization: snapshot.sevenDay, isStale: snapshot.isStale)
            }
            Spacer(minLength: 6)
            Text(snapshot.resetText(now: entry.date))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(snapshot.isStale ? .secondary : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

struct Ring: View {
    let title: String
    let utilization: Double?
    let isStale: Bool

    /// Same colors as the menu bar: orange from 80%, red from 95%, grey when outdated.
    private var color: Color {
        if isStale { return .gray }
        switch Level.of(utilization) {
        case .normal: return .blue
        case .warning: return .orange
        case .critical: return .red
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 6)
                Circle()
                    .trim(from: 0, to: min(max((utilization ?? 0) / 100, 0), 1))
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .widgetAccentable()
                Text(Fmt.percent(utilization))
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(isStale ? .secondary : .primary)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 60, height: 60)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
