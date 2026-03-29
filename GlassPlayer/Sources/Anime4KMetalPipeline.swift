import Metal
import QuartzCore

// ---------------------------------------------------------------------------
// Anime4K Metal Compute Pipeline Manager
// ---------------------------------------------------------------------------
// Manages the native Metal compute pipeline for Anime4K shaders.
// Replaces the GLSL-based mpv shader path with direct Metal compute shaders.
//
// Architecture:
//   VideoFrame → [Compute Pass 1] → [Pass 2] → ... → [Final Pass] → CAMetalLayer
//
// Each pass is a compute kernel that reads from input textures and writes
// to intermediate textures. The final pass writes to the display texture.
// ---------------------------------------------------------------------------

/// Represents a single compute pass in an Anime4K preset chain
struct ComputePass {
    let kernelName: String
    let shaderFile: String
    let passIndex: Int
    var pipelineState: MTLComputePipelineState?
}

/// Intermediate texture for chaining compute passes
struct IntermediateTexture {
    let texture: MTLTexture
    let width: Int
    let height: Int
}

/// Preset configuration - maps preset names to shader pass sequences
struct Anime4KPreset {
    let name: String
    let passes: [String]  // Shader filenames (without .metal extension)
}

class Anime4KMetalPipeline {

    // MARK: - Properties

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let library: MTLLibrary

    /// Cache of compiled compute pipeline states
    private var pipelineStates: [String: MTLComputePipelineState] = [:]

    /// Intermediate textures for pass chaining (reused across frames)
    private var intermediateTextures: [IntermediateTexture] = []

    /// Current preset configuration
    private var currentPreset: Anime4KPreset?

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

    // MARK: - Preset Definitions

    /// Maps preset names to their compute pass sequences
    /// These match the kShaderPresets in MPVController.swift
    static let presetDefinitions: [String: [String]] = [
        // HQ Presets
        "Mode A (HQ)": [
            "Anime4K_Clamp_Highlights",
            "Anime4K_Restore_CNN_VL",
            "Anime4K_Upscale_CNN_x2_VL",
            "Anime4K_AutoDownscalePre_x2",
            "Anime4K_AutoDownscalePre_x4",
            "Anime4K_Upscale_CNN_x2_M",
        ],
        "Mode B (HQ)": [
            "Anime4K_Clamp_Highlights",
            "Anime4K_Restore_CNN_Soft_VL",
            "Anime4K_Upscale_CNN_x2_VL",
            "Anime4K_AutoDownscalePre_x2",
            "Anime4K_AutoDownscalePre_x4",
            "Anime4K_Upscale_CNN_x2_M",
        ],
        "Mode C (HQ)": [
            "Anime4K_Clamp_Highlights",
            "Anime4K_Upscale_Denoise_CNN_x2_VL",
            "Anime4K_AutoDownscalePre_x2",
            "Anime4K_AutoDownscalePre_x4",
            "Anime4K_Upscale_CNN_x2_M",
        ],
        "Mode A+A (HQ)": [
            "Anime4K_Clamp_Highlights",
            "Anime4K_Restore_CNN_VL",
            "Anime4K_Upscale_CNN_x2_VL",
            "Anime4K_Restore_CNN_M",
            "Anime4K_AutoDownscalePre_x2",
            "Anime4K_AutoDownscalePre_x4",
            "Anime4K_Upscale_CNN_x2_M",
        ],
        "Mode B+B (HQ)": [
            "Anime4K_Clamp_Highlights",
            "Anime4K_Restore_CNN_Soft_VL",
            "Anime4K_Upscale_CNN_x2_VL",
            "Anime4K_Restore_CNN_Soft_M",
            "Anime4K_AutoDownscalePre_x2",
            "Anime4K_AutoDownscalePre_x4",
            "Anime4K_Upscale_CNN_x2_M",
        ],
        "Mode C+A (HQ)": [
            "Anime4K_Clamp_Highlights",
            "Anime4K_Upscale_Denoise_CNN_x2_VL",
            "Anime4K_AutoDownscalePre_x2",
            "Anime4K_AutoDownscalePre_x4",
            "Anime4K_Restore_CNN_M",
            "Anime4K_Upscale_CNN_x2_M",
        ],
        // Fast Presets
        "Mode A (Fast)": [
            "Anime4K_Clamp_Highlights",
            "Anime4K_Restore_CNN_M",
            "Anime4K_Upscale_CNN_x2_M",
            "Anime4K_AutoDownscalePre_x2",
            "Anime4K_AutoDownscalePre_x4",
            "Anime4K_Upscale_CNN_x2_S",
        ],
        "Mode B (Fast)": [
            "Anime4K_Clamp_Highlights",
            "Anime4K_Restore_CNN_Soft_M",
            "Anime4K_Upscale_CNN_x2_M",
            "Anime4K_AutoDownscalePre_x2",
            "Anime4K_AutoDownscalePre_x4",
            "Anime4K_Upscale_CNN_x2_S",
        ],
        "Mode C (Fast)": [
            "Anime4K_Clamp_Highlights",
            "Anime4K_Upscale_Denoise_CNN_x2_M",
            "Anime4K_AutoDownscalePre_x2",
            "Anime4K_AutoDownscalePre_x4",
            "Anime4K_Upscale_CNN_x2_S",
        ],
        "Mode A+A (Fast)": [
            "Anime4K_Clamp_Highlights",
            "Anime4K_Restore_CNN_M",
            "Anime4K_Upscale_CNN_x2_M",
            "Anime4K_Restore_CNN_S",
            "Anime4K_AutoDownscalePre_x2",
            "Anime4K_AutoDownscalePre_x4",
            "Anime4K_Upscale_CNN_x2_S",
        ],
        "Mode B+B (Fast)": [
            "Anime4K_Clamp_Highlights",
            "Anime4K_Restore_CNN_Soft_M",
            "Anime4K_Upscale_CNN_x2_M",
            "Anime4K_AutoDownscalePre_x2",
            "Anime4K_AutoDownscalePre_x4",
            "Anime4K_Restore_CNN_Soft_S",
            "Anime4K_Upscale_CNN_x2_S",
        ],
        "Mode C+A (Fast)": [
            "Anime4K_Clamp_Highlights",
            "Anime4K_Upscale_Denoise_CNN_x2_M",
            "Anime4K_AutoDownscalePre_x2",
            "Anime4K_AutoDownscalePre_x4",
            "Anime4K_Restore_CNN_S",
            "Anime4K_Upscale_CNN_x2_S",
        ],
    ]

