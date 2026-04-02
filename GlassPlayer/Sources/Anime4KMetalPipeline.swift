import Metal
import QuartzCore
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// ---------------------------------------------------------------------------
// Anime4K Metal Compute Pipeline Manager - Protocol Based
// ---------------------------------------------------------------------------
// Manages the native Metal compute pipeline for Anime4K shaders.
// Replaces the GLSL-based mpv shader path with direct Metal compute shaders.
//
// Architecture:
//   VideoFrame → [Compute Pass 1] → [Pass 2] → ... → [Final Pass] → CAMetalLayer
//
// Each pass is a compute kernel that reads from input textures and writes
// to intermediate textures. The final pass writes to the display texture.
//
// This version uses the protocol-based Anime4KMode architecture for type-safe
// preset definitions instead of hardcoded string dictionaries.
// ---------------------------------------------------------------------------

private struct PassOutputSize {
    let width: Int
    let height: Int
}

private struct KernelBindingSpec {
    let inputNames: [String]
    let outputName: String
}

/// Texture pool for reusing intermediate textures across frames
/// Reduces GPU memory allocation overhead and improves performance
final class TexturePool {
    private var pooledTextures: [String: [MTLTexture]] = [:]
    private let device: MTLDevice
    private let pixelFormat: MTLPixelFormat = .rgba16Float
    private let verboseLogging: Bool

    init(device: MTLDevice) {
        self.device = device
        self.verboseLogging = ProcessInfo.processInfo.environment["GLASS_VERBOSE_PIPELINE"] == "1"
        if verboseLogging {
            NSLog("[TexturePool] Initialized")
        }
    }

    /// Get a texture from the pool or create a new one
    func acquireTexture(width: Int, height: Int, label: String) -> MTLTexture? {
        let key = "\(width)x\(height)"

        // Try to get from pool
        if var textures = pooledTextures[key], !textures.isEmpty {
            let texture = textures.removeLast()
            pooledTextures[key] = textures
            texture.label = label
            if verboseLogging {
                NSLog("[TexturePool] Reused texture from pool: \(key)")
            }
            return texture
        }

        // Create new texture
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private

        if let texture = device.makeTexture(descriptor: descriptor) {
            texture.label = label
            if verboseLogging {
                NSLog("[TexturePool] Created new texture: \(key)")
            }
            return texture
        }

        NSLog("[TexturePool] Failed to create texture: \(key)")
        return nil
    }

    /// Return a texture to the pool for reuse
    func releaseTexture(_ texture: MTLTexture) {
        let key = "\(texture.width)x\(texture.height)"
        if pooledTextures[key] == nil {
            pooledTextures[key] = []
        }
        pooledTextures[key]?.append(texture)
        if verboseLogging {
            NSLog("[TexturePool] Released texture to pool: \(key) (pool size: \(pooledTextures[key]!.count))")
        }
    }

    /// Clear all pooled textures (call when preset changes or on deinit)
    func clear() {
        let totalTextures = pooledTextures.values.reduce(0) { $0 + $1.count }
        pooledTextures.removeAll()
        if verboseLogging {
            NSLog("[TexturePool] Cleared \(totalTextures) pooled textures")
        }
    }

    deinit {
        clear()
        if verboseLogging {
            NSLog("[TexturePool] Deinitialized")
        }
    }
}

/// Kernel function registry - maps shader files to their kernel function names
/// This replaces the hardcoded getKernelNamesForShader() method
struct KernelFunctionRegistry {
    private static var kernelMapping: [String: [String]] = [:]

    /// Register kernel functions for a shader file
    static func register(shaderFile: String, kernels: [String]) {
        kernelMapping[shaderFile] = kernels
    }

    /// Get all kernel functions for a shader file
    static func kernels(for shaderFile: String) -> [String] {
        guard let kernels = kernelMapping[shaderFile], !kernels.isEmpty else {
            NSLog("[Anime4K] ERROR: Missing kernel mapping for shader file %@", shaderFile)
            return []
        }
        return kernels
    }

