import Cocoa

// ---------------------------------------------------------------------------
// FlippedView – NSView with flipped coordinates so content starts at the top
// (required for NSScrollView document views on macOS).
// ---------------------------------------------------------------------------

private class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// ---------------------------------------------------------------------------
// SettingsWindow – IINA-style settings with comprehensive mpv options
// Apple-style sidebar, all sections with validated defaults.
// ---------------------------------------------------------------------------

class SettingsWindow: NSWindowController, NSTableViewDelegate, NSTableViewDataSource {

    // MARK: - Section Definition

    private struct Section {
        let title: String
        let icon: String      // SF Symbol name
        let builder: () -> NSView
    }

    private var sections: [Section] = []
    private let sidebarTable = NSTableView()
    private let contentContainer = NSView()
    private var currentContentView: NSView?

    // ── Mapping: UserDefaults key → mpv property name ──
    // Settings listed here are applied live to all open player windows.
    private static let keyToMPV: [String: String] = [
        // Video
        "hwdec":               "hwdec",
        "hwdecCodecs":         "hwdec-codecs",
        "screenshotFormat":    "screenshot-format",
        "screenshotJpegQuality": "screenshot-jpeg-quality",
        "debandEnabled":       "deband",
        "debandIterations":    "deband-iterations",
        "debandThreshold":     "deband-threshold",
        "debandRange":         "deband-range",
        "debandGrain":         "deband-grain",
        // Audio
        "volumeMax":           "volume-max",
        "audioOutput":         "ao",
        "audioChannels":       "audio-channels",
        "audioPassthrough":    "audio-spdif",
        "audioLang":           "alang",
        "defaultVolume":       "volume",
        // Subtitles
        "subAutoLoad":         "sub-auto",
        "subLang":             "slang",
        "subFontSize":         "sub-font-size",
        "subFont":             "sub-font",
        "subPosition":         "sub-pos",
        "subBorderSize":       "sub-border-size",
        "subShadowOffset":     "sub-shadow-offset",
        "subAssOverride":      "sub-ass-override",
        // Network
        "cacheEnabled":        "cache",
        "cacheSizeMB":         "demuxer-max-bytes",
        "cacheBackMB":         "demuxer-max-back-bytes",
        "readaheadSecs":       "demuxer-readahead-secs",
        "cacheSecs":           "cache-secs",
        "networkTimeout":      "network-timeout",
        "forceSeekable":       "force-seekable",
        "userAgent":           "user-agent",
        // Scaling
        "scaleFilter":         "scale",
        "dscaleFilter":        "dscale",
        "cscaleFilter":        "cscale",
        "ditherDepth":         "dither-depth",
        "ditherAlgo":          "dither",
        "correctDownscaling":  "correct-downscaling",
        "linearDownscaling":   "linear-downscaling",
        "sigmoidUpscaling":    "sigmoid-upscaling",
        // Color / HDR
        "toneMapping":         "tone-mapping",
        "toneMappingMode":     "tone-mapping-mode",
        "hdrComputePeak":      "hdr-compute-peak",
        "targetColorspaceHint":"target-colorspace-hint",
        "targetPeak":          "target-peak",
        "gamutMapping":        "gamut-mapping-mode",
        "iccProfile":          "icc-profile",
    ]

    // Keys that need value transforms before sending to mpv
    private static let boolKeys: Set<String> = [
        "debandEnabled", "cacheEnabled", "forceSeekable",
        "correctDownscaling", "linearDownscaling", "sigmoidUpscaling",
        "hdrComputePeak", "targetColorspaceHint",
    ]

    // Keys whose values need "MiB" appended
    private static let mibKeys: Set<String> = [
        "cacheSizeMB", "cacheBackMB",
    ]

    // MARK: - Init

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = .moveToActiveSpace
        window.center()

        super.init(window: window)

        buildSections()
        setupUI()

        sidebarTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        showSection(at: 0)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    // MARK: - Section Builders

