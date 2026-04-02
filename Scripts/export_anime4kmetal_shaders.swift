import Foundation

private struct ShaderSpec {
    let subdir: String
    let glslName: String
    let metalName: String
}

private let requiredShaders: [ShaderSpec] = [
    .init(subdir: "Restore", glslName: "Anime4K_Clamp_Highlights.glsl", metalName: "Anime4K_Clamp_Highlights.metal"),
    .init(subdir: "Restore", glslName: "Anime4K_Restore_CNN_S.glsl", metalName: "Anime4K_Restore_CNN_S.metal"),
    .init(subdir: "Restore", glslName: "Anime4K_Restore_CNN_M.glsl", metalName: "Anime4K_Restore_CNN_M.metal"),
    .init(subdir: "Restore", glslName: "Anime4K_Restore_CNN_VL.glsl", metalName: "Anime4K_Restore_CNN_VL.metal"),
    .init(subdir: "Restore", glslName: "Anime4K_Restore_CNN_Soft_S.glsl", metalName: "Anime4K_Restore_CNN_Soft_S.metal"),
    .init(subdir: "Restore", glslName: "Anime4K_Restore_CNN_Soft_M.glsl", metalName: "Anime4K_Restore_CNN_Soft_M.metal"),
    .init(subdir: "Restore", glslName: "Anime4K_Restore_CNN_Soft_VL.glsl", metalName: "Anime4K_Restore_CNN_Soft_VL.metal"),
    .init(subdir: "Upscale", glslName: "Anime4K_Upscale_CNN_x2_S.glsl", metalName: "Anime4K_Upscale_CNN_x2_S.metal"),
    .init(subdir: "Upscale", glslName: "Anime4K_Upscale_CNN_x2_M.glsl", metalName: "Anime4K_Upscale_CNN_x2_M.metal"),
    .init(subdir: "Upscale", glslName: "Anime4K_Upscale_CNN_x2_VL.glsl", metalName: "Anime4K_Upscale_CNN_x2_VL.metal"),
    .init(subdir: "Upscale+Denoise", glslName: "Anime4K_Upscale_Denoise_CNN_x2_M.glsl", metalName: "Anime4K_Upscale_Denoise_CNN_x2_M.metal"),
    .init(subdir: "Upscale+Denoise", glslName: "Anime4K_Upscale_Denoise_CNN_x2_VL.glsl", metalName: "Anime4K_Upscale_Denoise_CNN_x2_VL.metal"),
    .init(subdir: "Upscale", glslName: "Anime4K_AutoDownscalePre_x2.glsl", metalName: "Anime4K_AutoDownscalePre_x2.metal"),
    .init(subdir: "Upscale", glslName: "Anime4K_AutoDownscalePre_x4.glsl", metalName: "Anime4K_AutoDownscalePre_x4.metal")
]

private enum ExportError: Error, LocalizedError {
    case missingArguments
    case missingInputFile(String)

    var errorDescription: String? {
        switch self {
        case .missingArguments:
            return "Usage: export_anime4kmetal_shaders <glsl_root_dir> <output_dir>"
        case let .missingInputFile(path):
            return "Missing GLSL file: \(path)"
        }
    }
}

private func regexReplace(_ pattern: String,
                          in text: String,
                          with template: String,
                          options: NSRegularExpression.Options = []) -> String {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
        return text
    }
    let range = NSRange(location: 0, length: (text as NSString).length)
    return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
}

private func uniquifyKernelAndHookNames(metalCode: String,
                                        baseKernelName: String,
                                        passIndex: Int) -> String {
    let uniqueKernelName = passIndex == 0 ? baseKernelName : "\(baseKernelName)_pass\(passIndex)"
    let uniqueHookName = passIndex == 0 ? "hook" : "hook_pass\(passIndex)"

    var out = metalCode

    // Rename entry-point kernel function for static linking compatibility.
    let escapedBaseKernel = NSRegularExpression.escapedPattern(for: baseKernelName)
    out = regexReplace("kernel\\s+void\\s+\(escapedBaseKernel)\\s*\\(", in: out, with: "kernel void \(uniqueKernelName)(")

    // Rename helper hook function for static linking compatibility.
    if uniqueHookName != "hook" {
        out = regexReplace("\\bhook\\s*\\(", in: out, with: "\(uniqueHookName)(")
    }

    return out
}

