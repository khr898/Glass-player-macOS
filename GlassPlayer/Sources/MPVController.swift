import Cocoa
import IOKit.ps

// ---------------------------------------------------------------------------
// Track information parsed from mpv's track-list
// ---------------------------------------------------------------------------
struct TrackInfo {
    let id: Int
    let type: String          // "video", "audio", "sub"
    let title: String?
    let lang: String?
    let codec: String?
    var selected: Bool
    let label: String         // pre-computed at init

    init(id: Int, type: String, title: String?, lang: String?,
         codec: String?, selected: Bool) {
        self.id = id
        self.type = type
        self.title = title
        self.lang = lang
        self.codec = codec
        self.selected = selected
        // Pre-compute label once to avoid repeated string joins
        var parts: [String] = []
        if let t = title, !t.isEmpty { parts.append(t) }
        if let l = lang, !l.isEmpty  { parts.append(l.uppercased()) }
        if let c = codec, !c.isEmpty { parts.append(c) }
        if parts.isEmpty { parts.append("Track \(id)") }
        self.label = parts.joined(separator: " · ")
    }
}

// ---------------------------------------------------------------------------
// Video information snapshot
// ---------------------------------------------------------------------------
struct VideoInfo {
    var filename: String = ""
    var fileFormat: String = ""
    var fileSize: Int64 = 0
    var duration: Double = 0
    var videoCodec: String = ""
    var width: Int64 = 0
    var height: Int64 = 0
    var fps: Double = 0
    var videoBitrate: Double = 0
    var hwdec: String = ""
    var pixelFormat: String = ""
    var colormatrix: String = ""
    var colorspace: String = ""
    var audioCodec: String = ""
    var audioSampleRate: Int64 = 0
    var audioChannels: Int64 = 0
    var audioBitrate: Double = 0
    // HDR / Dolby / Atmos detection
    var gamma: String = ""
    var primaries: String = ""
    var audioChannelLayout: String = ""
    var audioCodecDesc: String = ""
}

/// Content format badges detected from mpv properties.
/// Matches Apple TV / Infuse badge display.
struct FormatBadges {
    var isDolbyVision: Bool = false
    var isHDR10: Bool = false
    var isHLG: Bool = false
    var isDolbyAtmos: Bool = false
    var channelLabel: String? = nil   // "5.1", "7.1", "Stereo"
    var resolution: String? = nil     // "4K", "1080p", "720p"
}

// ---------------------------------------------------------------------------
// Delegate protocol
// ---------------------------------------------------------------------------
protocol MPVControllerDelegate: AnyObject {
    func mpvPropertyChanged(_ name: String, value: Any?)
    func mpvFileLoaded()
    func mpvPlaybackEnded()
    func mpvTracksChanged(_ tracks: [TrackInfo])
}

