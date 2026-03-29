import Foundation
import Dispatch
import Accelerate
import Metal
import Cocoa

// ═══════════════════════════════════════════════════════════════════════════
// MARK: - PHASE 1A: Dynamic QoS Dispatch
//
// All concurrent work is dispatched through QoS-tagged queues so macOS
// scheduler routes heavy work to P-cores (.userInitiated) and maintenance
// to E-cores (.background). Works across M1–M5 with no chip-specific code.
// ═══════════════════════════════════════════════════════════════════════════

enum UniversalSiliconQoS {
    /// P-core affinity: video info collection, thumbnail generation,
    /// file I/O that blocks the user, shader compilation.
    static let heavy = DispatchQueue(
        label: "com.glassplayer.qos.heavy",
        qos: .userInitiated,
        attributes: .concurrent
    )

    /// E-core affinity: cache cleanup, log flushing, non-urgent analytics,
    /// thumbnail cache eviction, temp-file removal.
    static let maintenance = DispatchQueue(
        label: "com.glassplayer.qos.maintenance",
        qos: .background
    )

    /// Utility: medium-priority work that should not block UI but is
    /// more important than background (e.g. pre-fetching metadata).
    static let utility = DispatchQueue(
        label: "com.glassplayer.qos.utility",
        qos: .utility,
        attributes: .concurrent
    )
}

// ═══════════════════════════════════════════════════════════════════════════
// MARK: - PHASE 1C: SIMD / Accelerate Abstraction
//
// Scalar math replaced with Accelerate vDSP calls.  These dispatch to the
// best available hardware unit (AMX on M2+, NEON on M1) automatically.
// Each function uses @inline(__always) to eliminate call overhead for
// hot-path single-value operations.
// ═══════════════════════════════════════════════════════════════════════════

/// Clamp a scalar Double to [0, 1] via vDSP (AMX/NEON auto-dispatch).
@inline(__always)
func clampUnitIntervalAccelerate(_ value: Double) -> Double {
    var input = value
    var lower = 0.0
    var upper = 1.0
    var output = 0.0
    vDSP_vclipD(&input, 1, &lower, &upper, &output, 1, 1)
    return output
}

/// Clamp a scalar Double to [lower, upper] via vDSP (AMX/NEON auto-dispatch).
@inline(__always)
func clampRangeAccelerate(_ value: Double, lower: Double, upper: Double) -> Double {
    var input = value
    var low = lower
    var high = upper
    var output = 0.0
    vDSP_vclipD(&input, 1, &low, &high, &output, 1, 1)
    return output
}

/// Clamp Float volume to [0, 1] via vDSP — used in CoreAudio system volume paths.
@inline(__always)
func clampVolumeAccelerate(_ value: Float) -> Float {
    var input = value
    var lower: Float = 0.0
    var upper: Float = 1.0
    var output: Float = 0.0
    vDSP_vclip(&input, 1, &lower, &upper, &output, 1, 1)
    return output
}

/// Batch-clamp an array of Doubles to [lower, upper] in-place via vDSP.
/// Use for batch-processing seek positions, brightness arrays, etc.
@inline(__always)
func batchClampAccelerate(_ values: inout [Double], lower: Double, upper: Double) {
    var low = lower
    var high = upper
    // Swift exclusivity: use withUnsafeMutableBufferPointer for in-place vDSP
    values.withUnsafeMutableBufferPointer { buf in
        guard let ptr = buf.baseAddress else { return }
        vDSP_vclipD(ptr, 1, &low, &high, ptr, 1, vDSP_Length(buf.count))
    }
}

/// Linear interpolation via Accelerate — safe for timeline scrubbing math.
@inline(__always)
func lerpAccelerate(_ a: Double, _ b: Double, _ t: Double) -> Double {
    let clamped = clampUnitIntervalAccelerate(t)
    // a + (b - a) * t  computed via vDSP
    var diff = b - a
    var result = 0.0
    var ct = clamped
    vDSP_vsmulD(&ct, 1, &diff, &result, 1, 1)
    return a + result
}

// ═══════════════════════════════════════════════════════════════════════════
// MARK: - PHASE 1B: Unified Memory Architecture (UMA) Efficiency
//
// Zero-copy MTLBuffer creation with .storageModeShared eliminates the
// CPU→GPU copy bottleneck on all M-series chips.  Memory-floor awareness
// prevents aggressive allocation on 8 GB base models.
// ═══════════════════════════════════════════════════════════════════════════

