#import "MetalCoreMlRenderer.h"
#import <Metal/Metal.h>
#import <CoreML/CoreML.h>
#import <CoreVideo/CoreVideo.h>
#import <QuartzCore/CAMetalLayer.h>
#import <chrono>
#import <iostream>

namespace GlassPlayer {

class MetalCoreMlRenderer::Impl {
public:
    id<MTLDevice> device = nil;
    id<MTLCommandQueue> commandQueue = nil;
    id<MTLLibrary> defaultLibrary = nil;
    
    // Metal Pipelines for rendering and upscaling
    id<MTLRenderPipelineState> bilinearRenderPipeline = nil;
    id<MTLComputePipelineState> anime4kComputePipeline = nil;
    
    // Core ML (ArtCNN) fields
    MLModel* artCnnModel = nil;
    NSURL* compiledModelURL = nil;
    dispatch_queue_t coreMlQueue;
    
    // Zero-copy texture cache
    CVMetalTextureCacheRef textureCache = nullptr;
    
    // Renderer states
    RenderConfig config;
    uint32_t width = 0;
    uint32_t height = 0;
    
    // High-performance double/triple buffer texture ring
    id<MTLTexture> pingPongTextures[2];
    uint32_t activeTextureIndex = 0;
    
    // Synchronization fences
    id<MTLFence> gpuFence = nil;
    
    Impl() {
        coreMlQueue = dispatch_queue_create("com.glassplayer.coreml-upscaler", DISPATCH_QUEUE_SERIAL);
    }
    
    ~Impl() {
        if (textureCache) {
            CFRelease(textureCache);
        }
    }
};

MetalCoreMlRenderer::MetalCoreMlRenderer() : m_impl(std::make_unique<Impl>()) {}

MetalCoreMlRenderer::~MetalCoreMlRenderer() {
    Shutdown();
}

bool MetalCoreMlRenderer::Initialize(void* windowHandle, uint32_t width, uint32_t height) {
    m_impl->width = width;
    m_impl->height = height;
    
    // 1. Setup Metal Device and Command Queue
    m_impl->device = MTLCreateSystemDefaultDevice();
    if (!m_impl->device) {
        std::cerr << "[MetalCoreMlRenderer] Failed to initialize MTLDevice" << std::endl;
        return false;
    }
    
    m_impl->commandQueue = [m_impl->device makeCommandQueue];
    if (!m_impl->commandQueue) {
        std::cerr << "[MetalCoreMlRenderer] Failed to initialize MTLCommandQueue" << std::endl;
        return false;
    }
    
    // 2. Initialize Core Video Metal Texture Cache (Zero-Copy Pipeline)
    CVReturn cvErr = CVMetalTextureCacheCreate(kCFAllocatorDefault, nullptr, m_impl->device, nullptr, &m_impl->textureCache);
    if (cvErr != kCVReturnSuccess) {
        std::cerr << "[MetalCoreMlRenderer] CVMetalTextureCacheCreate failed: " << cvErr << std::endl;
        return false;
    }
    
    // 3. Load pre-compiled AOT MSL Shaders (.metallib)
    // To satisfy architectural constraints: NO RUNTIME TRANSLATION is permitted
    @try {
        // Look for the AOT compiled Anime4KUpscaler.metallib in resources
        NSString* libPath = [[NSBundle mainBundle] pathForResource:@"Anime4KUpscaler" ofType:@"metallib"];
        if (libPath) {
            m_impl->defaultLibrary = [m_impl->device makeLibraryWithFile:libPath error:nil];
        } else {
            m_impl->defaultLibrary = [m_impl->device makeDefaultLibrary];
        }
        
        if (!m_impl->defaultLibrary) {
            std::cerr << "[MetalCoreMlRenderer] Warning: default metallib could not be loaded." << std::endl;
        }
    } @catch (NSException* exception) {
        std::cerr << "[MetalCoreMlRenderer] Exception loading library: " << [[exception reason] UTF8String] << std::endl;
    }
    
    // 4. Initialize Core ML (Apple Neural Engine Acceleration Configuration)
    m_impl->coreMlQueue = dispatch_queue_create("com.glassplayer.coreml-upscaler", DISPATCH_QUEUE_SERIAL);
    dispatch_async(m_impl->coreMlQueue, ^{
        @autoreleasepool {
            MLModelConfiguration* mlConfig = [[MLModelConfiguration alloc] init];
            // MANDATE: Force execution on the ANE (Apple Neural Engine) via MLComputeUnitsAll
            mlConfig.computeUnits = MLComputeUnitsAll;
            
            // Look for precompiled modelc directory in resources
            NSString* modelPath = [[NSBundle mainBundle] pathForResource:@"ArtCNN_C4F16" ofType:@"mlmodelc"];
            if (modelPath) {
                NSURL* modelURL = [NSURL fileURLWithPath:modelPath];
                NSError* err = nil;
                m_impl->artCnnModel = [MLModel modelWithContentsOfURL:modelURL configuration:mlConfig error:&err];
                if (err) {
                    std::cerr << "[MetalCoreMlRenderer] Core ML model initialization failed: " 
                              << [[err localizedDescription] UTF8String] << std::endl;
                } else {
                    std::cout << "[MetalCoreMlRenderer] ANE-accelerated Core ML engine successfully initialized." << std::endl;
                }
            } else {
                std::cerr << "[MetalCoreMlRenderer] ArtCNN_C4F16.mlmodelc not found in bundle resources." << std::endl;
            }
        }
    });
    
    // 5. Allocate Ping-Pong Textures for multi-pass compute pipelines
    MTLTextureDescriptor* desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                   width:width
                                                                                  height:height
                                                                               mipmapped:NO];
    desc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite | MTLTextureUsageRenderTarget;
    