// ---------------------------------------------------------------------------
// Anime4K shader presets (matches the Electron version exactly)
// ---------------------------------------------------------------------------
let kShaderPresets: [String: [String]] = [
    // ── HQ Presets (higher-end GPU: M1 Pro/Max, M2 Pro/Max, M3/M4) ──
    "Mode A (HQ)": [
        "Anime4K_Clamp_Highlights.glsl",
        "Anime4K_Restore_CNN_VL.glsl",
        "Anime4K_Upscale_CNN_x2_VL.glsl",
        "Anime4K_AutoDownscalePre_x2.glsl",
        "Anime4K_AutoDownscalePre_x4.glsl",
        "Anime4K_Upscale_CNN_x2_M.glsl",
    ],
    "Mode B (HQ)": [
        "Anime4K_Clamp_Highlights.glsl",
        "Anime4K_Restore_CNN_Soft_VL.glsl",
        "Anime4K_Upscale_CNN_x2_VL.glsl",
        "Anime4K_AutoDownscalePre_x2.glsl",
        "Anime4K_AutoDownscalePre_x4.glsl",
        "Anime4K_Upscale_CNN_x2_M.glsl",
    ],
    "Mode C (HQ)": [
        "Anime4K_Clamp_Highlights.glsl",
        "Anime4K_Upscale_Denoise_CNN_x2_VL.glsl",
        "Anime4K_AutoDownscalePre_x2.glsl",
        "Anime4K_AutoDownscalePre_x4.glsl",
        "Anime4K_Upscale_CNN_x2_M.glsl",
    ],
    "Mode A+A (HQ)": [
        "Anime4K_Clamp_Highlights.glsl",
        "Anime4K_Restore_CNN_VL.glsl",
        "Anime4K_Upscale_CNN_x2_VL.glsl",
        "Anime4K_Restore_CNN_M.glsl",
        "Anime4K_AutoDownscalePre_x2.glsl",
        "Anime4K_AutoDownscalePre_x4.glsl",
        "Anime4K_Upscale_CNN_x2_M.glsl",
    ],
    "Mode B+B (HQ)": [
        "Anime4K_Clamp_Highlights.glsl",
        "Anime4K_Restore_CNN_Soft_VL.glsl",
        "Anime4K_Upscale_CNN_x2_VL.glsl",
        "Anime4K_Restore_CNN_Soft_M.glsl",
        "Anime4K_AutoDownscalePre_x2.glsl",
        "Anime4K_AutoDownscalePre_x4.glsl",
        "Anime4K_Upscale_CNN_x2_M.glsl",
    ],
    "Mode C+A (HQ)": [
        "Anime4K_Clamp_Highlights.glsl",
        "Anime4K_Upscale_Denoise_CNN_x2_VL.glsl",
        "Anime4K_AutoDownscalePre_x2.glsl",
        "Anime4K_AutoDownscalePre_x4.glsl",
        "Anime4K_Restore_CNN_M.glsl",
        "Anime4K_Upscale_CNN_x2_M.glsl",
    ],
    // ── Fast Presets (lower-end GPU: M1, M2, Intel) ──
    "Mode A (Fast)": [
        "Anime4K_Clamp_Highlights.glsl",
        "Anime4K_Restore_CNN_M.glsl",
        "Anime4K_Upscale_CNN_x2_M.glsl",
        "Anime4K_AutoDownscalePre_x2.glsl",
        "Anime4K_AutoDownscalePre_x4.glsl",
        "Anime4K_Upscale_CNN_x2_S.glsl",
    ],
    "Mode B (Fast)": [
        "Anime4K_Clamp_Highlights.glsl",
        "Anime4K_Restore_CNN_Soft_M.glsl",
        "Anime4K_Upscale_CNN_x2_M.glsl",
        "Anime4K_AutoDownscalePre_x2.glsl",
        "Anime4K_AutoDownscalePre_x4.glsl",
        "Anime4K_Upscale_CNN_x2_S.glsl",
    ],
    "Mode C (Fast)": [
        "Anime4K_Clamp_Highlights.glsl",
        "Anime4K_Upscale_Denoise_CNN_x2_M.glsl",
        "Anime4K_AutoDownscalePre_x2.glsl",
        "Anime4K_AutoDownscalePre_x4.glsl",
        "Anime4K_Upscale_CNN_x2_S.glsl",
    ],
    "Mode A+A (Fast)": [
        "Anime4K_Clamp_Highlights.glsl",
        "Anime4K_Restore_CNN_M.glsl",
        "Anime4K_Upscale_CNN_x2_M.glsl",
        "Anime4K_Restore_CNN_S.glsl",
        "Anime4K_AutoDownscalePre_x2.glsl",
        "Anime4K_AutoDownscalePre_x4.glsl",
        "Anime4K_Upscale_CNN_x2_S.glsl",
    ],
    "Mode B+B (Fast)": [
        "Anime4K_Clamp_Highlights.glsl",
        "Anime4K_Restore_CNN_Soft_M.glsl",
        "Anime4K_Upscale_CNN_x2_M.glsl",
        "Anime4K_AutoDownscalePre_x2.glsl",
        "Anime4K_AutoDownscalePre_x4.glsl",
        "Anime4K_Restore_CNN_Soft_S.glsl",
        "Anime4K_Upscale_CNN_x2_S.glsl",
    ],
    "Mode C+A (Fast)": [
        "Anime4K_Clamp_Highlights.glsl",
        "Anime4K_Upscale_Denoise_CNN_x2_M.glsl",
        "Anime4K_AutoDownscalePre_x2.glsl",
        "Anime4K_AutoDownscalePre_x4.glsl",
        "Anime4K_Restore_CNN_S.glsl",
        "Anime4K_Upscale_CNN_x2_S.glsl",
    ],
]

// ---------------------------------------------------------------------------
// MPVController – manages mpv handle, render context, event loop & properties
// ---------------------------------------------------------------------------

class MPVController {

    var mpvHandle: OpaquePointer?
    var mpvRenderContext: OpaquePointer?
    /// CGL context reference – owned by ViewLayer's Metal pipeline.
    /// Used internally by mpv's render API (the only remaining OpenGL
    /// dependency). All display rendering uses Metal 3 via CAMetalLayer.
    var openGLContext: CGLContextObj?

    weak var delegate: MPVControllerDelegate?

    private var eventThread: Thread?
    private var lastTimePosDispatch: CFTimeInterval = 0
    private var eventLoopRunning = true

    // Parsed track list
    var tracks: [TrackInfo] = []
    // Current shader preset name (nil = none)
    var currentShaderPreset: String?
    // Whether shaders are available
    var shadersAvailable: Bool = false
    // Shader directory path
    var shaderDir: String?
    // Power source state: true = AC, false = battery
    private var isOnAC: Bool = true
    // Power source notification run loop source
    private var powerSourceRunLoopSource: CFRunLoopSource?

    // MARK: - Initialization