final class UniversalSharedMetalBufferFactory {
    static let shared = UniversalSharedMetalBufferFactory()

    let device: MTLDevice?
    /// Physical memory in bytes — cached at init, used for memory-floor checks.
    let physicalMemory: UInt64
    /// True when running on an 8 GB base-model Mac.
    let isMemoryFloorDevice: Bool

    private init() {
        device = MTLCreateSystemDefaultDevice()
        physicalMemory = ProcessInfo.processInfo.physicalMemory
        isMemoryFloorDevice = physicalMemory <= (8 * 1024 * 1024 * 1024)
    }

    /// Create a .storageModeShared MTLBuffer (zero-copy UMA on all M-series).
    /// On apple8+ (M2+), uses cpuCacheModeWriteCombined for extra throughput
    /// on write-once GPU-read buffers (e.g. vertex data, uniforms).
    /// Guarded by `#available` + `supportsFamily` for universal safety.
    func makeSharedBuffer(length: Int) -> MTLBuffer? {
        guard length > 0, let device = device else { return nil }

        // Memory-floor guard: reject buffers > 64 MB on 8 GB Macs
        if isMemoryFloorDevice && length > 64 * 1024 * 1024 {
            NSLog("[UMA] Rejected %d MB buffer on memory-floor device", length / (1024*1024))
            return nil
        }

        if #available(macOS 14.0, *), device.supportsFamily(.apple8) {
            // M2+ (apple8): writeCombined is optimal for CPU→GPU streaming
            return device.makeBuffer(length: length, options: [.storageModeShared, .cpuCacheModeWriteCombined])
        }

