import Cocoa
import IOKit.pwr_mgt
import UniformTypeIdentifiers
import AVFoundation
import CoreAudio
import MediaPlayer

// ---------------------------------------------------------------------------
// PlayerWindow – full-featured player window with glass overlay controls
// Ports ALL features from the Electron React UI:
//   • Subtitle / Audio / Anime4K Shader popup menus
//   • Speed selector, seek ±10s, prev/next
//   • Pause indicator (center flash)
//   • Video info overlay (press 'i')
//   • Top bar with title, URL input, open file
//   • Click-to-pause, double-click fullscreen, scroll-wheel volume
//   • Comprehensive keyboard shortcuts
// ---------------------------------------------------------------------------

class PlayerWindow: NSWindowController, NSWindowDelegate, MPVControllerDelegate, NSTextFieldDelegate {

    let mpv = MPVController()
    let videoView: VideoView
    var filePath: String?

    // ── Bottom controls bar ──
    private let controlsContainer = NSVisualEffectView()

    // Timeline row
    private let timelineSlider = NSSlider()
    private let currentTimeLabel = NSTextField(labelWithString: "0:00")
    private let remainingTimeLabel = NSTextField(labelWithString: "-0:00")

    // Left group: track selectors
    private let subtitleButton = NSButton()
    private let audioButton = NSButton()
    private let shaderButton = NSButton()

    // Center group: transport
    private let seekBackButton = NSButton()
    private let prevButton = NSButton()
    private let playPauseButton = NSButton()
    private let nextButton = NSButton()
    private let seekForwardButton = NSButton()

    // Right group: volume, speed, fullscreen
    private let volumeButton = NSButton()
    private let volumeSlider = NSSlider()
    private let speedButton = NSButton()
    private let aspectButton = NSButton()
    private let fullscreenButton = NSButton()

    // ── Top bar ──
    private let topBar = NSVisualEffectView()
    private let titleLabel = NSTextField(labelWithString: "Glass Player")
    private let urlButton = NSButton()
    private let openFileButton = NSButton()
    private let urlTextField = NSTextField()
    private var urlInputVisible = false

    // ── Gradients ──
    private let topGradient = CAGradientLayer()
    private let bottomGradient = CAGradientLayer()

    // ── Pause indicator ──
    private var pauseIndicatorView: NSView?

    // ── Video info overlay ──
    private var videoInfoView: NSView?
    private var showingVideoInfo = false

    // ── State ──
    private var isPaused = true
    private var duration: Double = 0
    private var currentTime: Double = 0
    private var currentVolume: Double = 100
    private var currentSpeed: Double = 1.0
    private var isMuted = false
    private var isSeeking = false
    private var hideTimer: Timer?
    private var resizeDebounceTimer: Timer?
    private var controlsVisible = true
    private var videoWidth: Int64 = 0
    private var videoHeight: Int64 = 0
    private var displayWidth: Int64 = 0   // video-out-params/dw (accounts for aspect override + PAR)
    private var displayHeight: Int64 = 0  // video-out-params/dh
    private var isFirstPause = true  // skip pause indicator on first load
    private var currentTracks: [TrackInfo] = []
    private var lastSeekTime: CFTimeInterval = 0
    private var keyMonitor: Any?
    private var lastDisplayedSecond: Int = -1  // coalesce time-pos updates
    private var singleClickWorkItem: DispatchWorkItem?
    private var cursorHidden = false

    // ── Display sleep prevention ──
    private var sleepAssertionID: IOPMAssertionID = 0
    private var isSleepPrevented = false

    // ── Hover bars (brightness left, volume right) ──
    private var brightnessHoverBar: NSVisualEffectView?
    private var volumeHoverBar: NSVisualEffectView?
    private var brightnessSliderV: NSSlider?
    private var volumeSliderV: NSSlider?
    private var brightnessHoverVisible = false
    private var volumeHoverVisible = false
    private var leftTrackingArea: NSTrackingArea?
    private var rightTrackingArea: NSTrackingArea?
    private var currentBrightness: Double = 50   // 0-100 scale
    private var isBuiltInDisplay = true

    // ── Aspect ratio ──
    private var currentAspect: String = "auto"

    // ── Format badges (Apple TV / Infuse style) ──
    private let badgeStack = NSStackView()
    private var currentBadges: FormatBadges? = nil

    // ── Timeline preview thumbnail ──
    private var previewContainer: NSVisualEffectView?
    private var previewImageView: NSImageView?
    private var previewTimeLabel: NSTextField?
    private var lastThumbnailTime: Double = -1
    private var thumbnailCache: [Int: NSImage] = [:]   // keyed by second
    private var pendingThumbnailTime: Double = -1
    private var isGeneratingThumbnail = false
    private var thumbnailMPV: ThumbnailMPV?
    private var isHoveringTimeline = false
    private let thumbnailCacheLimit: Int

    // ── System brightness/volume sync ──
    private var systemSyncTimer: Timer?

    // ── Cached SF Symbol images (avoid repeated allocation) ──
    private static let symbolConfig14 = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
    private static let symbolConfig18 = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
    private let cachedPlayImage  = NSImage(systemSymbolName: "play.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(symbolConfig18)
    private let cachedPauseImage = NSImage(systemSymbolName: "pause.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(symbolConfig18)
    private let cachedSpeakerMuted  = NSImage(systemSymbolName: "speaker.slash.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(symbolConfig14)
    private let cachedSpeakerLow    = NSImage(systemSymbolName: "speaker.wave.1.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(symbolConfig14)
    private let cachedSpeakerNormal = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(symbolConfig14)
    private let cachedFSEnter = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: nil)?
        .withSymbolConfiguration(symbolConfig14)
    private let cachedFSExit  = NSImage(systemSymbolName: "arrow.down.right.and.arrow.up.left", accessibilityDescription: nil)?
        .withSymbolConfiguration(symbolConfig14)

    // MARK: - Init

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable,
                        .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = .black
        window.minSize = NSSize(width: 480, height: 270)
        window.title = "Glass Player"
        window.center()
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)  // always dark over video

        // Memory-floor-aware cache limit (Phase 1B: UMA Efficiency)
        thumbnailCacheLimit = UniversalSharedMetalBufferFactory.shared.recommendedThumbnailCacheLimit

        // IINA pattern: .managed makes macOS place new windows on a regular
        // desktop Space (never on a fullscreen Space).  .fullScreenPrimary
        // allows the window to enter native fullscreen later.
        window.collectionBehavior = [.managed, .fullScreenPrimary]

        // Create video view
        videoView = VideoView(frame: window.contentView!.bounds)

        super.init(window: window)
        window.windowController = self
        window.delegate = self

        // Add video view
        window.contentView!.addSubview(videoView)
        videoView.frame = window.contentView!.bounds
        videoView.autoresizingMask = [.width, .height]

        // Drag & drop
        window.contentView!.registerForDraggedTypes([.fileURL])

        // Setup UI
        setupGradients()
        setupTopBar()
        setupControls()
        setupMouseTracking()
        setupClickHandlers()

        // Initialize mpv
        mpv.delegate = self
        mpv.initialize()

        // Connect rendering
        videoView.videoLayer.initMPVRendering(mpv)

        // Detect built-in display via IOKit backlight service
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                IOServiceMatching("AppleBacklightDisplay"))
        isBuiltInDisplay = service != 0
        if service != 0 { IOObjectRelease(service) }

        // Setup hover bars
        setupHoverBars()

        // Register for macOS Now Playing (Control Center media controls)
        setupNowPlaying()

        // Register for memory pressure → evict thumbnail cache (Phase 1B)
        UMAMemoryPressureMonitor.shared.onPressure { [weak self] in
            DispatchQueue.main.async {
                self?.thumbnailCache.removeAll(keepingCapacity: false)
                NSLog("[PlayerWindow] Thumbnail cache evicted due to memory pressure")
            }
        }

        // Global key event monitor for reliable keyboard shortcuts
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self,
                  event.window == self.window else { return event }
            if self.handleKeyEvent(event) { return nil }
            return event
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    // MARK: - File Loading

    func loadFile(_ path: String) {
        filePath = path
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        mpv.loadFile(path)
        let filename = (path as NSString).lastPathComponent
        window?.title = filename
        titleLabel.stringValue = filename
        setupThumbnailGenerator()
    }

    func loadUrl(_ url: String) {
        filePath = nil
        thumbnailCache.removeAll()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        mpv.loadUrl(url)
        titleLabel.stringValue = url
        // Bug 4: set up thumbnail generator for streaming URLs
        setupThumbnailGeneratorForUrl(url)
        // Bug 5: ensure player window gets keyboard focus after URL load
        window?.makeFirstResponder(videoView)
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Top Bar
    // ═══════════════════════════════════════════════════════════════════

    private func setupTopBar() {
        guard let contentView = window?.contentView else { return }

        topBar.material = .hudWindow
        topBar.blendingMode = .withinWindow
        topBar.state = .active
        topBar.wantsLayer = true
        topBar.layer?.cornerRadius = 0
        topBar.layer?.masksToBounds = true
        topBar.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(topBar)

        // Title label
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .white
        titleLabel.backgroundColor = .clear
        titleLabel.isBezeled = false
        titleLabel.isEditable = false
        titleLabel.alignment = .left
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(titleLabel)

        // URL text field (hidden by default)
        urlTextField.placeholderString = "Paste URL (YouTube, HTTP, etc.)"
        urlTextField.font = .systemFont(ofSize: 12)
        urlTextField.textColor = .white
        urlTextField.backgroundColor = NSColor.white.withAlphaComponent(0.08)
        urlTextField.isBezeled = true
        urlTextField.bezelStyle = .roundedBezel
        urlTextField.focusRingType = .none
        urlTextField.isHidden = true
        urlTextField.target = self
        urlTextField.action = #selector(urlSubmitted)
        urlTextField.delegate = self
        urlTextField.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(urlTextField)

        // URL button
        configureIconButton(urlButton, symbolName: "link", size: 13)
        urlButton.target = self
        urlButton.action = #selector(toggleUrlInput)
        urlButton.alphaValue = 0.6
        urlButton.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(urlButton)

        // Open file button
        configureIconButton(openFileButton, symbolName: "folder", size: 13)
        openFileButton.target = self
        openFileButton.action = #selector(openFileAction)
        openFileButton.alphaValue = 0.6
        openFileButton.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(openFileButton)

        // Format badge stack (Dolby Vision • HDR • Atmos • 5.1 • 4K)
        badgeStack.orientation = .horizontal
        badgeStack.spacing = 5
        badgeStack.alignment = .centerY
        badgeStack.distribution = .fill
        badgeStack.translatesAutoresizingMaskIntoConstraints = false
        badgeStack.setHuggingPriority(.required, for: .horizontal)
        topBar.addSubview(badgeStack)

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: contentView.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 38),

            // Title (right after traffic light buttons)
            titleLabel.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 78),
            titleLabel.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: badgeStack.leadingAnchor, constant: -8),

            // Format badge stack (between title and URL button)
            badgeStack.trailingAnchor.constraint(equalTo: urlButton.leadingAnchor, constant: -8),
            badgeStack.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            badgeStack.heightAnchor.constraint(equalToConstant: 20),

