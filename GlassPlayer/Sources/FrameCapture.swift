import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Captures Metal textures to PNG files for quality comparison
///
/// Usage:
///   FrameCapture.capture(texture: sourceTexture, to: "frame_source.png")
///   FrameCapture.capture(texture: outputTexture, to: "frame_output.png")
///
/// These PNGs can then be compared against mpv GLSL reference renders
/// using the QualityCompare tool for SSIM/PSNR metrics.
public struct FrameCapture {

    /// Errors that can occur during frame capture
    public enum CaptureError: Error, CustomStringConvertible {
        case textureNotReadable
        case failedToCreateBitmapContext
        case failedToCreateData
        case failedToWriteFile(String)
        case unsupportedPixelFormat(MTLPixelFormat)

        public var description: String {
            switch self {
            case .textureNotReadable:
                return "Texture is not readable - ensure storageMode is .shared or .managed"
            case .failedToCreateBitmapContext:
                return "Failed to create CGBitmapContext for texture conversion"
            case .failedToCreateData:
                return "Failed to create data from CGImage"
            case .failedToWriteFile(let path):
                return "Failed to write PNG file to: \(path)"
            case .unsupportedPixelFormat(let format):
                return "Unsupported pixel format: \(format)"
            }
        }
    }

    /// Configuration for frame capture
    public struct Configuration {
        /// Output directory for captured frames
        public let outputDirectory: String

        /// Filename prefix for captured frames
        public let filenamePrefix: String

        /// Include timestamp in filename
        public let includeTimestamp: Bool

        /// Pixel format for conversion (must be .bgra8Unorm or .rgba8Unorm)
        public let targetPixelFormat: MTLPixelFormat

        public init(
            outputDirectory: String = "/tmp/glass-player-captures",
            filenamePrefix: String = "frame",
            includeTimestamp: Bool = true,
            targetPixelFormat: MTLPixelFormat = .bgra8Unorm
        ) {
            self.outputDirectory = outputDirectory
            self.filenamePrefix = filenamePrefix
            self.includeTimestamp = includeTimestamp
            self.targetPixelFormat = targetPixelFormat
        }
    }

    /// Captures a Metal texture to a PNG file
    ///
    /// - Parameters:
    ///   - texture: The MTLTexture to capture
    ///   - filename: Output filename (will be placed in outputDirectory)
    ///   - device: MTLDevice for creating staging textures if needed
    /// - Returns: Path to the captured PNG file
    /// - Throws: CaptureError if capture fails
    public static func capture(
        texture: MTLTexture,
        filename: String,
        device: MTLDevice,
        configuration: Configuration = Configuration()
    ) throws -> String {
        // Ensure output directory exists
        try FileManager.default.createDirectory(
            atPath: configuration.outputDirectory,
            withIntermediateDirectories: true
        )

        // Build full path
        let timestamp = configuration.includeTimestamp ?
            "_\(Date().timeIntervalSince1970)" : ""
        let fullPath = "\(configuration.outputDirectory)/\(configuration.filenamePrefix)\(timestamp)_\(filename)"

        // Convert texture to CGImage
        guard let cgImage = texture.toCGImage(device: device) else {
            throw CaptureError.failedToCreateBitmapContext
        }

        // Write to PNG
        guard let data = cgImage.pngRepresentation else {
            throw CaptureError.failedToCreateData
        }

        try data.write(to: URL(fileURLWithPath: fullPath))

        NSLog("[FrameCapture] Captured: \(fullPath) (\(texture.width)x\(texture.height))")
        return fullPath
    }

    /// Captures both source and processed frames for comparison
    ///
    /// - Parameters:
    ///   - sourceTexture: Original frame before Anime4K processing
    ///   - outputTexture: Processed frame after Anime4K
    ///   - presetName: Name of the Anime4K preset used
    ///   - device: MTLDevice
    /// - Returns: Tuple of (sourcePath, outputPath) for comparison
    public static func captureComparison(
        sourceTexture: MTLTexture,
        outputTexture: MTLTexture,
        presetName: String,
        device: MTLDevice,
        configuration: Configuration = Configuration()
    ) throws -> (sourcePath: String, outputPath: String) {
        let safePresetName = presetName
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")

        let sourcePath = try capture(
            texture: sourceTexture,
            filename: "source_\(safePresetName).png",
            device: device,
            configuration: configuration
        )

        let outputPath = try capture(
            texture: outputTexture,
            filename: "output_\(safePresetName).png",
            device: device,
            configuration: configuration
        )

        return (sourcePath, outputPath)
    }
}

// MARK: - MTLTexture Extension for Capture

extension MTLTexture {

    /// Converts a Metal texture to a CGImage
    ///
    /// - Parameter device: MTLDevice for creating staging textures
    /// - Returns: CGImage or nil if conversion fails
    func toCGImage(device: MTLDevice) -> CGImage? {
        // For simplicity, always copy to staging texture for CPU read
        return copyToStagingAndConvert(device: device)
    }

    /// Copies texture to a staging texture and converts to CGImage
    private func copyToStagingAndConvert(device: MTLDevice) -> CGImage? {
        let tex = self
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: tex.pixelFormat,
            width: tex.width,
            height: tex.height,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = [.shaderRead, .shaderWrite]

        guard let stagingTexture = device.makeTexture(descriptor: descriptor) else {
            return nil
        }

        // Copy from source to staging
        guard let commandQueue = device.makeCommandQueue(),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeBlitCommandEncoder() else {
            return nil
        }

        encoder.copy(from: tex, to: stagingTexture)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        return stagingTexture.convertToCGImage()
    }

    /// Converts a readable staging texture to CGImage
    private func convertToCGImage() -> CGImage? {
        // Only support BGRA8 and RGBA8 for now
        guard pixelFormat == .bgra8Unorm || pixelFormat == .rgba8Unorm else {
            NSLog("[FrameCapture] Unsupported pixel format: \(pixelFormat)")
            return nil
        }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let bytesPerImage = bytesPerRow * height

        // Allocate buffer for texture data
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bytesPerImage)
        defer { buffer.deallocate() }

        // Get texture data
        let region = MTLRegion(
            origin: MTLOrigin(x: 0, y: 0, z: 0),
            size: MTLSize(width: width, height: height, depth: 1)
        )

        getBytes(
            buffer,
            bytesPerRow: bytesPerRow,
            bytesPerImage: bytesPerImage,
            from: region,
            mipmapLevel: 0,
            slice: 0
        )

        // Create CGImage
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: buffer,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: pixelFormat == .bgra8Unorm ?
                    CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue :
                    CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        guard let cgImage = context.makeImage() else {
            return nil
        }

        return cgImage
    }
}

// MARK: - CGImage Extension

extension CGImage {

    /// Converts CGImage to PNG data representation
    var pngRepresentation: Data? {
        let data = NSMutableData()
        let pngType = UTType.png.identifier as CFString
        guard let destination = CGImageDestinationCreateWithData(
                data as CFMutableData,
                pngType,
                1,
                nil
        ) else {
            return nil
        }

        CGImageDestinationAddImage(destination, self, nil)

        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return data as Data
    }
}