    private func buildSections() {
        sections = [
            Section(title: "General",       icon: "gear",               builder: { [unowned self] in buildGeneralSection() }),
            Section(title: "Video",         icon: "play.rectangle",     builder: { [unowned self] in buildVideoSection() }),
            Section(title: "Audio",         icon: "speaker.wave.2",     builder: { [unowned self] in buildAudioSection() }),
            Section(title: "Subtitles",     icon: "captions.bubble",    builder: { [unowned self] in buildSubtitlesSection() }),
            Section(title: "Network",       icon: "network",            builder: { [unowned self] in buildNetworkSection() }),
            Section(title: "Scaling",       icon: "arrow.up.left.and.arrow.down.right", builder: { [unowned self] in buildScalingSection() }),
            Section(title: "Color",         icon: "paintpalette",       builder: { [unowned self] in buildColorSection() }),
            Section(title: "Anime4K",       icon: "sparkles",           builder: { [unowned self] in buildAnime4KSection() }),
            Section(title: "Cache & Cleanup", icon: "trash",            builder: { [unowned self] in buildCleanupSection() }),
        ]
    }

    // MARK: - UI Setup

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true

        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        sidebar.state = .active
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(sidebar)

        sidebarTable.delegate = self
        sidebarTable.dataSource = self
        sidebarTable.headerView = nil
        sidebarTable.backgroundColor = .clear
        sidebarTable.rowHeight = 32
        sidebarTable.selectionHighlightStyle = .regular
        sidebarTable.style = .sourceList
        sidebarTable.intercellSpacing = NSSize(width: 0, height: 2)
        sidebarTable.target = self
        sidebarTable.action = #selector(sidebarClicked)

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("section"))
        col.resizingMask = .autoresizingMask
        sidebarTable.addTableColumn(col)

        let scrollView = NSScrollView()
        scrollView.documentView = sidebarTable
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(scrollView)

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.wantsLayer = true
        contentView.addSubview(contentContainer)

        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(sep)

        NSLayoutConstraint.activate([
            sidebar.topAnchor.constraint(equalTo: contentView.topAnchor),
            sidebar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            sidebar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 180),

            scrollView.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor),

            sep.topAnchor.constraint(equalTo: contentView.topAnchor),
            sep.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            sep.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            sep.widthAnchor.constraint(equalToConstant: 1),

            contentContainer.topAnchor.constraint(equalTo: contentView.topAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: sep.trailingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    // MARK: - Sidebar Data Source / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int { sections.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        let section = sections[row]
        let cellID = NSUserInterfaceItemIdentifier("SidebarCell")

        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: cellID, owner: nil)
            as? NSTableCellView {
            cell = reused
            cell.textField?.stringValue = section.title
            cell.imageView?.image = NSImage(systemSymbolName: section.icon,
                                            accessibilityDescription: nil)
            return cell
        }

        cell = NSTableCellView()
        cell.identifier = cellID

        let iv = NSImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.image = NSImage(systemSymbolName: section.icon, accessibilityDescription: nil)
        iv.contentTintColor = .controlAccentColor
        cell.imageView = iv
        cell.addSubview(iv)

        let tf = NSTextField(labelWithString: section.title)
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.font = .systemFont(ofSize: 13)
        tf.textColor = .labelColor
        cell.textField = tf
        cell.addSubview(tf)

        NSLayoutConstraint.activate([
            iv.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            iv.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            iv.widthAnchor.constraint(equalToConstant: 18),
            iv.heightAnchor.constraint(equalToConstant: 18),
            tf.leadingAnchor.constraint(equalTo: iv.trailingAnchor, constant: 8),
            tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])

        return cell
    }

    @objc private func sidebarClicked() {
        let row = sidebarTable.selectedRow
        guard row >= 0 && row < sections.count else { return }
        showSection(at: row)
    }

    private func showSection(at index: Int) {
        currentContentView?.removeFromSuperview()
        let view = sections[index].builder()
        view.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])
        currentContentView = view
    }

    // MARK: - Show

    func showSettings() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Section: General
    // ═══════════════════════════════════════════════════════════════════

    private func buildGeneralSection() -> NSView {
        let scroll = makeScrollView()
        let container = scroll.documentView!

        var views: [NSView] = []
        views.append(makeSectionHeader("General"))

        views.append(makeToggleRow(
            title: "Resume playback where you left off",
            key: "resumePlayback",
            defaultValue: true
        ))
        views.append(makeToggleRow(
            title: "Pause when window loses focus",
            key: "pauseOnFocusLoss",
            defaultValue: false
        ))
        views.append(makeToggleRow(
            title: "Show welcome window on launch",
            key: "showWelcome",
            defaultValue: true
        ))
        views.append(makeToggleRow(
            title: "Quit when all windows are closed",
            key: "quitWhenAllClosed",
            defaultValue: false
        ))
        views.append(makeToggleRow(
            title: "Keep window on top during playback",
            key: "keepOnTop",
            defaultValue: false
        ))
        views.append(makePopUpRow(
            title: "Window Resize Behavior",
            key: "windowResize",
            options: ["Fit to video", "Never resize", "Resize to 50%", "Resize to 75%", "Resize to 100%"],
            defaultValue: "Fit to video"
        ))
        views.append(makePopUpRow(
            title: "Cursor Auto-hide (ms)",
            key: "cursorAutohide",
            options: ["500", "800", "1000", "2000", "3000", "never"],
            defaultValue: "800"
        ))

        views.append(makeRestoreDefaultsButton(keys: [
            "resumePlayback", "pauseOnFocusLoss", "showWelcome",
            "quitWhenAllClosed", "keepOnTop", "windowResize", "cursorAutohide"
        ]))

        addViewsToContainer(container, views: views)
        return scroll
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Section: Video
    // ═══════════════════════════════════════════════════════════════════

    private func buildVideoSection() -> NSView {
        let scroll = makeScrollView()
        let container = scroll.documentView!

        var views: [NSView] = []
        views.append(makeSectionHeader("Video"))

        views.append(makePopUpRow(
            title: "Hardware Decoding",
            key: "hwdec",
            options: ["videotoolbox", "auto-safe", "auto", "no"],
            defaultValue: "videotoolbox"
        ))
        views.append(makePopUpRow(
            title: "Hardware Decode Codecs",
            key: "hwdecCodecs",
            options: ["all", "h264,hevc,vp9,av1"],
            defaultValue: "all"
        ))
        views.append(makePopUpRow(
            title: "Default Speed",
            key: "defaultSpeed",
            options: ["0.25x", "0.5x", "0.75x", "1x", "1.25x", "1.5x", "2x", "3x", "4x"],
            defaultValue: "1x"
        ))
        views.append(makePopUpRow(
            title: "Screenshot Format",
            key: "screenshotFormat",
            options: ["png", "jpg", "webp"],
            defaultValue: "png"
        ))
        views.append(makePopUpRow(
            title: "Screenshot JPEG Quality",
            key: "screenshotJpegQuality",
            options: ["50", "70", "85", "95", "100"],
            defaultValue: "85"
        ))

        views.append(makeSectionHeader("Debanding"))
        views.append(makeDescriptionLabel(
            "Debanding reduces color banding artifacts in gradients. " +
            "Higher iterations/threshold = more aggressive (may reduce detail)."
        ))
        views.append(makeToggleRow(
            title: "Enable debanding",
            key: "debandEnabled",
            defaultValue: false
        ))
        views.append(makePopUpRow(
            title: "Deband Iterations",
            key: "debandIterations",
            options: ["1", "2", "3", "4", "8"],
            defaultValue: "4"
        ))
        views.append(makePopUpRow(
            title: "Deband Threshold",
            key: "debandThreshold",
            options: ["20", "25", "30", "35", "40", "48", "64"],
            defaultValue: "35"
        ))
        views.append(makePopUpRow(
            title: "Deband Range",
            key: "debandRange",
            options: ["8", "12", "16", "20", "24", "32"],
            defaultValue: "16"
        ))
        views.append(makePopUpRow(
            title: "Deband Grain",
            key: "debandGrain",
            options: ["0", "2", "4", "6", "8", "12", "16", "24", "48"],
            defaultValue: "4"
        ))

        views.append(makeRestoreDefaultsButton(keys: [
            "hwdec", "hwdecCodecs", "defaultSpeed", "screenshotFormat",
            "screenshotJpegQuality", "debandEnabled", "debandIterations",
            "debandThreshold", "debandRange", "debandGrain"
        ]))

        addViewsToContainer(container, views: views)
        return scroll
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Section: Audio
    // ═══════════════════════════════════════════════════════════════════

    private func buildAudioSection() -> NSView {
        let scroll = makeScrollView()
        let container = scroll.documentView!

        var views: [NSView] = []
        views.append(makeSectionHeader("Audio"))

        views.append(makePopUpRow(
            title: "Maximum Volume",
            key: "volumeMax",
            options: ["100%", "150%", "200%", "300%"],
            defaultValue: "200%"
        ))
        views.append(makePopUpRow(
            title: "Audio Output",
            key: "audioOutput",
            options: ["avfoundation", "coreaudio"],
            defaultValue: "avfoundation"
        ))
        views.append(makePopUpRow(
            title: "Audio Channels",
            key: "audioChannels",
            options: ["auto", "auto-safe", "stereo", "5.1", "7.1"],
            defaultValue: "auto"
        ))
        views.append(makeToggleRow(
            title: "Audio passthrough (AC3, EAC3, TrueHD, DTS-HD)",
            key: "audioPassthrough",
            defaultValue: true
        ))
        views.append(makePopUpRow(
            title: "Preferred Audio Language",
            key: "audioLang",
            options: ["eng,en,jpn,jp", "jpn,jp,eng,en", "eng,en", "jpn,jp", "kor,ko,eng,en", "chi,zh,eng,en"],
            defaultValue: "eng,en,jpn,jp"
        ))
        views.append(makePopUpRow(
            title: "Default Volume",
            key: "defaultVolume",
            options: ["25", "50", "75", "100", "125", "150"],
            defaultValue: "100"
        ))

        views.append(makeRestoreDefaultsButton(keys: [
            "volumeMax", "audioOutput", "audioChannels", "audioPassthrough",
            "audioLang", "defaultVolume"
        ]))

        addViewsToContainer(container, views: views)
        return scroll
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Section: Subtitles
    // ═══════════════════════════════════════════════════════════════════

    private func buildSubtitlesSection() -> NSView {
        let scroll = makeScrollView()
        let container = scroll.documentView!

        var views: [NSView] = []
        views.append(makeSectionHeader("Subtitles"))

        views.append(makeToggleRow(
            title: "Auto-load external subtitles",
            key: "subAutoLoad",
            defaultValue: true
        ))
        views.append(makePopUpRow(
            title: "Preferred Subtitle Language",
            key: "subLang",
            options: ["eng,en,enUS", "jpn,jp", "kor,ko", "chi,zh", "spa,es", "fre,fr", "ger,de", "por,pt"],
            defaultValue: "eng,en,enUS"
        ))
        views.append(makePopUpRow(
            title: "Font Size",
            key: "subFontSize",
            options: ["20", "24", "28", "32", "36", "40", "48", "56", "64"],
            defaultValue: "36"
        ))
        views.append(makePopUpRow(
            title: "Font",
            key: "subFont",
            options: ["(Default)", "SF Pro Display", "Helvetica Neue", "Arial", "Verdana", "Avenir Next"],
            defaultValue: "(Default)"
        ))
        views.append(makePopUpRow(
            title: "Position",
            key: "subPosition",
            options: ["Bottom", "Top"],
            defaultValue: "Bottom"
        ))
        views.append(makePopUpRow(
            title: "Border Size",
            key: "subBorderSize",
            options: ["0", "1", "2", "3", "4", "5"],
            defaultValue: "3"
        ))
        views.append(makePopUpRow(
            title: "Shadow Offset",
            key: "subShadowOffset",
            options: ["0", "1", "2", "3", "4"],
            defaultValue: "0"
        ))
        views.append(makeToggleRow(
            title: "Override ASS/SSA subtitle styles",
            key: "subAssOverride",
            defaultValue: false
        ))

        views.append(makeRestoreDefaultsButton(keys: [
            "subAutoLoad", "subLang", "subFontSize", "subFont", "subPosition",
            "subBorderSize", "subShadowOffset", "subAssOverride"
        ]))

        addViewsToContainer(container, views: views)
        return scroll
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Section: Network
    // ═══════════════════════════════════════════════════════════════════

    private func buildNetworkSection() -> NSView {
        let scroll = makeScrollView()
        let container = scroll.documentView!

        var views: [NSView] = []
        views.append(makeSectionHeader("Network & Streaming"))

        views.append(makeToggleRow(
            title: "Enable cache",
            key: "cacheEnabled",
            defaultValue: true
        ))
        views.append(makePopUpRow(
            title: "Demuxer Cache Size",
            key: "cacheSizeMB",
            options: ["64 MB", "128 MB", "256 MB", "512 MB", "1024 MB", "2000 MB"],
            defaultValue: "2000 MB"
        ))
        views.append(makePopUpRow(
            title: "Demuxer Back Buffer",
            key: "cacheBackMB",
            options: ["64 MB", "128 MB", "256 MB", "500 MB", "1024 MB"],
            defaultValue: "500 MB"
        ))
        views.append(makePopUpRow(
            title: "Read-ahead (seconds)",
            key: "readaheadSecs",
            options: ["10", "30", "60", "120", "300"],
            defaultValue: "60"
        ))
        views.append(makePopUpRow(
            title: "Cache Duration (seconds)",
            key: "cacheSecs",
            options: ["30", "60", "120", "300", "600"],
            defaultValue: "120"
        ))
        views.append(makePopUpRow(
            title: "Network Timeout (seconds)",
            key: "networkTimeout",
            options: ["15", "30", "60", "120"],
            defaultValue: "60"
        ))
        views.append(makeToggleRow(
            title: "Force seekable streams",
            key: "forceSeekable",
            defaultValue: true
        ))
        views.append(makeToggleRow(
            title: "Auto reconnect on failure",
            key: "reconnect",
            defaultValue: true
        ))
        views.append(makePopUpRow(
            title: "User Agent",
            key: "userAgent",
            options: ["(Default)", "Mozilla/5.0 (Macintosh)", "VLC/3.0"],
            defaultValue: "(Default)"
        ))

        views.append(makeRestoreDefaultsButton(keys: [
            "cacheEnabled", "cacheSizeMB", "cacheBackMB", "readaheadSecs",
            "cacheSecs", "networkTimeout", "forceSeekable", "reconnect", "userAgent"
        ]))

        addViewsToContainer(container, views: views)
        return scroll
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Section: Scaling
    // ═══════════════════════════════════════════════════════════════════

    private func buildScalingSection() -> NSView {
        let scroll = makeScrollView()
        let container = scroll.documentView!

        var views: [NSView] = []
        views.append(makeSectionHeader("Scaling & Rendering"))

        views.append(makePopUpRow(
            title: "Video Profile",
            key: "videoProfile",
            options: ["default", "high-quality", "fast"],
            defaultValue: "high-quality"
        ))
        views.append(makeDescriptionLabel(
            "'high-quality' enables high-quality scaling algorithms. " +
            "'fast' prioritizes performance."
        ))

        views.append(makePopUpRow(
            title: "Upscale Filter",
            key: "scaleFilter",
            options: ["ewa_lanczossharp", "ewa_lanczos", "lanczos", "spline36", "mitchell", "bilinear", "catmull_rom"],
            defaultValue: "ewa_lanczossharp"
        ))
        views.append(makePopUpRow(
            title: "Downscale Filter",
            key: "dscaleFilter",
            options: ["mitchell", "lanczos", "spline36", "bilinear", "catmull_rom", "ewa_lanczos"],
            defaultValue: "mitchell"
        ))
        views.append(makePopUpRow(
            title: "Chroma Scaler",
            key: "cscaleFilter",
            options: ["mitchell", "lanczos", "spline36", "bilinear", "catmull_rom", "ewa_lanczos", "ewa_lanczossharp"],
            defaultValue: "mitchell"
        ))
        views.append(makePopUpRow(
            title: "Dither Depth",
            key: "ditherDepth",
            options: ["auto", "no", "8", "10"],
            defaultValue: "auto"
        ))
        views.append(makePopUpRow(
            title: "Dither Algorithm",
            key: "ditherAlgo",
            options: ["fruit", "ordered", "error-diffusion", "no"],
            defaultValue: "fruit"
        ))
        views.append(makeToggleRow(
            title: "Correct downscaling",
            key: "correctDownscaling",
            defaultValue: true
        ))
        views.append(makeToggleRow(
            title: "Linear downscaling",
            key: "linearDownscaling",
            defaultValue: true
        ))
        views.append(makeToggleRow(
            title: "Sigmoid upscaling",
            key: "sigmoidUpscaling",
            defaultValue: true
        ))

        views.append(makeRestoreDefaultsButton(keys: [
            "videoProfile", "scaleFilter", "dscaleFilter", "cscaleFilter",
            "ditherDepth", "ditherAlgo", "correctDownscaling", "linearDownscaling",
            "sigmoidUpscaling"
        ]))

        addViewsToContainer(container, views: views)
        return scroll
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Section: Color / HDR
    // ═══════════════════════════════════════════════════════════════════

    private func buildColorSection() -> NSView {
        let scroll = makeScrollView()
        let container = scroll.documentView!

        var views: [NSView] = []
        views.append(makeSectionHeader("Color & HDR"))

        views.append(makeDescriptionLabel(
            "These settings control tone mapping for HDR/DV content and " +
            "color management. The conditional HDR profile in mpv.conf " +
            "activates automatically for HDR content."
        ))

        views.append(makePopUpRow(
            title: "Tone Mapping",
            key: "toneMapping",
            options: ["auto", "spline", "bt.2390", "reinhard", "hable", "mobius", "clip", "gamma", "linear"],
            defaultValue: "spline"
        ))
        views.append(makePopUpRow(
            title: "Tone Mapping Mode",
            key: "toneMappingMode",
            options: ["auto", "luma", "max", "rgb", "hybrid"],
            defaultValue: "auto"
        ))
        views.append(makeToggleRow(
            title: "HDR compute peak (dynamic)",
            key: "hdrComputePeak",
            defaultValue: true
        ))
        views.append(makeToggleRow(
            title: "Target colorspace hint (EDR/XDR)",
            key: "targetColorspaceHint",
            defaultValue: true
        ))
        views.append(makePopUpRow(
            title: "Target Peak",
            key: "targetPeak",
            options: ["auto", "100", "200", "400", "600", "1000", "1600"],
            defaultValue: "auto"
        ))
        views.append(makePopUpRow(
            title: "Gamut Mapping",
            key: "gamutMapping",
            options: ["perceptual", "relative", "saturation", "absolute", "desaturate", "darken", "warn", "linear"],
            defaultValue: "perceptual"
        ))
        views.append(makePopUpRow(
            title: "ICC Profile",
            key: "iccProfile",
            options: ["(None)", "(Auto)"],
            defaultValue: "(None)"
        ))

        views.append(makeRestoreDefaultsButton(keys: [
            "toneMapping", "toneMappingMode", "hdrComputePeak",
            "targetColorspaceHint", "targetPeak", "gamutMapping", "iccProfile"
        ]))

        addViewsToContainer(container, views: views)
        return scroll
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Section: Anime4K
    // ═══════════════════════════════════════════════════════════════════

    private func buildAnime4KSection() -> NSView {
        let scroll = makeScrollView()
        let container = scroll.documentView!

        var views: [NSView] = []
        views.append(makeSectionHeader("Anime4K Shaders"))

        views.append(makeDescriptionLabel(
            "Anime4K shaders enhance anime visuals using real-time GPU processing. " +
            "HQ presets require M1 Pro/Max or better. Fast presets work on all Apple Silicon."
        ))

        views.append(makePopUpRow(
            title: "Default Preset",
            key: "defaultShaderPreset",
            options: ["Off", "Auto (Recommended)", "Mode A (HQ)", "Mode B (HQ)", "Mode C (HQ)",
                      "Mode A+A (HQ)", "Mode B+B (HQ)", "Mode C+A (HQ)",
                      "Mode A (Fast)", "Mode B (Fast)", "Mode C (Fast)",
                      "Mode A+A (Fast)", "Mode B+B (Fast)", "Mode C+A (Fast)"],
            defaultValue: "Off"
        ))
        views.append(makeToggleRow(
            title: "Auto-apply when loading anime content",
            key: "autoApplyShaders",
            defaultValue: false
        ))

        views.append(makeRestoreDefaultsButton(keys: [
            "defaultShaderPreset", "autoApplyShaders"
        ]))

        addViewsToContainer(container, views: views)
        return scroll
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Section: Cache & Cleanup
    // ═══════════════════════════════════════════════════════════════════

    private func buildCleanupSection() -> NSView {
        let scroll = makeScrollView()
        let container = scroll.documentView!

        var views: [NSView] = []
        views.append(makeSectionHeader("Cache & Cleanup"))

        views.append(makeDescriptionLabel(
            "Clear stored data to free disk space. Watch history tracks your resume " +
            "positions. Caches include decoded media data. rclone caches are remote " +
            "file listings cached locally."
        ))

        views.append(makeActionButton(
            title: "Clear Watch History",
            icon: "clock.arrow.circlepath",
            action: #selector(clearWatchHistory)
        ))
        views.append(makeActionButton(
            title: "Clear Media Caches",
            icon: "internaldrive",
            action: #selector(clearMediaCaches)
        ))
        views.append(makeActionButton(
            title: "Clear rclone Caches",
            icon: "cloud",
            action: #selector(clearRcloneCaches)
        ))

        addViewsToContainer(container, views: views)
        return scroll
    }

    // MARK: - Cleanup Actions

    @objc private func clearWatchHistory() {
        let keys = UserDefaults.standard.dictionaryRepresentation().keys
            .filter { $0.hasPrefix("resume_") }
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        showCleanupAlert("Watch history cleared.")
    }

    @objc private func clearMediaCaches() {
        if let cacheDir = FileManager.default.urls(for: .cachesDirectory,
                                                    in: .userDomainMask).first {
            let appCache = cacheDir.appendingPathComponent("com.glassplayer")
            try? FileManager.default.removeItem(at: appCache)
        }
        showCleanupAlert("Media caches cleared.")
    }

    @objc private func clearRcloneCaches() {
        let home = NSHomeDirectory()
        let rcloneCacheDir = home + "/.cache/rclone"
        if FileManager.default.fileExists(atPath: rcloneCacheDir) {
            try? FileManager.default.removeItem(atPath: rcloneCacheDir)
        }
        showCleanupAlert("rclone caches cleared.")
    }

    private func showCleanupAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Cleanup Complete"
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        if let w = window {
            alert.beginSheetModal(for: w, completionHandler: nil)
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - UI Builder Helpers
    // ═══════════════════════════════════════════════════════════════════

    private func makeScrollView() -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        // Use a flipped view so content starts at the top, not the bottom
        let container = FlippedView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        scrollView.documentView = container

        container.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor).isActive = true
        container.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor).isActive = true
        container.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor).isActive = true

        return scrollView
    }

    private func addViewsToContainer(_ container: NSView, views: [NSView]) {
        for view in views {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor).isActive = true
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor).isActive = true
        }

        guard let first = views.first else { return }
        first.topAnchor.constraint(equalTo: container.topAnchor, constant: 16).isActive = true

        for i in 1..<views.count {
            views[i].topAnchor.constraint(equalTo: views[i-1].bottomAnchor, constant: 4).isActive = true
        }

        if let last = views.last {
            last.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -16).isActive = true
        }
    }

    private func makeSectionHeader(_ title: String) -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 20, weight: .semibold)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        view.heightAnchor.constraint(equalToConstant: 40).isActive = true
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        return view
    }

    private func makeDescriptionLabel(_ text: String) -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.usesSingleLineMode = false
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            label.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -4),
        ])
        return view
    }

    private func makeToggleRow(title: String, key: String, defaultValue: Bool) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(label)

        let toggle = NSSwitch()
        toggle.state = UserDefaults.standard.object(forKey: key) != nil
            ? (UserDefaults.standard.bool(forKey: key) ? .on : .off)
            : (defaultValue ? .on : .off)
        toggle.target = self
        toggle.action = #selector(toggleChanged(_:))
        toggle.tag = key.hashValue
        toggle.translatesAutoresizingMaskIntoConstraints = false
        objc_setAssociatedObject(toggle, AssociatedKeys.settingsKey, key,
                                 .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        row.addSubview(toggle)

        row.heightAnchor.constraint(equalToConstant: 36).isActive = true
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 24),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            toggle.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -24),
            toggle.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
        return row
    }

    @objc private func toggleChanged(_ sender: NSSwitch) {
        guard let key = objc_getAssociatedObject(sender, AssociatedKeys.settingsKey)
            as? String else { return }
        let isOn = sender.state == .on
        UserDefaults.standard.set(isOn, forKey: key)
        applySettingToMPV(key: key, value: isOn ? "yes" : "no")
    }

    private func makePopUpRow(title: String, key: String, options: [String],
                               defaultValue: String) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(label)

        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: options)
        let saved = UserDefaults.standard.string(forKey: key) ?? defaultValue
        popup.selectItem(withTitle: saved)
        popup.target = self
        popup.action = #selector(popUpChanged(_:))
        popup.font = .systemFont(ofSize: 12)
        objc_setAssociatedObject(popup, AssociatedKeys.settingsKey, key,
                                 .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        popup.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(popup)

        row.heightAnchor.constraint(equalToConstant: 36).isActive = true
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 24),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            popup.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -24),
            popup.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 140),
        ])
        return row
    }

    @objc private func popUpChanged(_ sender: NSPopUpButton) {
        guard let key = objc_getAssociatedObject(sender, AssociatedKeys.settingsKey)
            as? String else { return }
        let value = sender.titleOfSelectedItem ?? ""
        UserDefaults.standard.set(value, forKey: key)
        applySettingToMPV(key: key, value: value)
    }

    /// Apply a settings change to all open player windows' mpv instances.
    private func applySettingToMPV(key: String, value: String) {
        guard let mpvProp = Self.keyToMPV[key] else { return }

        var mpvValue = value

        // Special case: audioPassthrough stores bool but audio-spdif needs codec list
        if key == "audioPassthrough" {
            let lower = value.lowercased()
            let enabled = lower == "yes" || lower == "1" || lower == "true"
            mpvValue = enabled ? "ac3,eac3,truehd,dts-hd" : ""
        }

        // Transform bool-style values
        if Self.boolKeys.contains(key) {
            let lower = value.lowercased()
            if lower == "1" || lower == "true" { mpvValue = "yes" }
            else if lower == "0" || lower == "false" { mpvValue = "no" }
        }

        // Append MiB suffix for byte-size settings
        if Self.mibKeys.contains(key) {
            mpvValue = value + "MiB"
        }

        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        for pw in appDelegate.playerWindows {
            pw.mpv.setPropertyString(mpvProp, mpvValue)
        }
    }

    private func makeActionButton(title: String, icon: String, action: Selector) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let button = NSButton()
        button.bezelStyle = .rounded
        button.title = "  " + title
        button.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.target = self
        button.action = action
        button.font = .systemFont(ofSize: 13)
        button.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(button)

        row.heightAnchor.constraint(equalToConstant: 38).isActive = true
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 24),
            button.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
        return row
    }

    private func makeRestoreDefaultsButton(keys: [String]) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(sep)

        let button = NSButton()
        button.bezelStyle = .rounded
        button.title = "Restore Defaults"
        button.font = .systemFont(ofSize: 12)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.target = self
        button.action = #selector(restoreDefaultsTapped(_:))
        objc_setAssociatedObject(button, AssociatedKeys.settingsKey, keys,
                                 .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        row.addSubview(button)

        row.heightAnchor.constraint(equalToConstant: 50).isActive = true
        NSLayoutConstraint.activate([
            sep.topAnchor.constraint(equalTo: row.topAnchor, constant: 8),
            sep.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 24),
            sep.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -24),

            button.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -24),
            button.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -4),
        ])
        return row
    }

    @objc private func restoreDefaultsTapped(_ sender: NSButton) {
        guard let keys = objc_getAssociatedObject(sender, AssociatedKeys.settingsKey)
            as? [String] else { return }
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        let row = sidebarTable.selectedRow
        if row >= 0 { showSection(at: row) }
    }
}

// Associated object key for settings binding
private enum AssociatedKeys {
    static let settingsKey = UnsafeRawPointer(
        UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
    )
}
