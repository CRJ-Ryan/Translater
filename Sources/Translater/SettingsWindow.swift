import AppKit

/// Settings window for choosing languages and configuring translation API credentials.
final class SettingsWindow: NSWindow {

    private var sourceLanguage: LanguageOption
    private var targetLanguage: LanguageOption
    private var baiduAppID: String
    private var baiduSecret: String
    private var onApply: ((LanguageOption, LanguageOption) -> Void)?
    private var onCredentialsChange: ((String, String) -> Void)?

    private let sourcePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let targetPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let appIDField = NSTextField(frame: .zero)
    private let secretField = NSSecureTextField(frame: .zero)

    init(
        source: LanguageOption,
        target: LanguageOption,
        baiduAppID: String,
        baiduSecret: String,
        onApply: @escaping (LanguageOption, LanguageOption) -> Void,
        onCredentialsChange: @escaping (String, String) -> Void
    ) {
        self.sourceLanguage = source
        self.targetLanguage = target
        self.baiduAppID = baiduAppID
        self.baiduSecret = baiduSecret
        self.onApply = onApply
        self.onCredentialsChange = onCredentialsChange

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 420),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        title = "翻译设置"
        isReleasedWhenClosed = false
        setupUI()
        populateLanguages()
        selectCurrent()
        center()
    }

    // MARK: - UI

    private func setupUI() {
        guard let contentView = contentView else { return }

        // === Language Section ===
        let langHeader = makeHeader("语言设置")

        let srcTitle = makeLabel("源语言")
        sourcePopup.controlSize = .small
        sourcePopup.target = self
        sourcePopup.action = #selector(sourceDidChange)

        let swapBtn = NSButton(title: "⇄ 交换", target: self, action: #selector(swapTapped))
        swapBtn.bezelStyle = .rounded
        swapBtn.controlSize = .small

        let tgtTitle = makeLabel("目标语言")
        targetPopup.controlSize = .small
        targetPopup.target = self
        targetPopup.action = #selector(targetDidChange)

        // Quick presets
        let presets: [(String, String, String)] = [
            ("中→英", "zh", "en"),
            ("英→中", "en", "zh"),
            ("中→日", "zh", "ja"),
            ("日→中", "ja", "zh"),
        ]
        var presetBtns: [NSButton] = []
        for (title, src, tgt) in presets {
            let b = NSButton(title: title, target: self, action: #selector(presetTapped(_:)))
            b.bezelStyle = .inline
            b.controlSize = .small
            b.identifier = NSUserInterfaceItemIdentifier("\(src)|\(tgt)")
            presetBtns.append(b)
        }

        // === Baidu API Section ===
        let apiHeader = makeHeader("百度翻译 API（可选，不填则用免费引擎）")
        let apiHint = makeLabel("注册获取: https://fanyi-api.baidu.com")
        apiHint.font = .systemFont(ofSize: 10)
        apiHint.textColor = .tertiaryLabelColor

        let appIDLabel = makeLabel("APP ID")
        appIDField.controlSize = .small
        appIDField.placeholderString = "输入百度翻译 APP ID"
        appIDField.stringValue = baiduAppID
        appIDField.delegate = self

        let secretLabel = makeLabel("密钥 (Secret Key)")
        secretField.controlSize = .small
        secretField.placeholderString = "输入百度翻译 Secret Key"
        secretField.stringValue = baiduSecret
        secretField.delegate = self

        // === Layout ===
        let allViews: [NSView] = [
            langHeader, srcTitle, sourcePopup, swapBtn, tgtTitle, targetPopup,
            apiHeader, apiHint, appIDLabel, appIDField, secretLabel, secretField,
        ] + presetBtns
        for v in allViews { v.translatesAutoresizingMaskIntoConstraints = false }
        for v in allViews { contentView.addSubview(v) }

        let pad: CGFloat = 24
        var constraints: [NSLayoutConstraint] = []

        // Language header
        constraints += [
            langHeader.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            langHeader.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: pad),
        ]

        // Source
        constraints += [
            srcTitle.topAnchor.constraint(equalTo: langHeader.bottomAnchor, constant: 10),
            srcTitle.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: pad),

            sourcePopup.topAnchor.constraint(equalTo: srcTitle.bottomAnchor, constant: 4),
            sourcePopup.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: pad),
            sourcePopup.widthAnchor.constraint(equalToConstant: 130),

            swapBtn.centerYAnchor.constraint(equalTo: sourcePopup.centerYAnchor),
            swapBtn.leadingAnchor.constraint(equalTo: sourcePopup.trailingAnchor, constant: 12),
        ]

        // Target
        constraints += [
            tgtTitle.topAnchor.constraint(equalTo: srcTitle.topAnchor),
            tgtTitle.leadingAnchor.constraint(equalTo: swapBtn.trailingAnchor, constant: 20),

            targetPopup.topAnchor.constraint(equalTo: tgtTitle.bottomAnchor, constant: 4),
            targetPopup.leadingAnchor.constraint(equalTo: tgtTitle.leadingAnchor),
            targetPopup.widthAnchor.constraint(equalToConstant: 130),
        ]

        // Presets
        constraints += presetBtns.enumerated().map { i, btn in
            let prev: NSView = i == 0 ? sourcePopup : presetBtns[i - 1]
            return [
                btn.topAnchor.constraint(equalTo: prev.bottomAnchor, constant: 6),
                btn.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: pad),
            ]
        }.flatMap { $0 }

        // Separator-like spacing
        let lastPreset = presetBtns.last ?? sourcePopup

        // API section
        constraints += [
            apiHeader.topAnchor.constraint(equalTo: lastPreset.bottomAnchor, constant: 24),
            apiHeader.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: pad),

            apiHint.topAnchor.constraint(equalTo: apiHeader.bottomAnchor, constant: 2),
            apiHint.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: pad),

            appIDLabel.topAnchor.constraint(equalTo: apiHint.bottomAnchor, constant: 12),
            appIDLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: pad),

            appIDField.topAnchor.constraint(equalTo: appIDLabel.bottomAnchor, constant: 2),
            appIDField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: pad),
            appIDField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -pad),

            secretLabel.topAnchor.constraint(equalTo: appIDField.bottomAnchor, constant: 12),
            secretLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: pad),

            secretField.topAnchor.constraint(equalTo: secretLabel.bottomAnchor, constant: 2),
            secretField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: pad),
            secretField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -pad),
        ]

        NSLayoutConstraint.activate(constraints)
    }

    private func makeHeader(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .labelColor
        return label
    }

    private func makeLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        return label
    }

    // MARK: - Populate

    private func populateLanguages() {
        sourcePopup.removeAllItems()
        targetPopup.removeAllItems()
        for lang in LanguageOption.all {
            sourcePopup.addItem(withTitle: lang.displayName)
            sourcePopup.lastItem?.representedObject = lang
            targetPopup.addItem(withTitle: lang.displayName)
            targetPopup.lastItem?.representedObject = lang
        }
    }

    private func selectCurrent() {
        selectPopup(sourcePopup, language: sourceLanguage)
        selectPopup(targetPopup, language: targetLanguage)
    }

    private func selectPopup(_ popup: NSPopUpButton, language: LanguageOption) {
        for i in 0..<popup.numberOfItems {
            if let lang = popup.item(at: i)?.representedObject as? LanguageOption,
               lang.code == language.code {
                popup.selectItem(at: i)
                return
            }
        }
    }

    private func readSelected(_ popup: NSPopUpButton) -> LanguageOption? {
        popup.selectedItem?.representedObject as? LanguageOption
    }

    private func applyLanguages() {
        if let src = readSelected(sourcePopup) { sourceLanguage = src }
        if let tgt = readSelected(targetPopup) { targetLanguage = tgt }
        onApply?(sourceLanguage, targetLanguage)
    }

    private func applyCredentials() {
        baiduAppID = appIDField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        baiduSecret = secretField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        onCredentialsChange?(baiduAppID, baiduSecret)
        print("[Settings] 百度凭证已更新")
    }

    // MARK: - Actions

    @objc private func sourceDidChange() { applyLanguages() }
    @objc private func targetDidChange() { applyLanguages() }

    @objc private func swapTapped() {
        swap(&sourceLanguage, &targetLanguage)
        selectPopup(sourcePopup, language: sourceLanguage)
        selectPopup(targetPopup, language: targetLanguage)
        applyLanguages()
    }

    @objc private func presetTapped(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        let parts = id.split(separator: "|").map(String.init)
        guard parts.count == 2 else { return }
        sourceLanguage = LanguageOption.findByCode(parts[0])
        targetLanguage = LanguageOption.findByCode(parts[1])
        selectPopup(sourcePopup, language: sourceLanguage)
        selectPopup(targetPopup, language: targetLanguage)
        applyLanguages()
    }
}

// MARK: - NSTextFieldDelegate

extension SettingsWindow: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        applyCredentials()
    }
}