    func initialize() {
        // 1. Create mpv handle
        mpvHandle = mpv_create()
        guard mpvHandle != nil else {
            fatalError("[MPV] Failed to create mpv instance")
        }

        // 2. Set critical options BEFORE mpv_initialize
        setOption("vo", "libmpv")
        setOption("hwdec", "videotoolbox")
        setOption("hwdec-codecs", "all")
        setOption("keep-open", "yes")
        setOption("input-default-bindings", "yes")
        setOption("input-vo-keyboard", "no")
        setOption("osc", "no")
        setOption("osd-level", "0")
        setOption("idle", "yes")
        setOption("force-window", "no")

        // Audio
        setOption("ao", "avfoundation")
        setOption("audio-channels", "auto")
        setOption("audio-spdif", "ac3,eac3,truehd,dts-hd")

        // Volume max 200%
        setOption("volume-max", "200")

        // Quality
        setOption("profile", "high-quality")

        // Display P3 wide gamut – matches MacBook Pro's native panel gamut.
        // mpv renders in P3 colorspace with standard gamma for maximum color.
        // HDR tone mapping is handled by a conditional profile in mpv.conf.
        setOption("target-prim", "display-p3")

        // Try to load config file from bundle resources
        let execPath = ProcessInfo.processInfo.arguments[0]
        let macosDir = (execPath as NSString).deletingLastPathComponent
        let contentsDir = (macosDir as NSString).deletingLastPathComponent
        let configDir = (contentsDir as NSString)
            .appendingPathComponent("Resources")
            .appending("/configs")

        if FileManager.default.fileExists(atPath: configDir + "/mpv.conf") {
            setOption("config-dir", configDir)
            setOption("config", "yes")
            NSLog("[MPV] Loading config from: %@", configDir)
        }

        // Find shaders
        findShaders(contentsDir: contentsDir)

        // 3. Initialize mpv
        let err = mpv_initialize(mpvHandle!)
        if err < 0 {
            fatalError("[MPV] Failed to initialize: \(String(cString: mpv_error_string(err)))")
        }

        // 3.5  Apply any user-changed settings from the Settings UI.
        //      UserDefaults keys that map to mpv properties are applied here
        //      so they survive app restarts.
        applyUserDefaultsToMPV()

        // 4. Observe properties for UI updates
        observeProperty("time-pos", format: MPV_FORMAT_DOUBLE)
        observeProperty("duration", format: MPV_FORMAT_DOUBLE)
        observeProperty("pause", format: MPV_FORMAT_FLAG)
        observeProperty("media-title", format: MPV_FORMAT_STRING)
        observeProperty("video-params/w", format: MPV_FORMAT_INT64)
        observeProperty("video-params/h", format: MPV_FORMAT_INT64)
        observeProperty("video-out-params/dw", format: MPV_FORMAT_INT64)
        observeProperty("video-out-params/dh", format: MPV_FORMAT_INT64)
        observeProperty("speed", format: MPV_FORMAT_DOUBLE)
        observeProperty("volume", format: MPV_FORMAT_DOUBLE)
        observeProperty("mute", format: MPV_FORMAT_FLAG)
        observeProperty("brightness", format: MPV_FORMAT_DOUBLE)
        observeProperty("track-list/count", format: MPV_FORMAT_INT64)
        observeProperty("audio-device", format: MPV_FORMAT_STRING)

        // 5. Start event loop
        startEventLoop()

        // 6. Start power source monitoring (Bug 10: adapt quality to battery)
        setupPowerSourceMonitoring()

        NSLog("[MPV] Initialized successfully")
    }

    // MARK: - Shader Discovery

    private func findShaders(contentsDir: String) {
        let bundleShaders = contentsDir + "/Resources/shaders"
        let home = NSHomeDirectory()
        let candidates = [
            bundleShaders,
            home + "/.config/mpv/shaders",
            home + "/Library/Application Support/mpv/shaders",
            home + "/.mpv/shaders",
        ]
        for dir in candidates {
            if FileManager.default.fileExists(atPath: dir) {
                let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
                if files.contains(where: { $0.contains("Anime4K") }) {
                    shaderDir = dir
                    shadersAvailable = true
                    NSLog("[MPV] Found Anime4K shaders in: %@", dir)
                    return
                }
            }
        }
        NSLog("[MPV] No Anime4K shaders found")
    }

    // MARK: - Power Source Monitoring (Bug 10: battery-aware quality)

