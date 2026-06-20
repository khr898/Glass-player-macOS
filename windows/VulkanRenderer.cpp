#include "VulkanRenderer.h"
#include <chrono>
#include <iostream>
#include <vector>
#include <array>
#include <stdexcept>

#ifdef HAS_VULKAN
#define VK_USE_PLATFORM_WIN32_KHR
#include <vulkan/vulkan.h>
#else
// ============================================================================
// STUB/MOCK VULKAN IMPLEMENTATION FOR ENVRONMENTS LACKING THE VULKAN SDK
// ============================================================================
#define VK_NULL_HANDLE nullptr
#define VK_SUCCESS 0
#define VK_TRUE 1

#define VK_STRUCTURE_TYPE_APPLICATION_INFO 0
#define VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO 1
#define VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO 2
#define VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO 3
#define VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO 4
#define VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO 5
#define VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO 6
#define VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO 7
#define VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO 8
#define VK_STRUCTURE_TYPE_FENCE_CREATE_INFO 9
#define VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO 10
#define VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO 11
#define VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER 12
#define VK_STRUCTURE_TYPE_SUBMIT_INFO 13

#define VK_MAKE_VERSION(major, minor, patch) 0
#define VK_API_VERSION_1_3 0

#define VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT 1
#define VK_COMMAND_BUFFER_LEVEL_PRIMARY 0
#define VK_IMAGE_TYPE_2D 1
#define VK_FORMAT_B8G8R8A8_UNORM 44
#define VK_IMAGE_TILING_OPTIMAL 0
#define VK_IMAGE_LAYOUT_UNDEFINED 0
#define VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL 1
#define VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL 2
#define VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL 3
#define VK_IMAGE_LAYOUT_GENERAL 4
#define VK_IMAGE_VIEW_TYPE_2D 1

#define VK_IMAGE_USAGE_TRANSFER_SRC_BIT 1
#define VK_IMAGE_USAGE_TRANSFER_DST_BIT 2
#define VK_IMAGE_USAGE_SAMPLED_BIT 4
#define VK_IMAGE_USAGE_STORAGE_BIT 8
#define VK_SHARING_MODE_EXCLUSIVE 0
#define VK_SAMPLE_COUNT_1_BIT 1
#define VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT 1
#define VK_IMAGE_ASPECT_COLOR_BIT 1
#define VK_FENCE_CREATE_SIGNALED_BIT 1
#define VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT 1
#define VK_ACCESS_TRANSFER_READ_BIT 1
#define VK_ACCESS_SHADER_READ_BIT 2
#define VK_ACCESS_SHADER_WRITE_BIT 4
#define VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT 1
#define VK_PIPELINE_STAGE_TRANSFER_BIT 2
#define VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT 4
#define VK_PIPELINE_BIND_POINT_COMPUTE 1
#define VK_FILTER_LINEAR 1

typedef void* VkInstance;
typedef void* VkPhysicalDevice;
typedef void* VkDevice;
typedef void* VkQueue;
typedef void* VkCommandPool;
typedef void* VkCommandBuffer;
typedef void* VkShaderModule;
typedef void* VkPipelineLayout;
typedef void* VkPipeline;
typedef void* VkDescriptorPool;
typedef void* VkDescriptorSetLayout;
typedef void* VkDescriptorSet;
typedef void* VkImage;
typedef void* VkDeviceMemory;
typedef void* VkImageView;
typedef void* VkFence;
typedef void* VkSemaphore;
typedef int VkResult;
typedef uint32_t VkMemoryPropertyFlags;

struct VkApplicationInfo {
    int sType;
    const void* pNext;
    const char* pApplicationName;
    uint32_t applicationVersion;
    const char* pEngineName;
    uint32_t engineVersion;
    uint32_t apiVersion;
};

struct VkInstanceCreateInfo {
    int sType;
    const void* pNext;
    uint32_t flags;
    const VkApplicationInfo* pApplicationInfo;
    uint32_t enabledLayerCount;
    const char* const* ppEnabledLayerNames;
    uint32_t enabledExtensionCount;
    const char* const* ppEnabledExtensionNames;
};

struct VkDeviceQueueCreateInfo {
    int sType;
    const void* pNext;
    uint32_t flags;
    uint32_t queueFamilyIndex;
    uint32_t queueCount;
    const float* pQueuePriorities;
};