    // MARK: - Initialization

    init?(device: MTLDevice) {
        self.device = device

        guard let queue = device.makeCommandQueue() else {
            NSLog("[Anime4K] Failed to create command queue")
            return nil
        }
        self.commandQueue = queue

        // Load the pre-compiled metallib from bundle resources
        let execPath = ProcessInfo.processInfo.arguments[0]
        let macosDir = (execPath as NSString).deletingLastPathComponent
        let contentsDir = (macosDir as NSString).deletingLastPathComponent
        let metallibPath = contentsDir + "/Resources/default.metallib"

        if FileManager.default.fileExists(atPath: metallibPath) {
            do {
                let url = URL(fileURLWithPath: metallibPath)
                let data = try Data(contentsOf: url)
                self.library = try device.makeLibrary(data: data, options: nil)
                NSLog("[Anime4K] Loaded pre-compiled metallib from: %@", metallibPath)
            } catch {
                NSLog("[Anime4K] Failed to load metallib: \(error)")
                return nil
            }
        } else {
            // Fallback: compile from embedded source at runtime
            NSLog("[Anime4K] No pre-compiled metallib found, would compile from source")
            // For now, fail - the build script should always generate default.metallib
            return nil
        }

        // Create sampler state (linear filtering, clamp to edge)
        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.mipFilter = .none
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .clampToEdge
        samplerDesc.normalizedCoordinates = true

        guard let sampler = device.makeSamplerState(descriptor: samplerDesc) else {
            NSLog("[Anime4K] Failed to create sampler state")
            return nil
        }
        self.samplerState = sampler

        NSLog("[Anime4K] Metal pipeline initialized")
    }

    // MARK: - Public API