            // URL text field (overlaps title area when visible)
            urlTextField.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 78),
            urlTextField.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            urlTextField.trailingAnchor.constraint(equalTo: urlButton.leadingAnchor, constant: -6),
            urlTextField.heightAnchor.constraint(equalToConstant: 24),

            // URL button
            urlButton.trailingAnchor.constraint(equalTo: openFileButton.leadingAnchor, constant: -2),
            urlButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            urlButton.widthAnchor.constraint(equalToConstant: 28),
            urlButton.heightAnchor.constraint(equalToConstant: 28),

            // Open file button
            openFileButton.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -8),
            openFileButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            openFileButton.widthAnchor.constraint(equalToConstant: 28),
            openFileButton.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    @objc func toggleUrlInput() {
        urlInputVisible.toggle()
        urlTextField.isHidden = !urlInputVisible
        titleLabel.isHidden = urlInputVisible
        if urlInputVisible {
            window?.makeFirstResponder(urlTextField)
            urlButton.alphaValue = 1.0
        } else {
            urlTextField.stringValue = ""
            urlButton.alphaValue = 0.6
            window?.makeFirstResponder(nil)
        }
    }

    /// Dismiss URL input when it loses focus
    func controlTextDidEndEditing(_ obj: Notification) {
        if let field = obj.object as? NSTextField, field === urlTextField {
            // Auto-dismiss if user tabs/clicks away without submitting
            if urlInputVisible {
                urlInputVisible = false
                urlTextField.isHidden = true
                urlTextField.stringValue = ""
                titleLabel.isHidden = false
                urlButton.alphaValue = 0.6
            }
        }
    }

    @objc private func urlSubmitted() {
        let url = urlTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !url.isEmpty {
            loadUrl(url)
        }
        urlInputVisible = false
        urlTextField.isHidden = true
        urlTextField.stringValue = ""
        titleLabel.isHidden = false
        urlButton.alphaValue = 0.6
    }

    @objc private func openFileAction() {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.showOpenPanel()
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Gradients
    // ═══════════════════════════════════════════════════════════════════

    private func setupGradients() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true

        topGradient.colors = [
            NSColor.black.withAlphaComponent(0.6).cgColor,
            NSColor.clear.cgColor
        ]
        topGradient.locations = [0.0, 1.0]
        topGradient.frame = CGRect(x: 0, y: contentView.bounds.height - 80,
                                   width: contentView.bounds.width, height: 80)
        topGradient.autoresizingMask = [.layerWidthSizable, .layerMinYMargin]
        contentView.layer!.addSublayer(topGradient)

        bottomGradient.colors = [
            NSColor.clear.cgColor,
            NSColor.black.withAlphaComponent(0.6).cgColor
        ]
        bottomGradient.locations = [0.0, 1.0]
        bottomGradient.frame = CGRect(x: 0, y: 0,
                                      width: contentView.bounds.width, height: 120)
        bottomGradient.autoresizingMask = [.layerWidthSizable, .layerMaxYMargin]
        contentView.layer!.addSublayer(bottomGradient)
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Controls Setup
    // ═══════════════════════════════════════════════════════════════════

    private func setupControls() {
        guard let contentView = window?.contentView else { return }

        // Glass container for bottom controls
        controlsContainer.material = .hudWindow
        controlsContainer.blendingMode = .withinWindow
        controlsContainer.state = .active
        controlsContainer.wantsLayer = true
        controlsContainer.layer?.cornerRadius = 12
        controlsContainer.layer?.masksToBounds = true
        controlsContainer.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(controlsContainer)

        // ── Timeline row ──
        configureTimeLabel(currentTimeLabel)
        controlsContainer.addSubview(currentTimeLabel)

        timelineSlider.minValue = 0
        timelineSlider.maxValue = 100
        timelineSlider.doubleValue = 0
        timelineSlider.target = self
        timelineSlider.action = #selector(timelineAction(_:))
        timelineSlider.isContinuous = true
        timelineSlider.translatesAutoresizingMaskIntoConstraints = false
        controlsContainer.addSubview(timelineSlider)

        configureTimeLabel(remainingTimeLabel)
        controlsContainer.addSubview(remainingTimeLabel)

        // ── Left group: Track selectors ──
        configureIconButton(subtitleButton, symbolName: "captions.bubble", size: 15)
        subtitleButton.target = self
        subtitleButton.action = #selector(showSubtitleMenu(_:))
        subtitleButton.toolTip = "Subtitles (S)"
        subtitleButton.translatesAutoresizingMaskIntoConstraints = false
        controlsContainer.addSubview(subtitleButton)

        configureIconButton(audioButton, symbolName: "waveform", size: 15)
        audioButton.target = self
        audioButton.action = #selector(showAudioMenu(_:))
        audioButton.toolTip = "Audio Track (A)"
        audioButton.translatesAutoresizingMaskIntoConstraints = false
        controlsContainer.addSubview(audioButton)

        configureIconButton(shaderButton, symbolName: "sparkles", size: 15)
        shaderButton.target = self
        shaderButton.action = #selector(showShaderMenu(_:))
        shaderButton.toolTip = "Anime4K Enhancement"
        shaderButton.translatesAutoresizingMaskIntoConstraints = false
        controlsContainer.addSubview(shaderButton)

        // ── Center group: Transport ──
        configureIconButton(seekBackButton, symbolName: "gobackward.5", size: 16)
        seekBackButton.target = self
        seekBackButton.action = #selector(seekBackAction)
        seekBackButton.toolTip = "Rewind 5s"
        seekBackButton.translatesAutoresizingMaskIntoConstraints = false
        controlsContainer.addSubview(seekBackButton)

        configureIconButton(prevButton, symbolName: "backward.end.fill", size: 14)
        prevButton.target = self
        prevButton.action = #selector(prevAction)
        prevButton.toolTip = "Previous"
        prevButton.translatesAutoresizingMaskIntoConstraints = false
        controlsContainer.addSubview(prevButton)

        // Play/Pause – larger, circular
        playPauseButton.bezelStyle = .regularSquare
        playPauseButton.isBordered = false
        playPauseButton.imagePosition = .imageOnly
        playPauseButton.focusRingType = .none
        playPauseButton.wantsLayer = true
        if let layer = playPauseButton.layer {
            layer.masksToBounds = true
            layer.cornerRadius = 20
            layer.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
        }
        if let img = NSImage(systemSymbolName: "play.fill", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
            playPauseButton.image = img.withSymbolConfiguration(config)
        }
        playPauseButton.contentTintColor = .white
        playPauseButton.target = self
        playPauseButton.action = #selector(playPauseAction)
        playPauseButton.translatesAutoresizingMaskIntoConstraints = false
        controlsContainer.addSubview(playPauseButton)

        configureIconButton(nextButton, symbolName: "forward.end.fill", size: 14)
        nextButton.target = self
        nextButton.action = #selector(nextAction)
        nextButton.toolTip = "Next"
        nextButton.translatesAutoresizingMaskIntoConstraints = false
        controlsContainer.addSubview(nextButton)

        configureIconButton(seekForwardButton, symbolName: "goforward.5", size: 16)
        seekForwardButton.target = self
        seekForwardButton.action = #selector(seekForwardAction)
        seekForwardButton.toolTip = "Forward 5s"
        seekForwardButton.translatesAutoresizingMaskIntoConstraints = false
        controlsContainer.addSubview(seekForwardButton)

        // ── Right group: Volume, speed, fullscreen ──
        configureIconButton(volumeButton, symbolName: "speaker.wave.2.fill", size: 14)
        volumeButton.target = self
        volumeButton.action = #selector(toggleMuteAction)
        volumeButton.toolTip = "Mute (M)"
        volumeButton.translatesAutoresizingMaskIntoConstraints = false
        controlsContainer.addSubview(volumeButton)

        volumeSlider.minValue = 0
        volumeSlider.maxValue = 200
        volumeSlider.doubleValue = 100
        volumeSlider.target = self
        volumeSlider.action = #selector(volumeAction(_:))
        volumeSlider.isContinuous = true
        volumeSlider.translatesAutoresizingMaskIntoConstraints = false
        controlsContainer.addSubview(volumeSlider)

        // Speed button (text)
        speedButton.bezelStyle = .inline
        speedButton.isBordered = false
        speedButton.title = "1x"
        speedButton.font = .monospacedDigitSystemFont(ofSize: 12, weight: .bold)
        speedButton.contentTintColor = .white
        speedButton.target = self
        speedButton.action = #selector(showSpeedMenu(_:))
        speedButton.toolTip = "Playback Speed"
        speedButton.translatesAutoresizingMaskIntoConstraints = false
        controlsContainer.addSubview(speedButton)

        // Aspect ratio button
        configureIconButton(aspectButton, symbolName: "aspectratio", size: 14)
        aspectButton.target = self
        aspectButton.action = #selector(showAspectMenu(_:))
        aspectButton.toolTip = "Aspect Ratio"
        aspectButton.translatesAutoresizingMaskIntoConstraints = false
        controlsContainer.addSubview(aspectButton)

        configureIconButton(fullscreenButton, symbolName: "arrow.up.left.and.arrow.down.right", size: 14)
        fullscreenButton.target = self
        fullscreenButton.action = #selector(toggleFullscreenAction)
        fullscreenButton.toolTip = "Fullscreen (F)"
        fullscreenButton.translatesAutoresizingMaskIntoConstraints = false
        controlsContainer.addSubview(fullscreenButton)

        // ── Layout ──
        NSLayoutConstraint.activate([
            // Controls container
            controlsContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            controlsContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            controlsContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            controlsContainer.heightAnchor.constraint(equalToConstant: 90),

            // ── Timeline row (top of controls) ──
            currentTimeLabel.leadingAnchor.constraint(equalTo: controlsContainer.leadingAnchor, constant: 14),
            currentTimeLabel.topAnchor.constraint(equalTo: controlsContainer.topAnchor, constant: 8),
            currentTimeLabel.widthAnchor.constraint(equalToConstant: 72),

            timelineSlider.leadingAnchor.constraint(equalTo: currentTimeLabel.trailingAnchor, constant: 4),
            timelineSlider.centerYAnchor.constraint(equalTo: currentTimeLabel.centerYAnchor),

            remainingTimeLabel.leadingAnchor.constraint(equalTo: timelineSlider.trailingAnchor, constant: 4),
            remainingTimeLabel.trailingAnchor.constraint(equalTo: controlsContainer.trailingAnchor, constant: -14),
            remainingTimeLabel.centerYAnchor.constraint(equalTo: currentTimeLabel.centerYAnchor),
            remainingTimeLabel.widthAnchor.constraint(equalToConstant: 60),

            // ── Controls row (bottom of controls) ──
            // Left group
            subtitleButton.leadingAnchor.constraint(equalTo: controlsContainer.leadingAnchor, constant: 10),
            subtitleButton.bottomAnchor.constraint(equalTo: controlsContainer.bottomAnchor, constant: -10),
            subtitleButton.widthAnchor.constraint(equalToConstant: 30),
            subtitleButton.heightAnchor.constraint(equalToConstant: 30),

            audioButton.leadingAnchor.constraint(equalTo: subtitleButton.trailingAnchor, constant: 2),
            audioButton.centerYAnchor.constraint(equalTo: subtitleButton.centerYAnchor),
            audioButton.widthAnchor.constraint(equalToConstant: 30),
            audioButton.heightAnchor.constraint(equalToConstant: 30),

            shaderButton.leadingAnchor.constraint(equalTo: audioButton.trailingAnchor, constant: 2),
            shaderButton.centerYAnchor.constraint(equalTo: subtitleButton.centerYAnchor),
            shaderButton.widthAnchor.constraint(equalToConstant: 30),
            shaderButton.heightAnchor.constraint(equalToConstant: 30),

            // Center group (anchored to center of container)
            playPauseButton.centerXAnchor.constraint(equalTo: controlsContainer.centerXAnchor),
            playPauseButton.centerYAnchor.constraint(equalTo: subtitleButton.centerYAnchor),
            playPauseButton.widthAnchor.constraint(equalToConstant: 40),
            playPauseButton.heightAnchor.constraint(equalToConstant: 40),

            seekBackButton.trailingAnchor.constraint(equalTo: prevButton.leadingAnchor, constant: -4),
            seekBackButton.centerYAnchor.constraint(equalTo: subtitleButton.centerYAnchor),
            seekBackButton.widthAnchor.constraint(equalToConstant: 30),
            seekBackButton.heightAnchor.constraint(equalToConstant: 30),

            prevButton.trailingAnchor.constraint(equalTo: playPauseButton.leadingAnchor, constant: -6),
            prevButton.centerYAnchor.constraint(equalTo: subtitleButton.centerYAnchor),
            prevButton.widthAnchor.constraint(equalToConstant: 28),
            prevButton.heightAnchor.constraint(equalToConstant: 30),

            nextButton.leadingAnchor.constraint(equalTo: playPauseButton.trailingAnchor, constant: 6),
            nextButton.centerYAnchor.constraint(equalTo: subtitleButton.centerYAnchor),
            nextButton.widthAnchor.constraint(equalToConstant: 28),
            nextButton.heightAnchor.constraint(equalToConstant: 30),

            seekForwardButton.leadingAnchor.constraint(equalTo: nextButton.trailingAnchor, constant: 4),
            seekForwardButton.centerYAnchor.constraint(equalTo: subtitleButton.centerYAnchor),
            seekForwardButton.widthAnchor.constraint(equalToConstant: 30),
            seekForwardButton.heightAnchor.constraint(equalToConstant: 30),

            // Right group
            fullscreenButton.trailingAnchor.constraint(equalTo: controlsContainer.trailingAnchor, constant: -10),
            fullscreenButton.centerYAnchor.constraint(equalTo: subtitleButton.centerYAnchor),
            fullscreenButton.widthAnchor.constraint(equalToConstant: 28),
            fullscreenButton.heightAnchor.constraint(equalToConstant: 30),

            aspectButton.trailingAnchor.constraint(equalTo: fullscreenButton.leadingAnchor, constant: -2),
            aspectButton.centerYAnchor.constraint(equalTo: subtitleButton.centerYAnchor),
            aspectButton.widthAnchor.constraint(equalToConstant: 28),
            aspectButton.heightAnchor.constraint(equalToConstant: 30),

            speedButton.trailingAnchor.constraint(equalTo: aspectButton.leadingAnchor, constant: -4),
            speedButton.centerYAnchor.constraint(equalTo: subtitleButton.centerYAnchor),
            speedButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 32),
            speedButton.heightAnchor.constraint(equalToConstant: 30),

            volumeSlider.trailingAnchor.constraint(equalTo: speedButton.leadingAnchor, constant: -8),
            volumeSlider.centerYAnchor.constraint(equalTo: subtitleButton.centerYAnchor),
            volumeSlider.widthAnchor.constraint(equalToConstant: 70),

            volumeButton.trailingAnchor.constraint(equalTo: volumeSlider.leadingAnchor, constant: -4),
            volumeButton.centerYAnchor.constraint(equalTo: subtitleButton.centerYAnchor),
            volumeButton.widthAnchor.constraint(equalToConstant: 28),
            volumeButton.heightAnchor.constraint(equalToConstant: 30),
        ])

        // Start auto-hide timer
        resetHideTimer()
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Click & Scroll Handlers
    // ═══════════════════════════════════════════════════════════════════

    private func setupClickHandlers() {
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(videoClicked(_:)))
        clickGesture.numberOfClicksRequired = 1
        videoView.addGestureRecognizer(clickGesture)

        let doubleClickGesture = NSClickGestureRecognizer(target: self, action: #selector(videoDoubleClicked(_:)))
        doubleClickGesture.numberOfClicksRequired = 2
        videoView.addGestureRecognizer(doubleClickGesture)
    }

    @objc private func videoClicked(_ gesture: NSClickGestureRecognizer) {
        let location = gesture.location(in: window?.contentView)
        if controlsContainer.frame.contains(location) { return }
        if topBar.frame.contains(location) { return }
        // Delay single click to distinguish from double-click
        singleClickWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if self.controlsVisible {
                // Force-hide controls (bypass isPaused guard)
                self.controlsVisible = false
                self.hideTimer?.invalidate()
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.3
                    self.controlsContainer.animator().alphaValue = 0.0
                    self.topBar.animator().alphaValue = 0.0
                }
                CATransaction.begin()
                CATransaction.setAnimationDuration(0.3)
                self.topGradient.opacity = 0.0
                self.bottomGradient.opacity = 0.0
                CATransaction.commit()
                // Hide traffic light buttons with controls
                self.setTrafficLightsHidden(true)
                // Only hide cursor if mouse is inside this window
                if !self.cursorHidden, self.mouseIsInsideWindow() {
                    NSCursor.hide()
                    self.cursorHidden = true
                }
            } else {
                self.showControls()
                self.resetHideTimer()
            }
        }
        singleClickWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: work)
    }

    @objc private func videoDoubleClicked(_ gesture: NSClickGestureRecognizer) {
        let location = gesture.location(in: window?.contentView)
        if controlsContainer.frame.contains(location) { return }
        if topBar.frame.contains(location) { return }
        // Cancel pending single-click (prevent pause on double-click)
        singleClickWorkItem?.cancel()
        singleClickWorkItem = nil
        window?.toggleFullScreen(nil)
    }

    // Scroll wheel → volume (smooth trackpad + discrete mouse wheel)
    override func scrollWheel(with event: NSEvent) {
        let delta: Double
        if event.hasPreciseScrollingDeltas {
            // Trackpad: smooth, proportional
            delta = event.scrollingDeltaY * 0.5
        } else {
            // Mouse wheel: fixed steps
            delta = event.scrollingDeltaY > 0 ? 5.0 : -5.0
        }
        guard abs(delta) > 0.01 else { return }
        let newVol = min(200, max(0, currentVolume + delta))
        mpv.setVolume(newVol)
        currentVolume = newVol
        volumeSlider.doubleValue = newVol
        updateVolumeIcon()
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Popup Menus
    // ═══════════════════════════════════════════════════════════════════

    @objc private func showSubtitleMenu(_ sender: NSButton) {
        let menu = NSMenu()
        let subTracks = currentTracks.filter { $0.type == "sub" }
        let selectedSub = subTracks.first(where: { $0.selected })

        // "Off" option
        let offItem = NSMenuItem(title: "Off", action: #selector(setSubTrackOff), keyEquivalent: "")
        offItem.target = self
        if selectedSub == nil { offItem.state = .on }
        menu.addItem(offItem)

        menu.addItem(.separator())

        for track in subTracks {
            let item = NSMenuItem(title: track.label, action: #selector(setSubTrackAction(_:)), keyEquivalent: "")
            item.target = self
            item.tag = track.id
            item.state = track.selected ? .on : .off
            menu.addItem(item)
        }

        if subTracks.isEmpty {
            let item = NSMenuItem(title: "No subtitles available", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let addExtItem = NSMenuItem(title: "Add External Subtitle...", action: #selector(addExternalSubtitle), keyEquivalent: "")
        addExtItem.target = self
        menu.addItem(addExtItem)

        showMenu(menu, from: sender)
    }

    @objc private func showAudioMenu(_ sender: NSButton) {
        let menu = NSMenu()
        let audioTracks = currentTracks.filter { $0.type == "audio" }

        for track in audioTracks {
            let item = NSMenuItem(title: track.label, action: #selector(setAudioTrackAction(_:)), keyEquivalent: "")
            item.target = self
            item.tag = track.id
            item.state = track.selected ? .on : .off
            menu.addItem(item)
        }

        if audioTracks.isEmpty {
            let item = NSMenuItem(title: "No audio tracks available", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let addExtItem = NSMenuItem(title: "Add External Audio...", action: #selector(addExternalAudio), keyEquivalent: "")
        addExtItem.target = self
        menu.addItem(addExtItem)

        showMenu(menu, from: sender)
    }

    // MARK: - External Track Loading

    @objc func addExternalSubtitle() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "Add External Subtitle"
        panel.message = "Choose a subtitle file"
        if #available(macOS 12.0, *) {
            var types: [UTType] = []
            for ext in ["srt", "ass", "ssa", "sub", "vtt", "idx", "sup", "lrc"] {
                if let t = UTType(filenameExtension: ext) { types.append(t) }
            }
            panel.allowedContentTypes = types
        }
        if panel.runModal() == .OK, let url = panel.url {
            mpv.addExternalSubtitle(url.path)
        }
    }

    @objc func addExternalAudio() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "Add External Audio"
        panel.message = "Choose an audio file"
        if #available(macOS 12.0, *) {
            var types: [UTType] = [.audio, .mp3, .wav, .aiff]
            for ext in ["flac", "m4a", "ogg", "opus", "aac", "wma"] {
                if let t = UTType(filenameExtension: ext) { types.append(t) }
            }
            panel.allowedContentTypes = types
        }
        if panel.runModal() == .OK, let url = panel.url {
            mpv.addExternalAudio(url.path)
        }
    }

    @objc private func showShaderMenu(_ sender: NSButton) {
        let menu = NSMenu()
        let recommendedPreset = UniversalMetalRuntime.recommendedAnime4KPreset()

        // "Off" option
        let offItem = NSMenuItem(title: "Off", action: #selector(clearShadersAction), keyEquivalent: "")
        offItem.target = self
        if mpv.currentShaderPreset == nil { offItem.state = .on }
        menu.addItem(offItem)

        let autoItem = NSMenuItem(title: "Auto (Recommended)", action: #selector(applyAutoShaderAction), keyEquivalent: "")
        autoItem.target = self
        autoItem.toolTip = "Resolved now as: \(recommendedPreset)"
        menu.addItem(autoItem)

        menu.addItem(.separator())

        // HQ presets
        let hqHeaderTitle = recommendedPreset.contains("(HQ)")
            ? "── HQ Presets (Recommended on this Mac) ──"
            : "── HQ Presets ──"
        let hqHeader = NSMenuItem(title: hqHeaderTitle, action: nil, keyEquivalent: "")
        hqHeader.isEnabled = false
        menu.addItem(hqHeader)

        for preset in ["Mode A (HQ)", "Mode B (HQ)", "Mode C (HQ)",
                       "Mode A+A (HQ)", "Mode B+B (HQ)", "Mode C+A (HQ)"] {
            let item = NSMenuItem(title: preset, action: #selector(applyShaderAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset
            item.state = mpv.currentShaderPreset == preset ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        // Fast presets
        let fastHeaderTitle = recommendedPreset.contains("(Fast)")
            ? "── Fast Presets (Recommended on this Mac) ──"
            : "── Fast Presets ──"
        let fastHeader = NSMenuItem(title: fastHeaderTitle, action: nil, keyEquivalent: "")
        fastHeader.isEnabled = false
        menu.addItem(fastHeader)

        for preset in ["Mode A (Fast)", "Mode B (Fast)", "Mode C (Fast)",
                       "Mode A+A (Fast)", "Mode B+B (Fast)", "Mode C+A (Fast)"] {
            let item = NSMenuItem(title: preset, action: #selector(applyShaderAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset
            item.state = mpv.currentShaderPreset == preset ? .on : .off
            menu.addItem(item)
        }

        showMenu(menu, from: sender)
    }

    @objc private func showSpeedMenu(_ sender: NSButton) {
        let menu = NSMenu()
        let speeds: [Double] = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 2, 3, 4]

        for s in speeds {
            let title = s == Double(Int(s)) ? "\(Int(s))x" : "\(s)x"
            let item = NSMenuItem(title: title, action: #selector(setSpeedAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = s
            item.state = abs(currentSpeed - s) < 0.01 ? .on : .off
            menu.addItem(item)
        }

        showMenu(menu, from: sender)
    }

    private func showMenu(_ menu: NSMenu, from button: NSButton) {
        // Force dark appearance on popup menus (prevent wallpaper bleed-through)
        menu.appearance = NSAppearance(named: .darkAqua)
        let point = NSPoint(x: 0, y: button.bounds.height + 4)
        menu.popUp(positioning: nil, at: point, in: button)
    }

    // ── Menu actions ──

    @objc private func setSubTrackOff() {
        mpv.disableSubtitles()
        mpv.refreshTrackList()
    }

    @objc private func setSubTrackAction(_ sender: NSMenuItem) {
        mpv.setSubTrack(sender.tag)
        mpv.refreshTrackList()
    }

    @objc private func setAudioTrackAction(_ sender: NSMenuItem) {
        mpv.setAudioTrack(sender.tag)
        mpv.refreshTrackList()
    }

    @objc private func applyShaderAction(_ sender: NSMenuItem) {
        if let preset = sender.representedObject as? String {
            _ = mpv.applyShaderPreset(preset)
            updateShaderButton()
        }
    }

    @objc private func applyAutoShaderAction() {
        let resolved = UniversalMetalRuntime.recommendedAnime4KPreset()
        _ = mpv.applyShaderPreset(resolved)
        updateShaderButton()
    }

    @objc private func clearShadersAction() {
        mpv.clearShaders()
        updateShaderButton()
    }

    @objc private func setSpeedAction(_ sender: NSMenuItem) {
        if let speed = sender.representedObject as? Double {
            mpv.setSpeed(speed)
            currentSpeed = speed
            updateSpeedButton()
        }
    }

    @objc private func showAspectMenu(_ sender: NSButton) {
        let menu = NSMenu()
        let aspects = [("Auto", "auto"), ("16:9", "16:9"), ("4:3", "4:3"),
                       ("21:9", "21:9"), ("1:1", "1:1"), ("2.35:1", "2.35:1")]
        for (title, value) in aspects {
            let item = NSMenuItem(title: title, action: #selector(setAspectAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value
            item.state = currentAspect == value ? .on : .off
            menu.addItem(item)
        }
        showMenu(menu, from: sender)
    }

    @objc private func setAspectAction(_ sender: NSMenuItem) {
        if let aspect = sender.representedObject as? String {
            currentAspect = aspect
            mpv.setAspectOverride(aspect)
            // Tint button when non-auto
            aspectButton.contentTintColor = aspect == "auto" ? .white :
                NSColor(red: 0.04, green: 0.52, blue: 1.0, alpha: 1.0)
            // Wait for mpv to compute new display dimensions, then animate resize
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self else { return }
                let dims = self.mpv.getDisplayDimensions()
                if dims.width > 0 && dims.height > 0 {
                    self.displayWidth = dims.width
                    self.displayHeight = dims.height
                }
                self.resizeWindowToVideo()
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Pause Indicator
    // ═══════════════════════════════════════════════════════════════════

    private func showPauseIndicator(paused: Bool) {
        guard let contentView = window?.contentView else { return }

        // Remove previous
        pauseIndicatorView?.removeFromSuperview()

        let size: CGFloat = 72
        let indicator = NSView(frame: NSRect(
            x: (contentView.bounds.width - size) / 2,
            y: (contentView.bounds.height - size) / 2,
            width: size, height: size
        ))
        indicator.wantsLayer = true
        indicator.layer?.cornerRadius = size / 2
        indicator.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor

        // Icon
        let symbolName = paused ? "pause" : "play.fill"
        if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 30, weight: .medium)
            let imgView = NSImageView(frame: NSRect(x: (size - 40) / 2, y: (size - 40) / 2, width: 40, height: 40))
            imgView.image = img.withSymbolConfiguration(config)
            imgView.contentTintColor = .white
            indicator.addSubview(imgView)
        }

        contentView.addSubview(indicator)
        pauseIndicatorView = indicator

        // Animate: scale up + fade out
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.6
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            indicator.animator().alphaValue = 0.0
        }) {
            indicator.removeFromSuperview()
        }

        // Scale animation via layer
        let scaleAnim = CAKeyframeAnimation(keyPath: "transform.scale")
        scaleAnim.values = [0.75, 1.05, 1.2]
        scaleAnim.keyTimes = [0, 0.4, 1.0]
        scaleAnim.duration = 0.6
        scaleAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        indicator.layer?.add(scaleAnim, forKey: "scale")
    }

    /// Brief OSD text overlay — reuses the pause indicator fade pattern (Bug 14).
    private var osdView: NSView?
    private func showOSD(_ text: String) {
        guard let contentView = window?.contentView else { return }
        osdView?.removeFromSuperview()

        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.sizeToFit()

        let padding: CGFloat = 16
        let w = label.frame.width + padding * 2
        let h: CGFloat = 36
        let container = NSView(frame: NSRect(
            x: (contentView.bounds.width - w) / 2,
            y: contentView.bounds.height * 0.15,
            width: w, height: h
        ))
        container.wantsLayer = true
        container.layer?.cornerRadius = h / 2
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
        label.frame = NSRect(x: padding, y: (h - label.frame.height) / 2,
                             width: label.frame.width, height: label.frame.height)
        container.addSubview(label)
        contentView.addSubview(container)
        osdView = container

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 1.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            container.animator().alphaValue = 0.0
        }) { [weak container] in
            container?.removeFromSuperview()
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Video Info Overlay (press 'i')
    // ═══════════════════════════════════════════════════════════════════

    private func toggleVideoInfo() {
        if showingVideoInfo {
            hideVideoInfo()
        } else {
            showVideoInfo()
        }
    }

    private func showVideoInfo() {
        guard let contentView = window?.contentView else { return }
        showingVideoInfo = true

        // Gather video info off main thread to avoid blocking UI
        UniversalSiliconQoS.heavy.async { [weak self] in
            guard let self = self else { return }
            let info = self.mpv.getVideoInfo()
            DispatchQueue.main.async {
                self.buildVideoInfoPanel(info: info, contentView: contentView)
            }
        }
    }

    private func buildVideoInfoPanel(info: VideoInfo, contentView: NSView) {

        let panelWidth: CGFloat = 360
        let pad: CGFloat = 16
        let rowH: CGFloat = 18
        let sectionGap: CGFloat = 10

        // Build sections
        let sections: [(String, [(String, String)])] = [
            ("FILE", [
                ("Name", info.filename),
                ("Format", info.fileFormat),
                ("Size", formatBytes(info.fileSize)),
                ("Duration", formatTime(info.duration)),
            ]),
            ("VIDEO", [
                ("Codec", info.videoCodec),
                ("Resolution", info.width > 0 ? "\(info.width)×\(info.height)" : "N/A"),
                ("FPS", info.fps > 0 ? String(format: "%.3f", info.fps) : "N/A"),
                ("Bitrate", formatBitrate(info.videoBitrate)),
                ("Pixel Format", info.pixelFormat),
                ("HW Decode", info.hwdec.isEmpty ? "none" : info.hwdec),
            ]),
            ("AUDIO", [
                ("Codec", info.audioCodec),
                ("Sample Rate", info.audioSampleRate > 0 ? "\(info.audioSampleRate) Hz" : "N/A"),
                ("Channels", info.audioChannels > 0 ? "\(info.audioChannels)" : "N/A"),
                ("Bitrate", formatBitrate(info.audioBitrate)),
            ]),
        ]

        // Calculate total height dynamically
        var totalH: CGFloat = pad + 22 + 8  // top padding + header + gap
        for (_, rows) in sections {
            totalH += 16 + 4   // section title + gap
            totalH += CGFloat(rows.count) * rowH
            totalH += sectionGap
        }
        totalH += pad   // bottom padding

        let panel = NSVisualEffectView(frame: NSRect(
            x: 20,
            y: contentView.bounds.height - totalH - 50,
            width: panelWidth,
            height: totalH
        ))
        panel.material = .hudWindow
        panel.blendingMode = .withinWindow
        panel.state = .active
        panel.wantsLayer = true
        panel.layer?.cornerRadius = 12
        panel.layer?.masksToBounds = true
        panel.autoresizingMask = [.minYMargin]

        // Position items from top to bottom
        var y = totalH - pad

        // Header
        let header = makeInfoLabel("Video Information", size: 13, weight: .semibold, color: .white)
        header.frame = NSRect(x: pad, y: y - 18, width: panelWidth - 2 * pad - 30, height: 18)
        panel.addSubview(header)

        // Close button
        let closeBtn = NSButton(frame: NSRect(x: panelWidth - pad - 22, y: y - 18, width: 22, height: 22))
        closeBtn.bezelStyle = .inline
        closeBtn.isBordered = false
        closeBtn.title = "✕"
        closeBtn.contentTintColor = NSColor.white.withAlphaComponent(0.5)
        closeBtn.target = self
        closeBtn.action = #selector(closeVideoInfoAction)
        panel.addSubview(closeBtn)

        y -= 22 + 8

        // Sections
        for (sectionTitle, rows) in sections {
            let sLabel = makeInfoLabel(sectionTitle, size: 10, weight: .bold,
                                       color: NSColor(red: 0.04, green: 0.52, blue: 1.0, alpha: 1.0))
            sLabel.frame = NSRect(x: pad, y: y - 14, width: panelWidth - 2 * pad, height: 14)
            panel.addSubview(sLabel)
            y -= 16 + 4

            for (key, value) in rows {
                let displayValue = value.isEmpty ? "N/A" : value

                let kLabel = makeInfoLabel(key, size: 11, weight: .regular,
                                           color: NSColor.white.withAlphaComponent(0.5))
                kLabel.frame = NSRect(x: pad, y: y - rowH, width: 110, height: rowH)
                panel.addSubview(kLabel)

                let vLabel = makeInfoLabel(displayValue, size: 11, weight: .regular, color: .white)
                vLabel.frame = NSRect(x: pad + 114, y: y - rowH,
                                      width: panelWidth - 2 * pad - 114, height: rowH)
                vLabel.alignment = .right
                vLabel.lineBreakMode = .byTruncatingMiddle
                panel.addSubview(vLabel)

                y -= rowH
            }
            y -= sectionGap
        }

        // Animate in
        panel.alphaValue = 0
        contentView.addSubview(panel)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 1.0
        }

        videoInfoView = panel
    }

    private func hideVideoInfo() {
        showingVideoInfo = false
        if let view = videoInfoView {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                view.animator().alphaValue = 0
            }) {
                view.removeFromSuperview()
            }
        }
        videoInfoView = nil
    }

    @objc private func closeVideoInfoAction() {
        hideVideoInfo()
    }

    private func makeInfoLabel(_ text: String, size: CGFloat, weight: NSFont.Weight,
                               color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        return label
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Format Badges (Apple TV / Infuse style)
    //
    // Small rounded pills in the top bar showing content capabilities:
    //   • Dolby Vision (with Dolby Double-D icon)
    //   • HDR10 / HLG
    //   • Dolby Atmos (with Dolby Double-D icon)
    //   • Channel layout (5.1, 7.1, Stereo)
    //   • Resolution (4K, 1080p)
    // Styled to match Apple TV app: semi-transparent dark background,
    // compact rounded-rect pills with white text.
    // ═══════════════════════════════════════════════════════════════════

    private func updateFormatBadges() {
        let badges = mpv.getFormatBadges()
        currentBadges = badges

        // Clear existing badges
        for view in badgeStack.arrangedSubviews {
            badgeStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        // ── Video format badges ──
        if badges.isDolbyVision {
            badgeStack.addArrangedSubview(makeDolbyBadge("VISION"))
        } else if badges.isHDR10 {
            badgeStack.addArrangedSubview(makeFormatBadge("HDR10",
                bg: NSColor(red: 0.85, green: 0.65, blue: 0.13, alpha: 0.9)))
        } else if badges.isHLG {
            badgeStack.addArrangedSubview(makeFormatBadge("HLG",
                bg: NSColor(red: 0.55, green: 0.75, blue: 0.25, alpha: 0.9)))
        }

        // ── Resolution badge ──
        if let res = badges.resolution {
            badgeStack.addArrangedSubview(makeFormatBadge(res,
                bg: NSColor.white.withAlphaComponent(0.15)))
        }

        // ── Audio format badges ──
        if badges.isDolbyAtmos {
            badgeStack.addArrangedSubview(makeDolbyBadge("ATMOS"))
        }

        // ── Channel layout badge ──
        if let ch = badges.channelLabel, !badges.isDolbyAtmos || ch != "Stereo" {
            badgeStack.addArrangedSubview(makeFormatBadge(ch,
                bg: NSColor.white.withAlphaComponent(0.15)))
        }

        // Animate in
        badgeStack.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.4
            badgeStack.animator().alphaValue = 1.0
        }

        NSLog("[PlayerWindow] Format badges: DV=%d HDR10=%d HLG=%d Atmos=%d res=%@ ch=%@",
              badges.isDolbyVision ? 1 : 0,
              badges.isHDR10 ? 1 : 0,
              badges.isHLG ? 1 : 0,
              badges.isDolbyAtmos ? 1 : 0,
              badges.resolution ?? "nil",
              badges.channelLabel ?? "nil")
    }

    /// Create a standard format pill badge (resolution, channel layout, HDR)
    private func makeFormatBadge(_ text: String, bg: NSColor) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = bg.cgColor
        container.layer?.cornerRadius = 4
        container.layer?.masksToBounds = true
        container.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 9.5, weight: .bold)
        label.textColor = .white
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            container.heightAnchor.constraint(equalToConstant: 18),
        ])

        return container
    }

    /// Create a Dolby-branded badge ("VISION" or "ATMOS")
    /// Styled like Apple TV app: dark pill with Dolby Double-D + label text
    private func makeDolbyBadge(_ type: String) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 4
        container.layer?.masksToBounds = true
        container.layer?.borderWidth = 1.0
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.3).cgColor
        container.layer?.backgroundColor = NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 0.85).cgColor
        container.translatesAutoresizingMaskIntoConstraints = false

        // Dolby Double-D symbol
        let dolbyLabel = NSTextField(labelWithString: "\u{1D53B}")
        dolbyLabel.font = .systemFont(ofSize: 12, weight: .black)
        dolbyLabel.textColor = .white
        dolbyLabel.backgroundColor = .clear
        dolbyLabel.isBezeled = false
        dolbyLabel.isEditable = false
        dolbyLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(dolbyLabel)

        let typeLabel = NSTextField(labelWithString: type)
        typeLabel.font = .systemFont(ofSize: 8.5, weight: .bold)
        typeLabel.textColor = .white
        typeLabel.backgroundColor = .clear
        typeLabel.isBezeled = false
        typeLabel.isEditable = false
        typeLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(typeLabel)

        NSLayoutConstraint.activate([
            dolbyLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 5),
            dolbyLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            typeLabel.leadingAnchor.constraint(equalTo: dolbyLabel.trailingAnchor, constant: 2),
            typeLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
            typeLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            container.heightAnchor.constraint(equalToConstant: 18),
        ])

        return container
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Now Playing (macOS Control Center integration)
    //
    // Registers with MPNowPlayingInfoCenter + MPRemoteCommandCenter
    // so media shows in Control Center / AirPlay panel with proper
    // metadata. For Atmos content, macOS shows "Dolby Atmos" next to
    // the speaker controls when multichannel audio is passed through.
    // ═══════════════════════════════════════════════════════════════════

    private func setupNowPlaying() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.mpv.togglePause()
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.mpv.togglePause()
            return .success
        }

        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.mpv.togglePause()
            return .success
        }

        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.mpv.nextFile()
            return .success
        }

        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.mpv.prevFile()
            return .success
        }

        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let posEvent = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.mpv.seek(to: posEvent.positionTime)
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        let info = mpv.getVideoInfo()
        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: info.filename,
            MPMediaItemPropertyPlaybackDuration: info.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPaused ? 0.0 : currentSpeed,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
        ]

        // Media type: video
        nowPlayingInfo[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.video.rawValue

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        MPNowPlayingInfoCenter.default().playbackState = isPaused ? .paused : .playing
    }

    private func clearNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Actions
    // ═══════════════════════════════════════════════════════════════════

    @objc private func playPauseAction() {
        mpv.togglePause()
    }

    @objc private func seekBackAction() {
        mpv.seek(by: -5)
    }

    @objc private func seekForwardAction() {
        mpv.seek(by: 5)
    }

    @objc private func prevAction() {
        mpv.prevFile()
    }

    @objc private func nextAction() {
        mpv.nextFile()
    }

    @objc private func timelineAction(_ sender: NSSlider) {
        let position = sender.doubleValue / 100.0
        let time = position * duration

        // Immediately update time labels (ms-accurate display)
        currentTimeLabel.stringValue = formatTimePrecise(time)
        remainingTimeLabel.stringValue = "-" + formatTimePrecise(duration - time)

        let event = NSApp.currentEvent
        let isDragging = event?.type != .leftMouseUp

        if isDragging {
            // ── During drag: show preview + fast seek ──
            isSeeking = true
            showTimelinePreview(atPosition: position, time: time)

            // Seek at high frequency for smooth scrubbing (exact, not keyframe)
            let now = CACurrentMediaTime()
            if now - lastSeekTime > 0.03 {  // ~33fps seek rate
                lastSeekTime = now
                mpv.seek(to: time)
            }
        } else {
            // ── Mouse released: final exact seek + hide preview ──
            hideTimelinePreview()
            isHoveringTimeline = false
            mpv.seek(to: time)

            // Brief delay before accepting time-pos updates again
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.isSeeking = false
                self?.lastDisplayedSecond = -1
            }
        }
    }

    @objc private func volumeAction(_ sender: NSSlider) {
        currentVolume = sender.doubleValue
        mpv.setVolume(currentVolume)
        updateVolumeIcon()
    }

    @objc private func toggleMuteAction() {
        mpv.toggleMute()
    }

    @objc private func toggleFullscreenAction() {
        window?.toggleFullScreen(nil)
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Keyboard Handling
    // ═══════════════════════════════════════════════════════════════════

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        // Escape dismisses URL input
        if urlInputVisible {
            if event.keyCode == 53 { // Escape
                toggleUrlInput()
                return true
            }
            return false
        }

        // Cmd+O for open file
        if event.modifierFlags.contains(.command) {
            if event.keyCode == 31 { // O
                openFileAction()
                return true
            }
            // Bug 12: Cmd+U toggles URL input
            if event.keyCode == 32 { // U
                toggleUrlInput()
                return true
            }
            return false
        }

        switch event.keyCode {
        case 49:  // Space
            mpv.togglePause()
        case 40:  // K
            mpv.togglePause()
        case 123: // Left arrow
            mpv.seek(by: -5)
        case 124: // Right arrow
            mpv.seek(by: 5)
        case 125: // Down arrow
            let vol = max(0, currentVolume - 5)
            mpv.setVolume(vol)
            currentVolume = vol
            volumeSlider.doubleValue = vol
            updateVolumeIcon()
        case 126: // Up arrow
            let vol = min(200, currentVolume + 5)
            mpv.setVolume(vol)
            currentVolume = vol
            volumeSlider.doubleValue = vol
            updateVolumeIcon()
        case 3:   // F
            window?.toggleFullScreen(nil)
        case 53:  // Escape
            if let w = window, w.styleMask.contains(.fullScreen) {
                w.toggleFullScreen(nil)
            }
        case 46:  // M
            mpv.toggleMute()
        case 1:   // S
            mpv.cycleSubtitle()
        case 0:   // A
            mpv.cycleAudio()
        case 34:  // I
            toggleVideoInfo()
        case 38:  // J — seek backward 10s
            mpv.seek(by: -10)
        case 37:  // L — seek forward 10s
            mpv.seek(by: 10)
        case 43:  // , (comma) — frame back step
            mpv.frameBackStep()
        case 47:  // . (period) — frame step
            mpv.frameStep()
        case 33:  // [ — slow down
            let newSpeed = max(0.25, currentSpeed - 0.25)
            mpv.setSpeed(newSpeed)
            currentSpeed = newSpeed
            updateSpeedButton()
        case 30:  // ] — speed up
            let newSpeed = min(4.0, currentSpeed + 0.25)
            mpv.setSpeed(newSpeed)
            currentSpeed = newSpeed
            updateSpeedButton()
        case 41:  // ; — audio delay -0.1s (Bug 14)
            mpv_command_string(mpv.mpvHandle, "add audio-delay -0.1")
            let delay = (mpv.getAudioDelay() * 10).rounded() / 10
            showOSD(String(format: "Audio delay: %+.1fs", delay))
        case 39:  // ' — audio delay +0.1s (Bug 14)
            mpv_command_string(mpv.mpvHandle, "add audio-delay 0.1")
            let delay2 = (mpv.getAudioDelay() * 10).rounded() / 10
            showOSD(String(format: "Audio delay: %+.1fs", delay2))
        default:
            return false
        }
        return true
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Mouse Tracking (auto-hide)
    // ═══════════════════════════════════════════════════════════════════

    private func setupMouseTracking() {
        guard let contentView = window?.contentView else { return }
        let trackingArea = NSTrackingArea(
            rect: contentView.bounds,
            options: [.mouseMoved, .mouseEnteredAndExited,
                      .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        contentView.addTrackingArea(trackingArea)
        setupEdgeTrackingAreas()
    }

    /// Create dedicated tracking areas for the left/right edge zones.
    /// These fire mouseEntered/mouseExited reliably even during fast cursor movement.
    private func setupEdgeTrackingAreas() {
        guard let contentView = window?.contentView else { return }

        // Remove old tracking areas if present
        if let old = leftTrackingArea  { contentView.removeTrackingArea(old) }
        if let old = rightTrackingArea { contentView.removeTrackingArea(old) }

        let edgeWidth: CGFloat = 80
        let bounds = contentView.bounds
        let topInset: CGFloat = 50
        let bottomInset: CGFloat = 60
        let h = max(0, bounds.height - topInset - bottomInset)

        let leftRect  = NSRect(x: 0, y: bottomInset, width: edgeWidth, height: h)
        let rightRect = NSRect(x: bounds.width - edgeWidth, y: bottomInset,
                               width: edgeWidth, height: h)

        leftTrackingArea = NSTrackingArea(
            rect: leftRect,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: ["edge": "left"]
        )
        rightTrackingArea = NSTrackingArea(
            rect: rightRect,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: ["edge": "right"]
        )
        contentView.addTrackingArea(leftTrackingArea!)
        contentView.addTrackingArea(rightTrackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        guard let info = event.trackingArea?.userInfo as? [String: String],
              let edge = info["edge"] else { return }
        if edge == "left" && !brightnessHoverVisible {
            brightnessHoverVisible = true
            showHoverBar(brightnessHoverBar, show: true)
        } else if edge == "right" && !volumeHoverVisible {
            volumeHoverVisible = true
            showHoverBar(volumeHoverBar, show: true)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        showControls()
        resetHideTimer()
        guard let contentView = window?.contentView else { return }
        let location = contentView.convert(event.locationInWindow, from: nil)

        // Check edge hover for brightness/volume bars
        checkEdgeHover(at: location)

        // Check timeline hover for preview thumbnails
        checkTimelineHover(at: location)
    }

    private func resetHideTimer() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            self?.hideControls()
        }
    }

    private func showControls() {
        guard !controlsVisible else { return }
        controlsVisible = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            controlsContainer.animator().alphaValue = 1.0
            topBar.animator().alphaValue = 1.0
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.3)
        topGradient.opacity = 1.0
        bottomGradient.opacity = 1.0
        CATransaction.commit()
        // Show traffic light buttons with title bar
        setTrafficLightsHidden(false)
        if cursorHidden {
            NSCursor.unhide()
            cursorHidden = false
        }
    }

    private func hideControls() {
        guard controlsVisible, !isPaused else { return }
        controlsVisible = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.5
            controlsContainer.animator().alphaValue = 0.0
            topBar.animator().alphaValue = 0.0
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.5)
        topGradient.opacity = 0.0
        bottomGradient.opacity = 0.0
        CATransaction.commit()
        // Hide traffic light buttons with title bar
        setTrafficLightsHidden(true)
        // Only hide cursor if this window is key and mouse is inside it
        if !cursorHidden, window?.isKeyWindow == true, mouseIsInsideWindow() {
            NSCursor.hide()
            cursorHidden = true
        }
    }

    /// Show/hide the macOS traffic light buttons (close, minimize, zoom)
    /// so they fade with the title bar overlay.
    private func setTrafficLightsHidden(_ hidden: Bool) {
        guard let w = window else { return }
        for buttonType: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            w.standardWindowButton(buttonType)?.isHidden = hidden
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - UI Update Helpers
    // ═══════════════════════════════════════════════════════════════════

    private func updateVolumeIcon() {
        if isMuted || currentVolume == 0 {
            volumeButton.image = cachedSpeakerMuted
        } else if currentVolume < 50 {
            volumeButton.image = cachedSpeakerLow
        } else {
            volumeButton.image = cachedSpeakerNormal
        }
    }

    private func updateSpeedButton() {
        if currentSpeed == Double(Int(currentSpeed)) {
            speedButton.title = "\(Int(currentSpeed))x"
        } else {
            speedButton.title = "\(currentSpeed)x"
        }
        speedButton.contentTintColor = abs(currentSpeed - 1.0) < 0.01 ? .white :
            NSColor(red: 0.04, green: 0.52, blue: 1.0, alpha: 1.0)
    }

    private func updateShaderButton() {
        if mpv.currentShaderPreset != nil {
            shaderButton.contentTintColor = NSColor(red: 1.0, green: 0.42, blue: 0.8, alpha: 1.0)
        } else {
            shaderButton.contentTintColor = .white
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - MPVControllerDelegate
    // ═══════════════════════════════════════════════════════════════════

    func mpvPropertyChanged(_ name: String, value: Any?) {
        switch name {
        case "time-pos":
            if let time = value as? Double, !isSeeking {
                currentTime = time
                // Coalesce: only update labels when displayed second changes
                let sec = Int(time)
                if sec != lastDisplayedSecond {
                    lastDisplayedSecond = sec
                    currentTimeLabel.stringValue = formatTime(time)
                    remainingTimeLabel.stringValue = "-" + formatTime(duration - time)
                }
                if duration > 0 {
                    timelineSlider.doubleValue = (time / duration) * 100.0
                }
            }
        case "duration":
            if let dur = value as? Double {
                duration = dur
                remainingTimeLabel.stringValue = "-" + formatTime(dur)
            }
        case "pause":
            if let flag = value as? Int32 {
                let wasPaused = isPaused
                isPaused = flag != 0

                playPauseButton.image = isPaused ? cachedPlayImage : cachedPauseImage

                // Show pause indicator (skip the very first pause event)
                if !isFirstPause && wasPaused != isPaused {
                    showPauseIndicator(paused: isPaused)
                }
                isFirstPause = false

                if isPaused {
                    showControls()
                    allowSleep()
                } else {
                    resetHideTimer()
                    preventSleep()
                }
                // Update Now Playing state
                updateNowPlayingInfo()
            }
        case "brightness":
            // mpv brightness is separate — hover bar controls display brightness
            break
        case "media-title":
            if let title = value as? String {
                titleLabel.stringValue = title
                window?.title = title
            }
        case "video-params/w":
            if let w = value as? Int64 { videoWidth = w }
        case "video-params/h":
            if let h = value as? Int64 { videoHeight = h }
        case "video-out-params/dw":
            if let dw = value as? Int64 { displayWidth = dw; scheduleResizeToVideo() }
        case "video-out-params/dh":
            if let dh = value as? Int64 { displayHeight = dh; scheduleResizeToVideo() }
        case "speed":
            if let s = value as? Double {
                currentSpeed = s
                updateSpeedButton()
            }
        case "volume":
            if let v = value as? Double {
                currentVolume = v
                volumeSlider.doubleValue = v
                // Note: volumeSliderV is system volume, not mpv volume
                updateVolumeIcon()
            }
        case "mute":
            if let flag = value as? Int32 {
                isMuted = flag != 0
                updateVolumeIcon()
            }
        default:
            break
        }
    }

    func mpvFileLoaded() {
        print("[PlayerWindow] File loaded")
        isFirstPause = true  // reset for new file
        // Bug 15: reset seek state so time-pos updates flow through immediately
        isSeeking = false
        lastDisplayedSecond = -1
        // Bug 5: ensure keyboard focus is on the video view after any file/URL load
        window?.makeFirstResponder(videoView)

        let shouldAutoApply = UserDefaults.standard.bool(forKey: "autoApplyShaders")
        if shouldAutoApply {
            let configuredPreset = UserDefaults.standard.string(forKey: "defaultShaderPreset") ?? "Off"
            if configuredPreset == "Off" {
                mpv.clearShaders()
            } else if configuredPreset == "Auto (Recommended)" {
                let resolved = UniversalMetalRuntime.recommendedAnime4KPreset()
                _ = mpv.applyShaderPreset(resolved)
            } else {
                _ = mpv.applyShaderPreset(configuredPreset)
            }
            updateShaderButton()
        }

        // Detect format badges after a short delay (mpv needs time to probe)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.updateFormatBadges()
            self?.updateNowPlayingInfo()
        }
    }

    func mpvPlaybackEnded() {
        print("[PlayerWindow] Playback ended")
    }

    func mpvTracksChanged(_ tracks: [TrackInfo]) {
        currentTracks = tracks

        // Update subtitle button tint (highlight if any sub is selected)
        let hasSub = tracks.contains(where: { $0.type == "sub" && $0.selected })
        subtitleButton.contentTintColor = hasSub ?
            NSColor(red: 0.04, green: 0.52, blue: 1.0, alpha: 1.0) : .white

        // Dim audio button if only one audio track
        let audioCount = tracks.filter { $0.type == "audio" }.count
        audioButton.alphaValue = audioCount > 1 ? 1.0 : 0.5
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Window Sizing
    // ═══════════════════════════════════════════════════════════════════

    /// Debounced resize – coalesces rapid display-dimension updates
    /// (e.g. dw and dh arriving separately) into a single smooth resize.
    private func scheduleResizeToVideo() {
        resizeDebounceTimer?.invalidate()
        resizeDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
            self?.resizeWindowToVideo()
        }
    }

    private func resizeWindowToVideo() {
        resizeDebounceTimer?.invalidate()
        resizeDebounceTimer = nil

        // Use display dimensions (accounts for aspect override + pixel aspect ratio).
        // Fall back to coded dimensions if display dims not yet available.
        var dw = displayWidth
        var dh = displayHeight
        if dw <= 0 || dh <= 0 {
            // Try querying mpv directly
            let dims = mpv.getDisplayDimensions()
            dw = dims.width
            dh = dims.height
        }
        if dw <= 0 || dh <= 0 {
            dw = videoWidth
            dh = videoHeight
        }
        guard dw > 0 && dh > 0 else { return }
        guard let win = window, !win.styleMask.contains(.fullScreen) else { return }
        guard let screen = win.screen ?? NSScreen.main else { return }

        let aspect = Double(dw) / Double(dh)
        let screenFrame = screen.visibleFrame

        var newWidth = Double(dw)
        var newHeight = Double(dh)

        let maxWidth = screenFrame.width * 0.8
        let maxHeight = screenFrame.height * 0.8

        if newWidth > maxWidth {
            newWidth = maxWidth
            newHeight = newWidth / aspect
        }
        if newHeight > maxHeight {
            newHeight = maxHeight
            newWidth = newHeight * aspect
        }

        let newSize = NSSize(width: newWidth, height: newHeight)
        var frame = win.frame
        let oldCenter = NSPoint(x: frame.midX, y: frame.midY)
        frame.size = newSize
        frame.origin = NSPoint(x: oldCenter.x - newWidth / 2,
                               y: oldCenter.y - newHeight / 2)

        // Smooth animated resize
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            ctx.allowsImplicitAnimation = true
            win.animator().setFrame(frame, display: true)
        }, completionHandler: {
            win.aspectRatio = newSize
        })
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Window Delegate
    // ═══════════════════════════════════════════════════════════════════

    func windowWillClose(_ notification: Notification) {
        hideTimer?.invalidate()
        resizeDebounceTimer?.invalidate()
        singleClickWorkItem?.cancel()
        allowSleep()
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        if cursorHidden {
            NSCursor.unhide()
            cursorHidden = false
        }
        // Stop system sync timer
        stopSystemSync()

        // Clear Now Playing info from Control Center
        clearNowPlaying()

        // Clean up thumbnail preview resources (dispatch cleanup to E-cores)
        let cacheToClean = thumbnailCache
        thumbnailCache.removeAll()
        UniversalSiliconQoS.maintenance.async {
            _ = cacheToClean.count  // Release images on background thread
        }
        previewContainer?.removeFromSuperview()
        previewContainer = nil
        previewImageView = nil
        previewTimeLabel = nil
        isGeneratingThumbnail = false
        pendingThumbnailTime = -1
        thumbnailMPV?.shutdown()
        thumbnailMPV = nil

        videoView.uninit()
        mpv.shutdown()

        // Remove from AppDelegate's tracking so rclone/welcome can create a fresh player
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.removePlayerWindow(self)
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        // Restore cursor when player loses focus (user switched to rclone browser, etc.)
        if cursorHidden {
            NSCursor.unhide()
            cursorHidden = false
        }
        hideTimer?.invalidate()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        // Restart auto-hide when player regains focus
        if !isPaused {
            resetHideTimer()
        }
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        fullscreenButton.image = cachedFSExit
        // Hide titlebar in fullscreen, flush top bar to top edge
        window?.titlebarAppearsTransparent = true
        window?.toolbar?.isVisible = false
        // Clear aspect ratio lock — fullscreen should fill the entire screen
        // (mpv handles letterboxing internally)
        window?.resizeIncrements = NSSize(width: 1, height: 1)
        // Bug 6: end the live-resize guard now that the FS animation is complete
        videoView.videoLayer.liveResizeEnded()
        // topBar is managed via Auto Layout constraints pinned to contentView.topAnchor,
        // so it automatically adjusts — no manual frame manipulation needed.
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        // Bug 6: suppress IOSurface teardown during the fullscreen animation
        videoView.videoLayer.isInLiveResize = true
    }

    func windowWillExitFullScreen(_ notification: Notification) {
        // Bug 6: suppress IOSurface teardown during the exit animation
        videoView.videoLayer.isInLiveResize = true
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        fullscreenButton.image = cachedFSEnter
        window?.titlebarAppearsTransparent = true
        // Bug 6: end the live-resize guard after exit animation completes
        videoView.videoLayer.liveResizeEnded()
        // Restore correct aspect ratio constraint after leaving fullscreen
        resizeWindowToVideo()
    }

    func windowDidResize(_ notification: Notification) {
        // Refresh edge tracking areas so they match the new window size
        setupEdgeTrackingAreas()
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Hover Bars (brightness/volume on edges)
    // ═══════════════════════════════════════════════════════════════════

    private func setupHoverBars() {
        guard let contentView = window?.contentView else { return }

        // ── Brightness bar (left edge) ──
        let bBar = NSVisualEffectView()
        bBar.material = .hudWindow
        bBar.blendingMode = .withinWindow
        bBar.state = .active
        bBar.wantsLayer = true
        bBar.layer?.cornerRadius = 10
        bBar.layer?.masksToBounds = true
        bBar.alphaValue = 0
        bBar.translatesAutoresizingMaskIntoConstraints = false

        let bIcon = NSImageView(frame: NSRect(x: 6, y: 170, width: 24, height: 20))
        if let img = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            bIcon.image = img.withSymbolConfiguration(config)
        }
        bIcon.contentTintColor = .white
        bBar.addSubview(bIcon)

        let bSlider = NSSlider(frame: NSRect(x: 8, y: 10, width: 20, height: 155))
        bSlider.isVertical = true
        bSlider.minValue = 0
        bSlider.maxValue = 100
        // Read initial display brightness
        if let dispBrightness = getDisplayBrightness() {
            bSlider.doubleValue = Double(dispBrightness) * 100
        } else {
            bSlider.doubleValue = 50
        }
        bSlider.target = self
        bSlider.action = #selector(brightnessSliderAction(_:))
        bSlider.isContinuous = true
        bBar.addSubview(bSlider)
        brightnessSliderV = bSlider

        contentView.addSubview(bBar)
        brightnessHoverBar = bBar

        // ── Volume bar (right edge) ──
        let vBar = NSVisualEffectView()
        vBar.material = .hudWindow
        vBar.blendingMode = .withinWindow
        vBar.state = .active
        vBar.wantsLayer = true
        vBar.layer?.cornerRadius = 10
        vBar.layer?.masksToBounds = true
        vBar.alphaValue = 0
        vBar.translatesAutoresizingMaskIntoConstraints = false

        let vIcon = NSImageView(frame: NSRect(x: 6, y: 170, width: 24, height: 20))
        if let img = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            vIcon.image = img.withSymbolConfiguration(config)
        }
        vIcon.contentTintColor = .white
        vBar.addSubview(vIcon)

        let vSlider = NSSlider(frame: NSRect(x: 8, y: 10, width: 20, height: 155))
        vSlider.isVertical = true
        vSlider.minValue = 0
        vSlider.maxValue = 100
        // Read initial system volume
        vSlider.doubleValue = Double(getSystemVolume()) * 100
        vSlider.target = self
        vSlider.action = #selector(volumeHoverAction(_:))
        vSlider.isContinuous = true
        vBar.addSubview(vSlider)
        volumeSliderV = vSlider

        contentView.addSubview(vBar)
        volumeHoverBar = vBar

        // Auto Layout: anchor hover bars above the controls container
        NSLayoutConstraint.activate([
            // Brightness bar: left edge, sits above controls
            bBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            bBar.bottomAnchor.constraint(equalTo: controlsContainer.topAnchor, constant: -8),
            bBar.widthAnchor.constraint(equalToConstant: 36),
            bBar.heightAnchor.constraint(equalToConstant: 200),

            // Volume bar: right edge, sits above controls
            vBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            vBar.bottomAnchor.constraint(equalTo: controlsContainer.topAnchor, constant: -8),
            vBar.widthAnchor.constraint(equalToConstant: 36),
            vBar.heightAnchor.constraint(equalToConstant: 200),
        ])

        // Bring controls above hover bars
        contentView.addSubview(controlsContainer, positioned: .above, relativeTo: vBar)
        contentView.addSubview(topBar, positioned: .above, relativeTo: controlsContainer)
    }

    @objc private func brightnessSliderAction(_ sender: NSSlider) {
        // Control actual display brightness (nits), not mpv video brightness
        let brightness = Float(sender.doubleValue / 100.0)
        setDisplayBrightness(brightness)
    }

    @objc private func volumeHoverAction(_ sender: NSSlider) {
        // Control system volume (0-100), independent of mpv volume
        setSystemVolume(Float(sender.doubleValue / 100.0))
    }

    private func showHoverBar(_ bar: NSVisualEffectView?, show: Bool) {
        guard let bar = bar else { return }
        if show {
            // Instant appear — no animation delay
            bar.alphaValue = 1.0
            // Sync slider with current system value
            if bar === brightnessHoverBar {
                if let b = getDisplayBrightness() {
                    brightnessSliderV?.doubleValue = Double(b) * 100
                }
            } else if bar === volumeHoverBar {
                volumeSliderV?.doubleValue = Double(getSystemVolume()) * 100
            }
            startSystemSyncIfNeeded()
        } else {
            // Quick fade out
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                bar.animator().alphaValue = 0.0
            }
            if !brightnessHoverVisible && !volumeHoverVisible {
                stopSystemSync()
            }
        }
    }

    // Detect edge hover for brightness/volume bars (supplements dedicated
    // tracking areas for cases where the mouse is already moving inside the edge).
    private func checkEdgeHover(at location: NSPoint) {
        guard let contentView = window?.contentView else { return }
        let bounds = contentView.bounds
        let edgeWidth: CGFloat = 80

        // Left edge → brightness
        let inLeftEdge = location.x < edgeWidth && location.y > 60 && location.y < bounds.height - 50
        if inLeftEdge != brightnessHoverVisible {
            brightnessHoverVisible = inLeftEdge
            showHoverBar(brightnessHoverBar, show: inLeftEdge)
        }

        // Right edge → volume (system volume)
        let inRightEdge = location.x > bounds.width - edgeWidth && location.y > 60 && location.y < bounds.height - 50
        if inRightEdge != volumeHoverVisible {
            volumeHoverVisible = inRightEdge
            showHoverBar(volumeHoverBar, show: inRightEdge)
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Timeline Preview Thumbnail
    // ═══════════════════════════════════════════════════════════════════

    /// Initialize thumbnail state for a new file
    private func setupThumbnailGenerator() {
        thumbnailCache.removeAll()
        lastThumbnailTime = -1
        isGeneratingThumbnail = false
        pendingThumbnailTime = -1

        // Create or reconfigure the dedicated thumbnail mpv instance
        if let path = filePath {
            if thumbnailMPV == nil {
                thumbnailMPV = ThumbnailMPV()
            }
            thumbnailMPV?.loadFile(path)
        }
    }

    /// Initialize thumbnail state for a streaming URL (Bug 4)
    private func setupThumbnailGeneratorForUrl(_ url: String) {
        thumbnailCache.removeAll()
        lastThumbnailTime = -1
        isGeneratingThumbnail = false
        pendingThumbnailTime = -1

        if thumbnailMPV == nil {
            thumbnailMPV = ThumbnailMPV()
        }
        thumbnailMPV?.loadUrl(url)
    }

    /// Lazily create the preview popup view
    private func ensurePreviewView() {
        guard previewContainer == nil else { return }

        let container = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 180, height: 120))
        container.material = .hudWindow
        container.blendingMode = .withinWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.masksToBounds = true
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
        container.layer?.borderWidth = 1
        container.alphaValue = 0
        container.translatesAutoresizingMaskIntoConstraints = true

        // Thumbnail image
        let imgView = NSImageView(frame: NSRect(x: 4, y: 22, width: 172, height: 94))
        imgView.imageScaling = .scaleProportionallyUpOrDown
        imgView.wantsLayer = true
        imgView.layer?.cornerRadius = 4
        imgView.layer?.masksToBounds = true
        imgView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.3).cgColor
        container.addSubview(imgView)
        previewImageView = imgView

        // Time label
        let tLabel = NSTextField(labelWithString: "0:00.000")
        tLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        tLabel.textColor = .white
        tLabel.backgroundColor = .clear
        tLabel.isBezeled = false
        tLabel.isEditable = false
        tLabel.alignment = .center
        tLabel.frame = NSRect(x: 0, y: 2, width: 180, height: 18)
        container.addSubview(tLabel)
        previewTimeLabel = tLabel

        previewContainer = container
    }

    // ── Timeline hover detection for preview ──

    private func checkTimelineHover(at location: NSPoint) {
        guard duration > 0, controlsVisible,
              let contentView = window?.contentView else {
            if isHoveringTimeline { isHoveringTimeline = false; hideTimelinePreview() }
            return
        }

        // Convert slider bounds to contentView coordinates
        let sliderFrame = timelineSlider.convert(timelineSlider.bounds, to: contentView)
        // Expand hit area vertically for easier hover (±12pt above/below slider)
        let hoverRect = sliderFrame.insetBy(dx: 0, dy: -12)

        if hoverRect.contains(location) {
            isHoveringTimeline = true
            // Compute position (0-1) from cursor X within slider
            let position = clampUnitIntervalSIMD(Double((location.x - sliderFrame.origin.x) / sliderFrame.width))
            let time = position * duration
            showTimelinePreview(atPosition: position, time: time)
        } else if isHoveringTimeline {
            isHoveringTimeline = false
            hideTimelinePreview()
        }
    }

    /// Clamp to [0,1] via Accelerate vDSP (Phase 1C: SIMD/Accelerate Abstraction)
    private func clampUnitIntervalSIMD(_ value: Double) -> Double {
        clampUnitIntervalAccelerate(value)
    }

    /// Show preview thumbnail at a timeline position
    private func showTimelinePreview(atPosition position: Double, time: Double) {
        guard duration > 0 else { return }
        ensurePreviewView()
        guard let container = previewContainer, let contentView = window?.contentView else { return }

        // Add to content view if not already
        if container.superview == nil {
            contentView.addSubview(container, positioned: .above, relativeTo: controlsContainer)
        }

        // Position the preview centered on the cursor X
        let sliderFrame = timelineSlider.convert(timelineSlider.bounds, to: contentView)
        let knobX = sliderFrame.origin.x + CGFloat(position) * sliderFrame.width
        let previewW: CGFloat = 180
        let previewH: CGFloat = 120
        let padding: CGFloat = 8

        // Clamp X so it doesn't go off-screen
        var x = knobX - previewW / 2
        x = max(16, min(x, contentView.bounds.width - previewW - 16))

        let y = controlsContainer.frame.maxY + padding

        container.frame = NSRect(x: x, y: y, width: previewW, height: previewH)

        // Update time label (always ms-accurate)
        previewTimeLabel?.stringValue = formatTimePrecise(time)

        // Fade in
        if container.alphaValue < 0.5 {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                container.animator().alphaValue = 1.0
            }
        }

        // Generate thumbnail every 0.5s (throttled, cached)
        let halfSec = Int(time * 2)   // cache key per half-second
        if let cached = thumbnailCache[halfSec] {
            previewImageView?.image = cached
        } else if halfSec != Int(lastThumbnailTime * 2) {
            lastThumbnailTime = time
            generateThumbnail(at: time, cacheKey: halfSec)
        }
    }

    /// Generate a thumbnail using a dedicated headless mpv instance
    private func generateThumbnail(at time: Double, cacheKey: Int) {
        guard !isGeneratingThumbnail else {
            pendingThumbnailTime = time
            return
        }
        guard let thumbMPV = thumbnailMPV else { return }
        isGeneratingThumbnail = true

        // Dispatch to background: seek the thumbnail mpv + screenshot (no main player disruption)
        UniversalSiliconQoS.heavy.async { [weak self] in
            guard let self = self else { return }

            let image = thumbMPV.generateThumbnail(at: time)

            DispatchQueue.main.async {
                if let image = image {
                    // Cap cache size — simple eviction: clear when over limit
                    // avoids O(n log n) sort on every eviction
                    if self.thumbnailCache.count > self.thumbnailCacheLimit {
                        self.thumbnailCache.removeAll(keepingCapacity: true)
                    }
                    self.thumbnailCache[cacheKey] = image
                    self.previewImageView?.image = image
                }
                self.isGeneratingThumbnail = false

                if self.pendingThumbnailTime >= 0 {
                    let pending = self.pendingThumbnailTime
                    self.pendingThumbnailTime = -1
                    self.generateThumbnail(at: pending, cacheKey: Int(pending))
                }
            }
        }
    }

    /// Hide the preview popup
    private func hideTimelinePreview() {
        guard let container = previewContainer else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            container.animator().alphaValue = 0.0
        }) {
            container.removeFromSuperview()
        }
        lastThumbnailTime = -1
    }

    /// Format time with milliseconds: "H:MM:SS.mmm" or "M:SS.mmm"
    /// Always shows hours for videos ≥ 1h to avoid ambiguity
    /// Uses manual zero-padding to avoid String(format:) NSString bridging overhead
    private func formatTimePrecise(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 && seconds < 360000 else { return "0:00.000" }
        let total = Int(seconds)
        let ms = Int((seconds - Double(total)) * 1000)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        // Manual ms padding: avoid String(format:"%03d") which bridges to NSString
        let msStr: String
        if ms < 10 { msStr = "00\(ms)" }
        else if ms < 100 { msStr = "0\(ms)" }
        else { msStr = "\(ms)" }
        // Always show hours format for videos >= 1 hour, to avoid confusion
        if h > 0 || duration >= 3600 {
            return "\(h):\(m < 10 ? "0" : "")\(m):\(s < 10 ? "0" : "")\(s).\(msStr)"
        }
        return "\(m):\(s < 10 ? "0" : "")\(s).\(msStr)"
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Display Sleep Prevention
    // ═══════════════════════════════════════════════════════════════════

    private func preventSleep() {
        guard !isSleepPrevented else { return }
        let reason = "Glass Player video playback" as CFString
        let success = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &sleepAssertionID
        )
        if success == kIOReturnSuccess {
            isSleepPrevented = true
        }
    }

    private func allowSleep() {
        guard isSleepPrevented else { return }
        IOPMAssertionRelease(sleepAssertionID)
        isSleepPrevented = false
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Helpers
    // ═══════════════════════════════════════════════════════════════════

    private func configureIconButton(_ button: NSButton, symbolName: String, size: CGFloat) {
        button.bezelStyle = .inline
        button.isBordered = false
        button.imagePosition = .imageOnly
        if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
            button.image = img.withSymbolConfiguration(config)
        }
        button.contentTintColor = .white
    }

    private func configureTimeLabel(_ label: NSTextField) {
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        label.textColor = NSColor.white.withAlphaComponent(0.5)
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            // Manual formatting avoids String(format:) NSString bridging overhead
            return "\(h):\(m < 10 ? "0" : "")\(m):\(s < 10 ? "0" : "")\(s)"
        }
        return "\(m):\(s < 10 ? "0" : "")\(s)"
    }

    private func formatBytes(_ bytes: Int64) -> String {
        if bytes <= 0 { return "N/A" }
        let units = ["B", "KB", "MB", "GB", "TB"]
        let d = Double(bytes)
        let i = Int(log(d) / log(1024))
        let clamped = min(i, units.count - 1)
        return String(format: "%.1f %@", d / pow(1024, Double(clamped)), units[clamped])
    }

    private func formatBitrate(_ bps: Double) -> String {
        if bps <= 0 { return "N/A" }
        if bps >= 1_000_000 { return String(format: "%.1f Mbps", bps / 1_000_000) }
        if bps >= 1_000 { return String(format: "%.0f Kbps", bps / 1_000) }
        return String(format: "%.0f bps", bps)
    }

    /// Check if the mouse cursor is currently inside this window's frame
    private func mouseIsInsideWindow() -> Bool {
        guard let win = window else { return false }
        let mouseLocation = NSEvent.mouseLocation
        return win.frame.contains(mouseLocation)
    }

    override func mouseExited(with event: NSEvent) {
        // Check if this exit is from an edge tracking area
        if let info = event.trackingArea?.userInfo as? [String: String],
           let edge = info["edge"] {
            if edge == "left" && brightnessHoverVisible {
                brightnessHoverVisible = false
                showHoverBar(brightnessHoverBar, show: false)
            } else if edge == "right" && volumeHoverVisible {
                volumeHoverVisible = false
                showHoverBar(volumeHoverBar, show: false)
            }
            return
        }

        // Window-wide exit: restore cursor and hide hover bars
        if cursorHidden {
            NSCursor.unhide()
            cursorHidden = false
        }
        if brightnessHoverVisible {
            brightnessHoverVisible = false
            showHoverBar(brightnessHoverBar, show: false)
        }
        if volumeHoverVisible {
            volumeHoverVisible = false
            showHoverBar(volumeHoverBar, show: false)
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - System Display Brightness (IOKit)
    // ═══════════════════════════════════════════════════════════════════

    /// Cached DisplayServices framework handle (loaded once, kept for app lifetime)
    private static var displayServicesHandle: UnsafeMutableRawPointer? = {
        dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    }()

    /// Read the built-in display's backlight brightness (0.0 – 1.0)
    private func getDisplayBrightness() -> Float? {
        // Try IOKit first (Intel Macs, older macOS)
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("AppleBacklightDisplay"))
        if service != 0 {
            var brightness: Float = 0
            let result = IODisplayGetFloatParameter(
                service, 0, kIODisplayBrightnessKey as CFString, &brightness)
            IOObjectRelease(service)
            if result == kIOReturnSuccess { return brightness }
        }
        // Fallback: DisplayServices private framework (Apple Silicon / newer macOS)
        if let handle = PlayerWindow.displayServicesHandle,
           let sym = dlsym(handle, "DisplayServicesGetBrightness") {
            typealias Fn = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
            let getBrightness = unsafeBitCast(sym, to: Fn.self)
            var brightness: Float = 0
            if getBrightness(CGMainDisplayID(), &brightness) == 0 {
                return brightness
            }
        }
        return nil
    }

    /// Set the built-in display's backlight brightness (0.0 – 1.0)
    /// Uses Accelerate vDSP clamp (Phase 1C: SIMD/Accelerate Abstraction)
    private func setDisplayBrightness(_ value: Float) {
        let clamped = max(clampVolumeAccelerate(value), Float(0.01))  // Never go to absolute 0
        // Try IOKit first
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("AppleBacklightDisplay"))
        if service != 0 {
            let result = IODisplaySetFloatParameter(
                service, 0, kIODisplayBrightnessKey as CFString, clamped)
            IOObjectRelease(service)
            if result == kIOReturnSuccess { return }
        }
        // Fallback: DisplayServices private framework (Apple Silicon / newer macOS)
        if let handle = PlayerWindow.displayServicesHandle,
           let sym = dlsym(handle, "DisplayServicesSetBrightness") {
            typealias Fn = @convention(c) (UInt32, Float) -> Int32
            let setBrightness = unsafeBitCast(sym, to: Fn.self)
            _ = setBrightness(CGMainDisplayID(), clamped)
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - System Volume (CoreAudio)
    // ═══════════════════════════════════════════════════════════════════

    private func getDefaultOutputDeviceID() -> AudioDeviceID {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID)
        return deviceID
    }

    /// Read macOS system output volume (0.0 – 1.0)
    private func getSystemVolume() -> Float {
        let deviceID = getDefaultOutputDeviceID()
        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        if AudioObjectHasProperty(deviceID, &address) {
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
            return volume
        }
        // Fallback: try channel 1 (left)
        address.mElement = 1
        if AudioObjectHasProperty(deviceID, &address) {
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
        }
        return volume
    }

    /// Set macOS system output volume (0.0 – 1.0)
    /// Uses Accelerate vDSP clamp (Phase 1C: SIMD/Accelerate Abstraction)
    private func setSystemVolume(_ value: Float) {
        let deviceID = getDefaultOutputDeviceID()
        var vol = clampVolumeAccelerate(value)
        let size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        if AudioObjectHasProperty(deviceID, &address) {
            AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &vol)
            return
        }
        // Per-channel fallback
        for ch: UInt32 in [1, 2] {
            address.mElement = ch
            if AudioObjectHasProperty(deviceID, &address) {
                AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &vol)
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - System Sync Timer
    // ═══════════════════════════════════════════════════════════════════

    /// Polls system brightness / volume while hover bars are visible
    private func startSystemSyncIfNeeded() {
        guard systemSyncTimer == nil else { return }
        systemSyncTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) {
            [weak self] _ in
            guard let self = self else { return }
            if self.brightnessHoverVisible {
                if let b = self.getDisplayBrightness() {
                    self.brightnessSliderV?.doubleValue = Double(b) * 100
                }
            }
            if self.volumeHoverVisible {
                self.volumeSliderV?.doubleValue = Double(self.getSystemVolume()) * 100
            }
        }
    }

    private func stopSystemSync() {
        systemSyncTimer?.invalidate()
        systemSyncTimer = nil
    }
}

