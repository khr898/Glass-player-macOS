import Foundation

/// Command-line tool for comparing image quality using SSIM and PSNR
///
/// Usage:
///   QualityCompare <source.png> <processed.png> [--reference <ref.png>] [--output <report.json>]
@main
struct QualityCompareTool {

    static func main() {
        let args = CommandLine.arguments

        if args.count < 3 {
            print("""
            QualityCompare - Compare image quality using SSIM and PSNR

            Usage:
              QualityCompare <source.png> <processed.png> [--reference <ref.png>] [--output <report.json>]

            Options:
              --reference    Optional GLSL reference image for three-way comparison
              --output       Output path for JSON report (default: stdout)
              --heatmap      Generate difference heatmap image
              --ssim         SSIM threshold for passing (default: 0.99)
              --psnr         PSNR threshold for passing in dB (default: 40)

            Examples:
              # Compare Metal output vs source
              QualityCompare frame_source.png frame_output.png

              # Compare Metal vs GLSL reference
              QualityCompare frame_source.png frame_metal.png --reference frame_glsl.png

              # Generate full report with heatmap
              QualityCompare source.png output.png --reference glsl.png --heatmap diff.png --output report.json

            Output:
              JSON report with SSIM, PSNR, MSE, and pass/fail status

            Target thresholds for Metal vs GLSL comparison:
              - SSIM > 0.99 (excellent match)
              - PSNR > 40dB (high quality)
            """)
            return
        }

        // Parse arguments
        var sourcePath: String?
        var processedPath: String?
        var referencePath: String?
        var outputPath: String?
        var heatmapPath: String?
        var ssimThreshold = 0.99
        var psnrThreshold = 40.0

        var i = 1
        while i < args.count {
            switch args[i] {
            case "--reference":
                if i + 1 < args.count {
                    referencePath = args[i + 1]
                    i += 2
                }
            case "--output":
                if i + 1 < args.count {
                    outputPath = args[i + 1]
                    i += 2
                }
            case "--heatmap":
                if i + 1 < args.count {
                    heatmapPath = args[i + 1]
                    i += 2
                }
            case "--ssim":
                if i + 1 < args.count {
                    ssimThreshold = Double(args[i + 1]) ?? 0.99
                    i += 2
                }
            case "--psnr":
                if i + 1 < args.count {
                    psnrThreshold = Double(args[i + 1]) ?? 40.0
                    i += 2
                }
            default:
                if sourcePath == nil {
                    sourcePath = args[i]
                } else if processedPath == nil {
                    processedPath = args[i]
                }
                i += 1
            }
        }

        guard let source = sourcePath, let processed = processedPath else {
            print("Error: Source and processed images are required")
            return
        }

        print("[QualityCompare] Source: \(source)")
        print("[QualityCompare] Processed: \(processed)")
        if let ref = referencePath {
            print("[QualityCompare] Reference: \(ref)")
        }

        do {
            let config = QualityCompare.Configuration(
                ssimThreshold: ssimThreshold,
                psnrThreshold: psnrThreshold,
                generateHeatmap: heatmapPath != nil,
                heatmapOutputPath: heatmapPath
            )

            let result = try QualityCompare.compare(
                source: source,
                processed: processed,
                reference: referencePath,
                configuration: config
            )

            // Output result
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(result)

            if let output = outputPath {
                try jsonData.write(to: URL(fileURLWithPath: output), options: .atomic)
                print("[QualityCompare] Report saved to: \(output)")
            } else {
                print(String(data: jsonData, encoding: .utf8) ?? "{}")
            }

            // Print summary
            print("\n\(result)")

        } catch {
            print("[QualityCompare] Error: \(error)")
        }
    }
}
