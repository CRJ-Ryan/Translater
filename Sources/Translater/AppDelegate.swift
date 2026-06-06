import AppKit
import CoreGraphics
import Translation

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let eventTapManager = EventTapManager()
    private let floatingPanel = FloatingPanel()
    private var settingsWindow: SettingsWindow?

    /// Translation service
    private var translationService: TranslationService?
    /// Cached latest translation, used for Alt+Enter replacement
    private var latestTranslation: String = ""
    /// Debounced translation work item — fires after user pauses typing
    private var translateWorkItem: DispatchWorkItem?
    private let translateDebounce: TimeInterval = 0.4

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let sourceLanguage = "sourceLanguageCode"
        static let targetLanguage = "targetLanguageCode"
    }

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        checkAccessibilityPermissions()
    }

    // MARK: - Menu Bar

    private var monitorMenuItem: NSMenuItem!

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.title = "🌐"
            button.toolTip = "Translater - 边写边译 (Ctrl+Opt+T 开关)"
        }

        let menu = NSMenu()

        monitorMenuItem = NSMenuItem(
            title: "开启翻译",
            action: #selector(toggleMonitoring),
            keyEquivalent: ""
        )
        menu.addItem(monitorMenuItem)

        menu.addItem(.separator())
        let settingsItem = NSMenuItem(
            title: "语言设置...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = .command
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem(
            title: "显示/隐藏翻译面板",
            action: #selector(togglePanel),
            keyEquivalent: "t"
        ))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "请求辅助功能权限",
            action: #selector(requestPermissions),
            keyEquivalent: ""
        ))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "退出",
            action: #selector(quitApp),
            keyEquivalent: "q"
        ))

        statusItem.menu = menu
    }

    private func updateMonitorMenuItem() {
        if eventTapManager.isMonitoring {
            monitorMenuItem.title = "关闭翻译"
        } else {
            monitorMenuItem.title = "开启翻译"
        }
    }

    // MARK: - Permissions

    private func checkAccessibilityPermissions() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): false]
        let trusted = AXIsProcessTrustedWithOptions(options)

        if trusted {
            print("[Translater] ✅ 辅助功能权限已授权")
            startEventTap()
        } else {
            print("[Translater] ⚠️ 需要辅助功能权限")

            let alert = NSAlert()
            alert.messageText = "需要辅助功能权限"
            alert.informativeText = """
                Translater 需要辅助功能权限来监听键盘输入。

                请在「系统设置 → 隐私与安全性 → 辅助功能」中添加并启用 TranslaterProto。
                """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "稍后")
            if alert.runModal() == .alertFirstButtonReturn {
                requestPermissions()
            }
        }
    }

    @objc private func requestPermissions() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Event Tap

    private func startEventTap() {
        eventTapManager.onTextUpdate = { [weak self] text in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.floatingPanel.updateOriginalText(text)

                if text.isEmpty {
                    self.floatingPanel.updateTranslation("")
                    self.latestTranslation = ""
                    self.translateWorkItem?.cancel()
                    return
                }

                // Debounce: wait for typing pause before firing translation
                self.translateWorkItem?.cancel()
                self.floatingPanel.updateTranslation("...")

                let work = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    self.translationService?.translate(text) { [weak self] translatedText in
                        self?.floatingPanel.updateTranslation(translatedText)
                        self?.latestTranslation = translatedText
                    }
                }
                self.translateWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + self.translateDebounce, execute: work)
            }
        }

        eventTapManager.onConfirmTranslation = { [weak self] in
            DispatchQueue.main.async { self?.performTextReplacement() }
        }

        eventTapManager.onReset = { [weak self] in
            DispatchQueue.main.async { self?.floatingPanel.hide() }
        }

        eventTapManager.onToggleMonitoring = { [weak self] in
            DispatchQueue.main.async { self?.toggleMonitoring() }
        }

        // Init translation service with saved preferences
        if #available(macOS 15.0, *) {
            let source = loadSourceLanguage()
            let target = loadTargetLanguage()
            translationService = TranslationService()
            translationService?.setLanguages(source: source, target: target)
            print("[Translater] 🌐 翻译服务: \(source.displayName) → \(target.displayName)")
        }

        eventTapManager.start()
        eventTapManager.isMonitoring = true
        floatingPanel.show()
        updateMonitorMenuItem()

        print("[Translater] ✅ 已启动 | Ctrl+Opt+T 开关翻译 | ⌘, 语言设置")
    }

    // MARK: - Language Persistence

    private func loadSourceLanguage() -> LanguageOption {
        if let code = UserDefaults.standard.string(forKey: Keys.sourceLanguage) {
            return LanguageOption.findByCode(code)
        }
        return LanguageOption.findByCode("zh") // Default: Chinese
    }

    private func loadTargetLanguage() -> LanguageOption {
        if let code = UserDefaults.standard.string(forKey: Keys.targetLanguage) {
            return LanguageOption.findByCode(code)
        }
        return LanguageOption.findByCode("en") // Default: English
    }

    private func saveLanguages(source: LanguageOption, target: LanguageOption) {
        UserDefaults.standard.set(source.code, forKey: Keys.sourceLanguage)
        UserDefaults.standard.set(target.code, forKey: Keys.targetLanguage)
    }

    // MARK: - Settings

    @objc private func openSettings() {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let source = loadSourceLanguage()
        let target = loadTargetLanguage()

        settingsWindow = SettingsWindow(source: source, target: target) { [weak self] source, target in
            self?.saveLanguages(source: source, target: target)
            self?.translationService?.setLanguages(source: source, target: target)
            print("[Translater] 🔄 语言已切换: \(source.displayName) → \(target.displayName)")
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Monitoring Toggle

    @objc private func toggleMonitoring() {
        eventTapManager.isMonitoring.toggle()
        updateMonitorMenuItem()

        if eventTapManager.isMonitoring {
            floatingPanel.show()
        } else {
            floatingPanel.hide()
        }
    }

    @objc private func togglePanel() {
        if floatingPanel.panelVisible {
            floatingPanel.hide()
        } else {
            floatingPanel.show()
        }
    }

    @objc private func quitApp() {
        eventTapManager.stop()
        NSApp.terminate(nil)
    }

    // MARK: - Text Replacement

    private func performTextReplacement() {
        let buffer = eventTapManager.textBuffer
        let translation = latestTranslation.isEmpty ? buffer : latestTranslation

        guard !buffer.isEmpty else { return }

        // Prevent re-translation of pasted text
        eventTapManager.applyCooldown()

        print("[Translater] 🔄 替换: \"\(buffer)\" → \"\(translation)\"")

        // Save clipboard
        let pasteboard = NSPasteboard.general
        let oldContents = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(translation, forType: .string)
        Thread.sleep(forTimeInterval: 0.05)

        // Try AX-based precision selection first
        let axSuccess = replaceViaAXSelection()

        if !axSuccess {
            // Fallback: backspace count
            print("[Translater] ⚠️ AX 选择失败，回退到回退键方式")
            let deleteKeyCode: CGKeyCode = 0x33
            for i in 0..<buffer.count {
                if let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: deleteKeyCode, keyDown: true) {
                    keyDown.post(tap: .cghidEventTap)
                }
                if let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: deleteKeyCode, keyDown: false) {
                    keyUp.post(tap: .cghidEventTap)
                }
                if i < buffer.count - 1 {
                    Thread.sleep(forTimeInterval: 0.005)
                }
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        // Paste
        Thread.sleep(forTimeInterval: 0.05)
        let cmdVKeyCode: CGKeyCode = 0x09
        if let cmdVDown = CGEvent(keyboardEventSource: nil, virtualKey: cmdVKeyCode, keyDown: true) {
            cmdVDown.flags = .maskCommand
            cmdVDown.post(tap: .cghidEventTap)
        }
        if let cmdVUp = CGEvent(keyboardEventSource: nil, virtualKey: cmdVKeyCode, keyDown: false) {
            cmdVUp.post(tap: .cghidEventTap)
        }

        // Restore clipboard
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let old = oldContents {
                pasteboard.clearContents()
                pasteboard.setString(old, forType: .string)
            }
        }

        eventTapManager.clearBuffer()
        floatingPanel.hide()
        print("[Translater] ✅ 替换完成")
    }

    /// Use AX API to precisely select only the newly-typed delta range, then paste over it.
    /// Returns true if the AX selection succeeded.
    private func replaceViaAXSelection() -> Bool {
        guard let element = eventTapManager.getFocusedElement() else {
            print("[Translater] ⚠️ 无法获取焦点元素")
            return false
        }

        guard let currentValue = eventTapManager.readElementValue(element) else {
            print("[Translater] ⚠️ 无法读取当前值")
            return false
        }

        let baseline = eventTapManager.baseline
        let (start, length) = findDeltaRange(baseline: baseline, current: currentValue)

        guard length > 0 else {
            print("[Translater] ⚠️ delta 范围为空 (baseline=\"\(baseline)\", current=\"\(currentValue)\")")
            return false
        }

        print("[Translater] 🎯 AX 选中: pos=\(start) len=\(length)")

        var range = CFRange(location: start, length: length)
        guard let rangeValue = AXValueCreate(.cfRange, &range) else {
            return false
        }

        let setResult = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            rangeValue
        )

        if setResult != .success {
            print("[Translater] ⚠️ AX 设置选区失败: \(setResult.rawValue)")
            return false
        }

        // Short delay to let selection take effect
        Thread.sleep(forTimeInterval: 0.03)
        return true
    }

    /// Find the position and length of the delta (new text) in the current value,
    /// by comparing with the baseline (pre-typing value).
    private func findDeltaRange(baseline: String, current: String) -> (start: Int, length: Int) {
        if baseline.isEmpty { return (0, current.count) }

        let chars1 = Array(baseline)
        let chars2 = Array(current)

        // Common prefix
        var prefixLen = 0
        let minLen = min(chars1.count, chars2.count)
        while prefixLen < minLen && chars1[prefixLen] == chars2[prefixLen] {
            prefixLen += 1
        }

        // Common suffix (from the differing parts onward)
        var suffixLen = 0
        let rem1 = chars1.count - prefixLen
        let rem2 = chars2.count - prefixLen
        let maxSuffix = min(rem1, rem2)
        while suffixLen < maxSuffix &&
              chars1[chars1.count - 1 - suffixLen] == chars2[chars2.count - 1 - suffixLen] {
            suffixLen += 1
        }

        let deltaStart = prefixLen
        let deltaEnd = chars2.count - suffixLen
        let deltaLen = max(0, deltaEnd - deltaStart)

        if deltaLen == 0 && current.count > baseline.count {
            // Degenerate: insertion but couldn't locate precisely
            // Assume appended at end
            return (baseline.count, current.count - baseline.count)
        }

        return (deltaStart, deltaLen)
    }
}
