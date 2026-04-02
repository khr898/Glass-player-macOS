import Cocoa

// ---------------------------------------------------------------------------
// VideoView – NSView that hosts the Metal 3 ViewLayer (CAMetalLayer)
// ---------------------------------------------------------------------------

class VideoView: NSView {

    lazy var videoLayer: ViewLayer = ViewLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        // CRITICAL ORDER (IINA pattern):
        // Set layer BEFORE wantsLayer → makes this a layer-HOSTING view
        // (we own the layer, not AppKit)
        layer = videoLayer
        wantsLayer = true

        // ── Metal layer configuration ──
        // contentsScale: Retina high-DPI rendering
        // wantsExtendedDynamicRangeContent: HDR/EDR (set in ViewLayer init)

        // Color space: use the display's native color space so macOS does not
        // apply an sRGB→P3 conversion that washes out colors.  This matches the
        // approach used by IINA and other libmpv-based players on Apple Silicon.
        if let screen = NSScreen.main {
            videoLayer.colorspace = screen.colorSpace?.cgColorSpace
                ?? CGColorSpace(name: CGColorSpace.displayP3)!
            // Retina: set contentsScale for high-DPI rendering via Metal
            videoLayer.contentsScale = screen.backingScaleFactor
        } else {
            videoLayer.colorspace = CGColorSpace(name: CGColorSpace.displayP3)!
            videoLayer.contentsScale = 2.0  // Safe Retina default
        }

        autoresizingMask = [.width, .height]

        // Accept drag-and-drop of video files
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    // Update contentsScale when window moves between displays (Retina ↔ non-Retina)
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        guard let scale = window?.backingScaleFactor else { return }
        videoLayer.contentsScale = scale
    }

    // ── Live-resize optimisation: skip expensive IOSurface recreation ──
    override func viewWillStartLiveResize() {
        super.viewWillStartLiveResize()
        videoLayer.isInLiveResize = true
    }
    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        guard !videoLayer.isUninited else { return }
        videoLayer.liveResizeEnded()
    }

    // Accept drag-and-drop
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let items = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], let url = items.first else {
            return false
        }

        // Find the player window and load the file
        if let playerWindow = window?.windowController as? PlayerWindow {
            playerWindow.loadFile(url.path)
        }
        return true
    }

    /// Tear down rendering
    func uninit() {
        videoLayer.uninitRendering()
    }
}