struct VkPhysicalDeviceFeatures {
    uint32_t samplerAnisotropy;
};

struct VkDeviceCreateInfo {
    int sType;
    const void* pNext;
    uint32_t flags;
    uint32_t queueCreateInfoCount;
    const VkDeviceQueueCreateInfo* pQueueCreateInfos;
    uint32_t enabledLayerCount;
    const char* const* ppEnabledLayerNames;
    uint32_t enabledExtensionCount;
    const char* const* ppEnabledExtensionNames;
    const VkPhysicalDeviceFeatures* pEnabledFeatures;
};

struct VkCommandPoolCreateInfo {
    int sType;
    const void* pNext;
    uint32_t flags;
    uint32_t queueFamilyIndex;
};

struct VkCommandBufferAllocateInfo {
    int sType;
    const void* pNext;
    VkCommandPool commandPool;
    int level;
    uint32_t commandBufferCount;
};

struct VkExtent3D {
    uint32_t width;
    uint32_t height;
    uint32_t depth;
};

struct VkImageCreateInfo {
    int sType;
    const void* pNext;
    uint32_t flags;
    int imageType;
    int format;
    VkExtent3D extent;
    uint32_t mipLevels;
    uint32_t arrayLayers;
    int samples;
    int tiling;
    int usage;
    int sharingMode;
    uint32_t queueFamilyIndexCount;
    const uint32_t* pQueueFamilyIndices;
    int initialLayout;
};

struct VkMemoryRequirements {
    uint64_t size;
    uint64_t alignment;
    uint32_t memoryTypeBits;
};

struct VkMemoryType {
    VkMemoryPropertyFlags propertyFlags;
    uint32_t heapIndex;
};

struct VkMemoryHeap {
    uint64_t size;
    uint32_t flags;
};

struct VkPhysicalDeviceMemoryProperties {
    uint32_t memoryTypeCount;
    VkMemoryType memoryTypes[32];
    uint32_t memoryHeapCount;
    VkMemoryHeap memoryHeaps[16];
};

struct VkMemoryAllocateInfo {
    int sType;
    const void* pNext;
    uint64_t allocationSize;
    uint32_t memoryTypeIndex;
};

struct VkImageSubresourceRange {
    int aspectMask;
    uint32_t baseMipLevel;
    uint32_t levelCount;
    uint32_t baseArrayLayer;
    uint32_t layerCount;
};

struct VkImageViewCreateInfo {
    int sType;
    const void* pNext;
    uint32_t flags;
    VkImage image;
    int viewType;
    int format;
    int components[4];
    VkImageSubresourceRange subresourceRange;
};

struct VkFenceCreateInfo {
    int sType;
    const void* pNext;
    uint32_t flags;
};

struct VkSemaphoreCreateInfo {
    int sType;
    const void* pNext;
    uint32_t flags;
};

struct VkCommandBufferBeginInfo {
    int sType;
    const void* pNext;
    uint32_t flags;
    const void* pInheritanceInfo;
};

struct VkOffset3D {
    int32_t x;
    int32_t y;
    int32_t z;
};

struct VkImageSubresourceLayers {
    int aspectMask;
    uint32_t mipLevel;
    uint32_t baseArrayLayer;
    uint32_t layerCount;
};

struct VkImageBlit {
    VkImageSubresourceLayers srcSubresource;
    VkOffset3D srcOffsets[2];
    VkImageSubresourceLayers dstSubresource;
    VkOffset3D dstOffsets[2];
};

struct VkImageMemoryBarrier {
    int sType;
    const void* pNext;
    uint32_t srcAccessMask;
    uint32_t dstAccessMask;
    int oldLayout;
    int newLayout;
    uint32_t srcQueueFamilyIndex;
    uint32_t dstQueueFamilyIndex;
    VkImage image;
    VkImageSubresourceRange subresourceRange;
};

struct VkSubmitInfo {
    int sType;
    const void* pNext;
    uint32_t waitSemaphoreCount;
    const VkSemaphore* pWaitSemaphores;
    const uint32_t* pWaitDstStageMask;
    uint32_t commandBufferCount;
    const VkCommandBuffer* pCommandBuffers;
    uint32_t signalSemaphoreCount;
    const VkSemaphore* pSignalSemaphores;
};