        // M1 (apple7) and all other Silicon: plain shared mode
        return device.makeBuffer(length: length, options: [.storageModeShared])
    }

    /// Create a read-only shared buffer from existing data (zero-copy wrap).
    /// Avoids a memcpy on UMA — the GPU reads directly from the source pointer.
    func makeSharedBuffer(bytes: UnsafeRawPointer, length: Int) -> MTLBuffer? {
        guard length > 0, let device = device else { return nil }
        if isMemoryFloorDevice && length > 64 * 1024 * 1024 { return nil }
        return device.makeBuffer(bytes: bytes, length: length, options: [.storageModeShared])
    }

    /// Recommended thumbnail cache limit based on available memory.
    /// Prevents OOM on 8 GB Macs while allowing generous caching on 16 GB+.
    var recommendedThumbnailCacheLimit: Int {
        if physicalMemory <= (8 * 1024 * 1024 * 1024) { return 120 }     // 8 GB
        if physicalMemory <= (16 * 1024 * 1024 * 1024) { return 300 }    // 16 GB
        return 600                                                        // 24 GB+
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// MARK: - Memory Pressure Monitor
//
// Observes system memory pressure notifications and triggers cache eviction
// before the OOM killer gets involved.  Critical for 8 GB base models.
// ═══════════════════════════════════════════════════════════════════════════

final class UMAMemoryPressureMonitor {
    static let shared = UMAMemoryPressureMonitor()

    private let source: DispatchSourceMemoryPressure
    /// Callbacks registered for memory pressure events.
    private var handlers: [() -> Void] = []
    private let lock = NSLock()

    private init() {
        source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: UniversalSiliconQoS.maintenance
        )
        source.setEventHandler { [weak self] in
            self?.firePressureHandlers()
        }
        source.resume()
    }

    /// Register a callback to be invoked on memory pressure (warning or critical).
    /// Use this for thumbnail cache eviction, pre-fetch cancellation, etc.
    func onPressure(_ handler: @escaping () -> Void) {
        lock.lock()
        handlers.append(handler)
        lock.unlock()
    }

    private func firePressureHandlers() {
        lock.lock()
        let snapshot = handlers
        lock.unlock()
        NSLog("[UMA] Memory pressure detected — evicting caches (%d handlers)", snapshot.count)
        for handler in snapshot {
            handler()
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// MARK: - GPU Performance Tier Detection
//
// Runtime detection of GPU capability across M1–M5 using MTLDevice.supportsFamily.
// All checks are guarded by #available(macOS 14.0, *) for universal safety.
// ═══════════════════════════════════════════════════════════════════════════

enum UniversalGPUPerformanceTier: String {
    case high       // M1 Max/Ultra, M2 Max/Ultra, M3 Max/Ultra, M4 Max/Ultra
    case balanced   // M1/M2/M3/M4 base and Pro models
    case efficient  // Older Apple GPU families (fallback)
    case unknown
}

struct UniversalMetalRuntime {
    /// Cached GPU tier — computed once and reused.
    private static let _cachedTier: UniversalGPUPerformanceTier = {
        guard let device = MTLCreateSystemDefaultDevice() else { return .unknown }

        if #available(macOS 14.0, *) {
            // apple9 = M3+, apple8 = M2 family, apple7 = M1 family
            if device.supportsFamily(.apple9) || device.supportsFamily(.apple8) || device.supportsFamily(.apple7) {
                let vram = device.recommendedMaxWorkingSetSize
                // Max/Ultra chips expose > 32 GB working set (e.g. M3 Max = 48 GB+)
                // Pro chips sit in 18–24 GB range; base chips at 8–16 GB.
                // Using 32 GB threshold correctly excludes M3 Pro (18 GB) from "high".
                if vram > 32 * 1024 * 1024 * 1024 {
                    return .high
                }
                return .balanced
            }
            if device.supportsFamily(.apple5) || device.supportsFamily(.apple4) {
                return .efficient
            }
        }

        // macOS < 14.0 fallback — assume balanced
        return .balanced
    }()

    static func gpuTier() -> UniversalGPUPerformanceTier {
        return _cachedTier
    }

    /// Report whether the current GPU supports a Metal feature family.
    /// Provides a single safe entry point for runtime feature guards.
    static func supportsFamily(_ family: Int) -> Bool {
        guard let device = MTLCreateSystemDefaultDevice() else { return false }
        if #available(macOS 14.0, *) {
            switch family {
            case 9: return device.supportsFamily(.apple9)
            case 8: return device.supportsFamily(.apple8)
            case 7: return device.supportsFamily(.apple7)
            default: return false
            }
        }
        return false
    }

    /// Choose the best Anime4K shader preset for the current hardware.
    /// Memory-floor devices always get "Fast" presets to avoid OOM.
    /// Only Max/Ultra GPUs (.high tier) default to HQ; Pro/base get Fast.
    static func recommendedAnime4KPreset(physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory) -> String {
        let isMemoryFloorDevice = physicalMemory <= (8 * 1024 * 1024 * 1024)
        if isMemoryFloorDevice {
            return "Mode A (Fast)"
        }

        switch gpuTier() {
        case .high:
            return "Mode A (HQ)"
        case .balanced, .efficient, .unknown:
            return "Mode A (Fast)"
        }
    }

    /// Recommended Metal pixel format for the current display.
    /// XDR displays on M1 Pro+ can benefit from rgba16Float for HDR headroom.
    static func recommendedPixelFormat() -> MTLPixelFormat {
        guard let device = MTLCreateSystemDefaultDevice() else { return .bgra8Unorm }
        // Only use 16-bit float on high-tier GPUs with enough bandwidth
        if gpuTier() == .high {
            // Check if any connected display supports EDR (XDR)
            if let screen = NSScreen.main, screen.maximumPotentialExtendedDynamicRangeColorComponentValue > 1.0 {
                // Verify GPU supports it efficiently
                if #available(macOS 14.0, *), device.supportsFamily(.apple8) {
                    return .rgba16Float
                }
            }
        }
        return .bgra8Unorm
    }

    /// Log a summary of the detected hardware for debugging.
    static func logHardwareProfile() {
        let physMem = ProcessInfo.processInfo.physicalMemory
        let memGB = Double(physMem) / (1024 * 1024 * 1024)
        let tier = gpuTier()
        let preset = recommendedAnime4KPreset()
        let memFloor = UniversalSharedMetalBufferFactory.shared.isMemoryFloorDevice
        NSLog("[UniversalSilicon] GPU tier: %@ | Memory: %.0f GB (floor=%@) | Shader preset: %@",
              tier.rawValue, memGB, memFloor ? "YES" : "NO", preset)
    }
}
