// ---------------------------------------------------------------------------
// Anime4K Protocol-Based Preset Architecture
// ---------------------------------------------------------------------------
// This file defines the protocol-based architecture for Anime4K presets.
// It replaces the hardcoded kernel name mapping with type-safe definitions.
//
// Architecture:
//   Anime4KMode → defines a preset (e.g., "Mode A (Fast)")
//   Anime4KShaderPass → defines a single pass in the preset chain
//
// Benefits:
//   - Compile-time validation of preset definitions
//   - Easy to add new presets without modifying pipeline code
//   - Testable with unit tests
//   - Self-documenting preset structure
// ---------------------------------------------------------------------------

import Foundation

// MARK: - Anime4KShaderPass Protocol

/// Defines a single shader pass in an Anime4K preset chain
///
/// Each pass represents one compute shader operation. Passes are chained together,
/// with the output of one pass becoming the input of the next.
///
/// Example:
/// ```swift
/// let restorePass = Anime4KShaderPass(
///     shaderFile: "Anime4K_Restore_CNN_M",
///     kernelFunction: "Anime4K_Restore_CNN_M_pass0_...",
///     outputComponents: 4
/// )
/// ```
public struct Anime4KShaderPass: Sendable, CustomStringConvertible {
    /// Shader filename without extension (e.g., "Anime4K_Restore_CNN_M")
    public let shaderFile: String

    /// Primary kernel function name for this pass
    /// Note: Some shaders have multiple kernel functions (multi-pass)
    public let kernelFunction: String

    /// Number of color components in output (typically 4 for RGBA)
    public let outputComponents: Int

    /// Whether this pass performs 2x upscaling
    public let isUpscaling: Bool

    /// Human-readable description of this pass
    public let description: String

    public init(
        shaderFile: String,
        kernelFunction: String,
        outputComponents: Int = 4,
        isUpscaling: Bool = false,
        description: String = ""
    ) {
        self.shaderFile = shaderFile
        self.kernelFunction = kernelFunction
        self.outputComponents = outputComponents
        self.isUpscaling = isUpscaling
        self.description = description.isEmpty ? shaderFile : description
    }

    /// All kernel functions required by this pass
    /// Some shaders require multiple kernel passes (e.g., conv + residual)
    public var allKernelFunctions: [String] {
        // For now, returns single kernel - will be expanded with metadata extraction
        return [kernelFunction]
    }
}

// MARK: - Anime4KMode Protocol

/// Defines an Anime4K processing mode (preset)
///
/// A mode is a sequence of shader passes that transform the input frame.
/// Modes are identified by user-facing names like "Mode A (Fast)".
///
/// Example:
/// ```swift
/// struct ModeAFast: Anime4KMode {
///     static let displayName = "Mode A (Fast)"
///     static let shaderPasses = [/* ... */]
///     static let scaleFactor = 2
/// }
/// ```
public protocol Anime4KMode: Sendable, CustomStringConvertible {
    /// User-facing display name (e.g., "Mode A (Fast)")
    static var displayName: String { get }

    /// Ordered sequence of shader passes
    static var shaderPasses: [Anime4KShaderPass] { get }

    /// Output scale factor (1 = same size, 2 = 2x upscale)
    static var scaleFactor: Int { get }

    /// Hardware recommendation level
    static var hardwareRequirement: Anime4KHardwareRequirement { get }

    /// Human-readable description for UI
    static var presetDescription: String { get }
}

// MARK: - Hardware Requirement

/// Hardware requirement level for a preset
public enum Anime4KHardwareRequirement: Sendable, CustomStringConvertible {
    /// Runs smoothly on all Apple Silicon (M1+)
    case base

    /// Recommended for M1 Pro / M2 or better
    case enhanced

    /// Requires M2 Pro / M3 or better for smooth playback
    case pro

    /// For high-end hardware only (M3 Max, M4)
    case extreme

    public var description: String {
        switch self {
        case .base:
            return "All Apple Silicon (M1+)"
        case .enhanced:
            return "M1 Pro / M2 or better"
        case .pro:
            return "M2 Pro / M3 or better"
        case .extreme:
            return "M3 Max / M4 or better"
        }
    }