inline VkResult vkCreateInstance(const VkInstanceCreateInfo*, const void*, VkInstance* pInstance) {
    *pInstance = (VkInstance)1;
    return VK_SUCCESS;
}
inline VkResult vkEnumeratePhysicalDevices(VkInstance, uint32_t* pDeviceCount, VkPhysicalDevice* pDevices) {
    *pDeviceCount = 1;
    if (pDevices) pDevices[0] = (VkPhysicalDevice)1;
    return VK_SUCCESS;
}
inline VkResult vkCreateDevice(VkPhysicalDevice, const VkDeviceCreateInfo*, const void*, VkDevice* pDevice) {
    *pDevice = (VkDevice)1;
    return VK_SUCCESS;
}
inline void vkGetDeviceQueue(VkDevice, uint32_t, uint32_t, VkQueue* pQueue) {
    *pQueue = (VkQueue)1;
}
inline VkResult vkCreateCommandPool(VkDevice, const VkCommandPoolCreateInfo*, const void*, VkCommandPool* pPool) {
    *pPool = (VkCommandPool)1;
    return VK_SUCCESS;
}
inline VkResult vkAllocateCommandBuffers(VkDevice, const VkCommandBufferAllocateInfo*, VkCommandBuffer* pBuffers) {
    pBuffers[0] = (VkCommandBuffer)1;
    return VK_SUCCESS;
}
inline VkResult vkCreateImage(VkDevice, const VkImageCreateInfo*, const void*, VkImage* pImage) {
    *pImage = (VkImage)1;
    return VK_SUCCESS;
}
inline void vkGetImageMemoryRequirements(VkDevice, VkImage, VkMemoryRequirements* pMemReqs) {
    pMemReqs->size = 1024;
    pMemReqs->alignment = 64;
    pMemReqs->memoryTypeBits = 1;
}
inline void vkGetPhysicalDeviceMemoryProperties(VkPhysicalDevice, VkPhysicalDeviceMemoryProperties* pProps) {
    pProps->memoryTypeCount = 1;
    pProps->memoryTypes[0].propertyFlags = VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT;
}
inline VkResult vkAllocateMemory(VkDevice, const VkMemoryAllocateInfo*, const void*, VkDeviceMemory* pMemory) {
    *pMemory = (VkDeviceMemory)1;
    return VK_SUCCESS;
}
inline VkResult vkBindImageMemory(VkDevice, VkImage, VkDeviceMemory, uint64_t) {
    return VK_SUCCESS;
}
inline VkResult vkCreateImageView(VkDevice, const VkImageViewCreateInfo*, const void*, VkImageView* pView) {
    *pView = (VkImageView)1;
    return VK_SUCCESS;
}
inline VkResult vkCreateFence(VkDevice, const VkFenceCreateInfo*, const void*, VkFence* pFence) {
    *pFence = (VkFence)1;
    return VK_SUCCESS;
}
inline VkResult vkCreateSemaphore(VkDevice, const VkSemaphoreCreateInfo*, const void*, VkSemaphore* pSemaphore) {
    *pSemaphore = (VkSemaphore)1;
    return VK_SUCCESS;
}
inline VkResult vkWaitForFences(VkDevice, uint32_t, const VkFence*, uint32_t, uint64_t) {
    return VK_SUCCESS;
}
inline VkResult vkResetFences(VkDevice, uint32_t, const VkFence*) {
    return VK_SUCCESS;
}
inline VkResult vkBeginCommandBuffer(VkCommandBuffer, const VkCommandBufferBeginInfo*) {
    return VK_SUCCESS;
}
inline void vkCmdPipelineBarrier(VkCommandBuffer, int, int, uint32_t, uint32_t, const void*, uint32_t, const void*, uint32_t, const VkImageMemoryBarrier*) {}
inline void vkCmdBlitImage(VkCommandBuffer, VkImage, int, VkImage, int, uint32_t, const VkImageBlit*, int) {}
inline void vkCmdBindPipeline(VkCommandBuffer, int, VkPipeline) {}
inline void vkCmdBindDescriptorSets(VkCommandBuffer, int, VkPipelineLayout, uint32_t, uint32_t, const VkDescriptorSet*, uint32_t, const uint32_t*) {}
inline void vkCmdDispatch(VkCommandBuffer, uint32_t, uint32_t, uint32_t) {}
inline VkResult vkEndCommandBuffer(VkCommandBuffer) {
    return VK_SUCCESS;
}
inline VkResult vkQueueSubmit(VkQueue, uint32_t, const VkSubmitInfo*, VkFence) {
    return VK_SUCCESS;
}
inline VkResult vkDeviceWaitIdle(VkDevice) {
    return VK_SUCCESS;
}
inline void vkDestroyFence(VkDevice, VkFence, const void*) {}
inline void vkDestroySemaphore(VkDevice, VkSemaphore, const void*) {}
inline void vkDestroyImageView(VkDevice, VkImageView, const void*) {}
inline void vkDestroyImage(VkDevice, VkImage, const void*) {}
inline void vkFreeMemory(VkDevice, VkDeviceMemory, const void*) {}
inline void vkDestroyCommandPool(VkDevice, VkCommandPool, const void*) {}
inline void vkDestroyDevice(VkDevice, const void*) {}
inline void vkDestroyInstance(VkInstance, const void*) {}

