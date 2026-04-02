import Cocoa
import Metal
import QuartzCore
import IOSurface
import OpenGL.GL3  // Minimal: offscreen CGL context + IOSurface FBO for mpv render API interop

// ---------------------------------------------------------------------------
// C-compatible callback for mpv render-update notifications
// ---------------------------------------------------------------------------

/// mpv render-update callback – fires whenever a new video frame is available.
/// Bridges mpv's C callback to the ViewLayer's Metal render queue.
private func mpvRenderUpdateCallback(_ ctx: UnsafeMutableRawPointer?) {
    guard let ctx = ctx else { return }
    let layer = Unmanaged<ViewLayer>.fromOpaque(ctx).takeUnretainedValue()
    layer.update()
}

/// OpenGL function loader for mpv – resolves GL symbols from the OpenGL framework.
/// Required by mpv_opengl_init_params for its internal GPU renderer.
/// This is the only remaining OpenGL dependency: mpv's render API mandates it.
private func mpvGetOpenGLProc(_ ctx: UnsafeMutableRawPointer?,
                               _ name: UnsafePointer<Int8>?) -> UnsafeMutableRawPointer? {
    let symbolName = CFStringCreateWithCString(kCFAllocatorDefault, name, kCFStringEncodingASCII)
    guard let bundle = CFBundleGetBundleWithIdentifier("com.apple.opengl" as CFString),
          let addr = CFBundleGetFunctionPointerForName(bundle, symbolName) else {
        return nil
    }
    return addr
}

// ---------------------------------------------------------------------------
// ViewLayer – Native Metal 3 Display Layer with mpv Integration
//
// Architecture (Apple Silicon UMA zero-copy pipeline):
//
//   ┌──────────────────┐    IOSurface     ┌───────────────────┐
//   │  mpv GPU renderer │──(shared UMA)──▸│  Metal 3 Pipeline  │──▸ CAMetalLayer
//   │  (offscreen CGL)  │                 │  (MTLRenderPSO)    │      ▸ Screen
//   └──────────────────┘                 └───────────────────┘
//
// mpv's libmpv render API requires an OpenGL context (MPV_RENDER_API_TYPE_OPENGL).
// A minimal offscreen CGL context with an IOSurface-backed FBO bridges mpv's
// rendered frames to Metal. On Apple Silicon UMA, the IOSurface memory is
// physically shared between CPU and GPU – no staging buffer or GPU-to-GPU copy
// occurs (MTLResourceStorageModeShared).
//
// All display rendering uses statically compiled MTLRenderPipelineState objects
// initialized once at setup, replacing OpenGL's per-frame state machine calls
// (glEnable, glBlendFunc, glDepthMask, etc.) with pre-baked pipeline states.
//
// The Metal command encoding follows the standard per-frame pattern:
//   MTLCommandQueue → MTLCommandBuffer → MTLRenderCommandEncoder
// with loadAction = .clear (replaces glClear) and storeAction = .store.
// ---------------------------------------------------------------------------

class ViewLayer: CAMetalLayer {

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Metal 3 Pipeline (statically compiled at init, never recreated)
    // Replaces OpenGL state machine: glEnable, glBlendFunc, glDepthMask, etc.
    // are baked into the MTLRenderPipelineState at initialization time.
    // ═══════════════════════════════════════════════════════════════════

    private let mtlDevice: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let centerResizePipelineState: MTLComputePipelineState
    private let computeToRenderFence: MTLFence?

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - mpv Interop: Offscreen CGL Context
    // This is NOT used for display rendering. It exists solely because
    // mpv's render API (mpv_render_context) requires an OpenGL context
    // via MPV_RENDER_API_TYPE_OPENGL. All actual screen output is Metal.
    // ═══════════════════════════════════════════════════════════════════

    let cglCtx: CGLContextObj
    let cglPix: CGLPixelFormatObj

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - IOSurface Bridge (Apple Silicon UMA zero-copy)
    // Replaces glGenBuffers/glBindBuffer/glBufferData with IOSurface-backed
    // MTLTexture. Uses MTLResourceStorageModeShared – no staging buffers
    // needed on Apple Silicon's Unified Memory Architecture.
    // ═══════════════════════════════════════════════════════════════════

    private var ioSurface: IOSurface?
    private var metalVideoTexture: MTLTexture?
    private var glFBO: GLuint = 0
    private var glTexture: GLuint = 0
    private var surfaceWidth: Int = 0
    private var surfaceHeight: Int = 0

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Rendering State
    // ═══════════════════════════════════════════════════════════════════

    /// Serial queue for Metal rendering (replaces IINA's mpvGLQueue)
    private let metalRenderQueue = DispatchQueue(label: "com.glassplayer.metal-render",
                                                  qos: .userInitiated)

    private var bufferDepth: GLint = 8
    private let displayLock = NSRecursiveLock()
    private let renderState: UnsafeMutableRawPointer

    /// Back-reference to the MPV controller (weak to avoid retain cycle)
    weak var mpv: MPVController?

    /// Whether the layer has been uninitialized (teardown guard)
    var isUninited = false

    /// Set by VideoView during live window resize to skip expensive IOSurface
    /// recreation.  The existing texture is stretched to the new drawable size
    /// (cheap GPU scale) and the IOSurface is recreated once at final size.
    var isInLiveResize = false

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Anime4K Metal Compute Pipeline
    /// Optional Anime4K upscaling/enhancement pipeline. When active, frames
    /// are processed through compute shaders before display compositing.
    // ═══════════════════════════════════════════════════════════════════

    var anime4KPipeline: Anime4KMetalPipeline?
    /// Current Anime4K preset name (nil = disabled)
    var anime4KPreset: String?
    /// Texture containing Anime4K-processed frame (nil = use source texture)
    private var anime4KOutputTexture: MTLTexture?
    /// Reusable display-sized texture for final center-resize/format conversion.
    private var anime4KPresentationTexture: MTLTexture?

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Frame Capture for Quality Comparison
    /// Captures frames before/after Anime4K processing for SSIM/PSNR comparison
    /// against mpv GLSL reference renders.
    // ═══════════════════════════════════════════════════════════════════

    /// Enable frame capture mode for quality verification
    var frameCaptureEnabled: Bool = false  // Enable manually for quality comparison testing

    /// Output directory for captured frames
    let frameCaptureDirectory = "/tmp/glass-player-captures"

    /// Frame capture counter for unique filenames
    private var frameCaptureCount: Int = 0

    /// Maximum frames to capture (prevents disk space exhaustion)
    let maxFrameCaptures: Int = 10

    /// One-shot capture request used by CLI parity runs.
    private var pendingRenderedCapturePath: String?
    private var pendingRenderedCaptureCallback: ((Bool) -> Void)?
    private let renderedCaptureQueue = DispatchQueue(label: "com.glassplayer.rendered-capture", qos: .utility)

    // Automatic output verification for CLI runs.
    private var autoOutputVerificationEnabled: Bool = false
    private var autoOutputVerificationCompleted: Bool = false
    private var autoOutputVerificationFramesSeen: Int = 0
    private let autoOutputVerificationTriggerFrame: Int = 120
    private var autoOutputVerificationSourceStagingTexture: MTLTexture?
    private var autoOutputVerificationFinalStagingTexture: MTLTexture?
    private let autoOutputVerificationQueue = DispatchQueue(label: "com.glassplayer.output-verification",
                                                            qos: .utility)
    private let centerResizeEnabled: Bool = false
    private let verbosePipelineLogging: Bool = ProcessInfo.processInfo.environment["GLASS_VERBOSE_PIPELINE"] == "1"

