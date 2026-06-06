import AppKit

/// A floating translucent panel for translation preview.
/// Fixed size to prevent jitter; dark background for text legibility.
final class FloatingPanel: NSPanel {

    // MARK: - Constants

    private static let panelWidth: CGFloat = 340
    private static let maxHeight: CGFloat = 140
    private static let minHeight: CGFloat = 72
    private static let autoHideInterval: TimeInterval = 120.0

    // MARK: - UI Elements

    private let originalLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 12.5, weight: .semibold)
        label.textColor = NSColor(white: 0.95, alpha: 1.0)
        label.alignment = .left
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 4
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }()

    private let translationLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 12, weight: .regular)
        label.textColor = NSColor(white: 0.85, alpha: 1.0)
        label.alignment = .left
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 4
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }()

    private let hintLabel: NSTextField = {
        let label = NSTextField(labelWithString: "Alt+Enter → 译文 | Enter → 原文 | Esc → 取消")
        label.font = .systemFont(ofSize: 9, weight: .light)
        label.textColor = NSColor(white: 0.7, alpha: 0.7)
        label.alignment = .center
        return label
    }()

    private let backgroundView: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(white: 0.08, alpha: 0.75).cgColor
        view.layer?.cornerRadius = 14
        view.layer?.borderWidth = 0.5
        view.layer?.borderColor = NSColor(white: 0.3, alpha: 0.4).cgColor
        // Subtle inner shadow for depth
        view.layer?.shadowColor = NSColor.black.cgColor
        view.layer?.shadowOffset = NSSize(width: 0, height: -2)
        view.layer?.shadowRadius = 8
        view.layer?.shadowOpacity = 0.4
        return view
    }()

    // MARK: - State

    private(set) var panelVisible = false
    private var hideTimer: Timer?
    private var hasPositioned = false

    // MARK: - Init

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
    }

    convenience init() {
        let rect = NSRect(x: 100, y: 100, width: FloatingPanel.panelWidth, height: FloatingPanel.minHeight)
        self.init(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        setupWindow()
        setupUI()
    }

    // MARK: - Window Setup

    private func setupWindow() {
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        // Blur layer (behind the dark background for depth)
        if let contentView = contentView {
            let blur = NSVisualEffectView(frame: contentView.bounds)
            blur.material = .hudWindow
            blur.blendingMode = .behindWindow
            blur.state = .active
            blur.wantsLayer = true
            blur.layer?.cornerRadius = 14
            blur.layer?.masksToBounds = true
            blur.autoresizingMask = [.width, .height]
            contentView.addSubview(blur, positioned: .below, relativeTo: nil)
        }

        contentView?.wantsLayer = true
        contentView?.layer?.cornerRadius = 14
        contentView?.layer?.masksToBounds = true

        isMovableByWindowBackground = true
        standardWindowButton(.closeButton)?.isHidden = true
    }

    // MARK: - UI Setup

    private func setupUI() {
        guard let contentView = contentView else { return }

        // Dark background for text legibility
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(backgroundView)

        // Close button
        let closeButton = NSButton(frame: .zero)
        closeButton.title = "✕"
        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.font = .systemFont(ofSize: 10)
        closeButton.contentTintColor = NSColor(white: 0.6, alpha: 0.7)
        closeButton.target = self
        closeButton.action = #selector(hide)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(closeButton)

        // Separator line
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(separator)

        // Text labels
        originalLabel.translatesAutoresizingMaskIntoConstraints = false
        translationLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(originalLabel)
        contentView.addSubview(translationLabel)
        contentView.addSubview(hintLabel)

        NSLayoutConstraint.activate([
            // Background fills the window
            backgroundView.topAnchor.constraint(equalTo: contentView.topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            // Close button
            closeButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
            closeButton.widthAnchor.constraint(equalToConstant: 14),
            closeButton.heightAnchor.constraint(equalToConstant: 14),

            // Original label
            originalLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            originalLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            originalLabel.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -6),

            // Separator
            separator.topAnchor.constraint(equalTo: originalLabel.bottomAnchor, constant: 6),
            separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),

            // Translation label
            translationLabel.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 6),
            translationLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            translationLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),

            // Hint — pinned to bottom
            hintLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            hintLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
        ])

        originalLabel.stringValue = ""
        translationLabel.stringValue = ""
    }

    // MARK: - Public Methods

    func updateOriginalText(_ text: String) {
        originalLabel.stringValue = text
        translationLabel.stringValue = ""
        adjustHeightIfNeeded()

        if !panelVisible && !text.isEmpty {
            show()
        }
        resetHideTimer()
    }

    func updateTranslation(_ text: String) {
        translationLabel.stringValue = text
        adjustHeightIfNeeded()
    }

    func show() {
        guard !panelVisible else { return }
        positionOnce()
        makeKeyAndOrderFront(nil)
        panelVisible = true
    }

    @objc func hide() {
        guard panelVisible else { return }
        orderOut(nil)
        panelVisible = false
        hasPositioned = false
        hideTimer?.invalidate()
        hideTimer = nil
        // Reset size for next show
        var frame = self.frame
        frame.size.height = Self.minHeight
        setFrame(frame, display: false)
    }

    // MARK: - Private

    /// Position the panel once. After that, never reposition — prevents jitter.
    private func positionOnce() {
        guard !hasPositioned else { return }
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame

        let x = screenFrame.midX - Self.panelWidth / 2
        let y = screenFrame.minY + 60

        setFrameOrigin(NSPoint(x: x, y: y))
        hasPositioned = true
    }

    /// Only grow the panel height when text needs more space. Never shrink.
    private func adjustHeightIfNeeded() {
        let textWidth = Self.panelWidth - 28 // 14 padding each side

        let originalHeight = originalLabel.sizeThatFits(
            NSSize(width: textWidth, height: CGFloat.greatestFiniteMagnitude)
        ).height

        let translationHeight: CGFloat
        if translationLabel.stringValue.isEmpty {
            translationHeight = 0
        } else {
            translationHeight = translationLabel.sizeThatFits(
                NSSize(width: textWidth, height: CGFloat.greatestFiniteMagnitude)
            ).height
        }

        // 10 top + original + 6 gap + separator(1) + 6 gap + translation + 6 gap + hint(12) + 8 bottom
        let contentHeight = 10 + originalHeight + 6 + 1 + 6 + translationHeight + 6 + 12 + 8
        let needed = min(max(contentHeight, Self.minHeight), Self.maxHeight)

        var frame = self.frame
        guard needed > frame.height else { return } // Never shrink

        let bottomY = frame.minY
        frame.size.height = needed
        frame.origin.y = bottomY
        setFrame(frame, display: true, animate: false) // No animation = no visual jitter
    }

    private func resetHideTimer() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: Self.autoHideInterval, repeats: false) { [weak self] _ in
            guard let self = self, self.panelVisible else { return }
            self.hide()
        }
    }
}