    /// Activate a shader preset
    func activatePreset(_ presetName: String, inputWidth: Int, inputHeight: Int) -> Bool {
        guard let shaderFiles = Self.presetDefinitions[presetName] else {
            NSLog("[Anime4K] Unknown preset: %@", presetName)
            return false
        }

        // Determine scale factor from preset (upscale = 2x, others = 1x)
        let isUpscale = presetName.contains("Upscale") ||
                        shaderFiles.contains { $0.contains("Upscale") }
        self.scaleFactor = isUpscale ? 2 : 1

        self.inputWidth = inputWidth
        self.inputHeight = inputHeight

        // Compile/load all required kernel functions
        let requiredKernels = Set(shaderFiles.flatMap { shaderFile in
            getKernelNamesForShader(shaderFile)
        })

        for kernelName in requiredKernels {
            if pipelineStates[kernelName] == nil {
                guard let function = library.makeFunction(name: kernelName) else {
                    NSLog("[Anime4K] Kernel function not found: %@", kernelName)
                    continue
                }

                do {
                    let pipeline = try device.makeComputePipelineState(function: function)
                    pipelineStates[kernelName] = pipeline
                    NSLog("[Anime4K] Compiled pipeline: %@", kernelName)
                } catch {
                    NSLog("[Anime4K] Failed to compile pipeline %@: \(error)", kernelName)
                    return false
                }
            }
        }

        // Allocate intermediate textures
        allocateIntermediateTextures(shaderFiles: shaderFiles,
                                     inputWidth: inputWidth,
                                     inputHeight: inputHeight)

        // Create preset configuration
        let passes = shaderFiles.map { filename in
            ComputePass(kernelName: "", shaderFile: filename, passIndex: 0)
        }
        currentPreset = Anime4KPreset(name: presetName, passes: shaderFiles)

        isActive = true
        NSLog("[Anime4K] Activated preset: %@ (%dx%d → %dx%d, %d passes)",
              presetName, inputWidth, inputHeight,
              inputWidth * scaleFactor, inputHeight * scaleFactor,
              shaderFiles.count)

        return true
    }

    /// Deactivate the current preset
    func deactivate() {
        currentPreset = nil
        isActive = false
        intermediateTextures.removeAll()
        sourceTexture = nil
        outputTexture = nil
        NSLog("[Anime4K] Deactivated")
    }

    /// Process a frame through the Anime4K pipeline
    /// - Parameters:
    ///   - sourceTexture: Input texture from mpv render (IOSurface-backed)
    ///   - commandBuffer: Command buffer to encode compute passes
    /// - Returns: Output texture containing the processed frame
    func processFrame(sourceTexture: MTLTexture,
                      commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        guard isActive, let preset = currentPreset else {
            return sourceTexture
        }

        // Update source texture reference
        self.sourceTexture = sourceTexture

        // Encode all compute passes
        let encoder = commandBuffer.makeComputeCommandEncoder()
        guard let encoder = encoder else {
            NSLog("[Anime4K] Failed to create compute encoder")
            return sourceTexture
        }

        encoder.label = "Anime4K Compute Pipeline"

        // Chain passes together
        var currentInput = sourceTexture

        for (index, shaderFile) in preset.passes.enumerated() {
            let kernelNames = getKernelNamesForShader(shaderFile)

            for kernelName in kernelNames {
                guard let pipeline = pipelineStates[kernelName] else {
                    NSLog("[Anime4K] Pipeline not found: %@", kernelName)
                    continue
                }

                encoder.setComputePipelineState(pipeline)

                // Bind input texture at index 0
                encoder.setTexture(currentInput, index: 0)

                // Determine output texture
                let outputTexture: MTLTexture
                if index == preset.passes.count - 1 && kernelName == kernelNames.last! {
                    // Final pass - use display output texture
                    outputTexture = ensureOutputTexture(width: inputWidth * scaleFactor,
                                                        height: inputHeight * scaleFactor)
                } else {
                    // Intermediate pass - use intermediate texture
                    outputTexture = intermediateTextures[index].texture
                }

                // Bind output texture at index 1
                encoder.setTexture(outputTexture, index: 1)

                // Bind sampler at index 0
                encoder.setSamplerState(samplerState, index: 0)

                // Calculate thread groups
                let width = outputTexture.width
                let height = outputTexture.height
                let threadGroups = MTLSize(width: (width + threadGroupSize.width - 1) / threadGroupSize.width,
                                           height: (height + threadGroupSize.height - 1) / threadGroupSize.height,
                                           depth: 1)

                encoder.dispatchThreads(threadGroups, threadsPerThreadgroup: threadGroupSize)

                // Next pass reads from this pass's output
                currentInput = outputTexture
            }
        }

        encoder.endEncoding()

        self.outputTexture = currentInput
        return currentInput
    }

    /// Get the output texture dimensions for a given input size
    func getOutputDimensions(inputWidth: Int, inputHeight: Int) -> (width: Int, height: Int) {
        return (inputWidth * scaleFactor, inputHeight * scaleFactor)
    }

    // MARK: - Private Methods

