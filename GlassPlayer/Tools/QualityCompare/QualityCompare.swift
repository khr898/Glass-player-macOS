import Foundation
import Accelerate
import CoreGraphics
import ImageIO

/// Compares two images using SSIM and PSNR metrics
///
/// Usage:
///   QualityCompare.compare(source: "source.png", processed: "output.png")
///
/// Outputs JSON report with:
/// - SSIM (Structural Similarity Index): 0.0-1.0, higher is better
/// - PSNR (Peak Signal-to-Noise Ratio): dB, higher is better
/// - Difference heatmap image (optional)
///
/// Target thresholds for Metal vs GLSL comparison:
/// - SSIM > 0.99 (excellent match)
/// - PSNR > 40dB (high quality)
public struct QualityCompare {

    /// Comparison results
    public struct ComparisonResult: Codable, CustomStringConvertible {
        /// Path to the source (original) image
        public let sourcePath: String

        /// Path to the processed (Metal output) image
        public let processedPath: String

        /// Path to the reference (GLSL output) image, if provided
        public let referencePath: String?

        /// SSIM score (0.0-1.0, 1.0 = identical)
        public let ssim: Double

        /// PSNR score in dB (higher = better, >40dB is excellent)
        public let psnr: Double

        /// Mean squared error
        public let mse: Double

        /// Maximum difference in any pixel (0-255)
        public let maxDifference: UInt8

        /// Timestamp of comparison
        public let timestamp: String

        /// Whether the comparison passed quality thresholds
        public let passed: Bool

        /// Quality threshold for SSIM
        public let ssimThreshold: Double

        /// Quality threshold for PSNR
        public let psnrThreshold: Double

        public var description: String {
            """
            Quality Comparison Report
            =========================
            Source: \(sourcePath)
            Processed: \(processedPath)
            \(referencePath.map { "Reference: \($0)" } ?? "No reference")

            Metrics:
              SSIM:  \(String(format: "%.2f", ssim)) \(ssimStatus)
              PSNR:  \(String(format: "%.1f", psnr)) dB \(psnrStatus)
              MSE:   \(String(format: "%.2f", mse))
              Max Δ: \(maxDifference)

            Thresholds:
              SSIM:  \(ssimThreshold) (target > 0.99)
              PSNR:  \(psnrThreshold) dB (target > 40)

            Result: \(passed ? "PASSED" : "FAILED")
            """
        }

        private var ssimStatus: String {
            if ssim >= 0.99 { return "Excellent" }
            if ssim >= 0.95 { return "Good" }
            if ssim >= 0.90 { return "Acceptable" }
            return "Poor"
        }

        private var psnrStatus: String {
            if psnr >= 40 { return "Excellent" }
            if psnr >= 30 { return "Good" }
            if psnr >= 20 { return "Acceptable" }
            return "Poor"
        }
    }

    /// Errors that can occur during comparison
    public enum CompareError: Error, CustomStringConvertible {
        case fileNotFound(String)
        case failedToLoadImage(String)
        case imageSizeMismatch(CGSize, CGSize)
        case invalidPixelFormat
        case failedToAllocateBuffer
        case numericalInstability

        public var description: String {
            switch self {
            case .fileNotFound(let path):
                return "File not found: \(path)"
            case .failedToLoadImage(let path):
                return "Failed to load image: \(path)"
            case .imageSizeMismatch(let size1, let size2):
                return "Image sizes do not match: \(size1) vs \(size2)"
            case .invalidPixelFormat:
                return "Invalid pixel format - expected 8-bit grayscale or RGB"
            case .failedToAllocateBuffer:
                return "Failed to allocate memory buffer for comparison"
            case .numericalInstability:
                return "Numerical instability detected in calculation"
            }
        }
    }

    /// Configuration for quality comparison
    public struct Configuration {
        /// SSIM threshold for passing (default: 0.99)
        public let ssimThreshold: Double

        /// PSNR threshold for passing (default: 40.0 dB)
        public let psnrThreshold: Double

        /// Generate difference heatmap image
        public let generateHeatmap: Bool

        /// Output path for heatmap (if generated)
        public let heatmapOutputPath: String?

        public init(
            ssimThreshold: Double = 0.99,
            psnrThreshold: Double = 40.0,
            generateHeatmap: Bool = false,
            heatmapOutputPath: String? = nil
        ) {
            self.ssimThreshold = ssimThreshold
            self.psnrThreshold = psnrThreshold
            self.generateHeatmap = generateHeatmap
            self.heatmapOutputPath = heatmapOutputPath
        }
    }

