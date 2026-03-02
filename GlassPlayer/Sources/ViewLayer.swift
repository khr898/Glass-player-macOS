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
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    deinit {
        destroyIOSurface()
        CGLReleaseContext(cglCtx)
        CGLReleasePixelFormat(cglPix)
        GPAlignedRenderStateDestroy(renderState)
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
        if w != surfaceWidth || h != surfaceHeight {
            displayLock.lock()
            createIOSurface(width: w, height: h)
            displayLock.unlock()
        }
    }

    /// Called once when the live resize gesture ends.
    /// Recreates the IOSurface at the final viewport size so subsequent
    /// frames render at native resolution.
    func liveResizeEnded() {
        isInLiveResize = false
        let scale = contentsScale
        let bw = bounds.width * scale
        let bh = bounds.height * scale
        guard bw.isFinite && bh.isFinite && bw > 0 && bh > 0 else { return }
        let w = max(4, Int(bw))
        let h = max(4, Int(bh))
        drawableSize = CGSize(width: CGFloat(w), height: CGFloat(h))
        if w != surfaceWidth || h != surfaceHeight {
            displayLock.lock()
            createIOSurface(width: w, height: h)
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
            createIOSurface(width: w, height: h)
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
        // Get next drawable from CAMetalLayer
        guard let drawable = nextDrawable() else { return }

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

        // ── Allocate command buffer (one per frame) ──
        guard let cmdBuf = commandQueue.makeCommandBuffer() else { return }
        cmdBuf.label = "GlassPlayer Frame"

        // ── Encode render pass ──
        guard let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: passDesc) else { return }
        encoder.label = "Video Display Pass"

        // Bind statically compiled pipeline state
        // (replaces per-frame glEnable/glDisable/glBlendFunc state machine)
        encoder.setRenderPipelineState(pipelineState)

        // Bind video frame texture (IOSurface-backed, zero-copy on UMA)
        // Replaces OpenGL texture binding (glBindTexture, glActiveTexture)
        encoder.setFragmentTexture(videoTexture, index: 0)

        // Draw fullscreen quad – vertex positions generated in shader from vertex_id
        // Replaces glDrawArrays/glDrawElements with no VBO needed
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

        encoder.endEncoding()

        // Present drawable (replaces OpenGL buffer swap / CAOpenGLLayer display)
        cmdBuf.present(drawable)
        cmdBuf.commit()
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