    /// Extract kernel function names from a shader file
    private func getKernelNamesForShader(_ shaderFile: String) -> [String] {
        // Each shader file contains one or more kernel functions
        // Naming convention: Anime4K_<ShaderName>_pass<N>_<Description>
        // We need to find all kernel functions that start with the shader name

        // For now, use a simple mapping based on shader type
        // This should be enhanced to parse the actual metallib or shader source

        if shaderFile.contains("Clamp_Highlights") {
            // Clamp_Highlights has 3 passes
            return [
                "Anime4K_Clamp_Highlights_pass0_Anime4K_v4_0_De_Ring_Compute_Statistics",
                "Anime4K_Clamp_Highlights_pass1_Anime4K_v4_0_De_Ring_Compute_Statistics",
                "Anime4K_Clamp_Highlights_pass2_Anime4K_v4_0_De_Ring_Compute_Statistics"
            ]
        } else if shaderFile.contains("Restore_CNN_S") && !shaderFile.contains("Soft") {
            return [
                "Anime4K_Restore_CNN_S_pass0_Anime4K_v4_0_Restore_CNN_S_Conv_4x3x3x3",
                "Anime4K_Restore_CNN_S_pass1_Anime4K_v4_0_Restore_CNN_S_Conv_4x3x3x8",
                "Anime4K_Restore_CNN_S_pass2_Anime4K_v4_0_Restore_CNN_S_Conv_4x3x3x8",
                "Anime4K_Restore_CNN_S_pass3_Anime4K_v4_0_Restore_CNN_S_Residual"
            ]
        } else if shaderFile.contains("Restore_CNN_M") && !shaderFile.contains("Soft") {
            return [
                "Anime4K_Restore_CNN_M_pass0_Anime4K_v4_0_Restore_CNN_M_Conv_4x3x3x3",
                "Anime4K_Restore_CNN_M_pass1_Anime4K_v4_0_Restore_CNN_M_Conv_4x3x3x8",
                "Anime4K_Restore_CNN_M_pass2_Anime4K_v4_0_Restore_CNN_M_Conv_4x3x3x8",
                "Anime4K_Restore_CNN_M_pass3_Anime4K_v4_0_Restore_CNN_M_Conv_4x3x3x8",
                "Anime4K_Restore_CNN_M_pass4_Anime4K_v4_0_Restore_CNN_M_Conv_4x3x3x8",
                "Anime4K_Restore_CNN_M_pass5_Anime4K_v4_0_Restore_CNN_M_Conv_4x3x3x8",
                "Anime4K_Restore_CNN_M_pass6_Anime4K_v4_0_Restore_CNN_M_Residual"
            ]
        } else if shaderFile.contains("Restore_CNN_VL") && !shaderFile.contains("Soft") {
            return [
                "Anime4K_Restore_CNN_VL_pass0_Anime4K_v4_0_Restore_CNN_VL_Conv_4x3x3x3",
                "Anime4K_Restore_CNN_VL_pass1_Anime4K_v4_0_Restore_CNN_VL_Conv_4x3x3x8",
                "Anime4K_Restore_CNN_VL_pass2_Anime4K_v4_0_Restore_CNN_VL_Conv_4x3x3x8",
                "Anime4K_Restore_CNN_VL_pass3_Anime4K_v4_0_Restore_CNN_VL_Conv_4x3x3x8",
                "Anime4K_Restore_CNN_VL_pass4_Anime4K_v4_0_Restore_CNN_VL_Conv_4x3x3x8",
                "Anime4K_Restore_CNN_VL_pass5_Anime4K_v4_0_Restore_CNN_VL_Conv_4x3x3x8",
                "Anime4K_Restore_CNN_VL_pass6_Anime4K_v4_0_Restore_CNN_VL_Conv_4x3x3x8",
                "Anime4K_Restore_CNN_VL_pass7_Anime4K_v4_0_Restore_CNN_VL_Conv_4x3x3x8",
                "Anime4K_Restore_CNN_VL_pass8_Anime4K_v4_0_Restore_CNN_VL_Conv_4x3x3x8",
                "Anime4K_Restore_CNN_VL_pass9_Anime4K_v4_0_Restore_CNN_VL_Conv_4x3x3x8",
                "Anime4K_Restore_CNN_VL_pass10_Anime4K_v4_0_Restore_CNN_VL_Conv_4x3x3x8",
                "Anime4K_Restore_CNN_VL_pass11_Anime4K_v4_0_Restore_CNN_VL_Conv_4x3x3x8",
                "Anime4K_Restore_CNN_VL_pass12_Anime4K_v4_0_Restore_CNN_VL_Conv_4x3x3x8",
                "Anime4K_Restore_CNN_VL_pass13_Anime4K_v4_0_Restore_CNN_VL_Conv_4x3x3x8",
                "Anime4K_Restore_CNN_VL_pass14_Anime4K_v4_0_Restore_CNN_VL_Conv_4x3x3x8",
                "Anime4K_Restore_CNN_VL_pass15_Anime4K_v4_0_Restore_CNN_VL_Residual"
            ]
        } else if shaderFile.contains("Upscale_CNN_x2_S") {
            return [
                "Anime4K_Upscale_CNN_x2_S_pass0_Anime4K_v3_2_Upscale_CNN_x2_S_Conv_4x3x3x3",
                "Anime4K_Upscale_CNN_x2_S_pass1_Anime4K_v3_2_Upscale_CNN_x2_S_Conv_4x3x3x8",
                "Anime4K_Upscale_CNN_x2_S_pass2_Anime4K_v3_2_Upscale_CNN_x2_S_Conv_4x3x3x8",
                "Anime4K_Upscale_CNN_x2_S_pass3_Anime4K_v3_2_Upscale_CNN_x2_S_Deconv_4x3x3x8"
            ]
        } else if shaderFile.contains("Upscale_CNN_x2_M") {
            return [
                "Anime4K_Upscale_CNN_x2_M_pass0_Anime4K_v3_2_Upscale_CNN_x2_M_Conv_4x3x3x3",
                "Anime4K_Upscale_CNN_x2_M_pass1_Anime4K_v3_2_Upscale_CNN_x2_M_Conv_4x3x3x8",
                "Anime4K_Upscale_CNN_x2_M_pass2_Anime4K_v3_2_Upscale_CNN_x2_M_Conv_4x3x3x8",
                "Anime4K_Upscale_CNN_x2_M_pass3_Anime4K_v3_2_Upscale_CNN_x2_M_Conv_4x3x3x8",
                "Anime4K_Upscale_CNN_x2_M_pass4_Anime4K_v3_2_Upscale_CNN_x2_M_Conv_4x3x3x8",
                "Anime4K_Upscale_CNN_x2_M_pass5_Anime4K_v3_2_Upscale_CNN_x2_M_Conv_4x3x3x8",
                "Anime4K_Upscale_CNN_x2_M_pass6_Anime4K_v3_2_Upscale_CNN_x2_M_Conv_4x3x3x8",
                "Anime4K_Upscale_CNN_x2_M_pass7_Anime4K_v3_2_Upscale_CNN_x2_M_Deconv_4x3x3x8"
            ]
        } else if shaderFile.contains("Upscale_CNN_x2_VL") {
            return [
                "Anime4K_Upscale_CNN_x2_VL_pass0_Anime4K_v3_2_Upscale_CNN_x2_VL_Conv_4x3x3x3",
                "Anime4K_Upscale_CNN_x2_VL_pass1_Anime4K_v3_2_Upscale_CNN_x2_VL_Conv_4x3x3x8",
                "Anime4K_Upscale_CNN_x2_VL_pass2_Anime4K_v3_2_Upscale_CNN_x2_VL_Conv_4x3x3x8",
                "Anime4K_Upscale_CNN_x2_VL_pass3_Anime4K_v3_2_Upscale_CNN_x2_VL_Conv_4x3x3x8",
                "Anime4K_Upscale_CNN_x2_VL_pass4_Anime4K_v3_2_Upscale_CNN_x2_VL_Conv_4x3x3x8",
                "Anime4K_Upscale_CNN_x2_VL_pass5_Anime4K_v3_2_Upscale_CNN_x2_VL_Conv_4x3x3x8",
                "Anime4K_Upscale_CNN_x2_VL_pass6_Anime4K_v3_2_Upscale_CNN_x2_VL_Conv_4x3x3x8",
                "Anime4K_Upscale_CNN_x2_VL_pass7_Anime4K_v3_2_Upscale_CNN_x2_VL_Conv_4x3x3x8",
                "Anime4K_Upscale_CNN_x2_VL_pass8_Anime4K_v3_2_Upscale_CNN_x2_VL_Conv_4x3x3x8",
                "Anime4K_Upscale_CNN_x2_VL_pass9_Anime4K_v3_2_Upscale_CNN_x2_VL_Conv_4x3x3x8",
                "Anime4K_Upscale_CNN_x2_VL_pass10_Anime4K_v3_2_Upscale_CNN_x2_VL_Conv_4x3x3x8",
                "Anime4K_Upscale_CNN_x2_VL_pass11_Anime4K_v3_2_Upscale_CNN_x2_VL_Conv_4x3x3x8",
                "Anime4K_Upscale_CNN_x2_VL_pass12_Anime4K_v3_2_Upscale_CNN_x2_VL_Conv_4x3x3x8",
                "Anime4K_Upscale_CNN_x2_VL_pass13_Anime4K_v3_2_Upscale_CNN_x2_VL_Conv_4x3x3x8",
                "Anime4K_Upscale_CNN_x2_VL_pass14_Anime4K_v3_2_Upscale_CNN_x2_VL_Conv_4x3x3x8",
                "Anime4K_Upscale_CNN_x2_VL_pass15_Anime4K_v3_2_Upscale_CNN_x2_VL_Conv_4x3x3x8",
                "Anime4K_Upscale_CNN_x2_VL_pass16_Anime4K_v3_2_Upscale_CNN_x2_VL_Deconv_4x3x3x8"
            ]
        } else if shaderFile.contains("Upscale_Denoise_CNN_x2_S") {
            return [
                "Anime4K_Upscale_Denoise_CNN_x2_S_pass0_Anime4K_v3_2_Upscale_Denoise_CNN_x2_S_Conv_4x3x3x3",
                "Anime4K_Upscale_Denoise_CNN_x2_S_pass1_Anime4K_v3_2_Upscale_Denoise_CNN_x2_S_Conv_4x3x3x8",
                "Anime4K_Upscale_Denoise_CNN_x2_S_pass2_Anime4K_v3_2_Upscale_Denoise_CNN_x2_S_Conv_4x3x3x8",
                "Anime4K_Upscale_Denoise_CNN_x2_S_pass3_Anime4K_v3_2_Upscale_Denoise_CNN_x2_S_Deconv_4x3x3x8"
            ]
        } else if shaderFile.contains("Upscale_Denoise_CNN_x2_M") {
            return [
                "Anime4K_Upscale_Denoise_CNN_x2_M_pass0_Anime4K_v3_2_Upscale_Denoise_CNN_x2_M_Conv_4x3x3x3",
                "Anime4K_Upscale_Denoise_CNN_x2_M_pass1_Anime4K_v3_2_Upscale_Denoise_CNN_x2_M_Conv_4x3x3x8",
                "Anime4K_Upscale_Denoise_CNN_x2_M_pass2_Anime4K_v3_2_Upscale_Denoise_CNN_x2_M_Conv_4x3x3x8",
                "Anime4K_Upscale_Denoise_CNN_x2_M_pass3_Anime4K_v3_2_Upscale_Denoise_CNN_x2_M_Conv_4x3x3x8",
                "Anime4K_Upscale_Denoise_CNN_x2_M_pass4_Anime4K_v3_2_Upscale_Denoise_CNN_x2_M_Conv_4x3x3x8",
                "Anime4K_Upscale_Denoise_CNN_x2_M_pass5_Anime4K_v3_2_Upscale_Denoise_CNN_x2_M_Conv_4x3x3x8",
                "Anime4K_Upscale_Denoise_CNN_x2_M_pass6_Anime4K_v3_2_Upscale_Denoise_CNN_x2_M_Conv_4x3x3x8",
                "Anime4K_Upscale_Denoise_CNN_x2_M_pass7_Anime4K_v3_2_Upscale_Denoise_CNN_x2_M_Deconv_4x3x3x8"
            ]
        } else if shaderFile.contains("Upscale_Denoise_CNN_x2_VL") {
            return [
                "Anime4K_Upscale_Denoise_CNN_x2_VL_pass0_Anime4K_v3_2_Upscale_Denoise_CNN_x2_VL_Conv_4x3x3x3",
                "Anime4K_Upscale_Denoise_CNN_x2_VL_pass1_Anime4K_v3_2_Upscale_Denoise_CNN_x2_VL_Conv_4x3x3x8",
                "Anime4K_Upscale_Denoise_CNN_x2_VL_pass2_Anime4K_v3_2_Upscale_Denoise_CNN_x2_VL_Conv_4x3x3x8",
                "Anime4K_Upscale_Denoise_CNN_x2_VL_pass3_Anime4K_v3_2_Upscale_Denoise_CNN_x2_VL_Conv_4x3x3x8",
                "Anime4K_Upscale_Denoise_CNN_x2_VL_pass4_Anime4K_v3_2_Upscale_Denoise_CNN_x2_VL_Conv_4x3x3x8",
                "Anime4K_Upscale_Denoise_CNN_x2_VL_pass5_Anime4K_v3_2_Upscale_Denoise_CNN_x2_VL_Conv_4x3x3x8",
                "Anime4K_Upscale_Denoise_CNN_x2_VL_pass6_Anime4K_v3_2_Upscale_Denoise_CNN_x2_VL_Conv_4x3x3x8",
                "Anime4K_Upscale_Denoise_CNN_x2_VL_pass7_Anime4K_v3_2_Upscale_Denoise_CNN_x2_VL_Conv_4x3x3x8",
                "Anime4K_Upscale_Denoise_CNN_x2_VL_pass8_Anime4K_v3_2_Upscale_Denoise_CNN_x2_VL_Conv_4x3x3x8",
                "Anime4K_Upscale_Denoise_CNN_x2_VL_pass9_Anime4K_v3_2_Upscale_Denoise_CNN_x2_VL_Conv_4x3x3x8",
                "Anime4K_Upscale_Denoise_CNN_x2_VL_pass10_Anime4K_v3_2_Upscale_Denoise_CNN_x2_VL_Conv_4x3x3x8",
                "Anime4K_Upscale_Denoise_CNN_x2_VL_pass11_Anime4K_v3_2_Upscale_Denoise_CNN_x2_VL_Conv_4x3x3x8",
                "Anime4K_Upscale_Denoise_CNN_x2_VL_pass12_Anime4K_v3_2_Upscale_Denoise_CNN_x2_VL_Conv_4x3x3x8",
                "Anime4K_Upscale_Denoise_CNN_x2_VL_pass13_Anime4K_v3_2_Upscale_Denoise_CNN_x2_VL_Conv_4x3x3x8",
                "Anime4K_Upscale_Denoise_CNN_x2_VL_pass14_Anime4K_v3_2_Upscale_Denoise_CNN_x2_VL_Conv_4x3x3x8",
                "Anime4K_Upscale_Denoise_CNN_x2_VL_pass15_Anime4K_v3_2_Upscale_Denoise_CNN_x2_VL_Conv_4x3x3x8",
                "Anime4K_Upscale_Denoise_CNN_x2_VL_pass16_Anime4K_v3_2_Upscale_Denoise_CNN_x2_VL_Deconv_4x3x3x8"
            ]
        } else if shaderFile.contains("AutoDownscalePre_x2") {
            return [
                "Anime4K_AutoDownscalePre_x2_pass0_Anime4K_v4_0_AutoDownscalePre_x2",
            ]
        } else if shaderFile.contains("AutoDownscalePre_x4") {
            return [
                "Anime4K_AutoDownscalePre_x4_pass0_Anime4K_v4_0_AutoDownscalePre_x4",
            ]
        } else if shaderFile.contains("Restore_CNN_Soft") {
            // Soft variants have similar structure but different weights
            if shaderFile.contains("Soft_S") {
                return [
                    "Anime4K_Restore_CNN_Soft_S_pass0_Anime4K_v4_0_Restore_CNN_Soft_S_Conv_4x3x3x3",
                    "Anime4K_Restore_CNN_Soft_S_pass1_Anime4K_v4_0_Restore_CNN_Soft_S_Conv_4x3x3x8",
                    "Anime4K_Restore_CNN_Soft_S_pass2_Anime4K_v4_0_Restore_CNN_Soft_S_Conv_4x3x3x8",
                    "Anime4K_Restore_CNN_Soft_S_pass3_Anime4K_v4_0_Restore_CNN_Soft_S_Residual"
                ]
            } else if shaderFile.contains("Soft_M") {
                return [
                    "Anime4K_Restore_CNN_Soft_M_pass0_Anime4K_v4_0_Restore_CNN_Soft_M_Conv_4x3x3x3",
                    "Anime4K_Restore_CNN_Soft_M_pass1_Anime4K_v4_0_Restore_CNN_Soft_M_Conv_4x3x3x8",
                    "Anime4K_Restore_CNN_Soft_M_pass2_Anime4K_v4_0_Restore_CNN_Soft_M_Conv_4x3x3x8",
                    "Anime4K_Restore_CNN_Soft_M_pass3_Anime4K_v4_0_Restore_CNN_Soft_M_Conv_4x3x3x8",
                    "Anime4K_Restore_CNN_Soft_M_pass4_Anime4K_v4_0_Restore_CNN_Soft_M_Conv_4x3x3x8",
                    "Anime4K_Restore_CNN_Soft_M_pass5_Anime4K_v4_0_Restore_CNN_Soft_M_Conv_4x3x3x8",
                    "Anime4K_Restore_CNN_Soft_M_pass6_Anime4K_v4_0_Restore_CNN_Soft_M_Residual"
                ]
            } else if shaderFile.contains("Soft_VL") {
                return [
                    "Anime4K_Restore_CNN_Soft_VL_pass0_Anime4K_v4_0_Restore_CNN_Soft_VL_Conv_4x3x3x3",
                    "Anime4K_Restore_CNN_Soft_VL_pass1_Anime4K_v4_0_Restore_CNN_Soft_VL_Conv_4x3x3x8",
                    "Anime4K_Restore_CNN_Soft_VL_pass2_Anime4K_v4_0_Restore_CNN_Soft_VL_Conv_4x3x3x8",
                    "Anime4K_Restore_CNN_Soft_VL_pass3_Anime4K_v4_0_Restore_CNN_Soft_VL_Conv_4x3x3x8",
                    "Anime4K_Restore_CNN_Soft_VL_pass4_Anime4K_v4_0_Restore_CNN_Soft_VL_Conv_4x3x3x8",
                    "Anime4K_Restore_CNN_Soft_VL_pass5_Anime4K_v4_0_Restore_CNN_Soft_VL_Conv_4x3x3x8",
                    "Anime4K_Restore_CNN_Soft_VL_pass6_Anime4K_v4_0_Restore_CNN_Soft_VL_Conv_4x3x3x8",
                    "Anime4K_Restore_CNN_Soft_VL_pass7_Anime4K_v4_0_Restore_CNN_Soft_VL_Conv_4x3x3x8",
                    "Anime4K_Restore_CNN_Soft_VL_pass8_Anime4K_v4_0_Restore_CNN_Soft_VL_Conv_4x3x3x8",
                    "Anime4K_Restore_CNN_Soft_VL_pass9_Anime4K_v4_0_Restore_CNN_Soft_VL_Conv_4x3x3x8",
                    "Anime4K_Restore_CNN_Soft_VL_pass10_Anime4K_v4_0_Restore_CNN_Soft_VL_Conv_4x3x3x8",
                    "Anime4K_Restore_CNN_Soft_VL_pass11_Anime4K_v4_0_Restore_CNN_Soft_VL_Conv_4x3x3x8",
                    "Anime4K_Restore_CNN_Soft_VL_pass12_Anime4K_v4_0_Restore_CNN_Soft_VL_Conv_4x3x3x8",
                    "Anime4K_Restore_CNN_Soft_VL_pass13_Anime4K_v4_0_Restore_CNN_Soft_VL_Conv_4x3x3x8",
                    "Anime4K_Restore_CNN_Soft_VL_pass14_Anime4K_v4_0_Restore_CNN_Soft_VL_Conv_4x3x3x8",
                    "Anime4K_Restore_CNN_Soft_VL_pass15_Anime4K_v4_0_Restore_CNN_Soft_VL_Residual"
                ]
            }
        }

        // Fallback: try to find any kernel containing the shader name
        let allFunctions = library.functions
        let shaderPrefix = shaderFile.replacingOccurrences(of: ".metal", with: "")
        let matchingNames = allFunctions.filter { $0.contains(shaderPrefix) }

        if matchingNames.isEmpty {
            NSLog("[Anime4K] No kernel functions found for shader: %@", shaderFile)
        }

        return matchingNames
    }