    /// Icon representation for UI
    public var icon: String {
        switch self {
        case .base: return "cpu"
        case .enhanced: return "cpu.fill"
        case .pro: return "cpu.fill.badge.bolt"
        case .extreme: return "cpu.fill.badge.exclamationmark"
        }
    }
}

// MARK: - Default Protocol Implementations

public extension Anime4KMode {
    var description: String {
        Self.displayName
    }

    static var scaleFactor: Int {
        // Default: check if any pass upscales
        shaderPasses.contains { $0.isUpscaling } ? 2 : 1
    }

    static var hardwareRequirement: Anime4KHardwareRequirement {
        // Default heuristic based on pass count and types
        let passCount = shaderPasses.count
        let hasVeryLarge = shaderPasses.contains { $0.shaderFile.contains("_VL") }
        let hasMedium = shaderPasses.contains { $0.shaderFile.contains("_M") }

        if hasVeryLarge && passCount > 5 {
            return .pro
        } else if hasVeryLarge || passCount > 4 {
            return .enhanced
        } else if hasMedium {
            return .base
        } else {
            return .base
        }
    }

    static var presetDescription: String {
        // Generate description from shader types
        var components: [String] = []

        if shaderPasses.contains(where: { $0.shaderFile.contains("Restore") }) {
            components.append("Restoration")
        }
        if shaderPasses.contains(where: { $0.shaderFile.contains("Upscale") }) {
            components.append("2x Upscale")
        }
        if shaderPasses.contains(where: { $0.shaderFile.contains("Denoise") }) {
            components.append("Denoise")
        }
        if shaderPasses.contains(where: { $0.shaderFile.contains("Soft") }) {
            components.append("Soft (subtle)")
        }

        if components.isEmpty {
            return "Custom enhancement chain"
        }

        return components.joined(separator: " + ")
    }
}

// MARK: - Preset Registry

/// Registry of all available Anime4K presets
///
/// This replaces the hardcoded presetDefinitions dictionary.
/// Presets are registered at compile-time and discovered at runtime.
public struct Anime4KPresetRegistry {
    private static var registeredPresets: [String: Anime4KMode.Type] = [:]

    /// Register a preset type
    public static func register<T: Anime4KMode>(_ presetType: T.Type) {
        registeredPresets[T.displayName] = presetType
    }

    /// Get a preset by display name
    public static func preset(named name: String) -> Anime4KMode.Type? {
        return registeredPresets[name]
    }

    /// Get all registered preset names
    public static func allPresetNames() -> [String] {
        return Array(registeredPresets.keys).sorted()
    }

    /// Get all presets as mode instances
    public static func allPresets() -> [any Anime4KMode.Type] {
        return Array(registeredPresets.values)
    }
}

// MARK: - Concrete Preset Implementations

// ---------------------------------------------------------------------------
// HQ Presets - Maximum Quality (M2 Pro+ recommended)
// ---------------------------------------------------------------------------

/// Mode A (HQ) - Aggressive restoration with very large CNN
public struct ModeAHQ: Anime4KMode {
    public static let displayName = "Mode A (HQ)"
    public static let presetDescription = "Aggressive edge restoration for 720p→4K"

    public static let shaderPasses: [Anime4KShaderPass] = [
        Anime4KShaderPass(shaderFile: "Anime4K_Clamp_Highlights", kernelFunction: "Anime4Kv40DeRingComputeStatistics", description: "Clamp Highlights"),
        Anime4KShaderPass(shaderFile: "Anime4K_Restore_CNN_VL", kernelFunction: "Anime4Kv40RestoreCNNVLConv4x3x3x3", description: "Restore VL"),
        Anime4KShaderPass(shaderFile: "Anime4K_Upscale_CNN_x2_VL", kernelFunction: "Anime4Kv32UpscaleCNNx2VLConv4x3x3x3", isUpscaling: true, description: "Upscale x2 VL"),
        Anime4KShaderPass(shaderFile: "Anime4K_AutoDownscalePre_x2", kernelFunction: "Anime4Kv40AutoDownscalePrex2", description: "Auto Downscale x2"),
        Anime4KShaderPass(shaderFile: "Anime4K_AutoDownscalePre_x4", kernelFunction: "Anime4Kv32AutoDownscalePrex4", description: "Auto Downscale x4"),
        Anime4KShaderPass(shaderFile: "Anime4K_Upscale_CNN_x2_M", kernelFunction: "Anime4Kv32UpscaleCNNx2MConv4x3x3x3", isUpscaling: true, description: "Upscale x2 M"),
    ]