    /// Initialize all kernel mappings - called at app startup
    /// Kernel names match the translated Metal shaders from translate_anime4k_shaders.py
    static func initialize() {
        kernelMapping.removeAll()

        // Register all shader kernel mappings
        register(shaderFile: "Anime4K_Clamp_Highlights", kernels: [
            "Anime4Kv40DeRingComputeStatistics",      // pass0
            "Anime4Kv40DeRingComputeStatistics_pass1",// pass1
            "Anime4Kv40DeRingClamp_pass2"             // pass2
        ])
        register(shaderFile: "Anime4K_Restore_CNN_S", kernels: [
            "Anime4Kv40RestoreCNNSConv4x3x3x3",       // pass0
            "Anime4Kv40RestoreCNNSConv4x3x3x8_pass1", // pass1
            "Anime4Kv40RestoreCNNSConv4x3x3x8_pass2", // pass2
            "Anime4Kv40RestoreCNNSConv3x3x3x8_pass3"  // pass3 (residual)
        ])
        register(shaderFile: "Anime4K_Restore_CNN_M", kernels: [
            "Anime4Kv40RestoreCNNMConv4x3x3x3",       // pass0
            "Anime4Kv40RestoreCNNMConv4x3x3x8_pass1", // pass1
            "Anime4Kv40RestoreCNNMConv4x3x3x8_pass2", // pass2
            "Anime4Kv40RestoreCNNMConv4x3x3x8_pass3", // pass3
            "Anime4Kv40RestoreCNNMConv4x3x3x8_pass4", // pass4
            "Anime4Kv40RestoreCNNMConv4x3x3x8_pass5", // pass5
            "Anime4Kv40RestoreCNNMConv4x3x3x8_pass6", // pass6
            "Anime4Kv40RestoreCNNMConv3x1x1x56_pass7" // pass7 (residual)
        ])
        register(shaderFile: "Anime4K_Restore_CNN_VL", kernels: [
            "Anime4Kv40RestoreCNNVLConv4x3x3x3",      // pass0
            "Anime4Kv40RestoreCNNVLConv4x3x3x3_pass1",// pass1
            "Anime4Kv40RestoreCNNVLConv4x3x3x16_pass2",// pass2
            "Anime4Kv40RestoreCNNVLConv4x3x3x16_pass3",// pass3
            "Anime4Kv40RestoreCNNVLConv4x3x3x16_pass4",// pass4
            "Anime4Kv40RestoreCNNVLConv4x3x3x16_pass5",// pass5
            "Anime4Kv40RestoreCNNVLConv4x3x3x16_pass6",// pass6
            "Anime4Kv40RestoreCNNVLConv4x3x3x16_pass7",// pass7
            "Anime4Kv40RestoreCNNVLConv4x3x3x16_pass8",// pass8
            "Anime4Kv40RestoreCNNVLConv4x3x3x16_pass9",// pass9
            "Anime4Kv40RestoreCNNVLConv4x3x3x16_pass10",// pass10
            "Anime4Kv40RestoreCNNVLConv4x3x3x16_pass11",// pass11
            "Anime4Kv40RestoreCNNVLConv4x3x3x16_pass12",// pass12
            "Anime4Kv40RestoreCNNVLConv4x3x3x16_pass13",// pass13
            "Anime4Kv40RestoreCNNVLConv4x3x3x16_pass14",// pass14
            "Anime4Kv40RestoreCNNVLConv4x3x3x16_pass15",// pass15
            "Anime4Kv40RestoreCNNVLConv3x1x1x112_pass16"// pass16 (residual)
        ])
        register(shaderFile: "Anime4K_Restore_CNN_Soft_S", kernels: [
            "Anime4Kv40RestoreCNNSoftSConv4x3x3x3",    // pass0
            "Anime4Kv40RestoreCNNSoftSConv4x3x3x8_pass1",// pass1
            "Anime4Kv40RestoreCNNSoftSConv4x3x3x8_pass2",// pass2
            "Anime4Kv40RestoreCNNSoftSConv3x3x3x8_pass3" // pass3 (residual)
        ])
        register(shaderFile: "Anime4K_Restore_CNN_Soft_M", kernels: [
            "Anime4Kv40RestoreCNNSoftMConv4x3x3x3",    // pass0
            "Anime4Kv40RestoreCNNSoftMConv4x3x3x8_pass1",// pass1
            "Anime4Kv40RestoreCNNSoftMConv4x3x3x8_pass2",// pass2
            "Anime4Kv40RestoreCNNSoftMConv4x3x3x8_pass3",// pass3
            "Anime4Kv40RestoreCNNSoftMConv4x3x3x8_pass4",// pass4
            "Anime4Kv40RestoreCNNSoftMConv4x3x3x8_pass5",// pass5
            "Anime4Kv40RestoreCNNSoftMConv4x3x3x8_pass6",// pass6
            "Anime4Kv40RestoreCNNSoftMConv3x1x1x56_pass7"// pass7 (residual)
        ])
        register(shaderFile: "Anime4K_Restore_CNN_Soft_VL", kernels: [
            "Anime4Kv40RestoreCNNSoftVLConv4x3x3x3",   // pass0
            "Anime4Kv40RestoreCNNSoftVLConv4x3x3x3_pass1",// pass1
            "Anime4Kv40RestoreCNNSoftVLConv4x3x3x16_pass2",// pass2
            "Anime4Kv40RestoreCNNSoftVLConv4x3x3x16_pass3",// pass3
            "Anime4Kv40RestoreCNNSoftVLConv4x3x3x16_pass4",// pass4
            "Anime4Kv40RestoreCNNSoftVLConv4x3x3x16_pass5",// pass5
            "Anime4Kv40RestoreCNNSoftVLConv4x3x3x16_pass6",// pass6
            "Anime4Kv40RestoreCNNSoftVLConv4x3x3x16_pass7",// pass7
            "Anime4Kv40RestoreCNNSoftVLConv4x3x3x16_pass8",// pass8
            "Anime4Kv40RestoreCNNSoftVLConv4x3x3x16_pass9",// pass9
            "Anime4Kv40RestoreCNNSoftVLConv4x3x3x16_pass10",// pass10
            "Anime4Kv40RestoreCNNSoftVLConv4x3x3x16_pass11",// pass11
            "Anime4Kv40RestoreCNNSoftVLConv4x3x3x16_pass12",// pass12
            "Anime4Kv40RestoreCNNSoftVLConv4x3x3x16_pass13",// pass13
            "Anime4Kv40RestoreCNNSoftVLConv4x3x3x16_pass14",// pass14
            "Anime4Kv40RestoreCNNSoftVLConv4x3x3x16_pass15",// pass15
            "Anime4Kv40RestoreCNNSoftVLConv3x1x1x112_pass16"// pass16 (residual)
        ])
        register(shaderFile: "Anime4K_Upscale_CNN_x2_S", kernels: [
            "Anime4Kv32UpscaleCNNx2SConv4x3x3x3",      // pass0
            "Anime4Kv32UpscaleCNNx2SConv4x3x3x8_pass1",// pass1
            "Anime4Kv32UpscaleCNNx2SConv4x3x3x8_pass2",// pass2
            "Anime4Kv32UpscaleCNNx2SConv4x3x3x8_pass3",// pass3
            "Anime4Kv32UpscaleCNNx2SDepthtoSpace_pass4"// pass4
        ])
        register(shaderFile: "Anime4K_Upscale_CNN_x2_M", kernels: [
            "Anime4Kv32UpscaleCNNx2MConv4x3x3x3",      // pass0
            "Anime4Kv32UpscaleCNNx2MConv4x3x3x8_pass1",// pass1
            "Anime4Kv32UpscaleCNNx2MConv4x3x3x8_pass2",// pass2
            "Anime4Kv32UpscaleCNNx2MConv4x3x3x8_pass3",// pass3
            "Anime4Kv32UpscaleCNNx2MConv4x3x3x8_pass4",// pass4
            "Anime4Kv32UpscaleCNNx2MConv4x3x3x8_pass5",// pass5
            "Anime4Kv32UpscaleCNNx2MConv4x3x3x8_pass6",// pass6
            "Anime4Kv32UpscaleCNNx2MConv4x1x1x56_pass7",// pass7
            "Anime4Kv32UpscaleCNNx2MDepthtoSpace_pass8"// pass8
        ])
        register(shaderFile: "Anime4K_Upscale_CNN_x2_VL", kernels: [
            "Anime4Kv32UpscaleCNNx2VLConv4x3x3x3",     // pass0
            "Anime4Kv32UpscaleCNNx2VLConv4x3x3x3_pass1",// pass1
            "Anime4Kv32UpscaleCNNx2VLConv4x3x3x16_pass2",// pass2
            "Anime4Kv32UpscaleCNNx2VLConv4x3x3x16_pass3",// pass3
            "Anime4Kv32UpscaleCNNx2VLConv4x3x3x16_pass4",// pass4
            "Anime4Kv32UpscaleCNNx2VLConv4x3x3x16_pass5",// pass5
            "Anime4Kv32UpscaleCNNx2VLConv4x3x3x16_pass6",// pass6
            "Anime4Kv32UpscaleCNNx2VLConv4x3x3x16_pass7",// pass7
            "Anime4Kv32UpscaleCNNx2VLConv4x3x3x16_pass8",// pass8
            "Anime4Kv32UpscaleCNNx2VLConv4x3x3x16_pass9",// pass9
            "Anime4Kv32UpscaleCNNx2VLConv4x3x3x16_pass10",// pass10
            "Anime4Kv32UpscaleCNNx2VLConv4x3x3x16_pass11",// pass11
            "Anime4Kv32UpscaleCNNx2VLConv4x3x3x16_pass12",// pass12
            "Anime4Kv32UpscaleCNNx2VLConv4x3x3x16_pass13",// pass13
            "Anime4Kv32UpscaleCNNx2VLConv4x1x1x112_pass14",// pass14
            "Anime4Kv32UpscaleCNNx2VLConv4x1x1x112_pass15",// pass15
            "Anime4Kv32UpscaleCNNx2VLConv4x1x1x112_pass16",// pass16
            "Anime4Kv32UpscaleCNNx2VLDepthtoSpace_pass17"// pass17
        ])
        register(shaderFile: "Anime4K_Upscale_Denoise_CNN_x2_M", kernels: [
            "Anime4Kv32UpscaleDenoiseCNNx2MConv4x3x3x3",   // pass0
            "Anime4Kv32UpscaleDenoiseCNNx2MConv4x3x3x8_pass1",// pass1
            "Anime4Kv32UpscaleDenoiseCNNx2MConv4x3x3x8_pass2",// pass2
            "Anime4Kv32UpscaleDenoiseCNNx2MConv4x3x3x8_pass3",// pass3
            "Anime4Kv32UpscaleDenoiseCNNx2MConv4x3x3x8_pass4",// pass4
            "Anime4Kv32UpscaleDenoiseCNNx2MConv4x3x3x8_pass5",// pass5
            "Anime4Kv32UpscaleDenoiseCNNx2MConv4x3x3x8_pass6",// pass6
            "Anime4Kv32UpscaleDenoiseCNNx2MConv4x1x1x56_pass7",// pass7
            "Anime4Kv32UpscaleDenoiseCNNx2MDepthtoSpace_pass8" // pass8
        ])
        register(shaderFile: "Anime4K_Upscale_Denoise_CNN_x2_VL", kernels: [
            "Anime4Kv32UpscaleDenoiseCNNx2VLConv4x3x3x3",  // pass0
            "Anime4Kv32UpscaleDenoiseCNNx2VLConv4x3x3x3_pass1",// pass1
            "Anime4Kv32UpscaleDenoiseCNNx2VLConv4x3x3x16_pass2",// pass2
            "Anime4Kv32UpscaleDenoiseCNNx2VLConv4x3x3x16_pass3",// pass3
            "Anime4Kv32UpscaleDenoiseCNNx2VLConv4x3x3x16_pass4",// pass4
            "Anime4Kv32UpscaleDenoiseCNNx2VLConv4x3x3x16_pass5",// pass5
            "Anime4Kv32UpscaleDenoiseCNNx2VLConv4x3x3x16_pass6",// pass6
            "Anime4Kv32UpscaleDenoiseCNNx2VLConv4x3x3x16_pass7",// pass7
            "Anime4Kv32UpscaleDenoiseCNNx2VLConv4x3x3x16_pass8",// pass8
            "Anime4Kv32UpscaleDenoiseCNNx2VLConv4x3x3x16_pass9",// pass9
            "Anime4Kv32UpscaleDenoiseCNNx2VLConv4x3x3x16_pass10",// pass10
            "Anime4Kv32UpscaleDenoiseCNNx2VLConv4x3x3x16_pass11",// pass11
            "Anime4Kv32UpscaleDenoiseCNNx2VLConv4x3x3x16_pass12",// pass12
            "Anime4Kv32UpscaleDenoiseCNNx2VLConv4x3x3x16_pass13",// pass13
            "Anime4Kv32UpscaleDenoiseCNNx2VLConv4x1x1x112_pass14",// pass14
            "Anime4Kv32UpscaleDenoiseCNNx2VLConv4x1x1x112_pass15",// pass15
            "Anime4Kv32UpscaleDenoiseCNNx2VLConv4x1x1x112_pass16",// pass16
            "Anime4Kv32UpscaleDenoiseCNNx2VLDepthtoSpace_pass17"  // pass17
        ])
        register(shaderFile: "Anime4K_AutoDownscalePre_x2", kernels: [
            "Anime4Kv40AutoDownscalePrex2"
        ])
        register(shaderFile: "Anime4K_AutoDownscalePre_x4", kernels: [
            "Anime4Kv32AutoDownscalePrex4"
        ])
    }
}

