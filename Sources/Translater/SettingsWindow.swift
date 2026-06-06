import AppKit

/// Settings window for choosing source and target languages.
final class SettingsWindow: NSWindow {

    private var sourceLanguage: LanguageOption
    private var targetLanguage: LanguageOption
    private var onApply: ((LanguageOption, LanguageOption) -> Void)?

    private let sourcePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let targetPopup = NSPopUpButton(frame: .zero, pullsDown: false)

    init(source: LanguageOption, target: LanguageOption, onApply: @escaping (LanguageOption, LanguageOption) -> Void) {
        self.sourceLanguage = source
        self.targetLanguage = target
        self.onApply = onApply

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 260),
            styleMask: [.titled, .closable],
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

        // Source section
        let srcTitle = makeLabel("源语言（你输入的语言）")
        contentView.addSubview(srcTitle)

        sourcePopup.controlSize = .small
        sourcePopup.target = self
        sourcePopup.action = #selector(sourceDidChange)
        contentView.addSubview(sourcePopup)

        // Swap button
        let swapBtn = NSButton(
            title: "⇄ 交换",
            target: self,
            action: #selector(swapTapped)
        )
        swapBtn.bezelStyle = .rounded
        swapBtn.controlSize = .small
        contentView.addSubview(swapBtn)

        // Target section
        let tgtTitle = makeLabel("目标语言（翻译结果）")
        contentView.addSubview(tgtTitle)

        targetPopup.controlSize = .small
        targetPopup.target = self
        targetPopup.action = #selector(targetDidChange)
        contentView.addSubview(targetPopup)

        // Presets
        let presetsTitle = makeLabel("快捷预设：")
        presetsTitle.font = .systemFont(ofSize: 10, weight: .medium)
        presetsTitle.textColor = .secondaryLabelColor
        contentView.addSubview(presetsTitle)

        let presets: [(String, String, String)] = [
            ("中→英", "zh", "en"),
            ("英→中", "en", "zh"),
            ("中→日", "zh", "ja"),
            ("日→中", "ja", "zh"),
        ]

        var presetBtns: [NSButton] = []
        for (title, src, tgt) in presets {
            let btn = NSButton(title: title, target: self, action: #selector(presetTapped(_:)))
            btn.bezelStyle = .inline
            btn.controlSize = .small
            btn.identifier = NSUserInterfaceItemIdentifier("\(src)|\(tgt)")
            contentView.addSubview(btn)
            presetBtns.append(btn)
        }

        // Layout
        let views: [NSView] = [srcTitle, sourcePopup, swapBtn, tgtTitle, targetPopup, presetsTitle] + presetBtns
        for v in views { v.translatesAutoresizingMaskIntoConstraints = false }

        NSLayoutConstraint.activate([
            // Source
            srcTitle.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            srcTitle.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),

            sourcePopup.topAnchor.constraint(equalTo: srcTitle.bottomAnchor, constant: 6),
            sourcePopup.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            sourcePopup.widthAnchor.constraint(equalToConstant: 130),

            // Swap button
            swapBtn.centerYAnchor.constraint(equalTo: sourcePopup.centerYAnchor),
            swapBtn.leadingAnchor.constraint(equalTo: sourcePopup.trailingAnchor, constant: 12),

            // Target
            tgtTitle.topAnchor.constraint(equalTo: sourcePopup.bottomAnchor, constant: 20),
            tgtTitle.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),

            targetPopup.topAnchor.constraint(equalTo: tgtTitle.bottomAnchor, constant: 6),
            targetPopup.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            targetPopup.widthAnchor.constraint(equalToConstant: 130),

            // Presets
            presetsTitle.topAnchor.constraint(equalTo: targetPopup.bottomAnchor, constant: 20),
            presetsTitle.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
        ])

        // Preset buttons in a row
        var prev: NSView = presetsTitle
        for btn in presetBtns {
            NSLayoutConstraint.activate([
                btn.topAnchor.constraint(equalTo: prev.bottomAnchor, constant: 6),
                btn.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            ])
            prev = btn
        }
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
                print("[Settings] 选中 \(popup == sourcePopup ? "源" : "目标"): \(lang.displayName)")
                return
            }
        }
    }

    private func readSelected(_ popup: NSPopUpButton) -> LanguageOption? {
        return popup.selectedItem?.representedObject as? LanguageOption
    }

    private func apply() {
        if let src = readSelected(sourcePopup) { sourceLanguage = src }
        if let tgt = readSelected(targetPopup) { targetLanguage = tgt }
        print("[Settings] 应用: \(sourceLanguage.displayName) → \(targetLanguage.displayName)")
        onApply?(sourceLanguage, targetLanguage)
    }

    // MARK: - Actions

    @objc private func sourceDidChange() {
        print("[Settings] 源语言变更")
        apply()
    }

    @objc private func targetDidChange() {
        print("[Settings] 目标语言变更")
        apply()
    }

    @objc private func swapTapped() {
        swap(&sourceLanguage, &targetLanguage)
        selectPopup(sourcePopup, language: sourceLanguage)
        selectPopup(targetPopup, language: targetLanguage)
        apply()
    }

    @objc private func presetTapped(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        let parts = id.split(separator: "|").map(String.init)
        guard parts.count == 2 else { return }

        sourceLanguage = LanguageOption.findByCode(parts[0])
        targetLanguage = LanguageOption.findByCode(parts[1])

        selectPopup(sourcePopup, language: sourceLanguage)
        selectPopup(targetPopup, language: targetLanguage)

        print("[Settings] 预设: \(sourceLanguage.displayName) → \(targetLanguage.displayName)")
        apply()
    }
}