// ---------------------------------------------------------------------------
// ThumbnailMPV – lightweight headless mpv instance for thumbnail generation
// Seeks independently without disrupting the main player's playback.
// ---------------------------------------------------------------------------

private class ThumbnailMPV {
    private var handle: OpaquePointer?
    private let queue = DispatchQueue(label: "com.glassplayer.thumbnail-mpv", qos: .utility)
    private let tmpPath: String
    private var currentFile: String?

    init() {
        tmpPath = NSTemporaryDirectory() + "glassplayer_thumb_\(ProcessInfo.processInfo.processIdentifier).jpg"
        setupMPV()
    }

    private func setupMPV() {
        handle = mpv_create()
        guard handle != nil else {
            print("[ThumbnailMPV] Failed to create mpv instance")
            return
        }

        // Headless: no video/audio output
        setOpt("vo", "null")
        setOpt("ao", "null")
        setOpt("aid", "no")          // disable audio decoding
        setOpt("sid", "no")          // disable subtitle decoding
        setOpt("hwdec", "auto-safe")
        setOpt("keep-open", "yes")
        setOpt("idle", "yes")
        setOpt("osc", "no")
        setOpt("osd-level", "0")
        setOpt("terminal", "no")
        setOpt("msg-level", "all=no")
        // Fast decode for thumbnails
        setOpt("vd-lavc-threads", "4")
        setOpt("hr-seek-framedrop", "yes")
        setOpt("demuxer-max-bytes", "5MiB")
        setOpt("demuxer-max-back-bytes", "1MiB")
        // JPEG output for speed
        setOpt("screenshot-format", "jpg")
        setOpt("screenshot-jpeg-quality", "50")

        let err = mpv_initialize(handle!)
        if err < 0 {
            print("[ThumbnailMPV] Failed to initialize: \(String(cString: mpv_error_string(err)))")
            mpv_destroy(handle)
            handle = nil
        }
    }