    public static let hardwareRequirement: Anime4KHardwareRequirement = .extreme
}

/// Mode B (HQ) - Soft restoration with very large CNN
public struct ModeBHQ: Anime4KMode {
    public static let displayName = "Mode B (HQ)"
    public static let presetDescription = "Soft restoration preserving original art style"

    public static let shaderPasses: [Anime4KShaderPass] = [
        Anime4KShaderPass(shaderFile: "Anime4K_Clamp_Highlights", kernelFunction: "Anime4Kv40DeRingComputeStatistics", description: "Clamp Highlights"),
        Anime4KShaderPass(shaderFile: "Anime4K_Restore_CNN_Soft_VL", kernelFunction: "Anime4Kv40RestoreCNNSoftVLConv4x3x3x3", description: "Restore Soft VL"),
        Anime4KShaderPass(shaderFile: "Anime4K_Upscale_CNN_x2_VL", kernelFunction: "Anime4Kv32UpscaleCNNx2VLConv4x3x3x3", isUpscaling: true, description: "Upscale x2 VL"),
        Anime4KShaderPass(shaderFile: "Anime4K_AutoDownscalePre_x2", kernelFunction: "Anime4Kv40AutoDownscalePrex2", description: "Auto Downscale x2"),
        Anime4KShaderPass(shaderFile: "Anime4K_AutoDownscalePre_x4", kernelFunction: "Anime4Kv32AutoDownscalePrex4", description: "Auto Downscale x4"),
        Anime4KShaderPass(shaderFile: "Anime4K_Upscale_CNN_x2_M", kernelFunction: "Anime4Kv32UpscaleCNNx2MConv4x3x3x3", isUpscaling: true, description: "Upscale x2 M"),
    ]

    public static let hardwareRequirement: Anime4KHardwareRequirement = .extreme
}

/// Mode C (HQ) - Denoise + upscale
public struct ModeCHQ: Anime4KMode {
    public static let displayName = "Mode C (HQ)"
    public static let presetDescription = "Denoise and upscale for noisy sources"

    public static let shaderPasses: [Anime4KShaderPass] = [
        Anime4KShaderPass(shaderFile: "Anime4K_Clamp_Highlights", kernelFunction: "Anime4Kv40DeRingComputeStatistics", description: "Clamp Highlights"),
        Anime4KShaderPass(shaderFile: "Anime4K_Upscale_Denoise_CNN_x2_VL", kernelFunction: "Anime4Kv32UpscaleDenoiseCNNx2VLConv4x3x3x3", isUpscaling: true, description: "Denoise + Upscale VL"),
        Anime4KShaderPass(shaderFile: "Anime4K_AutoDownscalePre_x2", kernelFunction: "Anime4Kv40AutoDownscalePrex2", description: "Auto Downscale x2"),
        Anime4KShaderPass(shaderFile: "Anime4K_AutoDownscalePre_x4", kernelFunction: "Anime4Kv32AutoDownscalePrex4", description: "Auto Downscale x4"),
        Anime4KShaderPass(shaderFile: "Anime4K_Upscale_CNN_x2_M", kernelFunction: "Anime4Kv32UpscaleCNNx2MConv4x3x3x3", isUpscaling: true, description: "Upscale x2 M"),
    ]

    public static let hardwareRequirement: Anime4KHardwareRequirement = .extreme
}

/// Mode A+A (HQ) - Double aggressive restoration
public struct ModeAAHQ: Anime4KMode {
    public static let displayName = "Mode A+A (HQ)"
    public static let presetDescription = "Double aggressive restoration before upscaling"

