#pragma once
#include <cstdint>
#include <string>
#include <memory>

namespace GlassPlayer {

enum class ScaleMode : uint32_t {
    Bilinear = 0,
    Anime4K  = 1,
    ArtCNN   = 2
};

enum class FrameFormat : uint32_t {
    BGRA8 = 0,
    RGBA8,
    NV12,
    P010
};

struct RenderConfig {
    ScaleMode mode = ScaleMode::Bilinear;
    float intensity = 1.0f;       // Strength of the restoration/upscaling effect
    bool enableDenoise = false;   // Pre-denoising pass enabled/disabled
};

struct VideoFrame {
    uint32_t width = 0;
    uint32_t height = 0;
    FrameFormat format = FrameFormat::BGRA8;
    
    // Platform-specific frame descriptors:
    // macOS: CVPixelBufferRef or IOSurfaceRef (cast to void*)
    // Windows: VkImage or ID3D11Texture2D (cast to void*)
    void* handle = nullptr;
    
    // Hardware texture memory offsets, memory allocations, or descriptor indices (if needed)
    uint64_t allocationHandle = 0;
    
    // CPU fallback buffers if hardware surfaces are not direct-bound
    uint8_t* data[4] = {nullptr};
    int32_t strides[4] = {0};
    
    uint64_t timestampNs = 0;
};

class IGpuRenderer {
public:
    virtual ~IGpuRenderer() = default;

    /**
     * @brief Initialize graphics API (Metal/Vulkan) and allocate resources.
     * @param windowHandle Native window handle (HWND on Windows, NSView/CAMetalLayer on macOS).
     * @param width Native width of output render target.
     * @param height Native height of output render target.
     * @return true if initialization succeeded.
     */
    virtual bool Initialize(void* windowHandle, uint32_t width, uint32_t height) = 0;

    /**
     * @brief Update the rendering configurations dynamically.
     * @param config Configuration parameters containing ScaleMode and weights.
     */
    virtual void UpdateConfiguration(const RenderConfig& config) = 0;

    /**
     * @brief Render and upscale the incoming video frame asynchronously.
     * @param inputFrame Struct containing the raw input frame descriptor.
     * @param outputSurface Output swapchain surface or viewport target (cast to appropriate type).
     * @return true if upscale and render succeeded; false if fallback bilinear was engaged.
     */
    virtual bool RenderFrame(const VideoFrame& inputFrame, void* outputSurface) = 0;

    /**
     * @brief Shut down renderer, release device and command queues.
     */
    virtual void Shutdown() = 0;
};

} // namespace GlassPlayer