    func loadFile(_ path: String) {
        guard let handle = handle else { return }
        guard path != currentFile else { return }
        currentFile = path

        // Load file paused so it doesn't play
        mpv_command_string(handle, "set pause yes")
        let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
        mpv_command_string(handle, "loadfile '\(escaped)' replace")

        // Wait for file load
        for _ in 0..<40 {
            guard let event = mpv_wait_event(handle, 0.05) else { continue }
            if event.pointee.event_id == MPV_EVENT_FILE_LOADED { break }
        }
    }

    /// Load a streaming URL for thumbnail generation (Bug 4)
    func loadUrl(_ url: String) {
        guard let handle = handle else { return }
        guard url != currentFile else { return }
        currentFile = url

        mpv_command_string(handle, "set pause yes")
        let escaped = url.replacingOccurrences(of: "'", with: "'\\''")
        mpv_command_string(handle, "loadfile '\(escaped)' replace")

        // Wait for file load (longer timeout for network streams)
        for _ in 0..<60 {
            guard let event = mpv_wait_event(handle, 0.05) else { continue }
            if event.pointee.event_id == MPV_EVENT_FILE_LOADED { break }
        }
    }

    /// Seek to time and take screenshot. Thread-safe. Returns resized NSImage or nil.
    func generateThumbnail(at time: Double) -> NSImage? {
        guard let handle = handle else { return nil }

        return queue.sync {
            // Bug 11: use absolute+exact so preview matches the clicked seek position
            mpv_command_string(handle, "seek \(time) absolute+exact")

            // Wait for seek to complete (more iterations for exact seek)
            for _ in 0..<20 {
                guard let event = mpv_wait_event(handle, 0.03) else { continue }
                let eid = event.pointee.event_id
                if eid == MPV_EVENT_PLAYBACK_RESTART { break }
                if eid == MPV_EVENT_NONE { break }
            }

            // Take screenshot — stack-based withCString to avoid heap alloc
            "screenshot-to-file".withCString { a0 in
                self.tmpPath.withCString { a1 in
                    "video".withCString { a2 in
                        var cPtrs: [UnsafePointer<CChar>?] = [a0, a1, a2, nil]
                        mpv_command(handle, &cPtrs)
                    }
                }
            }

            // Load the image
            var result: NSImage? = nil
            for attempt in 0..<4 {
                if let img = NSImage(contentsOfFile: tmpPath) {
                    let thumbSize = NSSize(width: 240, height: 135)
                    result = NSImage(size: thumbSize, flipped: false) { rect in
                        img.draw(in: rect,
                                 from: NSRect(origin: .zero, size: img.size),
                                 operation: .copy, fraction: 1.0)
                        return true
                    }
                    break
                }
                if attempt < 3 { Thread.sleep(forTimeInterval: 0.01) }
            }
            try? FileManager.default.removeItem(atPath: tmpPath)
            return result
        }
    }

    func shutdown() {
        queue.sync {
            if let handle = handle {
                mpv_terminate_destroy(handle)
                self.handle = nil
            }
        }
        try? FileManager.default.removeItem(atPath: tmpPath)
        currentFile = nil
    }

    private func setOpt(_ name: String, _ value: String) {
        mpv_set_option_string(handle, name, value)
    }

    deinit {
        if let handle = handle {
            mpv_terminate_destroy(handle)
        }
        try? FileManager.default.removeItem(atPath: tmpPath)
    }
}