    private func setupPowerSourceMonitoring() {
        // Read initial power source
        updatePowerSourceState()

        // Register for power source change notifications
        let selfPtr = Unmanaged.passRetained(self).toOpaque()
        let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx = ctx else { return }
            let controller = Unmanaged<MPVController>.fromOpaque(ctx).takeUnretainedValue()
            controller.updatePowerSourceState()
        }, selfPtr)?.takeRetainedValue()
        if let src = src {
            powerSourceRunLoopSource = src
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        }
    }

    private func updatePowerSourceState() {
        let psInfo = IOPSCopyPowerSourcesInfo()?.takeRetainedValue()
        let psList = IOPSCopyPowerSourcesList(psInfo)?.takeRetainedValue() as? [CFTypeRef] ?? []
        var onAC = true
        for ps in psList {
            if let dict = IOPSGetPowerSourceDescription(psInfo, ps)?.takeUnretainedValue() as? [String: Any] {
                let src = dict[kIOPSPowerSourceStateKey as String] as? String ?? ""
                if src == kIOPSBatteryPowerValue as String {
                    onAC = false
                    break
                }
            }
        }
        let changed = onAC != isOnAC
        isOnAC = onAC
        if changed {
            DispatchQueue.main.async { [weak self] in
                self?.applyPowerProfile()
            }
        }
    }

    /// Apply quality profile based on current power source.
    /// On battery: switch to default profile (less CPU/GPU load).
    /// On AC: restore high-quality profile.
    func applyPowerProfile() {
        guard mpvHandle != nil else { return }
        if isOnAC {
            mpv_command_string(mpvHandle, "set profile high-quality")
            NSLog("[MPV] Power: AC — high-quality profile active")
        } else {
            mpv_command_string(mpvHandle, "set profile default")
            // Also clear active shaders on battery to reduce GPU load
            if currentShaderPreset != nil {
                mpv_command_string(mpvHandle, "change-list glsl-shaders clr \"\"")
                NSLog("[MPV] Power: Battery — cleared shaders, default profile active")
            } else {
                NSLog("[MPV] Power: Battery — default profile active")
            }
        }
    }

    // MARK: - Rendering

    func shouldRenderUpdateFrame() -> Bool {
        guard let ctx = mpvRenderContext else { return false }
        let flags = mpv_render_context_update(ctx)
        return flags & UInt64(MPV_RENDER_UPDATE_FRAME.rawValue) > 0
    }

    /// Lock the offscreen CGL context used by mpv's render API.
    /// This context is NOT used for display – Metal handles all screen output.
    /// Called only for mpv frame-skip operations during edge-case recovery.
    func lockAndSetOpenGLContext() {
        guard let ctx = openGLContext else { return }
        CGLLockContext(ctx)
        CGLSetCurrentContext(ctx)
    }

    /// Unlock the offscreen CGL context after mpv render operations.
    func unlockOpenGLContext() {
        guard let ctx = openGLContext else { return }
        CGLUnlockContext(ctx)
    }

    // MARK: - Commands

    func loadFile(_ path: String) {
        command(["loadfile", path])
    }

    func loadUrl(_ url: String) {
        command(["loadfile", url])
    }

    func togglePause() {
        mpv_command_string(mpvHandle, "cycle pause")
    }

    func seek(by seconds: Double) {
        mpv_command_string(mpvHandle, "seek \(seconds) relative+exact")
    }

    func seek(to position: Double) {
        mpv_command_string(mpvHandle, "seek \(position) absolute+exact")
    }

    /// Fast keyframe seek for scrubbing — snaps to nearest keyframe (instant)
    func seekKeyframe(to position: Double) {
        mpv_command_string(mpvHandle, "seek \(position) absolute+keyframes")
    }

    func frameStep() {
        mpv_command_string(mpvHandle, "frame-step")
    }

    func frameBackStep() {
        mpv_command_string(mpvHandle, "frame-back-step")
    }

    /// Set mpv volume (0-200).
    /// Uses Accelerate vDSP clamp (Phase 1C: SIMD/Accelerate Abstraction)
    func setVolume(_ volume: Double) {
        var vol = clampRangeAccelerate(volume, lower: 0, upper: 200)
        mpv_set_property(mpvHandle, "volume", MPV_FORMAT_DOUBLE, &vol)
    }

    func getVolume() -> Double {
        var vol: Double = 100
        mpv_get_property(mpvHandle, "volume", MPV_FORMAT_DOUBLE, &vol)
        return vol
    }

    func toggleMute() {
        mpv_command_string(mpvHandle, "cycle mute")
    }

    func setSpeed(_ speed: Double) {
        mpv_command_string(mpvHandle, "set speed \(speed)")
    }

    func getSpeed() -> Double {
        var s: Double = 1.0
        mpv_get_property(mpvHandle, "speed", MPV_FORMAT_DOUBLE, &s)
        return s
    }

    func getAudioDelay() -> Double {
        var d: Double = 0.0
        mpv_get_property(mpvHandle, "audio-delay", MPV_FORMAT_DOUBLE, &d)
        return d
    }

    // MARK: - Track Selection

    func cycleSubtitle() {
        mpv_command_string(mpvHandle, "cycle sub")
    }

    func cycleAudio() {
        mpv_command_string(mpvHandle, "cycle audio")
    }

    func setSubTrack(_ id: Int) {
        var val = Int64(id)
        mpv_set_property(mpvHandle, "sid", MPV_FORMAT_INT64, &val)
    }

    func disableSubtitles() {
        mpv_command_string(mpvHandle, "set sid no")
    }

    func setAudioTrack(_ id: Int) {
        var val = Int64(id)
        mpv_set_property(mpvHandle, "aid", MPV_FORMAT_INT64, &val)
    }

    func toggleSubVisibility() {
        mpv_command_string(mpvHandle, "cycle sub-visibility")
    }

    /// Add an external subtitle file
    func addExternalSubtitle(_ path: String) {
        command(["sub-add", path])
        refreshTrackList()
    }

    /// Add an external audio file
    func addExternalAudio(_ path: String) {
        command(["audio-add", path])
        refreshTrackList()
    }

    /// Set mpv software brightness (-100 to 100)
    /// Set mpv software brightness (-100 to 100)
    /// Uses Accelerate vDSP clamp (Phase 1C: SIMD/Accelerate Abstraction)
    func setBrightness(_ value: Double) {
        var v = clampRangeAccelerate(value, lower: -100, upper: 100)
        mpv_set_property(mpvHandle, "brightness", MPV_FORMAT_DOUBLE, &v)
    }

    func getBrightness() -> Double {
        var v: Double = 0
        mpv_get_property(mpvHandle, "brightness", MPV_FORMAT_DOUBLE, &v)
        return v
    }

    /// Return (displayWidth, displayHeight) from video-out-params.
    /// These account for pixel aspect ratio AND video-aspect-override.
    /// Falls back to video-params/w,h if out-params unavailable.
    func getDisplayDimensions() -> (width: Int64, height: Int64) {
        var dw: Int64 = 0
        var dh: Int64 = 0
        mpv_get_property(mpvHandle, "video-out-params/dw", MPV_FORMAT_INT64, &dw)
        mpv_get_property(mpvHandle, "video-out-params/dh", MPV_FORMAT_INT64, &dh)
        if dw > 0 && dh > 0 { return (dw, dh) }
        // Fallback to coded dimensions
        mpv_get_property(mpvHandle, "video-params/w", MPV_FORMAT_INT64, &dw)
        mpv_get_property(mpvHandle, "video-params/h", MPV_FORMAT_INT64, &dh)
        return (dw, dh)
    }

    /// Set aspect ratio override (empty string = auto)
    func setAspectOverride(_ aspect: String) {
        if aspect.isEmpty || aspect == "auto" {
            mpv_command_string(mpvHandle, "set video-aspect-override -1")
        } else {
            mpv_command_string(mpvHandle, "set video-aspect-override \(aspect)")
        }
    }

    func prevFile() {
        mpv_command_string(mpvHandle, "playlist-prev")
    }

    func nextFile() {
        mpv_command_string(mpvHandle, "playlist-next")
    }

    // MARK: - Track List Parsing

    func refreshTrackList() {
        guard let handle = mpvHandle else { return }
        var count: Int64 = 0
        mpv_get_property(handle, "track-list/count", MPV_FORMAT_INT64, &count)

        var newTracks: [TrackInfo] = []
        for i in 0..<Int(count) {
            let prefix = "track-list/\(i)"

            var trackId: Int64 = 0
            mpv_get_property(handle, "\(prefix)/id", MPV_FORMAT_INT64, &trackId)

            let type = getString("\(prefix)/type") ?? "unknown"
            let title = getString("\(prefix)/title")
            let lang = getString("\(prefix)/lang")
            let codec = getString("\(prefix)/codec")

            var sel: Int32 = 0
            mpv_get_property(handle, "\(prefix)/selected", MPV_FORMAT_FLAG, &sel)

            newTracks.append(TrackInfo(
                id: Int(trackId),
                type: type,
                title: title,
                lang: lang,
                codec: codec,
                selected: sel != 0
            ))
        }
        tracks = newTracks
        let snapshot = newTracks
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.mpvTracksChanged(snapshot)
        }
    }

    private func getString(_ name: String) -> String? {
        guard let handle = mpvHandle else { return nil }
        guard let cstr = mpv_get_property_string(handle, name) else { return nil }
        let str = String(cString: cstr)
        mpv_free(cstr)
        return str.isEmpty ? nil : str
    }

    // MARK: - Video Info

    func getVideoInfo() -> VideoInfo {
        var info = VideoInfo()
        info.filename = getString("filename") ?? ""
        info.fileFormat = getString("file-format") ?? ""

        var fileSize: Int64 = 0
        mpv_get_property(mpvHandle, "file-size", MPV_FORMAT_INT64, &fileSize)
        info.fileSize = fileSize

        var dur: Double = 0
        mpv_get_property(mpvHandle, "duration", MPV_FORMAT_DOUBLE, &dur)
        info.duration = dur

        info.videoCodec = getString("video-codec") ?? ""

        var w: Int64 = 0, h: Int64 = 0
        mpv_get_property(mpvHandle, "width", MPV_FORMAT_INT64, &w)
        mpv_get_property(mpvHandle, "height", MPV_FORMAT_INT64, &h)
        info.width = w
        info.height = h

        var fps: Double = 0
        mpv_get_property(mpvHandle, "estimated-vf-fps", MPV_FORMAT_DOUBLE, &fps)
        info.fps = fps

        var vbr: Double = 0
        mpv_get_property(mpvHandle, "video-bitrate", MPV_FORMAT_DOUBLE, &vbr)
        info.videoBitrate = vbr

        info.hwdec = getString("hwdec-current") ?? "none"
        info.pixelFormat = getString("video-params/pixelformat") ?? ""
        info.colormatrix = getString("video-params/colormatrix") ?? ""
        info.colorspace = getString("video-params/colorlevels") ?? ""
        info.gamma = getString("video-params/gamma") ?? ""
        info.primaries = getString("video-params/primaries") ?? ""

        info.audioCodec = getString("audio-codec-name") ?? ""
        info.audioCodecDesc = getString("audio-codec") ?? ""
        info.audioChannelLayout = getString("audio-params/channels") ?? ""

        var sr: Int64 = 0
        mpv_get_property(mpvHandle, "audio-params/samplerate", MPV_FORMAT_INT64, &sr)
        info.audioSampleRate = sr

        var ch: Int64 = 0
        mpv_get_property(mpvHandle, "audio-params/channel-count", MPV_FORMAT_INT64, &ch)
        info.audioChannels = ch

        var abr: Double = 0
        mpv_get_property(mpvHandle, "audio-bitrate", MPV_FORMAT_DOUBLE, &abr)
        info.audioBitrate = abr

        return info
    }

    /// Detect format badges from current media properties.
    /// Mimics Apple TV / Infuse format badge detection.
    func getFormatBadges() -> FormatBadges {
        let info = getVideoInfo()
        var badges = FormatBadges()

        // ── Resolution badge ──
        let h = info.height
        if h >= 2160 { badges.resolution = "4K" }
        else if h >= 1080 { badges.resolution = "1080p" }
        else if h >= 720 { badges.resolution = "720p" }

        // ── HDR / Dolby Vision detection ──
        // Dolby Vision: pixelformat contains "dovi" or codec is HEVC with DV profile,
        // or video-params/gamma is "pq" with BT.2020 primaries and DV metadata present
        let pixFmt = info.pixelFormat.lowercased()
        let gamma = info.gamma.lowercased()
        let primaries = info.primaries.lowercased()
        let videoCodec = info.videoCodec.lowercased()

        // Check for Dolby Vision: look for DV-specific pixel formats or codec profiles
        if pixFmt.contains("dovi") || pixFmt.contains("dvhe") || pixFmt.contains("dvh1") {
            badges.isDolbyVision = true
        } else if videoCodec.contains("dolby vision") || videoCodec.contains("dovi") {
            badges.isDolbyVision = true
        }
        // Also check track codec from track-list for DV profile
        if !badges.isDolbyVision {
            for track in tracks where track.type == "video" {
                if let codec = track.codec?.lowercased() {
                    if codec.contains("dovi") || codec.contains("dvhe") || codec.contains("dvh1") || codec.contains("dolby vision") {
                        badges.isDolbyVision = true
                        break
                    }
                }
            }
        }

        // HDR10: PQ transfer + BT.2020 primaries (but not DV)
        if gamma == "pq" && primaries.contains("bt.2020") {
            if !badges.isDolbyVision {
                badges.isHDR10 = true
            }
        }

        // HLG: Hybrid Log-Gamma
        if gamma == "hlg" {
            badges.isHLG = true
        }

        // ── Audio: Dolby Atmos detection ──
        let aCodec = info.audioCodec.lowercased()
        let aDesc = info.audioCodecDesc.lowercased()
        let aLayout = info.audioChannelLayout.lowercased()

        // E-AC3 JOC = Dolby Atmos over DD+
        // TrueHD with 7.1+ channels = Atmos (TrueHD is the lossless Atmos carrier)
        if aCodec.contains("eac3") || aDesc.contains("e-ac-3") || aDesc.contains("enhanced ac-3") {
            // E-AC3 can carry Atmos (JOC). Channel count > 6 or object metadata = Atmos
            if info.audioChannels > 6 || aDesc.contains("atmos") || aDesc.contains("joc") {
                badges.isDolbyAtmos = true
            } else {
                // Even stereo E-AC3 might carry Atmos objects; flag as Atmos for E-AC3
                // in movies/streaming (Apple TV+ uses E-AC3 JOC for all Atmos content)
                badges.isDolbyAtmos = true
            }
        } else if aCodec.contains("truehd") || aDesc.contains("truehd") {
            // TrueHD is always Atmos on Blu-ray when 7.1+
            if info.audioChannels >= 8 {
                badges.isDolbyAtmos = true
            }
        }

        // ── Channel layout label ──
        if aLayout.contains("7.1") { badges.channelLabel = "7.1" }
        else if aLayout.contains("5.1") { badges.channelLabel = "5.1" }
        else if info.audioChannels >= 8 { badges.channelLabel = "7.1" }
        else if info.audioChannels >= 6 { badges.channelLabel = "5.1" }
        else if info.audioChannels == 2 { badges.channelLabel = "Stereo" }
        else if info.audioChannels == 1 { badges.channelLabel = "Mono" }

        return badges
    }

    // MARK: - Anime4K Shader Presets

    /// Weak reference to the ViewLayer for Metal pipeline control
    weak var viewLayer: ViewLayer?

    /// Whether to use native Metal pipeline for Anime4K (true) or GLSL shaders via mpv (false)
    var useMetalPipeline: Bool = false

    /// Apply an Anime4K shader preset.
    /// If useMetalPipeline is true and the preset is available, uses the native Metal compute pipeline.
    /// Otherwise, falls back to GLSL shaders via mpv's glsl-shaders property.
    func applyShaderPreset(_ preset: String) -> Bool {
        // Try Metal pipeline first if enabled
        if useMetalPipeline, let layer = viewLayer {
            if layer.enableAnime4K(preset: preset) {
                currentShaderPreset = preset
                // Clear any GLSL shaders to prevent double-processing
                clearGLSLShaders()
                NSLog("[MPV] Applied Metal Anime4K preset: %@", preset)
                return true
            }
            // Metal pipeline failed, fall back to GLSL
            NSLog("[MPV] Metal pipeline failed for preset %@, falling back to GLSL", preset)
        }

        // Fall back to GLSL shaders via mpv
        guard let dir = shaderDir else {
            NSLog("[MPV] No shader directory available")
            return false
        }
        guard let shaderNames = kShaderPresets[preset] else {
            NSLog("[MPV] Unknown preset: %@", preset)
            return false
        }

        let paths = shaderNames
            .map { "\(dir)/\($0)" }
            .filter { FileManager.default.fileExists(atPath: $0) }

        guard !paths.isEmpty else { return false }

        let joined = paths.joined(separator: ":")
        mpv_command_string(mpvHandle, "change-list glsl-shaders set \"\(joined)\"")
        currentShaderPreset = preset
        NSLog("[MPV] Applied GLSL shader preset: %@ (%d shaders)", preset, paths.count)
        return true
    }

    /// Clear all Anime4K shaders (both Metal and GLSL)
    func clearShaders() {
        // Disable Metal pipeline
        if useMetalPipeline, let layer = viewLayer {
            layer.disableAnime4K()
        }
        // Clear GLSL shaders
        clearGLSLShaders()
        currentShaderPreset = nil
        NSLog("[MPV] Shaders cleared")
    }

    /// Clear only GLSL shaders (used when switching to Metal pipeline)
    private func clearGLSLShaders() {
        mpv_command_string(mpvHandle, "change-list glsl-shaders clr \"\"")
    }

    /// Switch between Metal and GLSL shader backend
    func setShaderBackend(_ useMetal: Bool) {
        useMetalPipeline = useMetal
        if useMetal {
            // Clear any active GLSL shaders
            clearGLSLShaders()
            // Re-apply current preset with Metal pipeline if one was active
            if let preset = currentShaderPreset {
                _ = applyShaderPreset(preset)
            }
        } else {
            // Disable Metal pipeline
            viewLayer?.disableAnime4K()
            // Re-apply current preset with GLSL if one was active
            if let preset = currentShaderPreset {
                _ = applyShaderPreset(preset)
            }
        }
        NSLog("[MPV] Shader backend: %@", useMetal ? "Metal" : "GLSL")
    }

    // MARK: - Property observation

    private func observeProperty(_ name: String, format: mpv_format) {
        mpv_observe_property(mpvHandle!, 0, name, format)
    }

    // MARK: - Event loop

    private func startEventLoop() {
        eventThread = Thread { [weak self] in
            while let self = self, self.eventLoopRunning {
                guard let handle = self.mpvHandle else { break }
                // Use a 1-second timeout instead of blocking forever (-1)
                // so the loop re-checks eventLoopRunning periodically and
                // can exit promptly during shutdown without racing on handle.
                guard let event = mpv_wait_event(handle, 1) else { continue }
                let eventID = event.pointee.event_id

                if eventID == MPV_EVENT_SHUTDOWN {
                    NSLog("[MPV] Shutdown event received")
                    break
                }
                if eventID == MPV_EVENT_NONE { continue }

                switch eventID {
                case MPV_EVENT_FILE_LOADED:
                    self.refreshTrackList()
                    DispatchQueue.main.async { [weak self] in self?.delegate?.mpvFileLoaded() }

                case MPV_EVENT_END_FILE:
                    DispatchQueue.main.async { [weak self] in self?.delegate?.mpvPlaybackEnded() }

                case MPV_EVENT_PROPERTY_CHANGE:
                    let prop = event.pointee.data.assumingMemoryBound(
                        to: mpv_event_property.self
                    ).pointee
                    guard let cName = prop.name else { break }  // UnsafePointer<CChar> — no heap allocation

                    if strcmp(cName, "track-list/count") == 0 {
                        self.refreshTrackList()
                    }
                    // Bug 8: Re-negotiate audio-channels after audio device switch
                    // so spatial audio / head tracking is re-established properly.
                    if strcmp(cName, "audio-device") == 0 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                            guard let self = self else { return }
                            mpv_command_string(self.mpvHandle, "set audio-channels auto")
                        }
                    }

                    switch prop.format {
                    case MPV_FORMAT_DOUBLE:
                        let val = prop.data?.assumingMemoryBound(to: Double.self).pointee
                        // Hot path: time-pos fires ~30fps — throttle and avoid String alloc
                        if strcmp(cName, "time-pos") == 0 {
                            let now = CACurrentMediaTime()
                            if now - self.lastTimePosDispatch < 0.033 { break }
                            self.lastTimePosDispatch = now
                        }
                        let name = String(cString: cName)
                        DispatchQueue.main.async { [weak self] in self?.delegate?.mpvPropertyChanged(name, value: val) }
                    case MPV_FORMAT_FLAG:
                        let val = prop.data?.assumingMemoryBound(to: Int32.self).pointee
                        let name = String(cString: cName)
                        DispatchQueue.main.async { [weak self] in self?.delegate?.mpvPropertyChanged(name, value: val) }
                    case MPV_FORMAT_INT64:
                        let val = prop.data?.assumingMemoryBound(to: Int64.self).pointee
                        let name = String(cString: cName)
                        DispatchQueue.main.async { [weak self] in self?.delegate?.mpvPropertyChanged(name, value: val) }
                    case MPV_FORMAT_STRING:
                        if let cstr = prop.data?.assumingMemoryBound(
                            to: UnsafePointer<CChar>?.self
                        ).pointee {
                            let name = String(cString: cName)
                            let val = String(cString: cstr)
                            DispatchQueue.main.async { [weak self] in self?.delegate?.mpvPropertyChanged(name, value: val) }
                        }
                    default:
                        break
                    }

                default:
                    break
                }
            }
            self?.eventLoopExited.signal()
        }
        eventThread?.name = "com.glassplayer.mpv-event"
        eventThread?.qualityOfService = .userInitiated
        eventThread?.start()
    }

    // MARK: - Shutdown

    private let eventLoopExited = DispatchSemaphore(value: 0)

    func shutdown() {
        // 0. Remove power source notification
        if let src = powerSourceRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .defaultMode)
            powerSourceRunLoopSource = nil
        }

        // 1. Signal event loop to exit
        eventLoopRunning = false
        if let handle = mpvHandle {
            mpv_wakeup(handle)  // unblock mpv_wait_event
        }

        // 2. Wait for event thread to actually exit (up to 2s)
        //    so it doesn't touch the mpv handle after we destroy it.
        if eventThread != nil {
            _ = eventLoopExited.wait(timeout: .now() + 2.0)
        }

        // 3. Free render context (may already be nil if ViewLayer.uninitRendering ran)
        if let ctx = mpvRenderContext {
            mpv_render_context_set_update_callback(ctx, nil, nil)
            mpv_render_context_free(ctx)
            mpvRenderContext = nil
        }

        // 4. Destroy mpv handle
        if let handle = mpvHandle {
            mpv_terminate_destroy(handle)
            mpvHandle = nil
        }

        // 5. Clear CGL reference — do NOT release it.
        //    ViewLayer (Metal 3 pipeline) owns the offscreen CGL context
        //    used for mpv interop and releases it in its deinit.
        openGLContext = nil

        // 6. Break retain cycle
        eventThread = nil

        NSLog("[MPV] Shutdown complete")
    }

    // MARK: - Helpers

    /// Take a screenshot of the current video frame to a file.
    /// Returns true if the command was sent successfully.
    func screenshotToFile(_ path: String) -> Bool {
        guard mpvHandle != nil else { return false }
        command(["screenshot-to-file", path, "video"])
        return true
    }

    /// Send command to mpv using safe array API (no string escaping needed)
    /// Uses stack-based withCString to avoid heap allocation per argument
    private func command(_ args: [String]) {
        guard let handle = mpvHandle else { return }
        // Fast path for common 1-3 argument commands (avoids array heap allocation)
        switch args.count {
        case 1:
            args[0].withCString { a0 in
                var ptrs: [UnsafePointer<CChar>?] = [a0, nil]
                mpv_command(handle, &ptrs)
            }
        case 2:
            args[0].withCString { a0 in
                args[1].withCString { a1 in
                    var ptrs: [UnsafePointer<CChar>?] = [a0, a1, nil]
                    mpv_command(handle, &ptrs)
                }
            }
        case 3:
            args[0].withCString { a0 in
                args[1].withCString { a1 in
                    args[2].withCString { a2 in
                        var ptrs: [UnsafePointer<CChar>?] = [a0, a1, a2, nil]
                        mpv_command(handle, &ptrs)
                    }
                }
            }
        default:
            // Fallback for 4+ args (rare) — heap allocate
            let cArgs = args.map { strdup($0)! }
            var cPointers: [UnsafePointer<CChar>?] = cArgs.map { UnsafePointer($0) }
            cPointers.append(nil)
            mpv_command(handle, &cPointers)
            cArgs.forEach { free($0) }
        }
    }

    private func setOption(_ name: String, _ value: String) {
        let err = mpv_set_option_string(mpvHandle, name, value)
        if err < 0 {
            NSLog("[MPV] Warning: failed to set %@=%@: %s", name, value,
                  mpv_error_string(err))
        }
    }

    /// Set an mpv property at runtime (after mpv_initialize).
    /// Use this for live settings changes from the Settings UI.
    func setPropertyString(_ name: String, _ value: String) {
        guard let handle = mpvHandle else { return }
        // Strip trailing '%' — some UI controls store e.g. "200%" but
        // mpv expects a plain number for numeric properties.
        let cleanValue = value.hasSuffix("%") ? String(value.dropLast()) : value
        let err = mpv_set_property_string(handle, name, cleanValue)
        if err < 0 {
            // Silently ignore "property not found" (MPV_ERROR_PROPERTY_NOT_FOUND = -8)
            // — some mpv versions don't support every property (e.g. tone-mapping-mode)
            if err != -8 {
                NSLog("[MPV] Warning: failed to set property %@=%@: %s", name, cleanValue,
                      mpv_error_string(err))
            }
        }
    }

    /// Apply all user-changed settings from UserDefaults to the mpv instance.
    /// Called once after mpv_initialize so that settings survive restarts.
    private func applyUserDefaultsToMPV() {
        let ud = UserDefaults.standard

        // Map of UserDefaults key → (mpv property, isBool, isMiB)
        let settings: [(key: String, mpv: String, isBool: Bool, isMiB: Bool)] = [
            ("hwdec",               "hwdec",                false, false),
            ("hwdecCodecs",         "hwdec-codecs",         false, false),
            ("screenshotFormat",    "screenshot-format",    false, false),
            ("screenshotJpegQuality","screenshot-jpeg-quality",false,false),
            ("debandEnabled",       "deband",               true,  false),
            ("debandIterations",    "deband-iterations",    false, false),
            ("debandThreshold",     "deband-threshold",     false, false),
            ("debandRange",         "deband-range",         false, false),
            ("debandGrain",         "deband-grain",         false, false),
            ("volumeMax",           "volume-max",           false, false),
            ("audioOutput",         "ao",                   false, false),
            ("audioChannels",       "audio-channels",       false, false),
            ("audioPassthrough",    "audio-spdif",          false, false),
            ("audioLang",           "alang",                false, false),
            ("defaultVolume",       "volume",               false, false),
            ("subAutoLoad",         "sub-auto",             false, false),
            ("subLang",             "slang",                false, false),
            ("subFontSize",         "sub-font-size",        false, false),
            ("subFont",             "sub-font",             false, false),
            ("subPosition",         "sub-pos",              false, false),
            ("subBorderSize",       "sub-border-size",      false, false),
            ("subShadowOffset",     "sub-shadow-offset",    false, false),
            ("subAssOverride",      "sub-ass-override",     false, false),
            ("cacheEnabled",        "cache",                true,  false),
            ("cacheSizeMB",         "demuxer-max-bytes",    false, true),
            ("cacheBackMB",         "demuxer-max-back-bytes",false,true),
            ("readaheadSecs",       "demuxer-readahead-secs",false,false),
            ("cacheSecs",           "cache-secs",           false, false),
            ("networkTimeout",      "network-timeout",      false, false),
            ("forceSeekable",       "force-seekable",       true,  false),
            ("userAgent",           "user-agent",           false, false),
            ("scaleFilter",         "scale",                false, false),
            ("dscaleFilter",        "dscale",               false, false),
            ("cscaleFilter",        "cscale",               false, false),
            ("ditherDepth",         "dither-depth",         false, false),
            ("ditherAlgo",          "dither",               false, false),
            ("correctDownscaling",  "correct-downscaling",  true,  false),
            ("linearDownscaling",   "linear-downscaling",   true,  false),
            ("sigmoidUpscaling",    "sigmoid-upscaling",    true,  false),
            ("toneMapping",         "tone-mapping",         false, false),
            ("toneMappingMode",     "tone-mapping-mode",    false, false),
            ("hdrComputePeak",      "hdr-compute-peak",     true,  false),
            ("targetColorspaceHint","target-colorspace-hint",true, false),
            ("targetPeak",          "target-peak",          false, false),
            ("gamutMapping",        "gamut-mapping-mode",   false, false),
            ("iccProfile",          "icc-profile",          false, false),
            ("audioDelay",          "audio-delay",          false, false),
        ]

        for s in settings {
            guard let raw = ud.object(forKey: s.key) else { continue }
            var value: String
            if s.isBool {
                value = (raw as? Bool ?? false) ? "yes" : "no"
            } else {
                value = "\(raw)"
            }
            if s.isMiB { value += "MiB" }
            // Special case: audioPassthrough stores a Bool but audio-spdif needs codec list
            if s.key == "audioPassthrough" {
                let enabled = raw as? Bool ?? true
                value = enabled ? "ac3,eac3,truehd,dts-hd" : ""
            }
            setPropertyString(s.mpv, value)
        }
    }
}
