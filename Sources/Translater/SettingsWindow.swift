import AppKit

/// Settings window — floats above other windows so it doesn't get lost.
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
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 310),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        title = "翻译设置"
        isReleasedWhenClosed = false
        level = .floating
        setupUI()
        populateLanguages()
        selectCurrent()
        center()
    }

    // MARK: - UI

    private func setupUI() {
        guard let contentView = contentView else { return }
        let pad: CGFloat = 24

        // Source label + popup
        let srcTitle = makeLabel("源语言")
        sourcePopup.controlSize = .small
        sourcePopup.target = self
        sourcePopup.action = #selector(sourceDidChange)

        // Swap button
        let swapBtn = NSButton(title: "⇄ 交换", target: self, action: #selector(swapTapped))
        swapBtn.bezelStyle = .rounded
        swapBtn.controlSize = .small

        // Target label + popup
        let tgtTitle = makeLabel("目标语言")
        targetPopup.controlSize = .small
        targetPopup.target = self
        targetPopup.action = #selector(targetDidChange)

        // Presets in a row
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

        // Separator
        let sep = NSBox()
        sep.boxType = .separator

        // API section (compact)
        let apiTitle = makeLabel("百度翻译 API（可选，不填则用免费引擎）")
        let apiHint = NSTextField(labelWithString: "注册: fanyi-api.baidu.com → 管理控制台")
        apiHint.font = .systemFont(ofSize: 10)
        apiHint.textColor = .tertiaryLabelColor

        let idLabel = makeLabel("APP ID")
        appIDField.controlSize = .small
        appIDField.placeholderString = "输入 APP ID"
        appIDField.stringValue = baiduAppID
        appIDField.delegate = self

        let skLabel = makeLabel("密钥 (Secret Key)")
        secretField.controlSize = .small
        secretField.placeholderString = "输入 Secret Key"
        secretField.stringValue = baiduSecret
        secretField.delegate = self

        // Layout
        let all: [NSView] = [
            srcTitle, sourcePopup, swapBtn, tgtTitle, targetPopup,
            sep, apiTitle, apiHint, idLabel, appIDField, skLabel, secretField,
        ] + presetBtns
        for v in all {
            v.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(v)
        }

        NSLayoutConstraint.activate([
            // Source
            srcTitle.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            srcTitle.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: pad),

            sourcePopup.topAnchor.constraint(equalTo: srcTitle.bottomAnchor, constant: 4),
            sourcePopup.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: pad),
            sourcePopup.widthAnchor.constraint(equalToConstant: 120),

            swapBtn.centerYAnchor.constraint(equalTo: sourcePopup.centerYAnchor),
            swapBtn.leadingAnchor.constraint(equalTo: sourcePopup.trailingAnchor, constant: 8),

            // Target — constrain trailing to window edge so it won't be clipped
            tgtTitle.topAnchor.constraint(equalTo: srcTitle.topAnchor),
            tgtTitle.leadingAnchor.constraint(equalTo: swapBtn.trailingAnchor, constant: 16),

            targetPopup.topAnchor.constraint(equalTo: tgtTitle.bottomAnchor, constant: 4),
            targetPopup.leadingAnchor.constraint(equalTo: tgtTitle.leadingAnchor),
            targetPopup.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -pad),
        ])

        // Presets in a row
        for (i, btn) in presetBtns.enumerated() {
            let leading: NSLayoutXAxisAnchor = i == 0
                ? contentView.leadingAnchor
                : presetBtns[i - 1].trailingAnchor
            NSLayoutConstraint.activate([
                btn.topAnchor.constraint(equalTo: sourcePopup.bottomAnchor, constant: 10),
                btn.leadingAnchor.constraint(equalTo: leading, constant: i == 0 ? pad : 8),
            ])
        }

        // Separator
        let lastPreset = presetBtns.last ?? sourcePopup
        NSLayoutConstraint.activate([
            sep.topAnchor.constraint(equalTo: lastPreset.bottomAnchor, constant: 14),
            sep.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: pad),
            sep.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -pad),
        ])

        // API section
        NSLayoutConstraint.activate([
            apiTitle.topAnchor.constraint(equalTo: sep.bottomAnchor, constant: 12),
            apiTitle.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: pad),

            apiHint.topAnchor.constraint(equalTo: apiTitle.bottomAnchor, constant: 2),
            apiHint.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: pad),

            idLabel.topAnchor.constraint(equalTo: apiHint.bottomAnchor, constant: 10),
            idLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: pad),

            appIDField.topAnchor.constraint(equalTo: idLabel.bottomAnchor, constant: 2),
            appIDField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: pad),
            appIDField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -pad),

            skLabel.topAnchor.constraint(equalTo: appIDField.bottomAnchor, constant: 8),
            skLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: pad),

            secretField.topAnchor.constraint(equalTo: skLabel.bottomAnchor, constant: 2),
            secretField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: pad),
            secretField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -pad),
        ])
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

extension SettingsWindow: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        applyCredentials()
    }
}
