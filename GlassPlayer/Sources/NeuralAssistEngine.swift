import Foundation
import AppKit
import Metal
import MetalPerformanceShaders
import CoreImage
import CoreML
import Vision

final class NeuralAssistEngine {
    static let shared = NeuralAssistEngine()

    private let ciContext = CIContext(options: nil)
    private let detailThreshold: Float
    private let advisoryOnly: Bool
    private let analysisMaxDimension: CGFloat
    private let mpsConvolutionEnabled: Bool
    private let mpsDevice: MTLDevice?
    private let mpsCommandQueue: MTLCommandQueue?

    private let neuralEngineDevice: MLComputeDevice?
    let hasNeuralEngine: Bool

    private init() {
        let env = ProcessInfo.processInfo.environment["GLASS_NEURAL_ASSIST_THRESHOLD"]
        if let env = env, let parsed = Float(env), parsed > 0 {
            detailThreshold = parsed
        } else {
            detailThreshold = 0.018
        }

        advisoryOnly = ProcessInfo.processInfo.environment["GLASS_NEURAL_ASSIST_ADVISORY"] != "0"
        let mpsOptIn = ProcessInfo.processInfo.environment["GLASS_NEURAL_ASSIST_USE_MPS"] != "0"
        if let raw = ProcessInfo.processInfo.environment["GLASS_NEURAL_ASSIST_MAX_DIM"],
           let parsed = Double(raw),
           parsed >= 160 {
            analysisMaxDimension = CGFloat(parsed)
        } else {
            analysisMaxDimension = 512
        }

        let device = MTLCreateSystemDefaultDevice()
        mpsDevice = device
        mpsCommandQueue = device?.makeCommandQueue()
        mpsConvolutionEnabled = mpsOptIn && mpsDevice != nil && mpsCommandQueue != nil

        if #available(macOS 13.0, *) {
            neuralEngineDevice = MLComputeDevice.allComputeDevices.first { device in
                String(describing: device).contains("MLNeuralEngineComputeDevice")
            }
            hasNeuralEngine = neuralEngineDevice != nil
        } else {
            neuralEngineDevice = nil
            hasNeuralEngine = false
        }

