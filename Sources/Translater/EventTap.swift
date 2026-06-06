import AppKit
import CoreGraphics
import ApplicationServices

/// Manages CGEvent tap + AX API for global keyboard monitoring.
/// Uses CGEvent for activity detection and shortcuts,
/// uses Accessibility API to read IME-composed text (e.g., Chinese characters).
///
/// The event tap always runs once started (to detect the toggle hotkey).
/// Use `isMonitoring` to enable/disable the translation features.
final class EventTapManager {
    // MARK: - Public Properties

    var onTextUpdate: ((String) -> Void)?
    var onConfirmTranslation: (() -> Void)?
    var onReset: (() -> Void)?
    var onToggleMonitoring: (() -> Void)?

    /// The actual text delta since typing started — read via AX API, not raw keystrokes.
    private(set) var textBuffer: String = ""

    /// When false, the event tap only checks for the toggle hotkey; no AX reads or text tracking.
    var isMonitoring = false {
        didSet {
            if !isMonitoring {
                resetAllState()
                onReset?()
            }
            print("[EventTap] 监听状态: \(isMonitoring ? "✅ 开启" : "⏸️ 暂停")")
        }
    }

    // MARK: - Private Properties

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isRunning = false
    private var lastAppBundleID: String?

    // AX-based text tracking
    private var baselineValue: String = ""
    private var lastKnownValue: String = ""
    private var readWorkItem: DispatchWorkItem?
    private let axReadDelay: TimeInterval = 0.15

    // Idle management
    private var idleTimer: Timer?
    private let idleTimeout: TimeInterval = 60.0

    // typingActive: true after first keystroke, reset on enter/esc/idle/app-switch
    private var typingActive = false

    // Cooldown: ignore AX reads for a short period after text replacement
    private var cooldownUntil: Date = .distantPast

    // MARK: - Start / Stop (Event Tap lifecycle)

    func start() {
        guard !isRunning else { return }
        guard checkPermissions() else {
            print("[EventTap] ❌ 需要辅助功能权限")
            return
        }

        let eventMask = (1 << CGEventType.keyDown.rawValue)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: eventTapCallback,
            userInfo: selfPtr
        )

        guard let tap = eventTap else {
            print("[EventTap] ❌ 无法创建 Event Tap — 可能需要辅助功能权限")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        isRunning = true
        resetAllState()

        // Watch for app switches
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        startIdleTimer()
        print("[EventTap] ✅ Event tap 已启动 (监听: \(isMonitoring ? "开" : "关"))")
    }

    func stop() {
        guard isRunning else { return }

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isRunning = false

        NSWorkspace.shared.notificationCenter.removeObserver(self)
        cancelReadWorkItem()
        stopIdleTimer()
        resetAllState()
        print("[EventTap] ⏹️ Event tap 已停止")
    }

    func clearBuffer() {
        textBuffer = ""
        baselineValue = ""
        lastKnownValue = ""
        typingActive = false
    }

    /// Prevent AX reads for a short period (used after text replacement)
    func applyCooldown(_ duration: TimeInterval = 1.5) {
        cooldownUntil = Date().addingTimeInterval(duration)
        print("[EventTap] 🧊 冷却 \(duration)秒，跳过 AX 读取")
    }