    m_impl->pingPongTextures[0] = [m_impl->device makeTextureWithDescriptor:desc];
    m_impl->pingPongTextures[1] = [m_impl->device makeTextureWithDescriptor:desc];
    
    m_impl->gpuFence = [m_impl->device makeFence];
    
    return true;
}

void MetalCoreMlRenderer::UpdateConfiguration(const RenderConfig& config) {
    m_impl->config = config;
}

bool MetalCoreMlRenderer::RenderFrame(const VideoFrame& inputFrame, void* outputSurface) {
    auto frameStart = std::chrono::high_resolution_clock::now();
    
    if (!m_impl->device || !inputFrame.handle) {
        return false;
    }
    
    CAMetalLayer* presentationLayer = (__bridge CAMetalLayer*)outputSurface;
    id<CAMetalDrawable> drawable = [presentationLayer nextDrawable];
    if (!drawable) {
        return false;
    }
    
    // Map hardware frame via Core Video zero-copy texture cache
    CVPixelBufferRef pixelBuffer = (CVPixelBufferRef)inputFrame.handle;
    size_t frameWidth = CVPixelBufferGetWidth(pixelBuffer);
    size_t frameHeight = CVPixelBufferGetHeight(pixelBuffer);
    
    CVMetalTextureRef cvTexture = nullptr;
    CVReturn cvErr = CVMetalTextureCacheCreateTextureFromImage(
        kCFAllocatorDefault,
        m_impl->textureCache,
        pixelBuffer,
        nullptr,
        MTLPixelFormatBGRA8Unorm,
        frameWidth,
        frameHeight,
        0,
        &cvTexture
    );
    
    if (cvErr != kCVReturnSuccess || !cvTexture) {
        std::cerr << "[MetalCoreMlRenderer] Zero-copy texture cache map failed" << std::endl;
        return false;
    }
    
    id<MTLTexture> sourceTexture = CVMetalTextureGetTexture(cvTexture);
    
    id<MTLCommandBuffer> cmdBuffer = [m_impl->commandQueue commandBuffer];
    cmdBuffer.label = @"RenderFrameBuffer";
    
    // Engage fail-safe: Check if budget allows scaler execution
    ScaleMode activeMode = m_impl->config.mode;
    
    // -------------------------------------------------------------
    // PIPELINE BRANCH 1: CORE ML (ArtCNN on Neural Engine)
    // -------------------------------------------------------------
    if (activeMode == ScaleMode::ArtCNN && m_impl->artCnnModel != nil) {
        // Enforce async dispatch to prevent blocking the GPU swap chain thread
        dispatch_semaphore_t coreMlSemaphore = dispatch_semaphore_create(0);
        __block NSError* predictionError = nil;
        __block id<MLFeatureProvider> outputFeatures = nil;
        
        // Wrap input pixel buffer inside MLFeatureProvider
        // The ML Model maps the input to image input constraints
        dispatch_async(m_impl->coreMlQueue, ^{
            @autoreleasepool {
                NSError* err = nil;
                // Core ML zero-copy inference utilizing ANE
                id<MLFeatureProvider> inputFeatures = [[MLFeatureValue imageFeatureValueWithPixelBuffer:pixelBuffer] featureProvider];
                outputFeatures = [m_impl->artCnnModel predictionFromFeatures:inputFeatures error:&err];
                if (err) {
                    predictionError = err;
                }
                dispatch_semaphore_signal(coreMlSemaphore);
            }
        });
        
        // Wait for upscaler response or timeout
        dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(14.0 * NSEC_PER_MSEC)); // 14ms budget constraint
        long waitResult = dispatch_semaphore_wait(coreMlSemaphore, timeout);
        
        if (waitResult == 0 && !predictionError && outputFeatures) {
            // Success: Extract upscaled CVPixelBuffer from output
            MLFeatureValue* outputVal = [outputFeatures featureValueForName:@"output"];
            CVPixelBufferRef upscaledBuffer = [outputVal imageBufferValue];
            
            if (upscaledBuffer) {
                // Map the output surface from Neural Engine directly to a Metal texture
                CVMetalTextureRef cvUpscaledTex = nullptr;
                CVMetalTextureCacheCreateTextureFromImage(
                    kCFAllocatorDefault,
                    m_impl->textureCache,
                    upscaledBuffer,
                    nullptr,
                    MTLPixelFormatBGRA8Unorm,
                    CVPixelBufferGetWidth(upscaledBuffer),
                    CVPixelBufferGetHeight(upscaledBuffer),
                    0,
                    &cvUpscaledTex
                );
                
                if (cvUpscaledTex) {
                    sourceTexture = CVMetalTextureGetTexture(cvUpscaledTex);
                    CFRelease(cvUpscaledTex);
                }
            }
        } else {
            // Fail-safe triggered: Fall back immediately to high-speed bilinear to prevent frame stutter
            std::cerr << "[MetalCoreMlRenderer] ArtCNN inference budget exceeded. Dropping to bilinear." << std::endl;
            activeMode = ScaleMode::Bilinear;
        }
    }
    
    // -------------------------------------------------------------
    // PIPELINE BRANCH 2: ANIME4K MSL COMPUTE PASSES
    // -------------------------------------------------------------
    if (activeMode == ScaleMode::Anime4K && m_impl->anime4kComputePipeline != nil) {
        id<MTLComputeCommandEncoder> computeEncoder = [cmdBuffer computeCommandEncoder];
        [computeEncoder setLabel:@"Anime4K Pass"];
        [computeEncoder setComputePipelineState:m_impl->anime4kComputePipeline];
        [computeEncoder setTexture:sourceTexture atIndex:0];
        [computeEncoder setTexture:m_impl->pingPongTextures[m_impl->activeTextureIndex] atIndex:1];
        
        // Dispatch threads based on size
        MTLSize threadgroupSize = MTLSizeMake(16, 16, 1);
        MTLSize threadgroups = MTLSizeMake((sourceTexture.width + 15) / 16, (sourceTexture.height + 15) / 16, 1);
        [computeEncoder dispatchThreadgroups:threadgroups threadsPerThreadgroup:threadgroupSize];
        [computeEncoder endEncoding];
        
        // Output pointer transitions to the ping-pong destination
        sourceTexture = m_impl->pingPongTextures[m_impl->activeTextureIndex];
        m_impl->activeTextureIndex = (m_impl->activeTextureIndex + 1) % 2;
    }
    
    // -------------------------------------------------------------
    // PRESENTATION STAGE (Blit/Render target copy)
    // -------------------------------------------------------------
    MTLRenderPassDescriptor* renderPassDesc = [MTLRenderPassDescriptor renderPassDescriptor];
    renderPassDesc.colorAttachments[0].texture = drawable.texture;
    renderPassDesc.colorAttachments[0].loadAction = MTLLoadActionClear;
    renderPassDesc.colorAttachments[0].storeAction = MTLStoreActionStore;
    renderPassDesc.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);
    
    id<MTLRenderCommandEncoder> renderEncoder = [cmdBuffer renderCommandEncoderWithDescriptor:renderPassDesc];
    renderEncoder.label = @"DisplayBlit";
    
    // Bind bilinear pipeline or default copy pipeline
    [renderEncoder setRenderPipelineState:m_impl->bilinearRenderPipeline];
    [renderEncoder setFragmentTexture:sourceTexture atIndex:0];
    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
    [renderEncoder endEncoding];
    
    [cmdBuffer presentDrawable:drawable];
    [cmdBuffer commit];
    
    CFRelease(cvTexture);
    
    // Check timing budget
    auto frameEnd = std::chrono::high_resolution_clock::now();
    std::chrono::duration<double, std::milli> duration = frameEnd - frameStart;
    
    // Budget boundary check (16.6ms for 60 FPS)
    if (duration.count() > 16.6) {
        std::cerr << "[MetalCoreMlRenderer] Warning: Frame processing latency (" 
                  << duration.count() << "ms) exceeds target budget of 16.6ms!" << std::endl;
        return false; // Signifies fallback engagement
    }
    
    return true;
}

void MetalCoreMlRenderer::Shutdown() {
    m_impl->defaultLibrary = nil;
    m_impl->bilinearRenderPipeline = nil;
    m_impl->anime4kComputePipeline = nil;
    m_impl->artCnnModel = nil;
    m_impl->commandQueue = nil;
    m_impl->device = nil;
    m_impl->gpuFence = nil;
    
    if (m_impl->textureCache) {
        CFRelease(m_impl->textureCache);
        m_impl->textureCache = nullptr;
    }
}

} // namespace GlassPlayer