        if hasNeuralEngine {
            NSLog("[NeuralAssist] Neural Engine detected (threshold=%.6f, advisoryOnly=%@, maxDim=%.0f, mpsConv=%@)",
                  detailThreshold,
                  advisoryOnly ? "YES" : "NO",
                  analysisMaxDimension,
                  mpsConvolutionEnabled ? "YES" : "NO")
        } else {
            NSLog("[NeuralAssist] Neural Engine not detected; falling back to GPU-only preset path")
        }
    }

    func resolvePreset(requestedPreset: String, frameImage: NSImage) -> String {
        guard hasNeuralEngine else { return requestedPreset }
        guard requestedPreset.contains("(HQ)") else { return requestedPreset }
        guard let score = computeDetailScore(image: frameImage) else {
            NSLog("[NeuralAssist] Unable to compute detail score; keeping requested preset %@", requestedPreset)
            return requestedPreset
        }

        // Quality lock: never auto-downgrade presets here. The score is retained
        // as advisory telemetry so users can profile difficult content with ANE.
        guard advisoryOnly else {
            NSLog("[NeuralAssist] advisory mode disabled but quality lock is active; keeping %@ (detail=%.6f)",
                  requestedPreset,
                  score)
            return requestedPreset
        }

        if score < detailThreshold {
            NSLog("[NeuralAssist] detail=%.6f < %.6f for %@ (advisory: low detail, keeping quality preset)",
                  score,
                  detailThreshold,
                  requestedPreset)
            return requestedPreset
        }

        NSLog("[NeuralAssist] detail=%.6f >= %.6f, keeping %@",
              score,
              detailThreshold,
              requestedPreset)
        return requestedPreset
    }

    private func computeDetailScore(image: NSImage) -> Float? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let analysisImage = downscaledIfNeeded(cgImage)

        // Fast path: use MPS convolution edge energy as a lightweight detail metric.
        if mpsConvolutionEnabled,
           let mpsScore = computeMPSConvolutionDetailScore(cgImage: analysisImage) {
            NSLog("[NeuralAssist] detail (MPS convolution)=%.6f", mpsScore)
            return mpsScore
        }

        // Fallback: Vision feature-print distance against a blurred reference.
        guard let blurredCGImage = makeBlurredImage(from: analysisImage) else {
            return nil
        }
        guard let originalObservation = featurePrint(for: analysisImage),
              let blurredObservation = featurePrint(for: blurredCGImage) else {
            return nil
        }

        var distance: Float = 0
        do {
            try originalObservation.computeDistance(&distance, to: blurredObservation)
            NSLog("[NeuralAssist] detail (Vision feature print)=%.6f", distance)
            return distance
        } catch {
            NSLog("[NeuralAssist] Failed to compute feature distance: %@", String(describing: error))
            return nil
        }
    }

    private func computeMPSConvolutionDetailScore(cgImage: CGImage) -> Float? {
        guard let device = mpsDevice,
              let commandQueue = mpsCommandQueue else {
            return nil
        }

        let width = max(1, cgImage.width)
        let height = max(1, cgImage.height)

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float,
                                                                  width: width,
                                                                  height: height,
                                                                  mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.shaderRead, .shaderWrite]

        guard let inputTexture = device.makeTexture(descriptor: descriptor),
              let outputTexture = device.makeTexture(descriptor: descriptor) else {
            return nil
        }

        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        ciContext.render(CIImage(cgImage: cgImage),
                         to: inputTexture,
                         commandBuffer: nil,
                         bounds: bounds,
                         colorSpace: colorSpace)

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            return nil
        }

        // Laplacian high-pass kernel; mean absolute response approximates detail energy.
        let laplacian: [Float] = [
             0, -1,  0,
            -1,  4, -1,
             0, -1,  0
        ]
        let convolution = MPSImageConvolution(device: device,
                                              kernelWidth: 3,
                                              kernelHeight: 3,
                                              weights: laplacian)
        convolution.edgeMode = .clamp
        convolution.encode(commandBuffer: commandBuffer,
                           sourceTexture: inputTexture,
                           destinationTexture: outputTexture)

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let bytesPerPixel = 8
        let bytesPerRow = width * bytesPerPixel
        let totalBytes = bytesPerRow * height
        let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                               size: MTLSize(width: width, height: height, depth: 1))
        var buffer = [UInt8](repeating: 0, count: totalBytes)
        outputTexture.getBytes(&buffer,
                               bytesPerRow: bytesPerRow,
                               from: region,
                               mipmapLevel: 0)

        @inline(__always)
        func decodeHalf(_ lo: UInt8, _ hi: UInt8) -> Float {
            let bits = UInt16(lo) | (UInt16(hi) << 8)
            return Float(Float16(bitPattern: bits))
        }

        var edgeSum: Float = 0
        var sampleCount = 0

        for y in 0..<height {
            let rowBase = y * bytesPerRow
            for x in 0..<width {
                let i = rowBase + x * bytesPerPixel
                let r = decodeHalf(buffer[i], buffer[i + 1])
                let g = decodeHalf(buffer[i + 2], buffer[i + 3])
                let b = decodeHalf(buffer[i + 4], buffer[i + 5])
                let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
                edgeSum += abs(luma)
                sampleCount += 1
            }
        }

        guard sampleCount > 0 else {
            return nil
        }

        return edgeSum / Float(sampleCount)
    }

    private func featurePrint(for cgImage: CGImage) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        if #available(macOS 14.0, *) {
            if let neuralEngineDevice = neuralEngineDevice {
                request.setComputeDevice(neuralEngineDevice, for: .main)
            }
        } else {
            request.usesCPUOnly = false
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            NSLog("[NeuralAssist] Feature print request failed: %@", String(describing: error))
            return nil
        }

        return request.results?.first as? VNFeaturePrintObservation
    }

    private func makeBlurredImage(from cgImage: CGImage) -> CGImage? {
        let input = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CIGaussianBlur") else {
            return nil
        }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(3.0, forKey: kCIInputRadiusKey)

        guard let output = filter.outputImage else {
            return nil
        }

        let blurred = output.cropped(to: input.extent)
        guard !blurred.extent.isEmpty else {
            return nil
        }
        return ciContext.createCGImage(blurred, from: blurred.extent)
    }

    private func downscaledIfNeeded(_ cgImage: CGImage) -> CGImage {
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let longest = max(width, height)
        guard longest > analysisMaxDimension else {
            return cgImage
        }

        let scale = analysisMaxDimension / longest
        let input = CIImage(cgImage: cgImage)

        guard let filter = CIFilter(name: "CILanczosScaleTransform") else {
            let transformed = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            return ciContext.createCGImage(transformed, from: transformed.extent) ?? cgImage
        }

        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(scale, forKey: kCIInputScaleKey)
        filter.setValue(1.0, forKey: kCIInputAspectRatioKey)

        guard let output = filter.outputImage,
              !output.extent.isEmpty,
              let scaled = ciContext.createCGImage(output, from: output.extent) else {
            return cgImage
        }

        return scaled
    }
}