import Cocoa
import UniformTypeIdentifiers

// ---------------------------------------------------------------------------
// AppDelegate – application lifecycle, menu bar, file opening
// ---------------------------------------------------------------------------

class AppDelegate: NSObject, NSApplicationDelegate {

    var playerWindow: PlayerWindow?           // most-recently active player
    var playerWindows: [PlayerWindow] = []    // all open player windows
    var rcloneBrowser: RcloneBrowser?
    var welcomeWindow: WelcomeWindow?
    var settingsWindow: SettingsWindow?
    private var fileOpenedExternally = false
    var pendingAnime4KPreset: String? = nil   // Anime4K preset to apply after file loads
    /// Flag: when true, the next openFile call came from Launch Services
    /// (re-invoked via `open -b`) so we skip the fullscreen redirect.
    private var reopenedFromFullscreen = false

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize Anime4K preset registry at app startup
        initializeAnime4KPresets()

        // Disable automatic window state restoration – eliminates
        // "Unable to find className=(null)" errors in system log
        NSApplication.shared.disableRelaunchOnLogin()
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")

        // Log hardware profile for diagnostics (Phase 1: Universal Silicon)
        UniversalMetalRuntime.logHardwareProfile()

        setupMenu()
        generateAppIcon()

        // If launched with a file argument, open it
        let args = CommandLine.arguments
        var anime4kPreset: String? = nil

        if args.count > 1 {
            var i = 1
            while i < args.count {
                switch args[i] {
                case "--anime4k":
                    if i + 1 < args.count {
                        anime4kPreset = args[i + 1]
                        i += 2
                    }
                default:
                    let path = args[i]
                    if FileManager.default.fileExists(atPath: path) {
                        openFile(path)
                        // Store preset to apply after file loads
                        pendingAnime4KPreset = anime4kPreset
                        return
                    }
                    i += 1
                }
            }
        }

