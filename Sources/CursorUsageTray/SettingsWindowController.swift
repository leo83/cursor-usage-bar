import AppKit

final class SettingsWindowController: NSWindowController {
    private let proxyCheckbox = NSButton(checkboxWithTitle: "Использовать HTTP(S)-прокси", target: nil, action: nil)
    private let colorCheckbox = NSButton(checkboxWithTitle: "Цветные столбики (иначе чёрно-белые)", target: nil, action: nil)
    private let lettersCheckbox = NSButton(checkboxWithTitle: "Показывать буквы в столбиках (f / a / o)", target: nil, action: nil)
    private let iconCheckbox = NSButton(checkboxWithTitle: "Показывать значок Cursor", target: nil, action: nil)
    private let copyBuildButton = NSButton(title: "Копировать", target: nil, action: nil)
    private let deleteTokenButton = NSButton(title: "Удалить сохранённый токен", target: nil, action: nil)
    private let proxyField = NSTextField()
    private let endpointField = NSTextField()
    private let tokenField = NSSecureTextField()
    private let intervalField = NSTextField()
    private let timeZonePopup = NSPopUpButton()

    private static let systemZoneTitle = "Системный (локальный)"
    private static let zoneIdentifiers = TimeZone.knownTimeZoneIdentifiers.sorted()

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Настройки Cursor Usage"
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
        buildUI()
        loadValues()
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        proxyCheckbox.target = self
        proxyCheckbox.action = #selector(proxyToggled)

        let proxyLabel = makeLabel("Прокси URL:")
        let endpointLabel = makeLabel("Usage endpoint:")
        let tokenLabel = makeLabel("Токен:")
        let intervalLabel = makeLabel("Интервал (сек):")
        let tzLabel = makeLabel("Часовой пояс:")

        timeZonePopup.addItem(withTitle: Self.systemZoneTitle)
        timeZonePopup.menu?.addItem(.separator())
        timeZonePopup.addItems(withTitles: Self.zoneIdentifiers)

        proxyField.placeholderString = "http://user:pass@host:3128"
        endpointField.placeholderString = Settings.defaultUsageEndpoint
        tokenField.placeholderString = "оставьте пустым, чтобы не менять Keychain"
        intervalField.placeholderString = "60"