private func makeHelpersStatic(_ metalCode: String) -> String {
    // In metallib linking, duplicate non-kernel global symbols collide.
    // Mark helper functions static to keep linkage internal per translation unit.
    var outLines: [String] = []

    let functionDefPattern = "^\\s*(?:float|vec[234]|ivec[234]|int|bool|half|half[234]|uint|uint[234]|void)\\s+[A-Za-z_][A-Za-z0-9_]*\\s*\\("
    let regex = try? NSRegularExpression(pattern: functionDefPattern)

    for line in metalCode.split(separator: "\n", omittingEmptySubsequences: false) {
        let lineStr = String(line)
        let trimmed = lineStr.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("kernel ") ||
            trimmed.hasPrefix("static ") ||
            trimmed.hasPrefix("#") ||
            trimmed.hasPrefix("using ") ||
            trimmed.hasPrefix("typedef ") ||
            trimmed.hasPrefix("struct ") ||
            trimmed.hasPrefix("enum ") ||
            trimmed.isEmpty {
            outLines.append(lineStr)
            continue
        }

        let range = NSRange(location: 0, length: (lineStr as NSString).length)
        if let regex, regex.firstMatch(in: lineStr, options: [], range: range) != nil {
            outLines.append("static " + lineStr)
        } else {
            outLines.append(lineStr)
        }
    }

    return outLines.joined(separator: "\n")
}

private func optimizeKernelEntryMath(_ metalCode: String) -> String {
    // Reuse reciprocal output scaling in kernel entry paths to avoid repeated per-component division.
    let pattern = #"(^[ \t]*)float2\s+mtlPos\s*=\s*float2\s*\(\s*gid\s*\)\s*/\s*\(\s*float2\s*\(\s*output\.get_width\(\)\s*,\s*output\.get_height\(\)\s*\)\s*-\s*float2\s*\(\s*1(?:\.0)?\s*,\s*1(?:\.0)?\s*\)\s*\)\s*;"#
    let template = """
$1float2 outSize = float2(output.get_width(), output.get_height());
$1float2 outScale = 1.0 / (outSize - float2(1.0, 1.0));
$1float2 mtlPos = float2(gid) * outScale;
"""
    return regexReplace(pattern, in: metalCode, with: template, options: [.anchorsMatchLines])
}

private func emitMetalFile(from shaders: [MPVShader], sourceName: String) -> String {
    var chunks: [String] = []

    chunks.append("// Auto-generated using Anime4KMetal Shared/MPVShader.swift")
    chunks.append("// Source: \(sourceName)")
    chunks.append("// Pass count: \(shaders.count)")
    chunks.append("")

    for (index, shader) in shaders.enumerated() {
        var passCode = shader.metalCode
        passCode = uniquifyKernelAndHookNames(metalCode: passCode,
                                              baseKernelName: shader.functionName,
                                              passIndex: index)
        passCode = makeHelpersStatic(passCode)
        passCode = optimizeKernelEntryMath(passCode)

        let fnName = index == 0 ? shader.functionName : "\(shader.functionName)_pass\(index)"
        let hookName = shader.hook ?? "nil"
        let saveName = shader.save ?? "nil"
        let widthBase = shader.width?.0 ?? "nil"
        let widthScale = shader.width?.1 ?? 1.0
        let heightBase = shader.height?.0 ?? "nil"
        let heightScale = shader.height?.1 ?? 1.0
        let whenExpr = shader.when ?? "nil"
        chunks.append("// Shader: \(shader.name)")
        chunks.append("// Function: \(fnName)")
        chunks.append("// BINDS: \(shader.binds)")
        chunks.append("// HOOK: \(hookName)")
        chunks.append("// SAVE: \(saveName)")
        chunks.append("// META_WIDTH_BASE: \(widthBase)")
        chunks.append("// META_WIDTH_SCALE: \(widthScale)")
        chunks.append("// META_HEIGHT_BASE: \(heightBase)")
        chunks.append("// META_HEIGHT_SCALE: \(heightScale)")
        chunks.append("// META_WHEN: \(whenExpr)")
        chunks.append(passCode)
        chunks.append("")
    }

    return chunks.joined(separator: "\n")
}

private func run() throws {
    guard CommandLine.arguments.count == 3 else {
        throw ExportError.missingArguments
    }

    let glslRoot = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let outputRoot = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)

    try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)

    var totalPasses = 0

    for spec in requiredShaders {
        let glslURL = glslRoot.appendingPathComponent(spec.subdir).appendingPathComponent(spec.glslName)
        let outURL = outputRoot.appendingPathComponent(spec.metalName)

        guard FileManager.default.fileExists(atPath: glslURL.path) else {
            throw ExportError.missingInputFile(glslURL.path)
        }

        let glsl = try String(contentsOf: glslURL, encoding: .utf8)
        let shaders = try MPVShader.parse(glsl)
        totalPasses += shaders.count

        let metal = emitMetalFile(from: shaders, sourceName: spec.glslName)
        try metal.write(to: outURL, atomically: true, encoding: .utf8)

        print("Translated \(shaders.count) passes: \(spec.metalName)")
    }

    print("Done. Generated \(requiredShaders.count) .metal files with \(totalPasses) passes total.")
    print("Output: \(outputRoot.path)")
}

@main
struct ExportMain {
    static func main() {
        do {
            try run()
        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