class Anime4KMetalPipeline {

    // MARK: - Properties

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let library: MTLLibrary

    /// Cache of compiled compute pipeline states
    private var pipelineStates: [String: MTLComputePipelineState] = [:]

    /// Named intermediate textures keyed by pass index and symbolic texture name.
    private var namedIntermediateTextures: [String: MTLTexture] = [:]

    /// Output dimensions for each shader pass (precomputed at activation).
    private var passOutputSizes: [PassOutputSize] = []

    /// Current preset configuration (stores the mode type)
    private var currentModeType: (any Anime4KMode.Type)?
    /// Runtime file pipelines built from Anime4K GLSL metadata.
    private var filePipelines: [A4KFilePipeline] = []

    /// Thread group size for compute dispatch
    private let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)

    /// Sampler state for texture sampling (linear filtering)
    private let samplerState: MTLSamplerState

    /// Source texture (from IOSurface/mpv render)
    private var sourceTexture: MTLTexture?

    /// Output texture (final result for display)
    private var outputTexture: MTLTexture?

    /// Whether the pipeline is currently active
    var isActive: Bool = false

    /// Current input dimensions
    private var inputWidth: Int = 0
    private var inputHeight: Int = 0

    /// Scale factor (1x for restore/denoise, 2x for upscale)
    private var scaleFactor: Int = 1

    /// Texture pool for reusing intermediate textures across frames
    private let texturePool: TexturePool

    /// Profiling: Timestamp for the last frame processing
    private var lastFrameTimestamp: CFTimeInterval = 0

    /// Profiling: Average compute time in milliseconds (rolling average)
    private var averageComputeTimeMs: Double = 0

    /// Profiling: Frame counter for statistics
    private var frameCount: UInt = 0

    /// Optional perf telemetry for heavy preset validation.
    private let perfStatsLoggingEnabled: Bool = ProcessInfo.processInfo.environment["GLASS_PERF_STATS"] == "1"
    private let perfStatsLogInterval: UInt = {
        if let raw = ProcessInfo.processInfo.environment["GLASS_PERF_LOG_INTERVAL"],
           let parsed = UInt(raw),
           parsed >= 30 {
            return parsed
        }
        return 120
    }()


    // MARK: - Initialization

    init?(device: MTLDevice) {
        self.device = device

        guard let queue = device.makeCommandQueue() else {
            NSLog("[Anime4K] Failed to create command queue")
            return nil
        }
        self.commandQueue = queue

        // Load the pre-compiled Anime4K metallib from bundle resources
        let execPath = ProcessInfo.processInfo.arguments[0]
        let macosDir = (execPath as NSString).deletingLastPathComponent
        let contentsDir = (macosDir as NSString).deletingLastPathComponent
        let metallibPath = contentsDir + "/Resources/Anime4K.metallib"

        do {
            if FileManager.default.fileExists(atPath: metallibPath) {
                let url = URL(fileURLWithPath: metallibPath)
                self.library = try device.makeLibrary(URL: url)
                NSLog("[Anime4K] Loaded pre-compiled metallib from: %@", metallibPath)
            } else {
                // Fallback: try default.metallib (combined library)
                let defaultLibPath = contentsDir + "/Resources/default.metallib"
                if FileManager.default.fileExists(atPath: defaultLibPath) {
                    let url = URL(fileURLWithPath: defaultLibPath)
                    self.library = try device.makeLibrary(URL: url)
                    NSLog("[Anime4K] Loaded combined metallib from: %@", defaultLibPath)
                } else {
                    NSLog("[Anime4K] No pre-compiled metallib found – runtime compilation required")
                    return nil
                }
            }
        } catch {
            NSLog("[Anime4K] Failed to load metallib: \(error)")
            return nil
        }

        // Create sampler state (linear filtering, clamp to edge)
        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.mipFilter = .notMipmapped
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .clampToEdge
        samplerDesc.normalizedCoordinates = true

        guard let sampler = device.makeSamplerState(descriptor: samplerDesc) else {
            NSLog("[Anime4K] Failed to create sampler state")
            return nil
        }
        self.samplerState = sampler

        // Initialize texture pool for intermediate texture reuse
        self.texturePool = TexturePool(device: device)

        // Initialize kernel registry
        KernelFunctionRegistry.initialize()

        NSLog("[Anime4K] Metal pipeline initialized")
    }

    // MARK: - Public API

    /// Activate a shader preset
    func activatePreset(_ presetName: String, inputWidth: Int, inputHeight: Int) -> Bool {
        NSLog("[Anime4K] activatePreset called with: %@", presetName)
        NSLog("[Anime4K] Available presets: %@", Anime4KPresetRegistry.allPresetNames().joined(separator: ", "))

        guard let modeType = Anime4KPresetRegistry.preset(named: presetName) else {
            NSLog("[Anime4K] ERROR: Unknown preset '%@' - not found in registry", presetName)
            return false
        }
        NSLog("[Anime4K] Found preset: %@ with %d shader files", modeType.displayName, modeType.shaderPasses.count)

        let shaderFiles = modeType.shaderPasses.map { $0.shaderFile }
        self.scaleFactor = modeType.scaleFactor
        self.inputWidth = inputWidth
        self.inputHeight = inputHeight

        // Reset runtime pipelines for the new preset.
        filePipelines.removeAll()

        for shaderFile in shaderFiles {
            guard let metalSource = loadMetalSource(shaderFile: shaderFile) else {
                NSLog("[Anime4K] ERROR: Missing .metal source metadata for %@", shaderFile)
                return false
            }

            guard let filePipeline = A4KFilePipeline(shaderFileName: shaderFile,
                                                     metalSource: metalSource,
                                                     targetOutputScale: Float(modeType.scaleFactor),
                                                     device: device,
                                                     library: library) else {
                NSLog("[Anime4K] ERROR: Failed to create runtime pipeline for %@", shaderFile)
                return false
            }

            guard filePipeline.recompileIfNeeded(inputWidth: inputWidth, inputHeight: inputHeight) else {
                NSLog("[Anime4K] ERROR: Failed to compile runtime pipeline for %@", shaderFile)
                return false
            }

            filePipelines.append(filePipeline)
        }

        self.currentModeType = modeType
        isActive = true

        NSLog("[Anime4K] Activated preset: %@ (%d runtime shader files)",
              presetName,
              filePipelines.count)

        return true
    }

    /// Deactivate the current preset
    func deactivate() {
        filePipelines.removeAll()

        // Return intermediate textures to pool before clearing.
        for texture in namedIntermediateTextures.values {
            texturePool.releaseTexture(texture)
        }
        namedIntermediateTextures.removeAll()
        passOutputSizes.removeAll()

        // Clear output texture
        if let output = outputTexture {
            texturePool.releaseTexture(output)
            outputTexture = nil
        }

        currentModeType = nil
        isActive = false
        sourceTexture = nil
        frameCount = 0
        averageComputeTimeMs = 0
        texturePool.clear()
        NSLog("[Anime4K] Deactivated (textures returned to pool)")
    }

    /// Process a frame through the Anime4K pipeline
    /// - Parameters:
    ///   - sourceTexture: Input texture from mpv render (IOSurface-backed)
    ///   - commandBuffer: Command buffer to encode compute passes
    /// - Returns: Output texture containing the processed frame
    func processFrame(sourceTexture: MTLTexture,
                      commandBuffer: MTLCommandBuffer,
                      completionFence: MTLFence? = nil) -> MTLTexture? {
        guard isActive, !filePipelines.isEmpty else {
            return sourceTexture
        }

        let frameStart = CACurrentMediaTime()
        self.sourceTexture = sourceTexture
        self.inputWidth = sourceTexture.width
        self.inputHeight = sourceTexture.height

        let nativeWidth = sourceTexture.width
        let nativeHeight = sourceTexture.height
        let targetOutputWidth = max(1, nativeWidth * max(1, scaleFactor))
        let targetOutputHeight = max(1, nativeHeight * max(1, scaleFactor))

        var currentTexture: MTLTexture = sourceTexture

        for filePipeline in filePipelines {
            filePipeline.updateFrameContext(nativeWidth: nativeWidth,
                                            nativeHeight: nativeHeight,
                                            targetOutputWidth: targetOutputWidth,
                                            targetOutputHeight: targetOutputHeight)

            guard filePipeline.recompileIfNeeded(inputWidth: currentTexture.width,
                                                 inputHeight: currentTexture.height) else {
                NSLog("[Anime4K] ERROR: Runtime pipeline recompile failed")
                return sourceTexture
            }

            guard let processed = filePipeline.encode(commandBuffer: commandBuffer,
                                                      input: currentTexture) else {
                NSLog("[Anime4K] ERROR: Runtime pipeline encode failed")
                return sourceTexture
            }

            currentTexture = processed
        }

        // Signal compute completion for render synchronization fence.
        if let completionFence,
           let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.updateFence(completionFence)
            blit.endEncoding()
        }

        let frameTime = (CACurrentMediaTime() - frameStart) * 1000.0
        frameCount += 1
        averageComputeTimeMs = averageComputeTimeMs * 0.95 + frameTime * 0.05

        if perfStatsLoggingEnabled,
           frameCount % perfStatsLogInterval == 0 {
            let estimatedFPS = 1000.0 / max(averageComputeTimeMs, 0.001)
            NSLog("[Anime4KPerf] preset=%@ frame=%u avgCompute=%.2fms estFPS=%.1f input=%dx%d output=%dx%d",
                  currentModeType?.displayName ?? "unknown",
                  UInt32(frameCount),
                  averageComputeTimeMs,
                  estimatedFPS,
                  sourceTexture.width,
                  sourceTexture.height,
                  currentTexture.width,
                  currentTexture.height)
        }

        self.outputTexture = currentTexture
        return currentTexture
    }

    private func loadMetalSource(shaderFile: String) -> String? {
        guard let url = resolveMetalSourceURL(shaderFile: shaderFile) else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private func resolveMetalSourceURL(shaderFile: String) -> URL? {
        let execPath = ProcessInfo.processInfo.arguments[0]
        let macosDir = (execPath as NSString).deletingLastPathComponent
        let contentsDir = (macosDir as NSString).deletingLastPathComponent

        let bundledPath = contentsDir + "/Resources/metal_sources/\(shaderFile).metal"
        if FileManager.default.fileExists(atPath: bundledPath) {
            return URL(fileURLWithPath: bundledPath)
        }

        // Fallback for local development runs outside installed app bundles.
        let cwd = FileManager.default.currentDirectoryPath
        let fallbackRoots = [
            cwd + "/MetalShaders",
            cwd + "/../GlassPlayer/MetalShaders",
            cwd + "/../MetalShaders"
        ]

        for root in fallbackRoots {
            let path = root + "/\(shaderFile).metal"
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        return nil
    }

    /// Get current profiling statistics
    func getProfilingStats() -> (averageComputeTimeMs: Double, framesProcessed: UInt) {
        return (averageComputeTimeMs, frameCount)
    }

    /// Get the output texture dimensions for a given input size
    func getOutputDimensions(inputWidth: Int, inputHeight: Int) -> (width: Int, height: Int) {
        return (inputWidth * scaleFactor, inputHeight * scaleFactor)
    }

    // MARK: - Frame Capture

    /// Capture the current source and output textures to PNG files
    /// - Parameters:
    ///   - outputDirectory: Directory to save captured frames
    ///   - presetName: Name of the preset (for filename)
    ///   - frameNumber: Frame number (for filename)
    /// - Returns: Tuple of (sourcePath, outputPath) if successful
    func captureFrame(outputDirectory: String = "/tmp/glass-player-captures",
                      presetName: String,
                      frameNumber: Int) -> (sourcePath: String, outputPath: String)? {
        guard let sourceTexture = sourceTexture,
              let outputTexture = outputTexture else {
            NSLog("[Anime4K] Cannot capture frame - textures not available")
            return nil
        }

        let safePresetName = presetName
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")

        let configuration = FrameCapture.Configuration(
            outputDirectory: outputDirectory,
            filenamePrefix: "frame_\(frameNumber)",
            includeTimestamp: false,
            targetPixelFormat: .bgra8Unorm
        )

        do {
            let sourcePath = try FrameCapture.capture(
                texture: sourceTexture,
                filename: "source_\(safePresetName).png",
                device: device,
                configuration: configuration
            )

            let outputPath = try FrameCapture.capture(
                texture: outputTexture,
                filename: "output_\(safePresetName).png",
                device: device,
                configuration: configuration
            )

            NSLog("[Anime4K] Captured frames: source=\(sourcePath), output=\(outputPath)")
            return (sourcePath, outputPath)
        } catch {
            NSLog("[Anime4K] Failed to capture frame: \(error)")
            return nil
        }
    }

    /// Trigger frame capture on next frame processing
    var shouldCaptureNextFrame: Bool = false

    // MARK: - Private Methods

    /// Configure output dimensions for each pass.
    private func configurePassOutputSizes(shaderFiles: [String],
                                          inputWidth: Int,
                                          inputHeight: Int) {
        // Return existing textures to pool before reallocating.
        for texture in namedIntermediateTextures.values {
            texturePool.releaseTexture(texture)
        }
        namedIntermediateTextures.removeAll()
        passOutputSizes.removeAll()

        var currentWidth = inputWidth
        var currentHeight = inputHeight
        var appliedScale = 1

        for shaderFile in shaderFiles {
            // Check if this shader upscales
            let isUpscale = shaderFile.contains("Upscale") &&
                           !shaderFile.contains("AutoDownscale")

            if isUpscale && appliedScale < scaleFactor {
                currentWidth *= 2
                currentHeight *= 2
                appliedScale *= 2
            }

            passOutputSizes.append(PassOutputSize(width: currentWidth, height: currentHeight))
        }

        NSLog("[Anime4K] Configured %d pass output sizes", passOutputSizes.count)
    }

    private func getOrCreateIntermediateTexture(passIndex: Int,
                                                textureName: String,
                                                width: Int,
                                                height: Int) -> MTLTexture? {
        let key = "p\(passIndex):\(textureName)"
        if let existing = namedIntermediateTextures[key] {
            if existing.width == width && existing.height == height {
                return existing
            }
            texturePool.releaseTexture(existing)
            namedIntermediateTextures.removeValue(forKey: key)
        }

        let label = "Anime4K_\(key)"
        guard let texture = texturePool.acquireTexture(width: width,
                                                       height: height,
                                                       label: label) else {
            return nil
        }

        namedIntermediateTextures[key] = texture
        return texture
    }

    private func resolveInputTexture(_ inputName: String,
                                     textureMap: [String: MTLTexture],
                                     currentInput: MTLTexture,
                                     originalSource: MTLTexture) -> MTLTexture? {
        if let bound = textureMap[inputName] { return bound }
        if inputName == "HOOKED" {
            // HOOKED is the pass source texture, not the rolling kernel output.
            return textureMap["MAIN"] ?? currentInput
        }
        if inputName == "$CURRENT" {
            return currentInput
        }
        if inputName == "MAIN" {
            return currentInput
        }
        if inputName == "ORIGINAL" {
            return originalSource
        }
        return nil
    }

    private func bindingSpec(for shaderFile: String,
                             kernelIndex: Int,
                             kernelCount: Int) -> KernelBindingSpec {
        if shaderFile == "Anime4K_Clamp_Highlights" {
            switch kernelIndex {
            case 0:
                return KernelBindingSpec(inputNames: ["HOOKED", "MAIN"], outputName: "STATSMAX")
            case 1:
                return KernelBindingSpec(inputNames: ["HOOKED", "STATSMAX", "MAIN"], outputName: "STATSMAX")
            default:
                return KernelBindingSpec(inputNames: ["HOOKED", "STATSMAX", "MAIN"], outputName: "OUTPUT")
            }
        }

        if shaderFile.contains("AutoDownscalePre") {
            return KernelBindingSpec(inputNames: ["MAIN"], outputName: "OUTPUT")
        }

        if shaderFile.contains("Restore_CNN_VL") || shaderFile.contains("Restore_CNN_Soft_VL") {
            return restoreVLSpec(kernelIndex: kernelIndex)
        }

        if shaderFile.contains("Upscale_CNN_x2_VL") || shaderFile.contains("Upscale_Denoise_CNN_x2_VL") {
            return upscaleVLSpec(kernelIndex: kernelIndex, kernelCount: kernelCount)
        }

        if shaderFile.contains("Upscale_CNN_x2") || shaderFile.contains("Upscale_Denoise_CNN_x2") {
            return upscaleStandardSpec(kernelIndex: kernelIndex, kernelCount: kernelCount)
        }

        if shaderFile.contains("Restore_CNN") {
            return restoreStandardSpec(kernelIndex: kernelIndex, kernelCount: kernelCount)
        }

        if kernelIndex == 0 {
            return KernelBindingSpec(inputNames: ["MAIN"], outputName: "$TMP0")
        }
        return KernelBindingSpec(inputNames: ["$CURRENT", "MAIN"], outputName: "$TMP\(kernelIndex)")
    }

    private func restoreStandardSpec(kernelIndex: Int,
                                     kernelCount: Int) -> KernelBindingSpec {
        if kernelIndex == 0 {
            return KernelBindingSpec(inputNames: ["MAIN"], outputName: "conv2d_tf")
        }

        if kernelIndex == kernelCount - 1 {
            let tailCount = max(kernelCount - 2, 0)
            var inputs = ["MAIN", "conv2d_tf"]
            if tailCount > 0 {
                for i in 1...tailCount {
                    inputs.append("conv2d_\(i)_tf")
                }
            }
            return KernelBindingSpec(inputNames: inputs, outputName: "OUTPUT")
        }

        let prevName = kernelIndex == 1 ? "conv2d_tf" : "conv2d_\(kernelIndex - 1)_tf"
        let outName = "conv2d_\(kernelIndex)_tf"
        return KernelBindingSpec(inputNames: [prevName, "MAIN"], outputName: outName)
    }

    private func upscaleStandardSpec(kernelIndex: Int,
                                     kernelCount: Int) -> KernelBindingSpec {
        if kernelIndex == 0 {
            return KernelBindingSpec(inputNames: ["MAIN"], outputName: "conv2d_tf")
        }

        if kernelIndex == kernelCount - 1 {
            return KernelBindingSpec(inputNames: ["MAIN", "conv2d_last_tf"], outputName: "OUTPUT")
        }

        if kernelIndex == kernelCount - 2 {
            let tailCount = max(kernelCount - 3, 0)
            var inputs = ["conv2d_tf"]
            if tailCount > 0 {
                for i in 1...tailCount {
                    inputs.append("conv2d_\(i)_tf")
                }
            }
            inputs.append("MAIN")
            return KernelBindingSpec(inputNames: inputs, outputName: "conv2d_last_tf")
        }

        let prevName = kernelIndex == 1 ? "conv2d_tf" : "conv2d_\(kernelIndex - 1)_tf"
        let outName = "conv2d_\(kernelIndex)_tf"
        return KernelBindingSpec(inputNames: [prevName, "MAIN"], outputName: outName)
    }

    private func restoreVLSpec(kernelIndex: Int) -> KernelBindingSpec {
        if kernelIndex == 0 {
            return KernelBindingSpec(inputNames: ["MAIN"], outputName: "conv2d_tf")
        }
        if kernelIndex == 1 {
            return KernelBindingSpec(inputNames: ["MAIN"], outputName: "conv2d_tf1")
        }
        if kernelIndex == 16 {
            var inputs = ["MAIN"]
            for i in 1...7 {
                inputs.append("conv2d_\(i)_tf")
                inputs.append("conv2d_\(i)_tf1")
            }
            return KernelBindingSpec(inputNames: inputs, outputName: "OUTPUT")
        }

        let pair = ((kernelIndex - 2) / 2) + 1
        let isFirst = ((kernelIndex - 2) % 2 == 0)
        let prevA = pair == 1 ? "conv2d_tf" : "conv2d_\(pair - 1)_tf"
        let prevB = pair == 1 ? "conv2d_tf1" : "conv2d_\(pair - 1)_tf1"
        let out = isFirst ? "conv2d_\(pair)_tf" : "conv2d_\(pair)_tf1"
        return KernelBindingSpec(inputNames: [prevA, prevB, "MAIN"], outputName: out)
    }

    private func upscaleVLSpec(kernelIndex: Int,
                               kernelCount: Int) -> KernelBindingSpec {
        if kernelIndex == 0 {
            return KernelBindingSpec(inputNames: ["MAIN"], outputName: "conv2d_tf")
        }
        if kernelIndex == 1 {
            return KernelBindingSpec(inputNames: ["MAIN"], outputName: "conv2d_tf1")
        }

        // Full VL chain (pass0..pass17).
        if kernelCount >= 18 {
            if kernelIndex == 17 {
                return KernelBindingSpec(inputNames: ["MAIN", "conv2d_last_tf", "conv2d_last_tf1", "conv2d_last_tf2"], outputName: "OUTPUT")
            }
            if kernelIndex >= 14 {
                let suffix = kernelIndex == 14 ? "" : (kernelIndex == 15 ? "1" : "2")
                return KernelBindingSpec(inputNames: fullVLLastInputs(), outputName: "conv2d_last_tf\(suffix)")
            }
            let pair = ((kernelIndex - 2) / 2) + 1
            let isFirst = ((kernelIndex - 2) % 2 == 0)
            let prevA = pair == 1 ? "conv2d_tf" : "conv2d_\(pair - 1)_tf"
            let prevB = pair == 1 ? "conv2d_tf1" : "conv2d_\(pair - 1)_tf1"
            let out = isFirst ? "conv2d_\(pair)_tf" : "conv2d_\(pair)_tf1"
            return KernelBindingSpec(inputNames: [prevA, prevB, "MAIN"], outputName: out)
        }

        // Legacy shortened chain used by current registry for Denoise VL.
        if kernelIndex == kernelCount - 1 {
            return KernelBindingSpec(inputNames: ["MAIN", "conv2d_last_tf", "conv2d_last_tf1", "conv2d_last_tf2"], outputName: "OUTPUT")
        }
        if kernelIndex >= kernelCount - 4 {
            let idx = kernelIndex - (kernelCount - 4)
            let suffix = idx == 0 ? "" : (idx == 1 ? "1" : "2")
            return KernelBindingSpec(inputNames: fullVLLastInputs(), outputName: "conv2d_last_tf\(suffix)")
        }

        let pair = ((kernelIndex - 2) / 2) + 1
        let isFirst = ((kernelIndex - 2) % 2 == 0)
        let prevA = pair == 1 ? "conv2d_tf" : "conv2d_\(pair - 1)_tf"
        let prevB = pair == 1 ? "conv2d_tf1" : "conv2d_\(pair - 1)_tf1"
        let out = isFirst ? "conv2d_\(pair)_tf" : "conv2d_\(pair)_tf1"
        return KernelBindingSpec(inputNames: [prevA, prevB, "MAIN"], outputName: out)
    }

    private func fullVLLastInputs() -> [String] {
        var inputs = ["conv2d_tf", "conv2d_tf1"]
        for i in 1...6 {
            inputs.append("conv2d_\(i)_tf")
            inputs.append("conv2d_\(i)_tf1")
        }
        inputs.append("MAIN")
        return inputs
    }

    /// Ensure output texture exists at the specified dimensions
    private func ensureOutputTexture(width: Int, height: Int) -> MTLTexture {
        if let existing = outputTexture,
           existing.width == width && existing.height == height {
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

        let texture = device.makeTexture(descriptor: descriptor)
        outputTexture = texture
        return texture!
    }

    // MARK: - Cleanup

    deinit {
        deactivate()
        NSLog("[Anime4K] Pipeline deallocated")
    }
}
