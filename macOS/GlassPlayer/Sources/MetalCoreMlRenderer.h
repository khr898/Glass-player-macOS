#pragma once
#include "../../../core/rendering/IGpuRenderer.hpp"
#include <memory>

namespace GlassPlayer {

class MetalCoreMlRenderer : public IGpuRenderer {
public:
    MetalCoreMlRenderer();
    ~MetalCoreMlRenderer() override;

    bool Initialize(void* windowHandle, uint32_t width, uint32_t height) override;
    void UpdateConfiguration(const RenderConfig& config) override;
    bool RenderFrame(const VideoFrame& inputFrame, void* outputSurface) override;
    void Shutdown() override;

private:
    class Impl;
    std::unique_ptr<Impl> m_impl;
};

} // namespace GlassPlayer
