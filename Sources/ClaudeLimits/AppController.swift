import AppKit
import ClaudeLimitsCore
import ServiceManagement
import WidgetKit

@MainActor
final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum Problem {
        case noLogin
        case loginExpired
        case rateLimited(until: Date)
        case error(String)
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let notifier = Notifier()
    private var policy = FetchPolicy()
    private var usage: UsageResponse?
    private var problem: Problem?
    private var isLoading = false
    private var menuIsOpen = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        // No timers and no automatic requests: data is fetched only via "Обновить".
        render()
    }

    /// The ↻ button on the desktop widget opens claudelimits://refresh.
    func application(_ application: NSApplication, open urls: [URL]) {
        if urls.contains(WidgetSnapshot.refreshURL) { refresh() }
    }

    @objc private func refresh() {
        guard policy.canFetch(now: Date()) else { return }
        Task { await fetch(reason: "manual") }
    }

    // MARK: - Fetching

    private func fetch(reason: String) async {
        guard !isLoading else { return }
        isLoading = true
        render()
        defer {
            isLoading = false
            render()
            publishToWidget()
        }

        let creds = await Task.detached { UsageAPI.readCredentials() }.value
        let now = Date()
        guard let creds else {
            problem = .noLogin
            return
        }
        if creds.isExpired(now: now) || policy.isRejected(token: creds.accessToken) {
            problem = .loginExpired
            return
        }

        log.info("fetch (\(reason, privacy: .public))")
        policy.recordAttempt(now: now)
        switch await UsageAPI.fetch(token: creds.accessToken) {
        case .success(let response):
            usage = response
            problem = nil
            policy.recordSuccess(now: Date())
            notifier.process(response)
        case .unauthorized:
            policy.recordAuthRejected(token: creds.accessToken)
            problem = .loginExpired
        case .rateLimited(let retryAfter):
            policy.recordRateLimit(now: Date(), retryAfter: retryAfter)
            problem = .rateLimited(until: policy.blockedUntil ?? Date())
        case .failed(let message):
            policy.recordNetworkError(now: Date())
            problem = .error(message)
        }
    }

    // MARK: - Widget

    /// Hands the result to the widget. Without fresh data the previous numbers stay, only greyed.
    private func publishToWidget() {
        var snapshot = usage.map { WidgetSnapshot(usage: $0, updatedAt: policy.lastSuccess, isStale: isStale) }
            ?? WidgetSnapshot.load() ?? WidgetSnapshot()
        snapshot.isStale = isStale
        do {
            try snapshot.save()
        } catch {
            log.error("widget snapshot: \(error.localizedDescription)")
        }
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshot.widgetKind)
    }

    // MARK: - Menu bar label

    /// Grey when the last request failed, so the numbers may be outdated.
    private var isStale: Bool {
        problem != nil
    }

    private func render() {
        renderLabel()
        if menuIsOpen { buildMenu() }
    }

    private func renderLabel() {
        guard let button = statusItem.button else { return }
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let title = NSMutableAttributedString()
        func add(_ text: String, _ color: NSColor) {
            title.append(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color]))
        }
        let base: NSColor = isStale ? .secondaryLabelColor : .labelColor
        add("✳ ", base)
        if let usage {
            add(Fmt.percent(usage.fiveHour?.utilization), color(for: usage.fiveHour?.utilization, base: base))
            add(" · ", base)
            add(Fmt.percent(usage.sevenDay?.utilization), color(for: usage.sevenDay?.utilization, base: base))
        } else {
            add("—", base)
        }
        button.attributedTitle = title
    }

    private func color(for utilization: Double?, base: NSColor) -> NSColor {
        switch Level.of(utilization) {
        case .normal: return base
        case .warning: return .systemOrange
        case .critical: return .systemRed
        }
    }

    // MARK: - Menu

    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
        buildMenu()
    }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
    }

    private func buildMenu() {
        let now = Date()
        menu.removeAllItems()

        let rows: [(String, UsageWindow?, Bool)] = [
            ("Сессия (5 ч)", usage?.fiveHour, true),
            ("Неделя", usage?.sevenDay, false),
            ("Неделя Opus", usage?.sevenDayOpus, false),
            ("Неделя Sonnet", usage?.sevenDaySonnet, false),
        ]
        for (index, (title, window, relative)) in rows.enumerated() {
            // Opus/Sonnet rows appear only when the API reports them.
            if index >= 2 && window?.utilization == nil { continue }
            var text = "\(title): \(Fmt.percent(window?.utilization))"
            if let reset = window?.resetsAt, reset > now {
                text += relative ? " · сброс \(Fmt.until(reset, now: now))"
                                 : " · сброс \(Fmt.dayTime(reset, now: now))"
            }
            menu.addItem(infoItem(text, color: color(for: window?.utilization, base: .labelColor)))
        }

        menu.addItem(.separator())
        for line in statusLines(now: now) {
            menu.addItem(infoItem(line, color: .secondaryLabelColor))
        }

        menu.addItem(.separator())
        let wait = policy.nextAllowed(now: now)
        let refreshTitle = isLoading ? "Обновляю…"
            : wait.map { "Обновить (можно в \(Fmt.clock($0)))" } ?? "Обновить"
        let refreshItem = NSMenuItem(title: refreshTitle, action: #selector(refresh), keyEquivalent: "r")
        refreshItem.target = self
        refreshItem.isEnabled = !isLoading && wait == nil
        menu.addItem(refreshItem)

        menu.addItem(.separator())
        let login = NSMenuItem(title: "Запускать при входе", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        let quit = NSMenuItem(title: "Выход", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func statusLines(now: Date) -> [String] {
        var lines: [String] = []
        switch problem {
        case .noLogin:
            lines.append("Нет входа Claude Code — выполните claude в терминале")
        case .loginExpired:
            lines.append("Вход истёк — откройте Claude Code, чтобы обновить")
        case .rateLimited(let until):
            lines.append("Сервер просит подождать до \(Fmt.clock(until))")
        case .error(let message):
            lines.append(message)
        case nil:
            break
        }
        if let last = policy.lastSuccess {
            lines.append("Данные от \(Fmt.clock(last)) (\(Fmt.ago(last, now: now)))")
        } else if !isLoading && problem == nil {
            lines.append("Нажмите «Обновить», чтобы загрузить лимиты")
        }
        return lines
    }

    private func infoItem(_ text: String, color: NSColor) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(string: text, attributes: [
            .foregroundColor: color,
            .font: NSFont.menuFont(ofSize: 0),
        ])
        return item
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            log.error("login item: \(error.localizedDescription)")
        }
    }
}