    public static let shaderPasses: [Anime4KShaderPass] = [
        Anime4KShaderPass(shaderFile: "Anime4K_Clamp_Highlights", kernelFunction: "Anime4Kv40DeRingComputeStatistics", description: "Clamp Highlights"),
        Anime4KShaderPass(shaderFile: "Anime4K_Restore_CNN_VL", kernelFunction: "Anime4Kv40RestoreCNNVLConv4x3x3x3", description: "Restore VL"),
        Anime4KShaderPass(shaderFile: "Anime4K_Upscale_CNN_x2_VL", kernelFunction: "Anime4Kv32UpscaleCNNx2VLConv4x3x3x3", isUpscaling: true, description: "Upscale x2 VL"),
        Anime4KShaderPass(shaderFile: "Anime4K_Restore_CNN_M", kernelFunction: "Anime4Kv40RestoreCNNMConv4x3x3x3", description: "Restore M"),
        Anime4KShaderPass(shaderFile: "Anime4K_AutoDownscalePre_x2", kernelFunction: "Anime4Kv40AutoDownscalePrex2", description: "Auto Downscale x2"),
        Anime4KShaderPass(shaderFile: "Anime4K_AutoDownscalePre_x4", kernelFunction: "Anime4Kv32AutoDownscalePrex4", description: "Auto Downscale x4"),
        Anime4KShaderPass(shaderFile: "Anime4K_Upscale_CNN_x2_M", kernelFunction: "Anime4Kv32UpscaleCNNx2MConv4x3x3x3", isUpscaling: true, description: "Upscale x2 M"),
    ]

    public static let hardwareRequirement: Anime4KHardwareRequirement = .extreme
}

/// Mode B+B (HQ) - Double soft restoration
public struct ModeBBHQ: Anime4KMode {
    public static let displayName = "Mode B+B (HQ)"
    public static let presetDescription = "Double soft restoration, smoothest results"

    public static let shaderPasses: [Anime4KShaderPass] = [
        Anime4KShaderPass(shaderFile: "Anime4K_Clamp_Highlights", kernelFunction: "Anime4Kv40DeRingComputeStatistics", description: "Clamp Highlights"),
        Anime4KShaderPass(shaderFile: "Anime4K_Restore_CNN_Soft_VL", kernelFunction: "Anime4Kv40RestoreCNNSoftVLConv4x3x3x3", description: "Restore Soft VL"),
        Anime4KShaderPass(shaderFile: "Anime4K_Upscale_CNN_x2_VL", kernelFunction: "Anime4Kv32UpscaleCNNx2VLConv4x3x3x3", isUpscaling: true, description: "Upscale x2 VL"),
        Anime4KShaderPass(shaderFile: "Anime4K_Restore_CNN_Soft_M", kernelFunction: "Anime4Kv40RestoreCNNSoftMConv4x3x3x3", description: "Restore Soft M"),
        Anime4KShaderPass(shaderFile: "Anime4K_AutoDownscalePre_x2", kernelFunction: "Anime4Kv40AutoDownscalePrex2", description: "Auto Downscale x2"),
        Anime4KShaderPass(shaderFile: "Anime4K_AutoDownscalePre_x4", kernelFunction: "Anime4Kv32AutoDownscalePrex4", description: "Auto Downscale x4"),
        Anime4KShaderPass(shaderFile: "Anime4K_Upscale_CNN_x2_M", kernelFunction: "Anime4Kv32UpscaleCNNx2MConv4x3x3x3", isUpscaling: true, description: "Upscale x2 M"),
    ]

    public static let hardwareRequirement: Anime4KHardwareRequirement = .extreme
}

/// Mode C+A (HQ) - Denoise + restoration
public struct ModeCAHQ: Anime4KMode {
    public static let displayName = "Mode C+A (HQ)"
    public static let presetDescription = "Denoise then restore, balanced quality"