    /// Compares two images and returns quality metrics
    ///
    /// - Parameters:
    ///   - sourcePath: Path to source image (before processing)
    ///   - processedPath: Path to processed image (after Anime4K)
    ///   - referencePath: Optional path to reference image (GLSL output)
    ///   - configuration: Comparison configuration
    /// - Returns: ComparisonResult with SSIM, PSNR, and other metrics
    /// - Throws: CompareError if comparison fails
    public static func compare(
        source sourcePath: String,
        processed processedPath: String,
        reference referencePath: String? = nil,
        configuration: Configuration = Configuration()
    ) throws -> ComparisonResult {

        // Verify files exist
        guard FileManager.default.fileExists(atPath: sourcePath) else {
            throw CompareError.fileNotFound(sourcePath)
        }
        guard FileManager.default.fileExists(atPath: processedPath) else {
            throw CompareError.fileNotFound(processedPath)
        }
        if let refPath = referencePath {
            guard FileManager.default.fileExists(atPath: refPath) else {
                throw CompareError.fileNotFound(refPath)
            }
        }

        // Load images
        guard let sourceImage = loadImage(from: sourcePath) else {
            throw CompareError.failedToLoadImage(sourcePath)
        }
        guard let processedImage = loadImage(from: processedPath) else {
            throw CompareError.failedToLoadImage(processedPath)
        }

        // Verify sizes match
        guard sourceImage.width == processedImage.width &&
              sourceImage.height == processedImage.height else {
            throw CompareError.imageSizeMismatch(
                CGSize(width: sourceImage.width, height: sourceImage.height),
                CGSize(width: processedImage.width, height: processedImage.height)
            )
        }

        // Convert to grayscale float arrays for comparison
        let sourceData = try imageToFloatArray(sourceImage)
        let processedData = try imageToFloatArray(processedImage)

        // Calculate metrics
        let mse = calculateMSE(sourceData, processedData)
        let psnr = calculatePSNR(sourceData, processedData, mse: mse)
        let ssim = calculateSSIM(sourceData, processedData)
        let maxDiff = calculateMaxDifference(sourceData, processedData)

        // If reference provided, compare against reference instead
        let finalSSIM: Double
        let finalPSNR: Double
        let finalMSE: Double

        if let refPath = referencePath,
           let referenceImage = loadImage(from: refPath) {
            let refData = try imageToFloatArray(referenceImage)
            finalMSE = calculateMSE(processedData, refData)
            finalPSNR = calculatePSNR(processedData, refData, mse: finalMSE)
            finalSSIM = calculateSSIM(processedData, refData)
        } else {
            finalMSE = mse
            finalPSNR = psnr
            finalSSIM = ssim
        }

        let passed = finalSSIM >= configuration.ssimThreshold &&
                     finalPSNR >= configuration.psnrThreshold

        // Generate heatmap if requested
        if configuration.generateHeatmap, let outputPath = configuration.heatmapOutputPath {
            try generateHeatmap(source: sourceData,
                               processed: processedData,
                               width: sourceImage.width,
                               height: sourceImage.height,
                               outputPath: outputPath)
        }

        return ComparisonResult(
            sourcePath: sourcePath,
            processedPath: processedPath,
            referencePath: referencePath,
            ssim: finalSSIM,
            psnr: finalPSNR,
            mse: finalMSE,
            maxDifference: maxDiff,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            passed: passed,
            ssimThreshold: configuration.ssimThreshold,
            psnrThreshold: configuration.psnrThreshold
        )
    }

    // MARK: - Private Methods

    /// Loads a CGImage from a file path
    private static func loadImage(from path: String) -> CGImage? {
        guard let data = FileManager.default.contents(atPath: path),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return image
    }

    /// Converts CGImage to float array for numerical comparison
    private static func imageToFloatArray(_ image: CGImage) throws -> [Float] {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4 // RGBA
        let bytesPerRow = width * bytesPerPixel
        let totalBytes = bytesPerRow * height

        guard let buffer = malloc(totalBytes) else {
            throw CompareError.failedToAllocateBuffer
        }
        defer { free(buffer) }

        guard let context = CGContext(
                data: buffer,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw CompareError.failedToAllocateBuffer
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Convert to grayscale float values (0.0-1.0)
        let sourceBuffer = buffer.bindMemory(to: UInt8.self, capacity: totalBytes)
        var floatArray = [Float](repeating: 0, count: width * height)

        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * bytesPerPixel
                let r = Float(sourceBuffer[offset]) / 255.0
                let g = Float(sourceBuffer[offset + 1]) / 255.0
                let b = Float(sourceBuffer[offset + 2]) / 255.0
                // Luminance formula for grayscale conversion
                floatArray[y * width + x] = 0.299 * r + 0.587 * g + 0.114 * b
            }
        }