        // Defer showing welcome to allow application(_:open:) to fire first
        // when launched via file association from Finder
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self = self else { return }
            if !self.fileOpenedExternally && self.playerWindow == nil {
                self.showWelcome()
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        fileOpenedExternally = true
        if let url = urls.first {
            openFile(url.path)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showWelcome()
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSCursor.unhide()
    }

    // MARK: - File Opening

    func openFile(_ path: String) {
        welcomeWindow?.close()
        // If the current player already has a video loaded, open a new window
        if let existing = playerWindow, existing.filePath != nil {
            // When the existing window is fullscreen, creating a new window
            // here would place it on the fullscreen space (wrong).
            // Instead, re-invoke via Launch Services (`open -b`), which makes
            // macOS switch to a regular desktop space before delivering the
            // file back to us through application(_:open:).
            // The old window stays fullscreen; the new one appears on Desktop 1.
            if let existingWin = existing.window,
               existingWin.styleMask.contains(.fullScreen),
               !reopenedFromFullscreen {
                reopenedFromFullscreen = true
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                task.arguments = ["-b", "com.glassplayer.app", path]
                try? task.run()
                return
            }
            reopenedFromFullscreen = false
            let newPlayer = PlayerWindow()
            newPlayer.loadFile(path)
            playerWindows.append(newPlayer)
            playerWindow = newPlayer
            // Apply pending Anime4K preset if specified
            if let preset = pendingAnime4KPreset {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    newPlayer.mpv.applyShaderPreset(preset)
                }
            }
        } else {
            if playerWindow == nil {
                let newPlayer = PlayerWindow()
                playerWindows.append(newPlayer)
                playerWindow = newPlayer
            }
            playerWindow?.loadFile(path)
            // Apply pending Anime4K preset if specified
            if let preset = pendingAnime4KPreset {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.playerWindow?.mpv.applyShaderPreset(preset)
                }
            }
        }
    }

    /// Remove a closed player window from tracking
    func removePlayerWindow(_ pw: PlayerWindow) {
        playerWindows.removeAll { $0 === pw }
        if playerWindow === pw {
            playerWindow = playerWindows.last
        }
    }

    func showWelcome() {
        if welcomeWindow == nil {
            welcomeWindow = WelcomeWindow(
                onOpenFile: { [weak self] in
                    self?.showOpenPanel()
                },
                onRclone: { [weak self] in
                    self?.openRcloneBrowser()
                },
                onDrop: { [weak self] path in
                    self?.openFile(path)
                }
            )
        }
        welcomeWindow?.showWelcome()
    }

    func showOpenPanel() {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "Open Video"
        panel.message = "Choose a video file to play"

        if #available(macOS 12.0, *) {
            var types: [UTType] = [.movie, .video, .audio, .mpeg4Movie, .quickTimeMovie, .avi]
            if let mkv = UTType(filenameExtension: "mkv") { types.append(mkv) }
            if let wmv = UTType(filenameExtension: "wmv") { types.append(wmv) }
            if let webm = UTType(filenameExtension: "webm") { types.append(webm) }
            if let flv = UTType(filenameExtension: "flv") { types.append(flv) }
            if let ts = UTType(filenameExtension: "ts") { types.append(ts) }
            panel.allowedContentTypes = types
        }

        let response = panel.runModal()
        if response == .OK, let url = panel.url {
            openFile(url.path)
        } else if playerWindow == nil {
            showWelcome()
        }
    }

    // MARK: - App Icon (runtime)

    private func generateAppIcon() {
        let s: CGFloat = 512
        let icon = NSImage(size: NSSize(width: s, height: s), flipped: false) { r in
            let inset = s * 0.02
            let rr = r.insetBy(dx: inset, dy: inset)
            let cr = s * 0.22
            let path = NSBezierPath(roundedRect: rr, xRadius: cr, yRadius: cr)
            NSGradient(colors: [
                NSColor(red: 0.06, green: 0.06, blue: 0.12, alpha: 1),
                NSColor(red: 0.12, green: 0.10, blue: 0.22, alpha: 1),
            ])!.draw(in: path, angle: -45)
            NSColor.white.withAlphaComponent(0.12).setStroke()
            path.lineWidth = 2
            path.stroke()
            let cy = s / 2, th = s * 0.34
            let tw = th * 0.866
            let leftX = s / 2 - tw / 3
            let rightX = s / 2 + 2 * tw / 3
            let tri = NSBezierPath()
            tri.move(to: NSPoint(x: leftX, y: cy + th / 2))
            tri.line(to: NSPoint(x: leftX, y: cy - th / 2))
            tri.line(to: NSPoint(x: rightX, y: cy))
            tri.close()
            NSColor.white.withAlphaComponent(0.9).setFill()
            tri.fill()
            return true
        }
        NSApp.applicationIconImage = icon
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Menu Bar (IINA-style)
    // ═══════════════════════════════════════════════════════════════════

    func setupMenu() {
        let mainMenu = NSMenu()

        // ── App menu ──
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Glass Player",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings...",
                        action: #selector(showSettings),
                        keyEquivalent: ",")
        appMenu.addItem(.separator())
        let hideItem = appMenu.addItem(withTitle: "Hide Glass Player",
                        action: #selector(NSApplication.hide(_:)),
                        keyEquivalent: "h")
        hideItem.target = NSApp
        let hideOthersItem = appMenu.addItem(withTitle: "Hide Others",
                        action: #selector(NSApplication.hideOtherApplications(_:)),
                        keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        hideOthersItem.target = NSApp
        appMenu.addItem(withTitle: "Show All",
                        action: #selector(NSApplication.unhideAllApplications(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Glass Player",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        // ── File menu ──
        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Open File...",
                         action: #selector(openFileAction),
                         keyEquivalent: "o")
        fileMenu.addItem(withTitle: "Open URL...",
                         action: #selector(openURLAction),
                         keyEquivalent: "u")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Add External Subtitle...",
                         action: #selector(addExternalSubtitleAction),
                         keyEquivalent: "")
        fileMenu.addItem(withTitle: "Add External Audio...",
                         action: #selector(addExternalAudioAction),
                         keyEquivalent: "")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Remote Browser...",
                         action: #selector(openRcloneBrowser),
                         keyEquivalent: "r")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close Window",
                         action: #selector(closeWindowAction),
                         keyEquivalent: "w")
        fileMenuItem.submenu = fileMenu

        // ── Edit menu ──
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu

        // ── Playback menu ──
        let playbackMenuItem = NSMenuItem()
        mainMenu.addItem(playbackMenuItem)
        let playbackMenu = NSMenu(title: "Playback")
        playbackMenu.addItem(withTitle: "Play / Pause",
                             action: #selector(togglePlayPauseAction),
                             keyEquivalent: " ")
        playbackMenu.addItem(withTitle: "Stop",
                             action: #selector(stopAction),
                             keyEquivalent: ".")
        playbackMenu.addItem(.separator())
        playbackMenu.addItem(withTitle: "Step Forward (1 frame)",
                             action: #selector(frameStepAction),
                             keyEquivalent: "")
        playbackMenu.addItem(withTitle: "Step Backward (1 frame)",
                             action: #selector(frameBackStepAction),
                             keyEquivalent: "")
        playbackMenu.addItem(.separator())
        let seekFwd5 = playbackMenu.addItem(withTitle: "Seek Forward 5s",
                             action: #selector(seekForwardAction),
                             keyEquivalent: String(UnicodeScalar(NSRightArrowFunctionKey)!))
        seekFwd5.keyEquivalentModifierMask = []
        let seekBwd5 = playbackMenu.addItem(withTitle: "Seek Backward 5s",
                             action: #selector(seekBackwardAction),
                             keyEquivalent: String(UnicodeScalar(NSLeftArrowFunctionKey)!))
        seekBwd5.keyEquivalentModifierMask = []
        playbackMenu.addItem(withTitle: "Seek Forward 30s",
                             action: #selector(seekForward30Action),
                             keyEquivalent: "")
        playbackMenu.addItem(withTitle: "Seek Backward 30s",
                             action: #selector(seekBackward30Action),
                             keyEquivalent: "")
        playbackMenu.addItem(.separator())

        // Speed submenu
        let speedSubMenuItem = NSMenuItem(title: "Speed", action: nil, keyEquivalent: "")
        let speedSubMenu = NSMenu(title: "Speed")
        speedSubMenu.addItem(withTitle: "Speed Up",
                             action: #selector(speedUpAction),
                             keyEquivalent: "]")
        speedSubMenu.addItem(withTitle: "Speed Down",
                             action: #selector(speedDownAction),
                             keyEquivalent: "[")
        speedSubMenu.addItem(withTitle: "Reset Speed",
                             action: #selector(resetSpeedAction),
                             keyEquivalent: "")
        speedSubMenu.addItem(.separator())
        for s in ["0.5x", "0.75x", "1x", "1.25x", "1.5x", "2x"] {
            let item = speedSubMenu.addItem(withTitle: s,
                                            action: #selector(setSpeedFromMenu(_:)),
                                            keyEquivalent: "")
            item.representedObject = s
        }
        speedSubMenuItem.submenu = speedSubMenu
        playbackMenu.addItem(speedSubMenuItem)

        // A-B loop
        playbackMenu.addItem(withTitle: "Set / Clear A-B Loop",
                             action: #selector(setABLoopAction),
                             keyEquivalent: "l")
        playbackMenu.addItem(.separator())
        playbackMenu.addItem(withTitle: "Previous",
                             action: #selector(prevFileAction),
                             keyEquivalent: "")
        playbackMenu.addItem(withTitle: "Next",
                             action: #selector(nextFileAction),
                             keyEquivalent: "")
        playbackMenuItem.submenu = playbackMenu

        // ── Video menu ──
        let videoMenuItem = NSMenuItem()
        mainMenu.addItem(videoMenuItem)
        let videoMenu = NSMenu(title: "Video")
        videoMenu.addItem(withTitle: "Toggle Full Screen",
                         action: #selector(toggleFullScreenAction),
                         keyEquivalent: "f")
        let halfSizeItem = videoMenu.addItem(withTitle: "Half Size",
                         action: #selector(halfSizeAction),
                         keyEquivalent: "0")
        halfSizeItem.keyEquivalentModifierMask = [.command]
        let normalSizeItem = videoMenu.addItem(withTitle: "Normal Size",
                         action: #selector(normalSizeAction),
                         keyEquivalent: "1")
        normalSizeItem.keyEquivalentModifierMask = [.command]
        let doubleSizeItem = videoMenu.addItem(withTitle: "Double Size",
                         action: #selector(doubleSizeAction),
                         keyEquivalent: "2")
        doubleSizeItem.keyEquivalentModifierMask = [.command]
        videoMenu.addItem(.separator())
        videoMenu.addItem(withTitle: "Video Information",
                         action: #selector(toggleVideoInfoAction),
                         keyEquivalent: "i")
        videoMenu.addItem(.separator())

        // Aspect ratio submenu
        let aspectSubMenuItem = NSMenuItem(title: "Aspect Ratio", action: nil, keyEquivalent: "")
        let aspectSubMenu = NSMenu(title: "Aspect Ratio")
        for (title, _) in [("Auto", "auto"), ("16:9", "16:9"), ("4:3", "4:3"),
                            ("21:9", "21:9"), ("1:1", "1:1"), ("2.35:1", "2.35:1")] {
            let item = aspectSubMenu.addItem(withTitle: title,
                                             action: #selector(setAspectFromMenu(_:)),
                                             keyEquivalent: "")
            item.representedObject = title == "Auto" ? "auto" : title
        }
        aspectSubMenuItem.submenu = aspectSubMenu
        videoMenu.addItem(aspectSubMenuItem)

        // Deinterlace
        videoMenu.addItem(withTitle: "Toggle Deinterlace",
                         action: #selector(toggleDeinterlaceAction),
                         keyEquivalent: "d")
        videoMenu.addItem(.separator())
        videoMenu.addItem(withTitle: "Take Screenshot",
                         action: #selector(screenshotAction),
                         keyEquivalent: "s")
        videoMenu.items.last?.keyEquivalentModifierMask = [.command, .shift]
        videoMenuItem.submenu = videoMenu

        // ── Audio menu ──
        let audioMenuItem = NSMenuItem()
        mainMenu.addItem(audioMenuItem)
        let audioMenu = NSMenu(title: "Audio")
        let volUp = audioMenu.addItem(withTitle: "Volume Up",
                             action: #selector(volumeUpAction),
                             keyEquivalent: String(UnicodeScalar(NSUpArrowFunctionKey)!))
        volUp.keyEquivalentModifierMask = []
        let volDown = audioMenu.addItem(withTitle: "Volume Down",
                             action: #selector(volumeDownAction),
                             keyEquivalent: String(UnicodeScalar(NSDownArrowFunctionKey)!))
        volDown.keyEquivalentModifierMask = []
        audioMenu.addItem(withTitle: "Mute / Unmute",
                             action: #selector(toggleMuteAction),
                             keyEquivalent: "m")
        audioMenu.items.last?.keyEquivalentModifierMask = []
        audioMenu.addItem(.separator())
        audioMenu.addItem(withTitle: "Cycle Audio Track",
                           action: #selector(cycleAudioAction),
                           keyEquivalent: "")
        audioMenu.addItem(.separator())
        audioMenu.addItem(withTitle: "Audio Delay +0.1s",
                           action: #selector(audioDelayUpAction),
                           keyEquivalent: "")
        audioMenu.addItem(withTitle: "Audio Delay -0.1s",
                           action: #selector(audioDelayDownAction),
                           keyEquivalent: "")
        audioMenu.addItem(withTitle: "Reset Audio Delay",
                           action: #selector(resetAudioDelayAction),
                           keyEquivalent: "")
        audioMenuItem.submenu = audioMenu

        // ── Subtitle menu ──
        let subtitleMenuItem = NSMenuItem()
        mainMenu.addItem(subtitleMenuItem)
        let subtitleMenu = NSMenu(title: "Subtitle")
        subtitleMenu.addItem(withTitle: "Cycle Subtitles",
                           action: #selector(cycleSubtitleAction),
                           keyEquivalent: "s")
        subtitleMenu.items.last?.keyEquivalentModifierMask = []
        subtitleMenu.addItem(withTitle: "Toggle Subtitle Visibility",
                           action: #selector(toggleSubVisibilityAction),
                           keyEquivalent: "v")
        subtitleMenu.items.last?.keyEquivalentModifierMask = []
        subtitleMenu.addItem(.separator())
        subtitleMenu.addItem(withTitle: "Subtitle Delay +0.1s",
                           action: #selector(subDelayUpAction),
                           keyEquivalent: "")
        subtitleMenu.addItem(withTitle: "Subtitle Delay -0.1s",
                           action: #selector(subDelayDownAction),
                           keyEquivalent: "")
        subtitleMenu.addItem(withTitle: "Reset Subtitle Delay",
                           action: #selector(resetSubDelayAction),
                           keyEquivalent: "")
        subtitleMenu.addItem(.separator())
        subtitleMenu.addItem(withTitle: "Increase Font Size",
                           action: #selector(subFontSizeUpAction),
                           keyEquivalent: "")
        subtitleMenu.addItem(withTitle: "Decrease Font Size",
                           action: #selector(subFontSizeDownAction),
                           keyEquivalent: "")
        subtitleMenuItem.submenu = subtitleMenu

        // ── Window menu ──
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize",
                           action: #selector(NSWindow.performMiniaturize(_:)),
                           keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom",
                           action: #selector(NSWindow.performZoom(_:)),
                           keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Float on Top",
                           action: #selector(toggleFloatOnTopAction),
                           keyEquivalent: "t")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Welcome Screen",
                           action: #selector(showWelcomeAction),
                           keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Bring All to Front",
                           action: #selector(NSApplication.arrangeInFront(_:)),
                           keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        // ── Help menu ──
        let helpMenuItem = NSMenuItem()
        mainMenu.addItem(helpMenuItem)
        let helpMenu = NSMenu(title: "Help")
        helpMenu.addItem(withTitle: "Glass Player Help",
                         action: nil,
                         keyEquivalent: "")
        helpMenuItem.submenu = helpMenu

        NSApp.mainMenu = mainMenu
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Menu Actions
    // ═══════════════════════════════════════════════════════════════════

    /// Returns the active (key) player window, or the most recent one
    private var activePlayer: PlayerWindow? {
        // Prefer the key window's player
        if let keyWin = NSApp.keyWindow,
           let pw = playerWindows.first(where: { $0.window === keyWin }) {
            return pw
        }
        return playerWindow
    }

    @objc func openFileAction() {
        showOpenPanel()
    }

    @objc func openRcloneBrowser() {
        if rcloneBrowser == nil {
            rcloneBrowser = RcloneBrowser()
        }
        rcloneBrowser?.playerWindow = playerWindow
        rcloneBrowser?.onFileSelected = { [weak self] url in
            guard let self = self else { return }
            // If current player already has a video, open in new window
            if let existing = self.playerWindow, existing.filePath != nil {
                let newPlayer = PlayerWindow()
                self.playerWindows.append(newPlayer)
                self.playerWindow = newPlayer
                self.rcloneBrowser?.playerWindow = newPlayer
                newPlayer.loadUrl(url)
            } else {
                if self.playerWindow == nil {
                    let newPlayer = PlayerWindow()
                    self.playerWindows.append(newPlayer)
                    self.playerWindow = newPlayer
                    self.rcloneBrowser?.playerWindow = newPlayer
                }
                self.playerWindow?.loadUrl(url)
            }
        }
        rcloneBrowser?.showBrowser()
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindow()
        }
        settingsWindow?.showSettings()
    }

    @objc func showWelcomeAction() {
        showWelcome()
    }

    @objc func toggleFullScreenAction() {
        activePlayer?.window?.toggleFullScreen(nil)
    }

    @objc func togglePlayPauseAction() {
        activePlayer?.mpv.togglePause()
    }

    @objc func seekForwardAction() {
        activePlayer?.mpv.seek(by: 5)
    }

    @objc func seekBackwardAction() {
        activePlayer?.mpv.seek(by: -5)
    }

    @objc func volumeUpAction() {
        guard let pw = activePlayer else { return }
        let vol = min(200, pw.mpv.getVolume() + 5)
        pw.mpv.setVolume(vol)
    }

    @objc func volumeDownAction() {
        guard let pw = activePlayer else { return }
        let vol = max(0, pw.mpv.getVolume() - 5)
        pw.mpv.setVolume(vol)
    }

    @objc func toggleMuteAction() {
        activePlayer?.mpv.toggleMute()
    }

    @objc func cycleSubtitleAction() {
        activePlayer?.mpv.cycleSubtitle()
    }

    @objc func cycleAudioAction() {
        activePlayer?.mpv.cycleAudio()
    }

    @objc func addExternalSubtitleAction() {
        activePlayer?.addExternalSubtitle()
    }

    @objc func addExternalAudioAction() {
        activePlayer?.addExternalAudio()
    }

    @objc func toggleVideoInfoAction() {
        if let pw = activePlayer, let win = pw.window, win.isVisible {
            let event = NSEvent.keyEvent(with: .keyDown,
                                         location: .zero,
                                         modifierFlags: [],
                                         timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: win.windowNumber,
                                         context: nil,
                                         characters: "i",
                                         charactersIgnoringModifiers: "i",
                                         isARepeat: false,
                                         keyCode: 34)
            if let event = event {
                win.sendEvent(event)
            }
        }
    }

    // ── New menu actions ──

    @objc func openURLAction() {
        // Bug 12: directly call toggleUrlInput on the active player window
        // (avoids fragile synthetic NSEvent that wasn't reaching the handler)
        if let pw = activePlayer, let win = pw.window, win.isVisible {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            pw.toggleUrlInput()
        } else {
            // No player open — show welcome with URL focus
            showWelcome()
        }
    }

    @objc func closeWindowAction() {
        NSApp.keyWindow?.close()
    }

    @objc func stopAction() {
        activePlayer?.mpv.loadFile("/dev/null")
    }

    @objc func frameStepAction() {
        activePlayer?.mpv.frameStep()
    }

    @objc func frameBackStepAction() {
        activePlayer?.mpv.frameBackStep()
    }

    @objc func seekForward30Action() {
        activePlayer?.mpv.seek(by: 30)
    }

    @objc func seekBackward30Action() {
        activePlayer?.mpv.seek(by: -30)
    }

    @objc func speedUpAction() {
        guard let pw = activePlayer else { return }
        let speed = min(4.0, pw.mpv.getSpeed() + 0.25)
        pw.mpv.setSpeed(speed)
    }

    @objc func speedDownAction() {
        guard let pw = activePlayer else { return }
        let speed = max(0.25, pw.mpv.getSpeed() - 0.25)
        pw.mpv.setSpeed(speed)
    }

    @objc func resetSpeedAction() {
        activePlayer?.mpv.setSpeed(1.0)
    }

    @objc func setSpeedFromMenu(_ sender: NSMenuItem) {
        guard let label = sender.representedObject as? String,
              let pw = activePlayer else { return }
        let s = Double(label.replacingOccurrences(of: "x", with: "")) ?? 1.0
        pw.mpv.setSpeed(s)
    }

    @objc func setABLoopAction() {
        guard let pw = activePlayer, let handle = pw.mpv.mpvHandle else { return }
        mpv_command_string(handle, "ab-loop")
    }

    @objc func prevFileAction() {
        activePlayer?.mpv.prevFile()
    }

    @objc func nextFileAction() {
        activePlayer?.mpv.nextFile()
    }

    @objc func halfSizeAction() {
        resizeActivePlayer(scale: 0.5)
    }

    @objc func normalSizeAction() {
        resizeActivePlayer(scale: 1.0)
    }

    @objc func doubleSizeAction() {
        resizeActivePlayer(scale: 2.0)
    }

    private func resizeActivePlayer(scale: Double) {
        guard let pw = activePlayer, let win = pw.window,
              !win.styleMask.contains(.fullScreen) else { return }
        let info = pw.mpv.getVideoInfo()
        guard info.width > 0, info.height > 0 else { return }
        let newW = Double(info.width) * scale
        let newH = Double(info.height) * scale
        var frame = win.frame
        let center = NSPoint(x: frame.midX, y: frame.midY)
        frame.size = NSSize(width: newW, height: newH)
        frame.origin = NSPoint(x: center.x - newW / 2, y: center.y - newH / 2)
        win.setFrame(frame, display: true, animate: true)
    }

    @objc func setAspectFromMenu(_ sender: NSMenuItem) {
        guard let aspect = sender.representedObject as? String,
              let pw = activePlayer else { return }
        pw.mpv.setAspectOverride(aspect)
    }

    @objc func toggleDeinterlaceAction() {
        guard let handle = activePlayer?.mpv.mpvHandle else { return }
        mpv_command_string(handle, "cycle deinterlace")
    }

    @objc func screenshotAction() {
        guard let pw = activePlayer else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "screenshot.png"
        if panel.runModal() == .OK, let url = panel.url {
            _ = pw.mpv.screenshotToFile(url.path)
        }
    }

    @objc func audioDelayUpAction() {
        guard let handle = activePlayer?.mpv.mpvHandle else { return }
        mpv_command_string(handle, "add audio-delay 0.1")
    }

    @objc func audioDelayDownAction() {
        guard let handle = activePlayer?.mpv.mpvHandle else { return }
        mpv_command_string(handle, "add audio-delay -0.1")
    }

    @objc func resetAudioDelayAction() {
        guard let handle = activePlayer?.mpv.mpvHandle else { return }
        mpv_command_string(handle, "set audio-delay 0")
    }

    @objc func toggleSubVisibilityAction() {
        activePlayer?.mpv.toggleSubVisibility()
    }

    @objc func subDelayUpAction() {
        guard let handle = activePlayer?.mpv.mpvHandle else { return }
        mpv_command_string(handle, "add sub-delay 0.1")
    }

    @objc func subDelayDownAction() {
        guard let handle = activePlayer?.mpv.mpvHandle else { return }
        mpv_command_string(handle, "add sub-delay -0.1")
    }

    @objc func resetSubDelayAction() {
        guard let handle = activePlayer?.mpv.mpvHandle else { return }
        mpv_command_string(handle, "set sub-delay 0")
    }

    @objc func subFontSizeUpAction() {
        guard let handle = activePlayer?.mpv.mpvHandle else { return }
        mpv_command_string(handle, "add sub-font-size 2")
    }

    @objc func subFontSizeDownAction() {
        guard let handle = activePlayer?.mpv.mpvHandle else { return }
        mpv_command_string(handle, "add sub-font-size -2")
    }

    @objc func toggleFloatOnTopAction() {
        guard let win = activePlayer?.window else { return }
        if win.level == .floating {
            win.level = .normal
        } else {
            win.level = .floating
        }
    }
}