#endif // HAS_VULKAN

namespace GlassPlayer {

class VulkanRenderer::Impl {
public:
    VkInstance instance = VK_NULL_HANDLE;
    VkPhysicalDevice physicalDevice = VK_NULL_HANDLE;
    VkDevice device = VK_NULL_HANDLE;
    VkQueue graphicsQueue = VK_NULL_HANDLE;
    VkQueue computeQueue = VK_NULL_HANDLE;
    VkCommandPool commandPool = VK_NULL_HANDLE;
    VkCommandBuffer commandBuffer = VK_NULL_HANDLE;
    
    // Shader modules and compute pipelines
    VkShaderModule copyShaderModule = VK_NULL_HANDLE;
    VkShaderModule anime4kShaderModule = VK_NULL_HANDLE;
    VkPipelineLayout pipelineLayout = VK_NULL_HANDLE;
    VkPipeline bilinearPipeline = VK_NULL_HANDLE;
    VkPipeline anime4kPipeline = VK_NULL_HANDLE;
    
    // Descriptors
    VkDescriptorPool descriptorPool = VK_NULL_HANDLE;
    VkDescriptorSetLayout descriptorSetLayout = VK_NULL_HANDLE;
    VkDescriptorSet descriptorSets[2] = {VK_NULL_HANDLE, VK_NULL_HANDLE};
    
    // Ping-Pong texture resources for multi-pass compute pipelines
    VkImage pingPongImages[2] = {VK_NULL_HANDLE, VK_NULL_HANDLE};
    VkDeviceMemory pingPongMemory[2] = {VK_NULL_HANDLE, VK_NULL_HANDLE};
    VkImageView pingPongImageViews[2] = {VK_NULL_HANDLE, VK_NULL_HANDLE};
    uint32_t activeIndex = 0;
    
    // Synchronization fences and semaphores (GPU-CPU-GPU)
    VkFence renderFence = VK_NULL_HANDLE;
    VkSemaphore imageAvailableSemaphore = VK_NULL_HANDLE;
    VkSemaphore renderFinishedSemaphore = VK_NULL_HANDLE;
    
    // Render status
    RenderConfig config;
    uint32_t width = 0;
    uint32_t height = 0;
    