    public static let shaderPasses: [Anime4KShaderPass] = [
        Anime4KShaderPass(shaderFile: "Anime4K_Clamp_Highlights", kernelFunction: "Anime4Kv40DeRingComputeStatistics", description: "Clamp Highlights"),
        Anime4KShaderPass(shaderFile: "Anime4K_Upscale_Denoise_CNN_x2_VL", kernelFunction: "Anime4Kv32UpscaleDenoiseCNNx2VLConv4x3x3x3", isUpscaling: true, description: "Denoise + Upscale VL"),
        Anime4KShaderPass(shaderFile: "Anime4K_AutoDownscalePre_x2", kernelFunction: "Anime4Kv40AutoDownscalePrex2", description: "Auto Downscale x2"),
        Anime4KShaderPass(shaderFile: "Anime4K_AutoDownscalePre_x4", kernelFunction: "Anime4Kv32AutoDownscalePrex4", description: "Auto Downscale x4"),
        Anime4KShaderPass(shaderFile: "Anime4K_Restore_CNN_M", kernelFunction: "Anime4Kv40RestoreCNNMConv4x3x3x3", description: "Restore M"),
        Anime4KShaderPass(shaderFile: "Anime4K_Upscale_CNN_x2_M", kernelFunction: "Anime4Kv32UpscaleCNNx2MConv4x3x3x3", isUpscaling: true, description: "Upscale x2 M"),
    ]

    public static let hardwareRequirement: Anime4KHardwareRequirement = .extreme
}

// ---------------------------------------------------------------------------
// Fast Presets - Optimized for Performance (Base M1+)
// ---------------------------------------------------------------------------

/// Mode A (Fast) - Quick restoration
public struct ModeAFast: Anime4KMode {
    public static let displayName = "Mode A (Fast)"
    public static let presetDescription = "Fast restoration for 720p→1080p"

    public static let shaderPasses: [Anime4KShaderPass] = [
        Anime4KShaderPass(shaderFile: "Anime4K_Clamp_Highlights", kernelFunction: "Anime4Kv40DeRingComputeStatistics", description: "Clamp Highlights"),
        Anime4KShaderPass(shaderFile: "Anime4K_Restore_CNN_M", kernelFunction: "Anime4Kv40RestoreCNNMConv4x3x3x3", description: "Restore M"),
        Anime4KShaderPass(shaderFile: "Anime4K_Upscale_CNN_x2_M", kernelFunction: "Anime4Kv32UpscaleCNNx2MConv4x3x3x3", isUpscaling: true, description: "Upscale x2 M"),
        Anime4KShaderPass(shaderFile: "Anime4K_AutoDownscalePre_x2", kernelFunction: "Anime4Kv40AutoDownscalePrex2", description: "Auto Downscale x2"),
        Anime4KShaderPass(shaderFile: "Anime4K_AutoDownscalePre_x4", kernelFunction: "Anime4Kv32AutoDownscalePrex4", description: "Auto Downscale x4"),
        Anime4KShaderPass(shaderFile: "Anime4K_Upscale_CNN_x2_S", kernelFunction: "Anime4Kv32UpscaleCNNx2SConv4x3x3x3", isUpscaling: true, description: "Upscale x2 S"),
    ]

    public static let hardwareRequirement: Anime4KHardwareRequirement = .base
}

/// Mode B (Fast) - Quick soft restoration
public struct ModeBFast: Anime4KMode {
    public static let displayName = "Mode B (Fast)"
    public static let presetDescription = "Fast soft restoration"

    public static let shaderPasses: [Anime4KShaderPass] = [
        Anime4KShaderPass(shaderFile: "Anime4K_Clamp_Highlights", kernelFunction: "Anime4Kv40DeRingComputeStatistics", description: "Clamp Highlights"),
        Anime4KShaderPass(shaderFile: "Anime4K_Restore_CNN_Soft_M", kernelFunction: "Anime4Kv40RestoreCNNSoftMConv4x3x3x3", description: "Restore Soft M"),
        Anime4KShaderPass(shaderFile: "Anime4K_Upscale_CNN_x2_M", kernelFunction: "Anime4Kv32UpscaleCNNx2MConv4x3x3x3", isUpscaling: true, description: "Upscale x2 M"),
        Anime4KShaderPass(shaderFile: "Anime4K_AutoDownscalePre_x2", kernelFunction: "Anime4Kv40AutoDownscalePrex2", description: "Auto Downscale x2"),
        Anime4KShaderPass(shaderFile: "Anime4K_AutoDownscalePre_x4", kernelFunction: "Anime4Kv32AutoDownscalePrex4", description: "Auto Downscale x4"),
        Anime4KShaderPass(shaderFile: "Anime4K_Upscale_CNN_x2_S", kernelFunction: "Anime4Kv32UpscaleCNNx2SConv4x3x3x3", isUpscaling: true, description: "Upscale x2 S"),
    ]