        return floatArray
    }

    /// Calculates Mean Squared Error between two images
    private static func calculateMSE(_ source: [Float], _ processed: [Float]) -> Double {
        precondition(source.count == processed.count, "Arrays must have same length")

        let n = vDSP_Length(source.count)

        // Calculate difference
        var difference = [Float](repeating: 0, count: source.count)
        vDSP_vsub(source, 1, processed, 1, &difference, 1, n)

        // Square the differences
        var squaredDifferences = [Float](repeating: 0, count: source.count)
        vDSP_vsq(difference, 1, &squaredDifferences, 1, n)

        // Calculate mean
        var mean: Float = 0
        vDSP_meanv(squaredDifferences, 1, &mean, n)

        return Double(mean)
    }

    /// Calculates Peak Signal-to-Noise Ratio
    private static func calculatePSNR(_ source: [Float], _ processed: [Float], mse: Double) -> Double {
        guard mse > 0 else { return Double.infinity } // Identical images

        let maxPixelValue: Double = 1.0 // Normalized range
        let psnr = 10.0 * log10((maxPixelValue * maxPixelValue) / mse)

        guard psnr.isFinite else {
            return 0.0 // Handle numerical instability
        }

        return psnr
    }

    /// Calculates Structural Similarity Index
    private static func calculateSSIM(_ source: [Float], _ processed: [Float]) -> Double {
        precondition(source.count == processed.count, "Arrays must have same length")

        let n = vDSP_Length(source.count)

        // Constants for SSIM (from original paper)
        let L: Float = 1.0 // Dynamic range
        let K1: Float = 0.01
        let K2: Float = 0.03
        let C1 = (K1 * L) * (K1 * L)
        let C2 = (K2 * L) * (K2 * L)

        // Calculate means
        var sourceMean: Float = 0
        var processedMean: Float = 0
        vDSP_meanv(source, 1, &sourceMean, n)
        vDSP_meanv(processed, 1, &processedMean, n)

        // Calculate variances
        var sourceVar: Float = 0
        var processedVar: Float = 0

        var sourceCopy = source
        var processedCopy = processed

        // Mean-corrected variance calculation
        vDSP_vsq(sourceCopy, 1, &sourceCopy, 1, n)
        vDSP_vsq(processedCopy, 1, &processedCopy, 1, n)

        var sourceVarRaw: Float = 0
        var processedVarRaw: Float = 0
        vDSP_meanv(sourceCopy, 1, &sourceVarRaw, n)
        vDSP_meanv(processedCopy, 1, &processedVarRaw, n)

        sourceVar = sourceVarRaw - sourceMean * sourceMean
        processedVar = processedVarRaw - processedMean * processedMean

        // Calculate covariance
        var covariance: Float = 0
        vDSP_dotpr(source, 1, processed, 1, &covariance, n)
        covariance = covariance / Float(n) - sourceMean * processedMean

        // Calculate SSIM
        let muX = sourceMean
        let muY = processedMean
        let sigmaX2 = max(sourceVar, 0)
        let sigmaY2 = max(processedVar, 0)
        let sigmaXY = max(covariance, 0)

        let numerator = (2 * muX * muY + C1) * (2 * sigmaXY + C2)
        let denominator = (muX * muX + muY * muY + C1) * (sigmaX2 + sigmaY2 + C2)

        guard denominator > 0 else { return 0.0 }

        return Double(numerator / denominator)
    }

    /// Calculates maximum pixel difference
    private static func calculateMaxDifference(_ source: [Float], _ processed: [Float]) -> UInt8 {
        precondition(source.count == processed.count, "Arrays must have same length")

        var sourceCopy = source
        var maxDiff: Float = 0

        vDSP_vsub(sourceCopy, 1, processed, 1, &sourceCopy, 1, vDSP_Length(source.count))
        vDSP_vabs(sourceCopy, 1, &sourceCopy, 1, vDSP_Length(source.count))
        vDSP_maxv(sourceCopy, 1, &maxDiff, vDSP_Length(source.count))

        return UInt8(min(maxDiff * 255, 255))
    }

    /// Generates a heatmap image showing pixel differences
    private static func generateHeatmap(
        source: [Float],
        processed: [Float],
        width: Int,
        height: Int,
        outputPath: String
    ) throws {
        let count = source.count
        var diffData = [UInt8](repeating: 0, count: count * 4) // RGBA

        for i in 0..<count {
            let diff = abs(source[i] - processed[i]) * 255
            let intensity = UInt8(min(diff, 255))

            // Color map: blue (low) -> green -> yellow -> red (high)
            let offset = i * 4
            if intensity < 64 {
                // Blue to green
                diffData[offset] = 0 // R
                diffData[offset + 1] = intensity * 4 // G
                diffData[offset + 2] = 255 - intensity * 4 // B
            } else if intensity < 128 {
                // Green to yellow
                diffData[offset] = (intensity - 64) * 4 // R
                diffData[offset + 1] = 255 // G
                diffData[offset + 2] = 255 - (intensity - 64) * 4 // B
            } else if intensity < 192 {
                // Yellow to orange
                diffData[offset] = 255 // R
                diffData[offset + 1] = 255 - (intensity - 128) * 4 // G
                diffData[offset + 2] = 0 // B
            } else {
                // Orange to red
                diffData[offset] = 255 // R
                diffData[offset + 1] = (192 - intensity) * 4 // G
                diffData[offset + 2] = 0 // B
            }
            diffData[offset + 3] = 255 // Alpha
        }

        // Create CGImage using mutable pointer
        try diffData.withUnsafeMutableBytes { ptr in
            guard let context = CGContext(
                    data: ptr.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ),
            let image = context.makeImage() else {
                return
            }

            // Write to file
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                    data as CFMutableData,
                    "public.png" as CFString,
                    1,
                    nil
            ) else {
                return
            }

            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)

            try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        }
    }
}