    /// Returns the currently focused AX element (e.g., text field being typed into).
    func getFocusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        guard result == .success, let element = focusedElement else {
            return nil
        }
        return (element as! AXUIElement)
    }

    /// Read the value of a given AX element.
    func readElementValue(_ element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &value
        )
        guard result == .success, let val = value as? String else {
            return nil
        }
        return val
    }

    /// The pre-typing baseline value (text before user started typing).
    var baseline: String { baselineValue }

    // MARK: - Private: State Reset

    private func resetAllState() {
        cancelReadWorkItem()
        textBuffer = ""
        baselineValue = ""
        lastKnownValue = ""
        typingActive = false
    }

    private func resetTypingState() {
        cancelReadWorkItem()
        textBuffer = ""
        baselineValue = ""
        typingActive = false
    }

    // MARK: - Permissions

    private func checkPermissions() -> Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): false]
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - App Switching

    @objc private func appDidActivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier else { return }

        if bundleID != lastAppBundleID {
            print("[EventTap] 🔄 App 切换: \(lastAppBundleID ?? "nil") → \(bundleID)")
            lastAppBundleID = bundleID
            resetAllState()
            onReset?()
        }
    }

    // MARK: - Idle Timer

    private func startIdleTimer() {
        stopIdleTimer()
        idleTimer = Timer.scheduledTimer(withTimeInterval: idleTimeout, repeats: false) { [weak self] _ in
            guard let self = self, self.typingActive else { return }
            print("[EventTap] ⏰ 空闲超时，重置")
            self.resetAllState()
            self.onReset?()
        }
    }

    private func stopIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = nil
    }

    private func resetIdleTimer() {
        guard idleTimer != nil else { return }
        startIdleTimer()
    }

    // MARK: - AX Text Reading

    private func readFocusedAXValue() -> String? {
        let systemWide = AXUIElementCreateSystemWide()

        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        guard result == .success, let element = focusedElement else {
            return nil
        }

        let axElement = element as! AXUIElement

        // Try kAXValueAttribute first (works for NSTextField, NSTextView, etc.)
        var value: CFTypeRef?
        let valueResult = AXUIElementCopyAttributeValue(
            axElement,
            kAXValueAttribute as CFString,
            &value
        )
        if valueResult == .success, let val = value as? String {
            return val
        }

        // Fallback: try kAXSelectedTextAttribute
        var selectedText: CFTypeRef?
        let selResult = AXUIElementCopyAttributeValue(
            axElement,
            kAXSelectedTextAttribute as CFString,
            &selectedText
        )
        if selResult == .success, let sel = selectedText as? String, !sel.isEmpty {
            return sel
        }

        return nil
    }

    private func scheduleAXRead() {
        cancelReadWorkItem()

        let work = DispatchWorkItem { [weak self] in
            self?.performAXRead()
        }
        readWorkItem = work

        DispatchQueue.main.asyncAfter(deadline: .now() + axReadDelay, execute: work)
    }

    private func cancelReadWorkItem() {
        readWorkItem?.cancel()
        readWorkItem = nil
    }

    /// Immediately capture the text field value as baseline.
    /// Called on the first keystroke BEFORE the IME or app processes it.
    private func captureBaseline() {
        guard !typingActive else { return }
        if let value = readFocusedAXValue() {
            baselineValue = value
            lastKnownValue = value
            typingActive = true
            print("[EventTap] 📸 基线捕获: \"\(value)\"")
        }
    }

    private func performAXRead() {
        // Skip if in cooldown
        guard Date() >= cooldownUntil else { return }

        guard typingActive, let currentValue = readFocusedAXValue() else {
            return
        }

        let delta = extractDelta(baseline: baselineValue, current: currentValue)

        if delta.isEmpty && currentValue == baselineValue {
            textBuffer = ""
            onTextUpdate?("")
        } else if !delta.isEmpty {
            textBuffer = delta
            onTextUpdate?(delta)
            print("[EventTap] 📖 AX 读取: delta=\"\(delta)\"")
        }

        lastKnownValue = currentValue
    }

    private func extractDelta(baseline: String, current: String) -> String {
        if baseline.isEmpty { return current }
        if current.isEmpty { return "" }

        if current.hasPrefix(baseline) {
            return String(current.dropFirst(baseline.count))
        }

        if current.hasSuffix(baseline) {
            return String(current.dropLast(baseline.count))
        }

        let chars1 = Array(baseline)
        let chars2 = Array(current)

        var prefixLen = 0
        let minLen = min(chars1.count, chars2.count)
        while prefixLen < minLen && chars1[prefixLen] == chars2[prefixLen] {
            prefixLen += 1
        }

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
        if deltaEnd > deltaStart {
            return String(chars2[deltaStart..<deltaEnd])
        }

        if current.count > baseline.count {
            return String(current.dropFirst(baseline.count))
        }

        return ""
    }

    // MARK: - Event Processing

    /// Toggle hotkey: Ctrl+Option+T  (maskControl + maskAlternate + key 'T')
    private static let toggleHotkeyKeyCode: CGKeyCode = 0x11  // kVK_ANSI_T
    private static let toggleHotkeyFlags: CGEventFlags = [.maskControl, .maskAlternate]

    fileprivate func handleKeyDown(event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        // ---- Toggle hotkey detection (always active, even when !isMonitoring) ----
        if keyCode == Self.toggleHotkeyKeyCode &&
           flags.intersection([.maskControl, .maskAlternate, .maskShift, .maskCommand]) == Self.toggleHotkeyFlags {
            print("[EventTap] ⌨️ 热键 Ctrl+Opt+T → 切换监听")
            onToggleMonitoring?()
            return nil // Swallow the hotkey
        }

        // ---- Alt+Enter (confirm translation) ----
        if keyCode == 0x24 && flags.contains(.maskAlternate) {
            if isMonitoring {
                print("[EventTap] 🎯 Alt+Enter → 触发翻译替换 (buffer=\"\(textBuffer)\")")
                onConfirmTranslation?()
                return nil // Swallow Alt+Enter
            }
            // If not monitoring, pass Alt+Enter through
            return Unmanaged.passRetained(event)
        }

        // ---- If monitoring is off, pass everything through ----
        guard isMonitoring else {
            return Unmanaged.passRetained(event)
        }

        // ---- Monitoring is ON — handle all keys ----

        // Skip Command-modified keys (Cmd+V paste, Cmd+Z undo, etc.)
        // These are system operations, not user typing
        if flags.contains(.maskCommand) {
            return Unmanaged.passRetained(event)
        }

        // Reset idle timer on any key
        resetIdleTimer()

        // Escape (cancel)
        if keyCode == 0x35 {
            print("[EventTap] ⎋ Escape — 取消")
            resetTypingState()
            onReset?()
            return Unmanaged.passRetained(event)
        }

        // Enter (normal — send original text)
        if keyCode == 0x24 {
            print("[EventTap] ↩ Enter — 发送原文")
            resetTypingState()
            onReset?()
            return Unmanaged.passRetained(event)
        }

        // On first keystroke: capture baseline BEFORE the text field changes
        if !typingActive {
            captureBaseline()
        }

        // Backspace — read AX immediately
        if keyCode == 0x33 {
            DispatchQueue.main.async { [weak self] in
                self?.performAXRead()
            }
            return Unmanaged.passRetained(event)
        }

        // All other keys: schedule debounced AX read (captures IME-committed text)
        scheduleAXRead()

        return Unmanaged.passRetained(event)
    }
}

// MARK: - CGEvent Callback

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon = refcon else {
        return Unmanaged.passRetained(event)
    }

    let manager = Unmanaged<EventTapManager>.fromOpaque(refcon).takeUnretainedValue()
    return manager.handleKeyDown(event: event)
}