    // MARK: - Initialization

    override init() {
        // ── 1. Metal Device & Command Queue (Apple Silicon M-series) ──
        // MTLCommandQueue is allocated once and reused for the lifetime of
        // the layer. A new MTLCommandBuffer is created per frame.
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("[ViewLayer] No Metal device available – Apple Silicon required")
        }
        mtlDevice = device

        guard let queue = device.makeCommandQueue() else {
            fatalError("[ViewLayer] Cannot create MTLCommandQueue")
        }
        commandQueue = queue
        computeToRenderFence = device.makeFence()

        // ── 2. Render Pipeline State (compiled once, reused per frame) ──
        // This single MTLRenderPipelineState replaces all OpenGL per-frame
        // state calls: glEnable, glDisable, glBlendFunc, glDepthMask, etc.
        // The pipeline is compiled from MSL 3.0 shaders.
        let library: MTLLibrary
        if let defaultLib = device.makeDefaultLibrary() {
            // Pre-compiled metallib found in app bundle Resources
            library = defaultLib
        } else {
            // Runtime compilation from embedded MSL source (no Metal toolchain needed)
            library = try! device.makeLibrary(source: ViewLayer.metalShaderSource, options: nil)
        }

        let pipelineDesc = MTLRenderPipelineDescriptor()
        pipelineDesc.label = "GlassPlayer Video Display"
        pipelineDesc.vertexFunction = library.makeFunction(name: "fullscreenVertex")
        pipelineDesc.fragmentFunction = library.makeFunction(name: "textureFragment")
        pipelineDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        // No blending – opaque video surface (replaces glDisable(GL_BLEND))
        pipelineDesc.colorAttachments[0].isBlendingEnabled = false

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDesc)
        } catch {
            fatalError("[ViewLayer] MTLRenderPipelineState creation failed: \(error)")
        }

        guard let centerResizeFn = library.makeFunction(name: "centerResizeKernel") else {
            fatalError("[ViewLayer] Missing centerResizeKernel in Metal library")
        }
        do {
            centerResizePipelineState = try device.makeComputePipelineState(function: centerResizeFn)
        } catch {
            fatalError("[ViewLayer] centerResizeKernel pipeline creation failed: \(error)")
        }

        // ── 3. Aligned Render State (lock-free frame flags) ──
        guard let state = GPAlignedRenderStateCreate() else {
            fatalError("[ViewLayer] Failed to allocate aligned render state")
        }
        renderState = state

        // ── 4. Offscreen CGL Context (mpv render API interop only) ──
        // This minimal CGL context is never used for display. It exists
        // solely because mpv_render_context_create requires OpenGL.
        // No OpenGL state machine calls (glEnable, etc.) are made.
        var pix: CGLPixelFormatObj?
        var npix: GLint = 0

        // Hardware-accelerated 3.2 Core profile – minimal for mpv's GPU renderer
        var attrs: [CGLPixelFormatAttribute] = [
            kCGLPFAOpenGLProfile,
            CGLPixelFormatAttribute(kCGLOGLPVersion_3_2_Core.rawValue),
            kCGLPFAAccelerated,
            kCGLPFAAllowOfflineRenderers,
            kCGLPFASupportsAutomaticGraphicsSwitching,
            CGLPixelFormatAttribute(0)
        ]
        var err = CGLChoosePixelFormat(attrs, &pix, &npix)

        // Fallback: simplified attributes
        if err != kCGLNoError || pix == nil {
            attrs = [
                kCGLPFAOpenGLProfile,
                CGLPixelFormatAttribute(kCGLOGLPVersion_3_2_Core.rawValue),
                kCGLPFAAccelerated,
                CGLPixelFormatAttribute(0)
            ]
            err = CGLChoosePixelFormat(attrs, &pix, &npix)
        }

        // Last resort: legacy profile
        if err != kCGLNoError || pix == nil {
            attrs = [
                kCGLPFAOpenGLProfile,
                CGLPixelFormatAttribute(kCGLOGLPVersion_Legacy.rawValue),
                CGLPixelFormatAttribute(0)
            ]
            err = CGLChoosePixelFormat(attrs, &pix, &npix)
        }

        guard err == kCGLNoError, let pixelFormat = pix else {
            fatalError("[ViewLayer] Cannot create CGL pixel format: \(err.rawValue)")
        }
        cglPix = pixelFormat

        var ctx: CGLContextObj?
        CGLCreateContext(pixelFormat, nil, &ctx)
        guard let context = ctx else {
            fatalError("[ViewLayer] Cannot create offscreen CGL context")
        }

        // Multi-threaded GL engine – mpv renders off the main thread
        CGLEnable(context, kCGLCEMPEngine)
        cglCtx = context

        super.init()

        // ── Configure CAMetalLayer ──
        self.device = mtlDevice
        self.pixelFormat = .bgra8Unorm
        // framebufferOnly = true: we only render to drawables, never read back
        // (Metal can optimize internal storage for display-only surfaces)
        self.framebufferOnly = true
        // Enable EDR headroom for HDR content on XDR displays
        self.wantsExtendedDynamicRangeContent = true
        // Display P3 wide gamut colorspace – matches the MacBook Pro's native
        // panel gamut. mpv renders with target-prim=display-p3 so the output
        // is in the P3 gamut with standard gamma, giving maximum color fidelity.
        // SDR content: full brightness, rich P3 colors.
        // HDR content: tone-mapped to SDR by mpv with excellent quality.
        if let p3 = CGColorSpace(name: CGColorSpace.displayP3) {
            self.colorspace = p3
        }
        self.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        self.backgroundColor = NSColor.black.cgColor
        // Allow 3 drawables in flight to prevent stalls during resize
        self.maximumDrawableCount = 3

        // CLI quality gate: run one-shot luminance verification only for
        // explicit capture workflows, not general playback.
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--capture-out") ||
            ProcessInfo.processInfo.environment["GLASS_AUTOVERIFY_OUTPUT"] == "1" {
            autoOutputVerificationEnabled = true
            NSLog("[AutoVerify] Enabled automatic non-black output verification")
        }
    }

    /// Request a one-shot capture of the displayed texture after Metal processing.
    /// This captures the true post-processing output used for presentation.
    func requestRenderedFrameCapture(to outputPath: String,
                                     completion: @escaping (Bool) -> Void) {
        let normalizedPath = (outputPath as NSString).expandingTildeInPath
        metalRenderQueue.async { [weak self] in
            guard let self = self else {
                completion(false)
                return
            }

            self.pendingRenderedCapturePath = normalizedPath
            self.pendingRenderedCaptureCallback = completion
            self.update(force: true)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    deinit {
        destroyIOSurface()
        CGLReleaseContext(cglCtx)
        CGLReleasePixelFormat(cglPix)
        GPAlignedRenderStateDestroy(renderState)
        anime4KPipeline = nil
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Anime4K Pipeline Control
    // ═══════════════════════════════════════════════════════════════════

    /// Enable Anime4K processing with the specified preset
    func enableAnime4K(preset: String) -> Bool {
        NSLog("[ViewLayer] enableAnime4K called with preset: %@", preset)

        // Handle "Auto (Recommended)" by mapping to Mode A (Fast)
        let actualPreset = (preset == "Auto (Recommended)") ? "Mode A (Fast)" : preset
        let layerDims = getLayerDimensions()
        let dims = getPreferredRenderInputDimensions(layerWidth: layerDims.width,
                                 layerHeight: layerDims.height)

        guard anime4KPipeline == nil else {
            NSLog("[ViewLayer] Pipeline already exists, checking preset change...")
            // Already enabled, just change preset if different
            if anime4KPreset != actualPreset {
                NSLog("[ViewLayer] Preset changed from %@ to %@", anime4KPreset ?? "nil", actualPreset)
                anime4KPipeline?.deactivate()
                if let pipeline = Anime4KMetalPipeline(device: mtlDevice) {
                    if let appliedPreset = activatePresetWithFallback(pipeline,
                                                                      requestedPreset: actualPreset,
                                                                      inputWidth: Int(dims.width),
                                                                      inputHeight: Int(dims.height)) {
                        anime4KPipeline = pipeline
                        anime4KPreset = appliedPreset
                        NSLog("[ViewLayer] Anime4K preset changed to: %@", appliedPreset)
                        // Force a refresh to apply the new preset
                        update(force: true)
                        return true
                    } else {
                        NSLog("[ViewLayer] activatePreset failed")
                    }
                } else {
                    NSLog("[ViewLayer] Failed to create new pipeline")
                }
            }
            return false
        }

        NSLog("[ViewLayer] Creating new Anime4K pipeline...")
        // Create new pipeline
        guard let pipeline = Anime4KMetalPipeline(device: mtlDevice) else {
            NSLog("[ViewLayer] ERROR: Failed to create Anime4K pipeline (makeLibrary failed?)")
            return false
        }
        NSLog("[ViewLayer] Pipeline created successfully")

        NSLog("[ViewLayer] Layer dimensions: %dx%d", dims.width, dims.height)
          if let appliedPreset = activatePresetWithFallback(pipeline,
                                            requestedPreset: actualPreset,
                                            inputWidth: Int(dims.width),
                                            inputHeight: Int(dims.height)) {
            anime4KPipeline = pipeline
            anime4KPreset = appliedPreset
            let outDims = pipeline.getOutputDimensions(inputWidth: Int(dims.width), inputHeight: Int(dims.height))
            NSLog("[ViewLayer] SUCCESS: Anime4K enabled: %@ (%dx%d → %dx%d)",
                appliedPreset, dims.width, dims.height, outDims.width, outDims.height)
            // Force a refresh to apply the new preset
            update(force: true)
            return true
        } else {
            NSLog("[ViewLayer] ERROR: activatePreset returned false")
        }

        return false
    }

    /// Try requested preset first; if activation fails and it's an HQ mode,
    /// fallback once to the matching Fast mode.
    private func activatePresetWithFallback(_ pipeline: Anime4KMetalPipeline,
                                            requestedPreset: String,
                                            inputWidth: Int,
                                            inputHeight: Int) -> String? {
        if pipeline.activatePreset(requestedPreset, inputWidth: inputWidth, inputHeight: inputHeight) {
            return requestedPreset
        }

        guard requestedPreset.contains("(HQ)") else { return nil }
        let fastPreset = requestedPreset.replacingOccurrences(of: "(HQ)", with: "(Fast)")
        guard ViewLayer.availableAnime4KPresets.contains(fastPreset) else { return nil }

        NSLog("[ViewLayer] Requested preset %@ failed, trying fallback %@", requestedPreset, fastPreset)
        guard pipeline.activatePreset(fastPreset, inputWidth: inputWidth, inputHeight: inputHeight) else {
            return nil
        }
        return fastPreset
    }

    /// Disable Anime4K processing
    func disableAnime4K() {
        anime4KPipeline?.deactivate()
        anime4KPipeline = nil
        anime4KPreset = nil
        anime4KOutputTexture = nil
        NSLog("[ViewLayer] Anime4K disabled")
    }

    /// Get list of available Anime4K presets
    static var availableAnime4KPresets: [String] {
        return Anime4KPresetRegistry.allPresetNames()
    }

    /// Get current layer dimensions for Anime4K processing
    private func getLayerDimensions() -> (width: Int, height: Int) {
        let scale = contentsScale
        let w = max(1, Int(bounds.width * scale))
        let h = max(1, Int(bounds.height * scale))
        return (w, h)
    }

    /// Resolve the preferred mpv render input size.
    /// When Anime4K is active, prefer video display dimensions so the pipeline
    /// enhances native content rather than an already window-upscaled frame.
    private func getPreferredRenderInputDimensions(layerWidth: Int,
                                                   layerHeight: Int) -> (width: Int, height: Int) {
        guard anime4KPipeline?.isActive == true, let mpv else {
            return (layerWidth, layerHeight)
        }

        let videoDims = mpv.getNativeVideoDimensions()
        let vw = max(4, Int(videoDims.width))
        let vh = max(4, Int(videoDims.height))

        if vw > 0 && vh > 0 {
            return (min(vw, layerWidth), min(vh, layerHeight))
        }

        return (layerWidth, layerHeight)
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - IOSurface Management (Apple Silicon UMA zero-copy bridge)
    //
    // Replaces OpenGL buffer management (glGenBuffers, glBindBuffer,
    // glBufferData) with IOSurface + MTLTexture using
    // MTLResourceStorageModeShared for Apple Silicon UMA.
    // No staging buffers are needed – CPU and GPU share the same memory.
    // ═══════════════════════════════════════════════════════════════════

    /// Create or recreate the IOSurface at the given dimensions.
    /// Both the OpenGL FBO (for mpv) and Metal texture (for display)
    /// are backed by the same IOSurface memory – zero-copy on UMA.
    /// Phase 1B: UMA Zero-Copy with Accelerate-based bounds clamping.
    private func createIOSurface(width: Int, height: Int) {
        // Clamp to valid range via Accelerate (Phase 1C)
        let width = Int(clampRangeAccelerate(Double(width), lower: 4, upper: 16384))
        let height = Int(clampRangeAccelerate(Double(height), lower: 4, upper: 16384))

        // Skip recreation if already at the correct size
        if width == surfaceWidth && height == surfaceHeight && ioSurface != nil {
            return
        }

        // Tear down existing resources
        destroyIOSurface()

        // ── Create IOSurface (UMA shared memory) ──
        let bytesPerPixel = 4  // BGRA8 (4 channels × 1 byte)
        // Align bytesPerRow to Metal's minimum texture alignment to prevent
        // _mtlValidateStrideTextureParameters assertion during resize.
        let alignment = mtlDevice.minimumLinearTextureAlignment(for: .bgra8Unorm)
        let rawBytesPerRow = width * bytesPerPixel
        let bytesPerRow = ((rawBytesPerRow + alignment - 1) / alignment) * alignment

        let properties: [IOSurfacePropertyKey: Any] = [
            .width: width,
            .height: height,
            .bytesPerElement: bytesPerPixel,
            .bytesPerRow: bytesPerRow,
            .pixelFormat: kCVPixelFormatType_32BGRA,
            .allocSize: bytesPerRow * height,
        ]

        guard let surface = IOSurface(properties: properties) else {
            NSLog("[ViewLayer] Failed to create IOSurface %d×%d", width, height)
            return
        }
        ioSurface = surface
        surfaceWidth = width
        surfaceHeight = height

        // ── OpenGL side: Create texture + FBO from IOSurface ──
        // This is the minimal GL setup for mpv's render target.
        // No OpenGL state machine calls (glEnable, glBlendFunc, etc.)
        CGLLockContext(cglCtx)
        CGLSetCurrentContext(cglCtx)

        glGenTextures(1, &glTexture)
        glBindTexture(GLenum(GL_TEXTURE_RECTANGLE), glTexture)

        // Bind IOSurface to the GL texture – same physical memory on UMA
        CGLTexImageIOSurface2D(cglCtx,
                               GLenum(GL_TEXTURE_RECTANGLE),
                               GLenum(GL_RGBA8),
                               GLsizei(width), GLsizei(height),
                               GLenum(GL_BGRA),
                               GLenum(GL_UNSIGNED_INT_8_8_8_8_REV),
                               surface, 0)

        // Create FBO with IOSurface-backed texture as color attachment
        glGenFramebuffers(1, &glFBO)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), glFBO)
        glFramebufferTexture2D(GLenum(GL_FRAMEBUFFER),
                               GLenum(GL_COLOR_ATTACHMENT0),
                               GLenum(GL_TEXTURE_RECTANGLE),
                               glTexture, 0)

        let status = glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER))
        if status != GLenum(GL_FRAMEBUFFER_COMPLETE) {
            NSLog("[ViewLayer] FBO incomplete: status=%d", status)
        }

        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
        glBindTexture(GLenum(GL_TEXTURE_RECTANGLE), 0)
        CGLUnlockContext(cglCtx)

        // ── Metal side: Create texture from same IOSurface (zero-copy) ──
        // Uses MTLResourceStorageModeShared – Apple Silicon UMA means CPU
        // and GPU access the same physical memory. No staging buffer needed.
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        texDesc.usage = .shaderRead
        // storageMode is determined by the IOSurface on UMA hardware

        metalVideoTexture = mtlDevice.makeTexture(
            descriptor: texDesc,
            iosurface: surface,
            plane: 0
        )

        if metalVideoTexture == nil {
            NSLog("[ViewLayer] Failed to create Metal texture from IOSurface")
        }
    }

    /// Destroy IOSurface and all associated GPU resources
    private func destroyIOSurface() {
        // Metal textures released via ARC
        metalVideoTexture = nil

        // Clean up OpenGL FBO + texture
        if glFBO != 0 || glTexture != 0 {
            CGLLockContext(cglCtx)
            CGLSetCurrentContext(cglCtx)
            if glFBO != 0 {
                glDeleteFramebuffers(1, &glFBO)
                glFBO = 0
            }
            if glTexture != 0 {
                glDeleteTextures(1, &glTexture)
                glTexture = 0
            }
            CGLUnlockContext(cglCtx)
        }

        ioSurface = nil
        surfaceWidth = 0
        surfaceHeight = 0
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Viewport Management
    // ═══════════════════════════════════════════════════════════════════

    /// Recreate IOSurface when the layer resizes.
    /// Replaces the OpenGL glGetIntegerv(GL_VIEWPORT) per-frame query
    /// with a single resize-driven update.
    override func layoutSublayers() {
        super.layoutSublayers()

        // Ignore resize/layout notifications after teardown.
        guard !isUninited else { return }

        // Update drawable size for Retina displays
        let scale = contentsScale
        let bw = bounds.width * scale
        let bh = bounds.height * scale
        // Guard against NaN, Inf, or zero during resize transitions
        guard bw.isFinite && bh.isFinite && bw > 0 && bh > 0 else { return }
        let w = max(4, Int(bw))
        let h = max(4, Int(bh))
        drawableSize = CGSize(width: CGFloat(w), height: CGFloat(h))

        // During live window resize, skip the expensive IOSurface tear-down /
        // recreation.  Metal will scale the existing texture to fill the new
        // drawable size (cheap GPU stretch), and we recreate at the final size
        // once the resize gesture ends (see liveResizeEnded()).
        guard !isInLiveResize else { return }

        // Recreate IOSurface if viewport dimensions changed.
        // Lock to prevent race with renderFrame() on metalRenderQueue.
        let preferred = getPreferredRenderInputDimensions(layerWidth: w, layerHeight: h)
        if preferred.width != surfaceWidth || preferred.height != surfaceHeight {
            displayLock.lock()
            createIOSurface(width: preferred.width, height: preferred.height)
            displayLock.unlock()
        }
    }

    /// Called once when the live resize gesture ends.
    /// Recreates the IOSurface at the final viewport size so subsequent
    /// frames render at native resolution.
    func liveResizeEnded() {
        guard !isUninited else { return }
        isInLiveResize = false
        let scale = contentsScale
        let bw = bounds.width * scale
        let bh = bounds.height * scale
        guard bw.isFinite && bh.isFinite && bw > 0 && bh > 0 else { return }
        let w = max(4, Int(bw))
        let h = max(4, Int(bh))
        drawableSize = CGSize(width: CGFloat(w), height: CGFloat(h))
        let preferred = getPreferredRenderInputDimensions(layerWidth: w, layerHeight: h)
        if preferred.width != surfaceWidth || preferred.height != surfaceHeight {
            displayLock.lock()
            createIOSurface(width: preferred.width, height: preferred.height)
            displayLock.unlock()
        }
        // Force a fresh render at the new resolution
        update(force: true)
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - update() – Called from mpv's render-update callback
    // ═══════════════════════════════════════════════════════════════════

    func update(force: Bool = false) {
        metalRenderQueue.async { [weak self] in
            guard let self = self, !self.isUninited else { return }
            GPAlignedRenderStateMarkUpdate(self.renderState, force ? 1 : 0)
            self.renderFrame()
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Frame Rendering (Metal 3 Command Encoding)
    //
    // Replaces the OpenGL game loop (glClear → glDrawArrays → glFlush)
    // with Metal's command buffer pattern:
    //   MTLCommandQueue → MTLCommandBuffer → MTLRenderCommandEncoder
    //
    // The MTLRenderPassDescriptor uses:
    //   .loadAction  = .clear   (replaces glClear(GL_COLOR_BUFFER_BIT))
    //   .storeAction = .store   (preserve rendered content for display)
    // ═══════════════════════════════════════════════════════════════════

    /// Render one frame: mpv → IOSurface → Metal → CAMetalLayer → Screen
    private func renderFrame() {
        displayLock.lock()
        defer { displayLock.unlock() }

        guard !isUninited else { return }
        guard let mpv = mpv, let renderCtx = mpv.mpvRenderContext else { return }

        // Check if a new frame should be rendered
        let forceRender = GPAlignedRenderStateGetForceRender(renderState) != 0
        guard forceRender || mpv.shouldRenderUpdateFrame() else { return }

        GPAlignedRenderStateClearFrameFlags(renderState)

        // Ensure IOSurface exists at the correct viewport size
        if surfaceWidth == 0 || surfaceHeight == 0 || ioSurface == nil {
            let scale = contentsScale
            let w = max(1, Int(bounds.width * scale))
            let h = max(1, Int(bounds.height * scale))
            guard w > 0 && h > 0 else { return }
            let preferred = getPreferredRenderInputDimensions(layerWidth: w, layerHeight: h)
            createIOSurface(width: preferred.width, height: preferred.height)
        }

        guard glFBO != 0, let metalTex = metalVideoTexture else {
            // Cannot render – skip this mpv frame to prevent stall
            skipMPVFrame(renderCtx)
            return
        }

        // ── Step 1: mpv renders video frame to IOSurface-backed FBO ──
        renderMPVToIOSurface(renderCtx)

        // ── Step 2: Metal displays the IOSurface content on screen ──
        displayWithMetal(metalTex)
    }

    /// Have mpv render the current video frame to the IOSurface-backed OpenGL FBO.
    /// The CGL context is locked for the duration of the render call.
    private func renderMPVToIOSurface(_ renderCtx: OpaquePointer) {
        CGLLockContext(cglCtx)
        CGLSetCurrentContext(cglCtx)

        var fboData = mpv_opengl_fbo(
            fbo: Int32(glFBO),
            w: Int32(surfaceWidth),
            h: Int32(surfaceHeight),
            internal_format: 0
        )

        var flip: CInt = 0  // No flip: OpenGL FBO row 0 = bottom; Metal UV (0,0) = top-left → correct orientation

        withUnsafeMutablePointer(to: &fboData) { dataPtr in
            withUnsafeMutablePointer(to: &flip) { flipPtr in
                withUnsafeMutablePointer(to: &bufferDepth) { depthPtr in
                    var params: [mpv_render_param] = [
                        mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO,
                                         data: .init(dataPtr)),
                        mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y,
                                         data: .init(flipPtr)),
                        mpv_render_param(type: MPV_RENDER_PARAM_DEPTH,
                                         data: .init(depthPtr)),
                        mpv_render_param()   // sentinel
                    ]
                    mpv_render_context_render(renderCtx, &params)
                }
            }
        }

        // Wait for GL commands to complete before Metal reads the IOSurface.
        // glFinish() guarantees the FBO write is done; glFlush() only submits.
        glFinish()

        CGLUnlockContext(cglCtx)
    }

    /// Render the IOSurface-backed Metal texture to the CAMetalLayer drawable.
    /// This is the Metal 3 command encoding path:
    ///   MTLCommandBuffer → MTLRenderCommandEncoder → present drawable.
    private func displayWithMetal(_ videoTexture: MTLTexture) {
        // ── Allocate command buffer (one per frame) ──
        guard let cmdBuf = commandQueue.makeCommandBuffer() else { return }
        cmdBuf.label = "GlassPlayer Frame"

        // ── Process through Anime4K pipeline if active ──
        var finalTexture = videoTexture
        var computeWorkSubmitted = false

        if let pipeline = anime4KPipeline, pipeline.isActive {
            // Process frame through Anime4K compute shaders
            if let processedTexture = pipeline.processFrame(
                    sourceTexture: videoTexture,
                    commandBuffer: cmdBuf,
                    completionFence: computeToRenderFence) {
                finalTexture = processedTexture
                anime4KOutputTexture = processedTexture
                computeWorkSubmitted = true
                if verbosePipelineLogging {
                    NSLog("[ViewLayer] Anime4K output texture: %dx%d, format=%@",
                          processedTexture.width,
                          processedTexture.height,
                          String(describing: processedTexture.pixelFormat))
                }

                // Capture frames for quality comparison if enabled (async to avoid blocking)
                if frameCaptureEnabled {
                    DispatchQueue.global(qos: .background).async { [weak self] in
                        self?.captureFrame(sourceTexture: videoTexture, outputTexture: processedTexture)
                    }
                }
            } else {
                NSLog("[ViewLayer] ERROR: Anime4K processFrame returned nil!")
            }
        } else if anime4KPipeline != nil, verbosePipelineLogging {
            NSLog("[ViewLayer] Anime4K pipeline exists but NOT active (may be initializing)")
        }

        // Acquire drawable as late as possible to avoid holding scarce drawable
        // resources while compute work is still being encoded.
        guard let drawable = nextDrawable() else { return }

        // Match Anime4KMetal display architecture: center-resize Anime4K output
        // into a drawable-sized presentation texture before fragment sampling.
        if centerResizeEnabled,
           computeWorkSubmitted,
           let presentationTexture = ensurePresentationTexture(width: drawable.texture.width,
                                                               height: drawable.texture.height) {
            encodeCenterResize(input: finalTexture,
                               output: presentationTexture,
                               commandBuffer: cmdBuf)
            finalTexture = presentationTexture
        }

        runAutoOutputVerificationIfNeeded(sourceTexture: videoTexture,
                          finalTexture: finalTexture,
                          commandBuffer: cmdBuf)

        maybeScheduleRenderedCapture(texture: finalTexture, commandBuffer: cmdBuf)

        // ── Configure render pass descriptor ──
        // .loadAction = .clear replaces glClear(GL_COLOR_BUFFER_BIT)
        // .storeAction = .store preserves rendered content for presentation
        let passDesc = MTLRenderPassDescriptor()
        passDesc.colorAttachments[0].texture = drawable.texture
        passDesc.colorAttachments[0].loadAction = .clear
        passDesc.colorAttachments[0].storeAction = .store
        passDesc.colorAttachments[0].clearColor = MTLClearColor(
            red: 0, green: 0, blue: 0, alpha: 1
        )

        // ── Encode render pass ──
        guard let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: passDesc) else { return }
        encoder.label = "Video Display Pass"

        // Only wait for compute work if it was actually submitted
        // This prevents unnecessary stalls when Anime4K is not active
        if computeWorkSubmitted, let fence = computeToRenderFence {
            encoder.waitForFence(fence, before: .fragment)
        }

        // Bind statically compiled pipeline state
        // (replaces per-frame glEnable/glDisable/glBlendFunc state machine)
        encoder.setRenderPipelineState(pipelineState)

        // Bind video frame texture (IOSurface-backed, zero-copy on UMA)
        // Replaces OpenGL texture binding (glBindTexture, glActiveTexture)
        encoder.setFragmentTexture(finalTexture, index: 0)

        // Draw fullscreen quad – vertex positions generated in shader from vertex_id
        // Replaces glDrawArrays/glDrawElements with no VBO needed
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

        encoder.endEncoding()

        // Present drawable (replaces OpenGL buffer swap / CAOpenGLLayer display)
        cmdBuf.present(drawable)
        cmdBuf.commit()
    }

    private func maybeScheduleRenderedCapture(texture: MTLTexture,
                                              commandBuffer: MTLCommandBuffer) {
        guard let outputPath = pendingRenderedCapturePath else { return }
        let callback = pendingRenderedCaptureCallback
        pendingRenderedCapturePath = nil
        pendingRenderedCaptureCallback = nil

        commandBuffer.addCompletedHandler { [weak self] _ in
            guard let self = self else {
                callback?(false)
                return
            }

            self.renderedCaptureQueue.async {
                let success = self.saveTexture(texture, toPNGAtPath: outputPath)
                callback?(success)
            }
        }
    }

    private func runAutoOutputVerificationIfNeeded(sourceTexture: MTLTexture,
                                                   finalTexture: MTLTexture,
                                                   commandBuffer: MTLCommandBuffer) {
        guard autoOutputVerificationEnabled,
              !autoOutputVerificationCompleted else { return }

        autoOutputVerificationFramesSeen += 1
        guard autoOutputVerificationFramesSeen >= autoOutputVerificationTriggerFrame else { return }
        autoOutputVerificationCompleted = true

        scheduleAutoOutputVerification(texture: sourceTexture,
                                       textureLabel: "Source",
                                       sourceStaging: true,
                                       commandBuffer: commandBuffer)
        scheduleAutoOutputVerification(texture: finalTexture,
                                       textureLabel: "Final",
                                       sourceStaging: false,
                                       commandBuffer: commandBuffer)
    }

    private func scheduleAutoOutputVerification(texture: MTLTexture,
                                                textureLabel: String,
                                                sourceStaging: Bool,
                                                commandBuffer: MTLCommandBuffer) {
        guard let stagingTexture = ensureAutoOutputVerificationStagingTexture(width: texture.width,
                                                                              height: texture.height,
                                                                              pixelFormat: texture.pixelFormat,
                                                                              sourceStaging: sourceStaging) else {
            NSLog("[AutoVerify] FAIL: Unable to create %@ staging texture", textureLabel)
            return
        }

        guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
            NSLog("[AutoVerify] FAIL: Unable to create blit encoder for %@ verification", textureLabel)
            return
        }

        blitEncoder.label = "Auto Verify \(textureLabel) Copy"
        blitEncoder.copy(from: texture,
                         sourceSlice: 0,
                         sourceLevel: 0,
                         sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                         sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1),
                         to: stagingTexture,
                         destinationSlice: 0,
                         destinationLevel: 0,
                         destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blitEncoder.endEncoding()

        let width = texture.width
        let height = texture.height
        let pixelFormat = texture.pixelFormat
        commandBuffer.addCompletedHandler { [weak self] _ in
            guard let self = self else { return }
            self.autoOutputVerificationQueue.async {
                self.evaluateAutoOutputVerification(texture: stagingTexture,
                                                    textureLabel: textureLabel,
                                                    width: width,
                                                    height: height,
                                                    pixelFormat: pixelFormat)
            }
        }
    }

    private func ensureAutoOutputVerificationStagingTexture(width: Int,
                                                            height: Int,
                                                            pixelFormat: MTLPixelFormat,
                                                            sourceStaging: Bool) -> MTLTexture? {
        guard pixelFormat == .bgra8Unorm ||
              pixelFormat == .rgba8Unorm ||
              pixelFormat == .rgba16Float else {
            NSLog("[AutoVerify] FAIL: Unsupported pixel format %@",
                  String(describing: pixelFormat))
            return nil
        }

        let existingTexture = sourceStaging ?
            autoOutputVerificationSourceStagingTexture : autoOutputVerificationFinalStagingTexture
        if let existing = existingTexture,
           existing.width == width,
           existing.height == height,
           existing.pixelFormat == pixelFormat {
            return existing
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat,
                                                                  width: width,
                                                                  height: height,
                                                                  mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.shaderRead, .shaderWrite]

        let texture = mtlDevice.makeTexture(descriptor: descriptor)
        texture?.label = sourceStaging ?
            "Auto Output Verification Source Staging" :
            "Auto Output Verification Final Staging"
        if sourceStaging {
            autoOutputVerificationSourceStagingTexture = texture
        } else {
            autoOutputVerificationFinalStagingTexture = texture
        }
        return texture
    }

    private func evaluateAutoOutputVerification(texture: MTLTexture,
                                                textureLabel: String,
                                                width: Int,
                                                height: Int,
                                                pixelFormat: MTLPixelFormat) {
        let bytesPerPixel: Int
        switch pixelFormat {
        case .bgra8Unorm, .rgba8Unorm:
            bytesPerPixel = 4
        case .rgba16Float:
            bytesPerPixel = 8
        default:
            NSLog("[AutoVerify] FAIL: %@ unsupported format %@",
                textureLabel, String(describing: pixelFormat))
            return
        }

        let bytesPerRow = width * bytesPerPixel
        let bytesPerImage = bytesPerRow * height
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bytesPerImage)
        defer { buffer.deallocate() }

        let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                               size: MTLSize(width: width, height: height, depth: 1))
        texture.getBytes(buffer,
                         bytesPerRow: bytesPerRow,
                         bytesPerImage: bytesPerImage,
                         from: region,
                         mipmapLevel: 0,
                         slice: 0)

        let sampleGrid = 64
        let stepX = max(1, width / sampleGrid)
        let stepY = max(1, height / sampleGrid)

        var sampleCount: Int = 0
        var nonZeroCount: Int = 0
        var luminanceSum: Float = 0
        var luminanceMax: Float = 0

        func halfFloat(_ lo: UInt8, _ hi: UInt8) -> Float {
            let bits = UInt16(lo) | (UInt16(hi) << 8)
            return Float(Float16(bitPattern: bits))
        }

        for y in stride(from: 0, to: height, by: stepY) {
            for x in stride(from: 0, to: width, by: stepX) {
                let i = y * bytesPerRow + x * bytesPerPixel

                let r: Float
                let g: Float
                let b: Float

                switch pixelFormat {
                case .bgra8Unorm:
                    b = Float(buffer[i]) / 255.0
                    g = Float(buffer[i + 1]) / 255.0
                    r = Float(buffer[i + 2]) / 255.0
                case .rgba8Unorm:
                    r = Float(buffer[i]) / 255.0
                    g = Float(buffer[i + 1]) / 255.0
                    b = Float(buffer[i + 2]) / 255.0
                case .rgba16Float:
                    r = halfFloat(buffer[i], buffer[i + 1])
                    g = halfFloat(buffer[i + 2], buffer[i + 3])
                    b = halfFloat(buffer[i + 4], buffer[i + 5])
                default:
                    continue
                }

                let luminance = max(0, 0.2126 * r + 0.7152 * g + 0.0722 * b)
                luminanceSum += luminance
                luminanceMax = max(luminanceMax, luminance)
                sampleCount += 1
                if luminance > 0.002 { nonZeroCount += 1 }
            }
        }

        guard sampleCount > 0 else {
            NSLog("[AutoVerify] FAIL: %@ no samples collected", textureLabel)
            return
        }

        let mean = luminanceSum / Float(sampleCount)
        let nonZeroRatio = Float(nonZeroCount) / Float(sampleCount)
        let passed = luminanceMax > 0.02 && nonZeroRatio > 0.01

        NSLog("[AutoVerify] %@ stats: mean=%.6f max=%.6f nonZero=%.4f dims=%dx%d format=%@",
              textureLabel, mean, luminanceMax, nonZeroRatio, width, height, String(describing: pixelFormat))

        if passed {
            NSLog("[AutoVerify] PASS: %@ contains visible non-black content", textureLabel)
        } else {
            NSLog("[AutoVerify] FAIL: %@ appears black or near-black", textureLabel)
        }
    }

    private func ensurePresentationTexture(width: Int, height: Int) -> MTLTexture? {
        if let existing = anime4KPresentationTexture,
           existing.width == width,
           existing.height == height,
           existing.pixelFormat == .rgba16Float {
            return existing
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private

        anime4KPresentationTexture = mtlDevice.makeTexture(descriptor: descriptor)
        anime4KPresentationTexture?.label = "Anime4K Presentation Texture"
        return anime4KPresentationTexture
    }

    private func encodeCenterResize(input: MTLTexture,
                                    output: MTLTexture,
                                    commandBuffer: MTLCommandBuffer) {
        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else { return }
        computeEncoder.label = "Anime4K CenterResize"
        computeEncoder.setComputePipelineState(centerResizePipelineState)
        computeEncoder.setTexture(input, index: 0)
        computeEncoder.setTexture(output, index: 1)

        let threadsPerThreadgroup = recommendedThreadgroupSize(for: centerResizePipelineState)
        let threadgroupsPerGrid = MTLSize(
            width: (output.width + threadsPerThreadgroup.width - 1) / threadsPerThreadgroup.width,
            height: (output.height + threadsPerThreadgroup.height - 1) / threadsPerThreadgroup.height,
            depth: 1
        )
        computeEncoder.dispatchThreadgroups(threadgroupsPerGrid,
                                            threadsPerThreadgroup: threadsPerThreadgroup)
        computeEncoder.endEncoding()
    }

    private func recommendedThreadgroupSize(for pipeline: MTLComputePipelineState) -> MTLSize {
        let width = max(1, pipeline.threadExecutionWidth)
        let maxHeight = max(1, pipeline.maxTotalThreadsPerThreadgroup / width)
        let targetThreads = 256
        let preferredHeight = max(1, targetThreads / width)
        let height = min(maxHeight, preferredHeight)
        return MTLSize(width: width, height: height, depth: 1)
    }

    /// Skip an mpv frame to prevent renderer stall when display isn't possible.
    /// Replaces the OpenGL frame-skip path from the original displayOnQueue().
    private func skipMPVFrame(_ renderCtx: OpaquePointer) {
        CGLLockContext(cglCtx)
        CGLSetCurrentContext(cglCtx)

        var skip: CInt = 1
        withUnsafeMutablePointer(to: &skip) { skipPtr in
            var params: [mpv_render_param] = [
                mpv_render_param(type: MPV_RENDER_PARAM_SKIP_RENDERING,
                                 data: .init(skipPtr)),
                mpv_render_param()
            ]
            mpv_render_context_render(renderCtx, &params)
        }

        CGLUnlockContext(cglCtx)
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Frame Capture for Quality Comparison
    // ═══════════════════════════════════════════════════════════════════

    /// Extension to convert MTLTexture to CGImage for frame capture
    /// This is a duplicate of the FrameCapture utility - included here for integration
    private func textureToCGImage(_ texture: MTLTexture) -> CGImage? {
        if texture.pixelFormat == .bgra8Unorm || texture.pixelFormat == .rgba8Unorm {
            return textureToCGImage8Bit(texture)
        }

        if texture.pixelFormat == .rgba16Float {
            return textureToCGImageRGBA16Float(texture)
        }

        NSLog("[FrameCapture] Unsupported pixel format for capture: %@", String(describing: texture.pixelFormat))
        return nil
    }

    private func textureToCGImage8Bit(_ texture: MTLTexture) -> CGImage? {

        // Copy to staging texture for CPU read
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: texture.pixelFormat,
            width: texture.width,
            height: texture.height,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = [.shaderRead, .shaderWrite]

        guard let stagingTexture = mtlDevice.makeTexture(descriptor: descriptor) else {
            NSLog("[FrameCapture] Failed to create staging texture")
            return nil
        }

        // Copy from source to staging
        guard let commandQueue = mtlDevice.makeCommandQueue(),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeBlitCommandEncoder() else {
            NSLog("[FrameCapture] Failed to create blit encoder")
            return nil
        }

        encoder.copy(from: texture, to: stagingTexture)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let bytesPerPixel = 4
        let bytesPerRow = texture.width * bytesPerPixel
        let bytesPerImage = bytesPerRow * texture.height

        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bytesPerImage)
        defer { buffer.deallocate() }

        let region = MTLRegion(
            origin: MTLOrigin(x: 0, y: 0, z: 0),
            size: MTLSize(width: texture.width, height: texture.height, depth: 1)
        )

        stagingTexture.getBytes(
            buffer,
            bytesPerRow: bytesPerRow,
            bytesPerImage: bytesPerImage,
            from: region,
            mipmapLevel: 0,
            slice: 0
        )

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: buffer,
                width: texture.width,
                height: texture.height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: texture.pixelFormat == .bgra8Unorm ?
                    CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue :
                    CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            NSLog("[FrameCapture] Failed to create CGContext")
            return nil
        }

        return context.makeImage()
    }

    private func textureToCGImageRGBA16Float(_ texture: MTLTexture) -> CGImage? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: texture.width,
            height: texture.height,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = [.shaderRead, .shaderWrite]

        guard let stagingTexture = mtlDevice.makeTexture(descriptor: descriptor) else {
            NSLog("[FrameCapture] Failed to create rgba16 staging texture")
            return nil
        }

        guard let commandQueue = mtlDevice.makeCommandQueue(),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeBlitCommandEncoder() else {
            NSLog("[FrameCapture] Failed to create rgba16 blit encoder")
            return nil
        }

        encoder.copy(from: texture, to: stagingTexture)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let halfBytesPerPixel = 8
        let halfBytesPerRow = texture.width * halfBytesPerPixel
        let halfBytesPerImage = halfBytesPerRow * texture.height

        let halfBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: halfBytesPerImage)
        defer { halfBuffer.deallocate() }

        let region = MTLRegion(
            origin: MTLOrigin(x: 0, y: 0, z: 0),
            size: MTLSize(width: texture.width, height: texture.height, depth: 1)
        )

        stagingTexture.getBytes(
            halfBuffer,
            bytesPerRow: halfBytesPerRow,
            bytesPerImage: halfBytesPerImage,
            from: region,
            mipmapLevel: 0,
            slice: 0
        )

        let outBytesPerPixel = 4
        let outBytesPerRow = texture.width * outBytesPerPixel
        let outBytesPerImage = outBytesPerRow * texture.height
        let outBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: outBytesPerImage)
        defer { outBuffer.deallocate() }

        @inline(__always)
        func decodeHalf(_ lo: UInt8, _ hi: UInt8) -> Float {
            let bits = UInt16(lo) | (UInt16(hi) << 8)
            return Float(Float16(bitPattern: bits))
        }

        for y in 0..<texture.height {
            for x in 0..<texture.width {
                let src = y * halfBytesPerRow + x * halfBytesPerPixel
                let dst = y * outBytesPerRow + x * outBytesPerPixel

                let r = max(0, min(1, decodeHalf(halfBuffer[src], halfBuffer[src + 1])))
                let g = max(0, min(1, decodeHalf(halfBuffer[src + 2], halfBuffer[src + 3])))
                let b = max(0, min(1, decodeHalf(halfBuffer[src + 4], halfBuffer[src + 5])))
                let a = max(0, min(1, decodeHalf(halfBuffer[src + 6], halfBuffer[src + 7])))

                outBuffer[dst] = UInt8((r * 255).rounded())
                outBuffer[dst + 1] = UInt8((g * 255).rounded())
                outBuffer[dst + 2] = UInt8((b * 255).rounded())
                outBuffer[dst + 3] = UInt8((a * 255).rounded())
            }
        }

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: outBuffer,
                width: texture.width,
                height: texture.height,
                bitsPerComponent: 8,
                bytesPerRow: outBytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            NSLog("[FrameCapture] Failed to create rgba16 CGContext")
            return nil
        }

        return context.makeImage()
    }

    private func saveTexture(_ texture: MTLTexture, toPNGAtPath path: String) -> Bool {
        guard let cgImage = textureToCGImage(texture),
              let pngData = cgImageToPNG(cgImage) else {
            NSLog("[CLICapture] Failed to convert rendered texture to PNG: %@", path)
            return false
        }

        do {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try pngData.write(to: url, options: .atomic)
            NSLog("[CLICapture] Saved rendered Metal frame: %@", path)
            return true
        } catch {
            NSLog("[CLICapture] Failed writing rendered frame %@: %@", path, String(describing: error))
            return false
        }
    }

    /// Converts CGImage to PNG data representation
    private func cgImageToPNG(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
                data as CFMutableData,
                "public.png" as CFString,
                1,
                nil
        ) else {
            return nil
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return data as Data
    }

    /// Captures the current source and Anime4K-processed frames to PNG files
    /// for SSIM/PSNR comparison against mpv GLSL reference renders.
    ///
    /// Usage: Call this method after Anime4K processing in displayWithMetal()
    /// to capture paired frames for quality verification.
    ///
    /// Output files:
    ///   - frame_N_source.png (before Anime4K)
    ///   - frame_N_output.png (after Anime4K)
    ///
    /// These can then be compared using the QualityCompare tool:
    ///   QualityCompare frame_source.png frame_output.png --reference glsl_output.png
    private func captureFrame(sourceTexture: MTLTexture, outputTexture: MTLTexture) {
        guard frameCaptureEnabled else { return }
        guard frameCaptureCount < maxFrameCaptures else {
            NSLog("[FrameCapture] Max captures reached (\(maxFrameCaptures)), disabling")
            frameCaptureEnabled = false
            return
        }

        // Ensure output directory exists
        try? FileManager.default.createDirectory(
            atPath: frameCaptureDirectory,
            withIntermediateDirectories: true
        )

        let frameNum = frameCaptureCount
        let sourcePath = "\(frameCaptureDirectory)/frame_\(frameNum)_source.png"
        let outputPath = "\(frameCaptureDirectory)/frame_\(frameNum)_output.png"

        NSLog("[FrameCapture] Capturing frame %d: source=%dx%d, output=%dx%d",
              frameNum, sourceTexture.width, sourceTexture.height,
              outputTexture.width, outputTexture.height)

        // Capture source texture
        if let sourceCGImage = textureToCGImage(sourceTexture) {
            if let sourceData = cgImageToPNG(sourceCGImage) {
                try? sourceData.write(to: URL(fileURLWithPath: sourcePath))
                NSLog("[FrameCapture] Saved source: %@", sourcePath)
            }
        }

        // Capture output texture (after Anime4K)
        if let outputCGImage = textureToCGImage(outputTexture) {
            if let outputData = cgImageToPNG(outputCGImage) {
                try? outputData.write(to: URL(fileURLWithPath: outputPath))
                NSLog("[FrameCapture] Saved output: %@", outputPath)
            }
        }

        frameCaptureCount += 1

        if frameCaptureCount >= maxFrameCaptures {
            NSLog("[FrameCapture] Captured %d frames, limit reached", maxFrameCaptures)
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Rendering Lifecycle
    // ═══════════════════════════════════════════════════════════════════

    /// Set up mpv render context with the offscreen CGL context, then configure
    /// the Metal display pipeline. This creates the IOSurface bridge between
    /// mpv's OpenGL renderer and the Metal display layer.
    func initMPVRendering(_ controller: MPVController) {
        self.mpv = controller

        // Make offscreen CGL context current for mpv_render_context_create
        CGLLockContext(cglCtx)
        CGLSetCurrentContext(cglCtx)

        var initParams = mpv_opengl_init_params(
            get_proc_address: mpvGetOpenGLProc,
            get_proc_address_ctx: nil
        )

        let apiType = UnsafeMutableRawPointer(
            mutating: (MPV_RENDER_API_TYPE_OPENGL as NSString).utf8String
        )

        withUnsafeMutablePointer(to: &initParams) { initParamsPtr in
            var advanced: CInt = 1
            withUnsafeMutablePointer(to: &advanced) { advancedPtr in
                var params = [
                    mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE,
                                     data: apiType),
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS,
                                     data: .init(initParamsPtr)),
                    mpv_render_param(type: MPV_RENDER_PARAM_ADVANCED_CONTROL,
                                     data: .init(advancedPtr)),
                    mpv_render_param()
                ]
                let err = mpv_render_context_create(
                    &controller.mpvRenderContext,
                    controller.mpvHandle,
                    &params
                )
                if err < 0 {
                    NSLog("[ViewLayer] Failed to create render context: %s",
                          mpv_error_string(err))
                }
            }
        }

        // Store CGL context reference for lifecycle management
        controller.openGLContext = cglCtx
        // Set back-reference so MPVController can control the Metal pipeline
        controller.viewLayer = self
        CGLUnlockContext(cglCtx)

        // Set mpv update callback – pass self as unretained pointer
        let layerPtr = Unmanaged.passUnretained(self).toOpaque()
        mpv_render_context_set_update_callback(
            controller.mpvRenderContext!,
            mpvRenderUpdateCallback,
            layerPtr
        )

        // Create initial IOSurface at current viewport size
        let scale = contentsScale
        let w = max(1, Int(bounds.width * scale))
        let h = max(1, Int(bounds.height * scale))
        if w > 0 && h > 0 {
            createIOSurface(width: w, height: h)
        }

        NSLog("[ViewLayer] Metal 3 render pipeline initialized successfully")
    }

    /// Tear down rendering (call before destroying mpv).
    /// Releases the mpv render context and cleans up the IOSurface bridge.
    func uninitRendering() {
        isUninited = true
        // Drain any pending render blocks so they don't race with teardown
        metalRenderQueue.sync {}
        guard let mpv = mpv, let renderCtx = mpv.mpvRenderContext else { return }

        // Lock CGL context so no render cycle races with teardown
        CGLLockContext(cglCtx)
        CGLSetCurrentContext(cglCtx)

        mpv_render_context_set_update_callback(renderCtx, nil, nil)
        mpv_render_context_free(renderCtx)
        mpv.mpvRenderContext = nil

        CGLSetCurrentContext(nil)
        CGLUnlockContext(cglCtx)

        // Clean up IOSurface and GPU resources
        destroyIOSurface()

        NSLog("[ViewLayer] Render context freed")
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Embedded MSL 3.0 Shader Source
    //
    // Fullscreen video display pipeline shaders. These are compiled at
    // runtime via makeLibrary(source:) if no pre-compiled default.metallib
    // is found in the app bundle. The vertex shader generates a
    // fullscreen quad from vertex_id (no VBO needed). The fragment
    // shader samples the IOSurface-backed video texture.
    //
    // Metal NDC Z range is [0, 1] (OpenGL used [-1, 1]). Z is set to
    // 0.5 to avoid near-plane clipping artifacts from the coordinate
    // system difference.
    // ═══════════════════════════════════════════════════════════════════

    private static let metalShaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
        float2 texCoord;
    };

    vertex VertexOut fullscreenVertex(uint vid [[vertex_id]]) {
        const float2 positions[4] = {
            float2(-1.0, -1.0),
            float2( 1.0, -1.0),
            float2(-1.0,  1.0),
            float2( 1.0,  1.0),
        };
        const float2 texCoords[4] = {
            float2(0.0, 1.0),
            float2(1.0, 1.0),
            float2(0.0, 0.0),
            float2(1.0, 0.0),
        };
        VertexOut out;
        out.position = float4(positions[vid], 0.5, 1.0);
        out.texCoord = texCoords[vid];
        return out;
    }

    fragment float4 textureFragment(VertexOut in [[stage_in]],
                                    texture2d<float, access::sample> videoFrame [[texture(0)]]) {
        constexpr sampler linearSampler(filter::linear,
                                        mip_filter::none,
                                        address::clamp_to_edge);
        return videoFrame.sample(linearSampler, in.texCoord);
    }
    """
}
