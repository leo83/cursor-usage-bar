import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let client = UsageClient()
    private var timer: Timer?
    private var minuteTimer: Timer?
    private var lastBars: [BarSpec] = []
    private var lastFetch: Date?
    private var currentStale: Stale?
    private var settingsController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Settings.adoptEnvProxyIfEmpty()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = BarsRenderer.placeholder(monochrome: Settings.monochrome, showLetters: Settings.showLetters, showIcon: Settings.showIcon)
        statusItem.button?.toolTip = "Cursor usage: загрузка..."

        buildMenu(bars: [], error: nil, stale: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsChanged),
            name: .settingsChanged,
            object: nil
        )

        refresh()
        startTimer()

        minuteTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self, !self.lastBars.isEmpty else { return }
            self.renderIcon(bars: self.lastBars, stale: self.currentStale)
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(Settings.pollSeconds), repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    @objc private func settingsChanged() {
        startTimer()
        refresh()
    }

    @objc func refresh() {
        client.fetch { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let bars):
                self.lastBars = bars
                self.lastFetch = Date()
                self.currentStale = nil
                self.renderIcon(bars: bars, stale: nil)
                self.buildMenu(bars: bars, error: nil, stale: nil)
            case .failure(let error):
                if error.isTransient, !self.lastBars.isEmpty {
                    let stale: Stale = (error: error, since: self.lastFetch)
                    self.currentStale = stale
                    self.renderIcon(bars: self.lastBars, stale: stale)
                    self.buildMenu(bars: self.lastBars, error: nil, stale: stale)
                } else {
                    self.lastBars = []
                    self.currentStale = nil
                    self.statusItem.button?.image = BarsRenderer.placeholder(monochrome: Settings.monochrome, showLetters: Settings.showLetters, showIcon: Settings.showIcon)
                    self.statusItem.button?.toolTip = "Cursor usage: \(error.localizedDescription)"
                    self.buildMenu(bars: [], error: error, stale: nil)
                }
            }
        }
    }

    typealias Stale = (error: UsageError, since: Date?)

    private func renderIcon(bars: [BarSpec], stale: Stale?) {
        let blockingReset = soonestBlockingReset(bars)
        let countdown = blockingReset.map { compactCountdown(to: $0) }
        statusItem.button?.image = BarsRenderer.image(
            for: bars,
            monochrome: Settings.monochrome,
            showLetters: Settings.showLetters,
            showIcon: Settings.showIcon,
            countdown: countdown
        )
        statusItem.button?.toolTip = tooltip(for: bars, blockingReset: blockingReset, stale: stale)
    }

    private func soonestBlockingReset(_ bars: [BarSpec]) -> Date? {
        bars.filter { $0.isBlocking }
            .compactMap { $0.resetsAt }
            .filter { $0.timeIntervalSinceNow > 0 }
            .min()
    }

    private func compactCountdown(to date: Date) -> String {
        let totalMin = ceilMinutes(to: date)
        return String(format: "%d:%02d", totalMin / 60, totalMin % 60)
    }

    private func humanCountdown(to date: Date) -> String {
        let totalMin = ceilMinutes(to: date)
        let h = totalMin / 60
        let m = totalMin % 60
        return h > 0 ? "\(h)ч \(m)м" : "\(m)м"
    }

    private func ceilMinutes(to date: Date) -> Int {
        let secs = max(0, Int(date.timeIntervalSinceNow.rounded(.up)))
        return (secs + 59) / 60
    }

    private func staleNote(_ stale: Stale) -> String {
        let when = stale.since.map { "данные от \(formatClock($0))" } ?? "нет свежих данных"
        return "\(when) · \(stale.error.localizedDescription)"
    }

    private func formatReset(_ date: Date) -> String {
        Self.resetFormatter.timeZone = Settings.displayTimeZone
        return Self.resetFormatter.string(from: date)
    }

    private func formatClock(_ date: Date) -> String {
        Self.timeFormatter.timeZone = Settings.displayTimeZone
        return Self.timeFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.timeZone = .autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate("HH:mm")
        return f
    }()

    private func tooltip(for bars: [BarSpec], blockingReset: Date?, stale: Stale?) -> String {
        var lines = ["Cursor usage"]
        if let stale {
            lines.append("⚠️ \(staleNote(stale))")
        }
        if let reset = blockingReset {
            lines.append("⛔ Лимит исчерпан, разблокировка через \(humanCountdown(to: reset))")
        }
        for bar in bars {
            var line = "• \(bar.label): \(Int(bar.percent.rounded()))%"
            if let valueText = bar.valueText {
                line += " (\(valueText))"
            }
            if bar.isBlocking {
                line += " ⛔"
            }
            if let reset = bar.resetsAt {
                line += "  · сброс \(formatReset(reset))"
            }
            lines.append(line)
        }
        if bars.isEmpty { lines.append("нет данных") }
        return lines.joined(separator: "\n")
    }

    private static let resetFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.timeZone = .autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate("EEE d MMM HH:mm")
        return f
    }()

    private func buildMenu(bars: [BarSpec], error: UsageError?, stale: Stale?) {
        let menu = NSMenu()

        if let stale {
            let item = NSMenuItem(title: "⚠️ \(staleNote(stale))", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        if let error {
            let item = NSMenuItem(title: error.localizedDescription, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else if bars.isEmpty {
            let item = NSMenuItem(title: "Загрузка...", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            for bar in bars {
                var title = "\(bar.label): \(Int(bar.percent.rounded()))%"
                if let valueText = bar.valueText {
                    title += "  (\(valueText))"
                }
                if bar.isBlocking, let reset = bar.resetsAt {
                    title += "  ·  ⛔ разблокировка через \(humanCountdown(to: reset))"
                } else if let reset = bar.resetsAt {
                    title += "  ·  сброс \(formatReset(reset))"
                }
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: "Обновить", action: #selector(refresh), keyEquivalent: "r").target = self
        menu.addItem(withTitle: "Настройки...", action: #selector(openSettings), keyEquivalent: ",").target = self

        let loginItem = NSMenuItem(title: "Запускать при входе", action: #selector(toggleLoginItem), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = isLoginItemEnabled() ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Выход", action: #selector(quit), keyEquivalent: "q").target = self

        statusItem.menu = menu
    }

    @objc private func openSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController()
        }
        settingsController?.loadValues()
        NSApp.activate(ignoringOtherApps: true)
        settingsController?.showWindow(nil)
        settingsController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func isLoginItemEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    @objc private func toggleLoginItem() {
        do {
            if isLoginItemEnabled() {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Не удалось изменить автозапуск"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        refresh()
    }
}

extension Notification.Name {
    static let settingsChanged = Notification.Name("CursorUsageTray.settingsChanged")
}