    public static let hardwareRequirement: Anime4KHardwareRequirement = .base
}

/// Mode C (Fast) - Quick denoise
public struct ModeCFast: Anime4KMode {
    public static let displayName = "Mode C (Fast)"
    public static let presetDescription = "Fast denoise + upscale"

    public static let shaderPasses: [Anime4KShaderPass] = [
        Anime4KShaderPass(shaderFile: "Anime4K_Clamp_Highlights", kernelFunction: "Anime4Kv40DeRingComputeStatistics", description: "Clamp Highlights"),
        Anime4KShaderPass(shaderFile: "Anime4K_Upscale_Denoise_CNN_x2_M", kernelFunction: "Anime4Kv32UpscaleDenoiseCNNx2MConv4x3x3x3", isUpscaling: true, description: "Denoise + Upscale M"),
        Anime4KShaderPass(shaderFile: "Anime4K_AutoDownscalePre_x2", kernelFunction: "Anime4Kv40AutoDownscalePrex2", description: "Auto Downscale x2"),
        Anime4KShaderPass(shaderFile: "Anime4K_AutoDownscalePre_x4", kernelFunction: "Anime4Kv32AutoDownscalePrex4", description: "Auto Downscale x4"),
        Anime4KShaderPass(shaderFile: "Anime4K_Upscale_CNN_x2_S", kernelFunction: "Anime4Kv32UpscaleCNNx2SConv4x3x3x3", isUpscaling: true, description: "Upscale x2 S"),
    ]

    public static let hardwareRequirement: Anime4KHardwareRequirement = .base
}

/// Mode A+A (Fast) - Double fast restoration
public struct ModeAAFast: Anime4KMode {
    public static let displayName = "Mode A+A (Fast)"
    public static let presetDescription = "Double restoration, optimized for speed"

    public static let shaderPasses: [Anime4KShaderPass] = [
        Anime4KShaderPass(shaderFile: "Anime4K_Clamp_Highlights", kernelFunction: "Anime4Kv40DeRingComputeStatistics", description: "Clamp Highlights"),
        Anime4KShaderPass(shaderFile: "Anime4K_Restore_CNN_M", kernelFunction: "Anime4Kv40RestoreCNNMConv4x3x3x3", description: "Restore M"),
        Anime4KShaderPass(shaderFile: "Anime4K_Upscale_CNN_x2_M", kernelFunction: "Anime4Kv32UpscaleCNNx2MConv4x3x3x3", isUpscaling: true, description: "Upscale x2 M"),
        Anime4KShaderPass(shaderFile: "Anime4K_Restore_CNN_S", kernelFunction: "Anime4Kv40RestoreCNNSConv4x3x3x3", description: "Restore S"),
        Anime4KShaderPass(shaderFile: "Anime4K_AutoDownscalePre_x2", kernelFunction: "Anime4Kv40AutoDownscalePrex2", description: "Auto Downscale x2"),
        Anime4KShaderPass(shaderFile: "Anime4K_AutoDownscalePre_x4", kernelFunction: "Anime4Kv32AutoDownscalePrex4", description: "Auto Downscale x4"),
        Anime4KShaderPass(shaderFile: "Anime4K_Upscale_CNN_x2_S", kernelFunction: "Anime4Kv32UpscaleCNNx2SConv4x3x3x3", isUpscaling: true, description: "Upscale x2 S"),
    ]

    public static let hardwareRequirement: Anime4KHardwareRequirement = .enhanced
}

/// Mode B+B (Fast) - Double soft fast restoration
public struct ModeBBFast: Anime4KMode {
    public static let displayName = "Mode B+B (Fast)"
    public static let presetDescription = "Double soft restoration, fast"