    uint32_t findMemoryType(uint32_t typeFilter, VkMemoryPropertyFlags properties) {
        VkPhysicalDeviceMemoryProperties memProperties;
        vkGetPhysicalDeviceMemoryProperties(physicalDevice, &memProperties);
        for (uint32_t i = 0; i < memProperties.memoryTypeCount; i++) {
            if ((typeFilter & (1 << i)) && (memProperties.memoryTypes[i].propertyFlags & properties) == properties) {
                return i;
            }
        }
        throw std::runtime_error("Failed to find suitable memory type.");
    }
};

VulkanRenderer::VulkanRenderer() : m_impl(std::make_unique<Impl>()) {}

VulkanRenderer::~VulkanRenderer() {
    Shutdown();
}

bool VulkanRenderer::Initialize(void* windowHandle, uint32_t width, uint32_t height) {
    (void)windowHandle;
    m_impl->width = width;
    m_impl->height = height;
    
    // 1. Create Vulkan 1.3 Instance
    VkApplicationInfo appInfo{};
    appInfo.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    appInfo.pApplicationName = "Glass Player";
    appInfo.applicationVersion = VK_MAKE_VERSION(1, 0, 0);
    appInfo.pEngineName = "Glass Engine";
    appInfo.engineVersion = VK_MAKE_VERSION(1, 0, 0);
    appInfo.apiVersion = VK_API_VERSION_1_3; // Mandated version
    
    std::vector<const char*> extensions = {
        "VK_KHR_surface",
        "VK_KHR_win32_surface"
    };
    
    VkInstanceCreateInfo createInfo{};
    createInfo.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    createInfo.pApplicationInfo = &appInfo;
    createInfo.enabledExtensionCount = static_cast<uint32_t>(extensions.size());
    createInfo.ppEnabledExtensionNames = extensions.data();
    
    if (vkCreateInstance(&createInfo, nullptr, &m_impl->instance) != VK_SUCCESS) {
        std::cerr << "[VulkanRenderer] Failed to create Vulkan instance" << std::endl;
        return false;
    }
    
    // 2. Select Physical Device supporting Compute/Vulkan 1.3
    uint32_t deviceCount = 0;
    vkEnumeratePhysicalDevices(m_impl->instance, &deviceCount, nullptr);
    if (deviceCount == 0) {
        std::cerr << "[VulkanRenderer] No GPUs with Vulkan support found" << std::endl;
        return false;
    }
    std::vector<VkPhysicalDevice> devices(deviceCount);
    vkEnumeratePhysicalDevices(m_impl->instance, &deviceCount, devices.data());
    
    // Select the first device (or perform scoring based on limits/Vulkan 1.3 support)
    m_impl->physicalDevice = devices[0];
    
    // 3. Create Logical Device and retrieve Graphics + Compute Queues
    float queuePriority = 1.0f;
    VkDeviceQueueCreateInfo queueCreateInfos[2]{};
    
    // Graphics queue setup
    queueCreateInfos[0].sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
    queueCreateInfos[0].queueFamilyIndex = 0; // standard graphics queue family
    queueCreateInfos[0].queueCount = 1;
    queueCreateInfos[0].pQueuePriorities = &queuePriority;
    
    // Compute queue setup
    queueCreateInfos[1].sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
    queueCreateInfos[1].queueFamilyIndex = 0; // assuming shared family for simple contexts
    queueCreateInfos[1].queueCount = 1;
    queueCreateInfos[1].pQueuePriorities = &queuePriority;
    
    VkPhysicalDeviceFeatures deviceFeatures{};
    deviceFeatures.samplerAnisotropy = VK_TRUE;
    
    VkDeviceCreateInfo deviceCreateInfo{};
    deviceCreateInfo.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
    deviceCreateInfo.queueCreateInfoCount = 1;
    deviceCreateInfo.pQueueCreateInfos = queueCreateInfos;
    deviceCreateInfo.pEnabledFeatures = &deviceFeatures;
    
    if (vkCreateDevice(m_impl->physicalDevice, &deviceCreateInfo, nullptr, &m_impl->device) != VK_SUCCESS) {
        std::cerr << "[VulkanRenderer] Failed to create logical Vulkan device" << std::endl;
        return false;
    }
    
    vkGetDeviceQueue(m_impl->device, 0, 0, &m_impl->graphicsQueue);
    vkGetDeviceQueue(m_impl->device, 0, 0, &m_impl->computeQueue);
    
    // 4. Initialize Command Pools and Command Buffers
    VkCommandPoolCreateInfo poolInfo{};
    poolInfo.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
    poolInfo.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    poolInfo.queueFamilyIndex = 0;
    
    if (vkCreateCommandPool(m_impl->device, &poolInfo, nullptr, &m_impl->commandPool) != VK_SUCCESS) {
        std::cerr << "[VulkanRenderer] Failed to create command pool" << std::endl;
        return false;
    }
    
    VkCommandBufferAllocateInfo allocInfo{};
    allocInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    allocInfo.commandPool = m_impl->commandPool;
    allocInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    allocInfo.commandBufferCount = 1;
    
    if (vkAllocateCommandBuffers(m_impl->device, &allocInfo, &m_impl->commandBuffer) != VK_SUCCESS) {
        std::cerr << "[VulkanRenderer] Failed to allocate command buffers" << std::endl;
        return false;
    }
    
    // 5. Establish Ping-Pong Textures for multi-pass compute operations
    for (int i = 0; i < 2; ++i) {
        VkImageCreateInfo imageInfo{};
        imageInfo.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
        imageInfo.imageType = VK_IMAGE_TYPE_2D;
        imageInfo.extent.width = width;
        imageInfo.extent.height = height;
        imageInfo.extent.depth = 1;
        imageInfo.mipLevels = 1;
        imageInfo.arrayLayers = 1;
        imageInfo.format = VK_FORMAT_B8G8R8A8_UNORM;
        imageInfo.tiling = VK_IMAGE_TILING_OPTIMAL;
        imageInfo.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
        imageInfo.usage = VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_STORAGE_BIT;
        imageInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
        imageInfo.samples = VK_SAMPLE_COUNT_1_BIT;
        
        if (vkCreateImage(m_impl->device, &imageInfo, nullptr, &m_impl->pingPongImages[i]) != VK_SUCCESS) {
            std::cerr << "[VulkanRenderer] Failed to create Ping-Pong VkImage " << i << std::endl;
            return false;
        }
        
        VkMemoryRequirements memReqs;
        vkGetImageMemoryRequirements(m_impl->device, m_impl->pingPongImages[i], &memReqs);
        
        VkMemoryAllocateInfo memAlloc{};
        memAlloc.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
        memAlloc.allocationSize = memReqs.size;
        memAlloc.memoryTypeIndex = m_impl->findMemoryType(memReqs.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
        
        if (vkAllocateMemory(m_impl->device, &memAlloc, nullptr, &m_impl->pingPongMemory[i]) != VK_SUCCESS) {
            std::cerr << "[VulkanRenderer] Failed to allocate device memory for Ping-Pong " << i << std::endl;
            return false;
        }
        
        vkBindImageMemory(m_impl->device, m_impl->pingPongImages[i], m_impl->pingPongMemory[i], 0);
        
        VkImageViewCreateInfo viewInfo{};
        viewInfo.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
        viewInfo.image = m_impl->pingPongImages[i];
        viewInfo.viewType = VK_IMAGE_VIEW_TYPE_2D;
        viewInfo.format = VK_FORMAT_B8G8R8A8_UNORM;
        viewInfo.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
        viewInfo.subresourceRange.baseMipLevel = 0;
        viewInfo.subresourceRange.levelCount = 1;
        viewInfo.subresourceRange.baseArrayLayer = 0;
        viewInfo.subresourceRange.layerCount = 1;
        
        if (vkCreateImageView(m_impl->device, &viewInfo, nullptr, &m_impl->pingPongImageViews[i]) != VK_SUCCESS) {
            std::cerr << "[VulkanRenderer] Failed to create Ping-Pong ImageView " << i << std::endl;
            return false;
        }
    }
    
    // 6. Create Synchronization Primitives
    VkFenceCreateInfo fenceInfo{};
    fenceInfo.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
    fenceInfo.flags = VK_FENCE_CREATE_SIGNALED_BIT;
    
    VkSemaphoreCreateInfo semaphoreInfo{};
    semaphoreInfo.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;
    
    if (vkCreateFence(m_impl->device, &fenceInfo, nullptr, &m_impl->renderFence) != VK_SUCCESS ||
        vkCreateSemaphore(m_impl->device, &semaphoreInfo, nullptr, &m_impl->imageAvailableSemaphore) != VK_SUCCESS ||
        vkCreateSemaphore(m_impl->device, &semaphoreInfo, nullptr, &m_impl->renderFinishedSemaphore) != VK_SUCCESS) {
        std::cerr << "[VulkanRenderer] Failed to create sync structures" << std::endl;
        return false;
    }
    
    std::cout << "[VulkanRenderer] Vulkan 1.3 pipeline successfully initialized." << std::endl;
    return true;
}

void VulkanRenderer::UpdateConfiguration(const RenderConfig& config) {
    m_impl->config = config;
}

bool VulkanRenderer::RenderFrame(const VideoFrame& inputFrame, void* outputSurface) {
    auto renderStart = std::chrono::high_resolution_clock::now();
    
    if (!m_impl->device || !inputFrame.handle) {
        return false;
    }
    
    // Ensure GPU has finished previous work before writing command buffer
    vkWaitForFences(m_impl->device, 1, &m_impl->renderFence, VK_TRUE, UINT64_MAX);
    vkResetFences(m_impl->device, 1, &m_impl->renderFence);
    
    VkImage sourceImage = reinterpret_cast<VkImage>(inputFrame.handle);
    VkImage targetSurface = reinterpret_cast<VkImage>(outputSurface);
    
    // Reset and start command buffer encoding
    VkCommandBufferBeginInfo beginInfo{};
    beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    beginInfo.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    
    vkBeginCommandBuffer(m_impl->commandBuffer, &beginInfo);
    
    ScaleMode activeMode = m_impl->config.mode;
    
    // Check timing constraint dynamically to maintain 16.6ms threshold
    auto timeCheck = std::chrono::high_resolution_clock::now();
    std::chrono::duration<double, std::milli> initialDuration = timeCheck - renderStart;
    
    if (initialDuration.count() > 16.0) {
        std::cerr << "[VulkanRenderer] Latency budget exceeded prior to dispatch. Falling back to Bilinear." << std::endl;
        activeMode = ScaleMode::Bilinear;
    }
    
    if (activeMode == ScaleMode::Bilinear) {
        // Direct blit: fast linear copy using Vulkan device hardware pipeline
        VkImageBlit blitRegion{};
        blitRegion.srcOffsets[0] = {0, 0, 0};
        blitRegion.srcOffsets[1] = {static_cast<int32_t>(inputFrame.width), static_cast<int32_t>(inputFrame.height), 1};
        blitRegion.srcSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
        blitRegion.srcSubresource.mipLevel = 0;
        blitRegion.srcSubresource.baseArrayLayer = 0;
        blitRegion.srcSubresource.layerCount = 1;
        
        blitRegion.dstOffsets[0] = {0, 0, 0};
        blitRegion.dstOffsets[1] = {static_cast<int32_t>(m_impl->width), static_cast<int32_t>(m_impl->height), 1};
        blitRegion.dstSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
        blitRegion.dstSubresource.mipLevel = 0;
        blitRegion.dstSubresource.baseArrayLayer = 0;
        blitRegion.dstSubresource.layerCount = 1;
        
        // Ensure layouts are prepared for transfer blit
        VkImageMemoryBarrier barrier{};
        barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
        barrier.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED;
        barrier.newLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
        barrier.srcAccessMask = 0;
        barrier.dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
        barrier.image = sourceImage;
        barrier.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
        barrier.subresourceRange.levelCount = 1;
        barrier.subresourceRange.layerCount = 1;
        
        vkCmdPipelineBarrier(m_impl->commandBuffer, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nullptr, 0, nullptr, 1, &barrier);
        
        vkCmdBlitImage(
            m_impl->commandBuffer,
            sourceImage, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
            targetSurface, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            1, &blitRegion,
            VK_FILTER_LINEAR
        );
    } else {
        // Multi-pass compute path (Anime4K/ArtCNN upscaling) on the GPU timeline
        // 1. Transition layouts to Shader Read and Storage boundaries
        VkImageMemoryBarrier barriers[2]{};
        barriers[0].sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
        barriers[0].oldLayout = VK_IMAGE_LAYOUT_UNDEFINED;
        barriers[0].newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        barriers[0].srcAccessMask = 0;
        barriers[0].dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
        barriers[0].image = sourceImage;
        barriers[0].subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
        barriers[0].subresourceRange.levelCount = 1;
        barriers[0].subresourceRange.layerCount = 1;
        
        barriers[1].sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
        barriers[1].oldLayout = VK_IMAGE_LAYOUT_UNDEFINED;
        barriers[1].newLayout = VK_IMAGE_LAYOUT_GENERAL;
        barriers[1].srcAccessMask = 0;
        barriers[1].dstAccessMask = VK_ACCESS_SHADER_WRITE_BIT;
        barriers[1].image = m_impl->pingPongImages[m_impl->activeIndex];
        barriers[1].subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
        barriers[1].subresourceRange.levelCount = 1;
        barriers[1].subresourceRange.layerCount = 1;
        
        vkCmdPipelineBarrier(m_impl->commandBuffer, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0, 0, nullptr, 0, nullptr, 2, barriers);
        
        // 2. Bind layout descriptors and dispatch compute invocation
        vkCmdBindPipeline(m_impl->commandBuffer, VK_PIPELINE_BIND_POINT_COMPUTE, m_impl->anime4kPipeline);
        vkCmdBindDescriptorSets(m_impl->commandBuffer, VK_PIPELINE_BIND_POINT_COMPUTE, m_impl->pipelineLayout, 0, 1, &m_impl->descriptorSets[m_impl->activeIndex], 0, nullptr);
        
        // Calculate workgroups based on scaling dimensions (e.g. 16x16 threads per group)
        uint32_t groupCountX = (m_impl->width + 15) / 16;
        uint32_t groupCountY = (m_impl->height + 15) / 16;
        vkCmdDispatch(m_impl->commandBuffer, groupCountX, groupCountY, 1);
        
        // Swap active ping-pong index
        m_impl->activeIndex = (m_impl->activeIndex + 1) % 2;
    }
    
    vkEndCommandBuffer(m_impl->commandBuffer);
    
    // Submit commands to queue
    VkSubmitInfo submitInfo{};
    submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    submitInfo.commandBufferCount = 1;
    submitInfo.pCommandBuffers = &m_impl->commandBuffer;
    
    if (vkQueueSubmit(m_impl->graphicsQueue, 1, &submitInfo, m_impl->renderFence) != VK_SUCCESS) {
        std::cerr << "[VulkanRenderer] Failed to submit Vulkan rendering commands" << std::endl;
        return false;
    }
    
    // Check total frame time
    auto renderEnd = std::chrono::high_resolution_clock::now();
    std::chrono::duration<double, std::milli> frameDuration = renderEnd - renderStart;
    
    if (frameDuration.count() > 16.6) {
        std::cerr << "[VulkanRenderer] Frame time (" << frameDuration.count() << "ms) exceeded 16.6ms threshold." << std::endl;
        return false; // Signifies that fallback occurred or was forced
    }
    
    return true;
}

void VulkanRenderer::Shutdown() {
    if (m_impl->device != VK_NULL_HANDLE) {
        vkDeviceWaitIdle(m_impl->device);
        
        if (m_impl->renderFence != VK_NULL_HANDLE) {
            vkDestroyFence(m_impl->device, m_impl->renderFence, nullptr);
        }
        if (m_impl->imageAvailableSemaphore != VK_NULL_HANDLE) {
            vkDestroySemaphore(m_impl->device, m_impl->imageAvailableSemaphore, nullptr);
        }
        if (m_impl->renderFinishedSemaphore != VK_NULL_HANDLE) {
            vkDestroySemaphore(m_impl->device, m_impl->renderFinishedSemaphore, nullptr);
        }
        
        for (int i = 0; i < 2; ++i) {
            if (m_impl->pingPongImageViews[i] != VK_NULL_HANDLE) {
                vkDestroyImageView(m_impl->device, m_impl->pingPongImageViews[i], nullptr);
            }
            if (m_impl->pingPongImages[i] != VK_NULL_HANDLE) {
                vkDestroyImage(m_impl->device, m_impl->pingPongImages[i], nullptr);
            }
            if (m_impl->pingPongMemory[i] != VK_NULL_HANDLE) {
                vkFreeMemory(m_impl->device, m_impl->pingPongMemory[i], nullptr);
            }
        }
        
        if (m_impl->commandPool != VK_NULL_HANDLE) {
            vkDestroyCommandPool(m_impl->device, m_impl->commandPool, nullptr);
        }
        if (m_impl->device != VK_NULL_HANDLE) {
            vkDestroyDevice(m_impl->device, nullptr);
        }
    }
    if (m_impl->instance != VK_NULL_HANDLE) {
        vkDestroyInstance(m_impl->instance, nullptr);
    }
}

} // namespace GlassPlayer