        [proxyField, endpointField, tokenField, intervalField].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.usesSingleLineMode = true
            $0.lineBreakMode = .byTruncatingTail
            $0.cell?.wraps = false
            $0.cell?.isScrollable = true
            $0.maximumNumberOfLines = 1
        }

        let proxyHint = hintLabel(
            "Формат как в HTTPS_PROXY, включая логин:пароль. Если поле пустое, прокси автоматически берётся из окружения."
        )
        let tokenHint = hintLabel(
            "Поддерживаются env-переменные CURSOR_API_KEY/CURSOR_TOKEN. Заполненное поле сохраняется в Keychain приложения."
        )

        let saveButton = NSButton(title: "Сохранить", target: self, action: #selector(save))
        saveButton.keyEquivalent = "\r"
        let cancelButton = NSButton(title: "Закрыть", target: self, action: #selector(closeWindow))

        deleteTokenButton.target = self
        deleteTokenButton.action = #selector(deleteToken)
        deleteTokenButton.controlSize = .small
        deleteTokenButton.bezelStyle = .rounded

        let buildLabel = makeLabel("Сборка:")
        let buildValue = NSTextField(labelWithString: BuildInfo.display)
        buildValue.isSelectable = true
        buildValue.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        buildValue.textColor = .secondaryLabelColor
        copyBuildButton.target = self
        copyBuildButton.action = #selector(copyBuild)
        copyBuildButton.controlSize = .small
        copyBuildButton.bezelStyle = .rounded
        let buildRow = NSStackView(views: [buildValue, copyBuildButton])
        buildRow.orientation = .horizontal
        buildRow.spacing = 8

        let grid = NSGridView(views: [
            [NSGridCell.emptyContentView, proxyCheckbox],
            [proxyLabel, proxyField],
            [NSGridCell.emptyContentView, proxyHint],
            [endpointLabel, endpointField],
            [tokenLabel, tokenField],
            [NSGridCell.emptyContentView, tokenHint],
            [NSGridCell.emptyContentView, deleteTokenButton],
            [intervalLabel, intervalField],
            [NSGridCell.emptyContentView, iconCheckbox],
            [NSGridCell.emptyContentView, colorCheckbox],
            [NSGridCell.emptyContentView, lettersCheckbox],
            [tzLabel, timeZonePopup],
            [buildLabel, buildRow],
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowAlignment = .firstBaseline
        grid.rowSpacing = 10
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        for row in [0, 2, 5, 6, 8, 9, 10, 11, 12] {
            grid.cell(atColumnIndex: 1, rowIndex: row).xPlacement = .leading
        }
        grid.row(at: 2).rowAlignment = .none
        grid.row(at: 5).rowAlignment = .none

        let buttons = NSStackView(views: [cancelButton, saveButton])
        buttons.orientation = .horizontal
        buttons.spacing = 12
        buttons.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(grid)
        content.addSubview(buttons)

        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            proxyField.widthAnchor.constraint(greaterThanOrEqualToConstant: 360),
            endpointField.widthAnchor.constraint(greaterThanOrEqualToConstant: 360),
            tokenField.widthAnchor.constraint(greaterThanOrEqualToConstant: 360),
            buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
        ])
    }

    private func makeLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.alignment = .right
        return label
    }

    private func hintLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.preferredMaxLayoutWidth = 360
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    func loadValues() {
        proxyCheckbox.state = Settings.proxyEnabled ? .on : .off
        colorCheckbox.state = Settings.monochrome ? .off : .on
        lettersCheckbox.state = Settings.showLetters ? .on : .off
        iconCheckbox.state = Settings.showIcon ? .on : .off
        proxyField.stringValue = Settings.proxyURL
        endpointField.stringValue = Settings.usageEndpoint
        tokenField.stringValue = ""
        intervalField.stringValue = String(Settings.pollSeconds)

        let tzID = Settings.displayTimeZoneID
        if tzID.isEmpty || timeZonePopup.item(withTitle: tzID) == nil {
            timeZonePopup.selectItem(withTitle: Self.systemZoneTitle)
        } else {
            timeZonePopup.selectItem(withTitle: tzID)
        }
        updateProxyFieldsEnabled()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let editor = self.window?.fieldEditor(true, for: self.proxyField) as? NSTextView {
                editor.isAutomaticLinkDetectionEnabled = false
                editor.isAutomaticDataDetectionEnabled = false
                editor.isAutomaticTextReplacementEnabled = false
            }
            self.window?.makeFirstResponder(nil)
        }
    }

    private func updateProxyFieldsEnabled() {
        proxyField.isEnabled = proxyCheckbox.state == .on
    }

    @objc private func copyBuild() {
        BuildInfo.copyHashToPasteboard()
        copyBuildButton.title = "Скопировано ✓"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.copyBuildButton.title = "Копировать"
        }
    }

    @objc private func deleteToken() {
        if Credentials.deleteManualToken() {
            deleteTokenButton.title = "Удалено"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.deleteTokenButton.title = "Удалить сохранённый токен"
            }
        } else {
            showError("Не удалось удалить токен из Keychain")
        }
    }

    @objc private func proxyToggled() {
        updateProxyFieldsEnabled()
    }

    @objc private func save() {
        Settings.proxyEnabled = proxyCheckbox.state == .on
        Settings.monochrome = colorCheckbox.state == .off
        Settings.showLetters = lettersCheckbox.state == .on
        Settings.showIcon = iconCheckbox.state == .on
        Settings.proxyURL = proxyField.stringValue.trimmingCharacters(in: .whitespaces)
        Settings.usageEndpoint = endpointField.stringValue.trimmingCharacters(in: .whitespaces)
        if let interval = Int(intervalField.stringValue.trimmingCharacters(in: .whitespaces)) {
            Settings.pollSeconds = interval
        }
        let tzTitle = timeZonePopup.titleOfSelectedItem ?? Self.systemZoneTitle
        Settings.displayTimeZoneID = tzTitle == Self.systemZoneTitle ? "" : tzTitle

        let token = tokenField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty, !Credentials.saveManualToken(token) {
            showError("Не удалось сохранить токен в Keychain")
            return
        }

        NotificationCenter.default.post(name: .settingsChanged, object: nil)
        closeWindow()
    }

    private func showError(_ text: String) {
        let alert = NSAlert()
        alert.messageText = text
        alert.runModal()
    }

    @objc private func closeWindow() {
        window?.close()
    }
}
