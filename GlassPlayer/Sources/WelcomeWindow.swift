import Cocoa

// ---------------------------------------------------------------------------
// WelcomeWindow – non-blocking launch screen with Open File & rclone options
// Follows system appearance (light/dark mode)
// ---------------------------------------------------------------------------

class WelcomeWindow: NSWindowController {

    private var onOpenFile: (() -> Void)?
    private var onRclone: (() -> Void)?
    private var onDrop: ((String) -> Void)?

    init(onOpenFile: @escaping () -> Void,
         onRclone: @escaping () -> Void,
         onDrop: @escaping (String) -> Void) {
        self.onOpenFile = onOpenFile
        self.onRclone = onRclone
        self.onDrop = onDrop

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 340),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = .windowBackgroundColor
        window.center()
        window.isReleasedWhenClosed = false
        window.title = "Glass Player"
        // Follow system theme — do NOT force darkAqua

        super.init(window: window)

        setupUI()
        setupDragDrop()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    // MARK: - UI

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true

        // Background: use NSVisualEffectView for theme-adaptive surface
        let bg = NSVisualEffectView(frame: contentView.bounds)
        bg.material = .underWindowBackground
        bg.blendingMode = .behindWindow
        bg.state = .active
        bg.autoresizingMask = [.width, .height]
        contentView.addSubview(bg)

        // ── App icon (play triangle – matches actual AppIcon) ──
        let iconSize: CGFloat = 64
        let iconView = NSView(frame: .zero)
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 16
        iconView.layer?.masksToBounds = true
        iconView.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        iconView.layer?.borderWidth = 1
        iconView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(iconView)

        // Dark gradient background (matches app icon)
        let gradientLayer = CAGradientLayer()
        gradientLayer.colors = [
            NSColor(red: 0.06, green: 0.06, blue: 0.12, alpha: 1).cgColor,
            NSColor(red: 0.12, green: 0.10, blue: 0.22, alpha: 1).cgColor,
        ]
        gradientLayer.startPoint = CGPoint(x: 1, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0, y: 1)
        gradientLayer.frame = CGRect(x: 0, y: 0, width: iconSize, height: iconSize)
        iconView.layer?.addSublayer(gradientLayer)

        let triangleLayer = CAShapeLayer()
        let triH: CGFloat = 24
        let triW = triH * 0.866
        let triPath = CGMutablePath()
        let cx: CGFloat = iconSize / 2 + 2
        let cy: CGFloat = iconSize / 2
        triPath.move(to: CGPoint(x: cx - triW / 2, y: cy + triH / 2))
        triPath.addLine(to: CGPoint(x: cx - triW / 2, y: cy - triH / 2))
        triPath.addLine(to: CGPoint(x: cx + triW / 2, y: cy))
        triPath.closeSubpath()
        triangleLayer.path = triPath
        triangleLayer.fillColor = NSColor.white.withAlphaComponent(0.9).cgColor
        iconView.layer?.addSublayer(triangleLayer)

        // ── Title ──
        let titleLabel = NSTextField(labelWithString: "Glass Player")
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        // ── Subtitle ──
        let subtitleLabel = NSTextField(labelWithString: "Drop a video file here, or choose an option below")
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.alignment = .center
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(subtitleLabel)

        // ── Buttons ──
        let openFileButton = makeActionButton(
            title: "Open File",
            symbol: "folder",
            subtitle: "Browse local files",
            action: #selector(openFileClicked)
        )
        contentView.addSubview(openFileButton)

        let rcloneButton = makeActionButton(
            title: "rclone Browser",
            symbol: "network",
            subtitle: "Stream from remote storage",
            action: #selector(rcloneClicked)
        )
        contentView.addSubview(rcloneButton)

        // ── Layout ──
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            iconView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 50),
            iconView.widthAnchor.constraint(equalToConstant: iconSize),
            iconView.heightAnchor.constraint(equalToConstant: iconSize),

            titleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 16),

            subtitleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),

            openFileButton.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 32),
            openFileButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor, constant: -100),
            openFileButton.widthAnchor.constraint(equalToConstant: 170),
            openFileButton.heightAnchor.constraint(equalToConstant: 90),

            rcloneButton.topAnchor.constraint(equalTo: openFileButton.topAnchor),
            rcloneButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor, constant: 100),
            rcloneButton.widthAnchor.constraint(equalToConstant: 170),
            rcloneButton.heightAnchor.constraint(equalToConstant: 90),
        ])
    }

    private func makeActionButton(title: String, symbol: String, subtitle: String,
                                   action: Selector) -> NSView {
        let container = HoverableButtonView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.separatorColor.cgColor
        container.translatesAutoresizingMaskIntoConstraints = false

        // Icon
        let iconView = NSImageView()
        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        iconView.contentTintColor = .controlAccentColor
        iconView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(iconView)

        // Title
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)

        // Subtitle
        let subLabel = NSTextField(labelWithString: subtitle)
        subLabel.font = .systemFont(ofSize: 10)
        subLabel.textColor = .tertiaryLabelColor
        subLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(subLabel)

        // Click gesture
        let click = NSClickGestureRecognizer(target: self, action: action)
        container.addGestureRecognizer(click)

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            iconView.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),

            titleLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 8),

            subLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            subLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
        ])

        return container
    }

    // MARK: - Drag & Drop

    private func setupDragDrop() {
        window?.contentView?.registerForDraggedTypes([.fileURL])
        guard let contentView = window?.contentView else { return }
        let dropView = WelcomeDropView(frame: contentView.bounds)
        dropView.autoresizingMask = [.width, .height]
        dropView.onDrop = { [weak self] path in
            self?.onDrop?(path)
            self?.close()
        }
        contentView.addSubview(dropView, positioned: .below, relativeTo: contentView.subviews.first)
    }

    // MARK: - Actions

    @objc private func openFileClicked() {
        close()
        onOpenFile?()
    }

    @objc private func rcloneClicked() {
        close()
        onRclone?()
    }

    // MARK: - Show

    func showWelcome() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
    }
}

// ---------------------------------------------------------------------------
// WelcomeDropView – accepts drag-and-drop of video files
// ---------------------------------------------------------------------------

class WelcomeDropView: NSView {
    var onDrop: ((String) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if hasFileURL(sender) { return .copy }
        return []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let items = sender.draggingPasteboard.pasteboardItems else { return false }
        for item in items {
            if let urlString = item.string(forType: .fileURL),
               let url = URL(string: urlString) {
                onDrop?(url.path)
                return true
            }
        }
        return false
    }

    private func hasFileURL(_ sender: NSDraggingInfo) -> Bool {
        return sender.draggingPasteboard.canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )
    }
}

// ---------------------------------------------------------------------------
// HoverableButtonView – NSView with hover highlight (theme-adaptive)
// ---------------------------------------------------------------------------

class HoverableButtonView: NSView {
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.allowsImplicitAnimation = true
            self.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
            self.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.3).cgColor
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.allowsImplicitAnimation = true
            self.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
            self.layer?.borderColor = NSColor.separatorColor.cgColor
        }
    }
}