    public static let shaderPasses: [Anime4KShaderPass] = [
        Anime4KShaderPass(shaderFile: "Anime4K_Clamp_Highlights", kernelFunction: "Anime4Kv40DeRingComputeStatistics", description: "Clamp Highlights"),
        Anime4KShaderPass(shaderFile: "Anime4K_Restore_CNN_Soft_M", kernelFunction: "Anime4Kv40RestoreCNNSoftMConv4x3x3x3", description: "Restore Soft M"),
        Anime4KShaderPass(shaderFile: "Anime4K_Upscale_CNN_x2_M", kernelFunction: "Anime4Kv32UpscaleCNNx2MConv4x3x3x3", isUpscaling: true, description: "Upscale x2 M"),
        Anime4KShaderPass(shaderFile: "Anime4K_AutoDownscalePre_x2", kernelFunction: "Anime4Kv40AutoDownscalePrex2", description: "Auto Downscale x2"),
        Anime4KShaderPass(shaderFile: "Anime4K_AutoDownscalePre_x4", kernelFunction: "Anime4Kv32AutoDownscalePrex4", description: "Auto Downscale x4"),
        Anime4KShaderPass(shaderFile: "Anime4K_Restore_CNN_Soft_S", kernelFunction: "Anime4Kv40RestoreCNNSoftSConv4x3x3x3", description: "Restore Soft S"),
        Anime4KShaderPass(shaderFile: "Anime4K_Upscale_CNN_x2_S", kernelFunction: "Anime4Kv32UpscaleCNNx2SConv4x3x3x3", isUpscaling: true, description: "Upscale x2 S"),
    ]

    public static let hardwareRequirement: Anime4KHardwareRequirement = .enhanced
}

/// Mode C+A (Fast) - Denoise + fast restoration
public struct ModeCAFast: Anime4KMode {
    public static let displayName = "Mode C+A (Fast)"
    public static let presetDescription = "Denoise then restore, optimized"

    public static let shaderPasses: [Anime4KShaderPass] = [
        Anime4KShaderPass(shaderFile: "Anime4K_Clamp_Highlights", kernelFunction: "Anime4Kv40DeRingComputeStatistics", description: "Clamp Highlights"),
        Anime4KShaderPass(shaderFile: "Anime4K_Upscale_Denoise_CNN_x2_M", kernelFunction: "Anime4Kv32UpscaleDenoiseCNNx2MConv4x3x3x3", isUpscaling: true, description: "Denoise + Upscale M"),
        Anime4KShaderPass(shaderFile: "Anime4K_AutoDownscalePre_x2", kernelFunction: "Anime4Kv40AutoDownscalePrex2", description: "Auto Downscale x2"),
        Anime4KShaderPass(shaderFile: "Anime4K_AutoDownscalePre_x4", kernelFunction: "Anime4Kv32AutoDownscalePrex4", description: "Auto Downscale x4"),
        Anime4KShaderPass(shaderFile: "Anime4K_Restore_CNN_S", kernelFunction: "Anime4Kv40RestoreCNNSConv4x3x3x3", description: "Restore S"),
        Anime4KShaderPass(shaderFile: "Anime4K_Upscale_CNN_x2_S", kernelFunction: "Anime4Kv32UpscaleCNNx2SConv4x3x3x3", isUpscaling: true, description: "Upscale x2 S"),
    ]

    public static let hardwareRequirement: Anime4KHardwareRequirement = .enhanced
}

// MARK: - Registry Initialization

/// Initialize and register all presets
/// Call this once at app startup
public func initializeAnime4KPresets() {
    Anime4KPresetRegistry.register(ModeAHQ.self)
    Anime4KPresetRegistry.register(ModeBHQ.self)
    Anime4KPresetRegistry.register(ModeCHQ.self)
    Anime4KPresetRegistry.register(ModeAAHQ.self)
    Anime4KPresetRegistry.register(ModeBBHQ.self)
    Anime4KPresetRegistry.register(ModeCAHQ.self)
    Anime4KPresetRegistry.register(ModeAFast.self)
    Anime4KPresetRegistry.register(ModeBFast.self)
    Anime4KPresetRegistry.register(ModeCFast.self)
    Anime4KPresetRegistry.register(ModeAAFast.self)
    Anime4KPresetRegistry.register(ModeBBFast.self)
    Anime4KPresetRegistry.register(ModeCAFast.self)
}