    /// Allocate intermediate textures for pass chaining
    private func allocateIntermediateTextures(shaderFiles: [String],
                                              inputWidth: Int,
                                              inputHeight: Int) {
        // Clear existing textures
        intermediateTextures.removeAll()

        var currentWidth = inputWidth
        var currentHeight = inputHeight

        for (index, shaderFile) in shaderFiles.enumerated() {
            // Check if this shader upscales
            let isUpscale = shaderFile.contains("Upscale") &&
                           !shaderFile.contains("AutoDownscale")

            if isUpscale {
                currentWidth *= 2
                currentHeight *= 2
            }

            // Create intermediate texture
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm,
                width: currentWidth,
                height: currentHeight,
                mipmapped: false
            )
            descriptor.usage = [.shaderRead, .shaderWrite]
            descriptor.storageMode = .private

            if let texture = device.makeTexture(descriptor: descriptor) {
                intermediateTextures.append(IntermediateTexture(
                    texture: texture,
                    width: currentWidth,
                    height: currentHeight
                ))
            }
        }
    }

    /// Ensure output texture exists at the specified dimensions
    private func ensureOutputTexture(width: Int, height: Int) -> MTLTexture {
        if let existing = outputTexture,
           existing.width == width && existing.height == height {
            return existing
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
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
