import Foundation
import Metal

struct A4KShaderPass {
    var name: String
    var function: String?
    var hook: String?
    var binds: [String]
    var save: String?
    var components: Int?
    var width: (String, Float)?
    var height: (String, Float)?
    var when: String?
    var sigma: Double?
    var code: [String]

    var functionName: String {
        var fn = name
        fn.removeAll { ".-()".contains($0) }
        return fn
    }

    func entryFunctionName(passIndex: Int) -> String {
        if let function {
            return function
        }
        if passIndex == 0 {
            return functionName
        }
        return "\(functionName)_pass\(passIndex)"
    }

    var inputTextureNames: [String] {
        var names = binds
        if hook == "MAIN" && !binds.contains("MAIN") {
            names.append("MAIN")
        }
        return names
    }

    var outputTextureName: String {
        if let save, save != "MAIN" {
            return save
        }
        return "output"
    }

    init(_ name: String) {
        self.name = name
        self.function = nil
        self.hook = nil
        self.binds = []
        self.save = nil
        self.components = nil
        self.width = nil
        self.height = nil
        self.when = nil
        self.sigma = nil
        self.code = []
    }

    static func parse(_ metalSource: String) throws -> [A4KShaderPass] {
        var shaders: [A4KShaderPass] = []
        var current: A4KShaderPass? = nil

        let lines = metalSource.split(separator: "\n").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        for line in lines {
            guard line.starts(with: "//") else {
                continue
            }

            let payload = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
            if payload.isEmpty {
                continue
            }

            if payload.hasPrefix("Shader:") {
                if let current = current {
                    shaders.append(current)
                }
                let name = payload.replacingOccurrences(of: "Shader:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                current = A4KShaderPass(name)
                continue
            }

            guard current != nil else {
                continue
            }

            if payload.hasPrefix("Function:") {
                current?.function = payload.replacingOccurrences(of: "Function:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                continue
            }

            if payload.hasPrefix("BINDS:") {
                let bindsRaw = payload.replacingOccurrences(of: "BINDS:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                current?.binds = parseArrayLiteral(bindsRaw)
                continue
            }

            if payload.hasPrefix("HOOK:") {
                let value = payload.replacingOccurrences(of: "HOOK:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                current?.hook = (value == "nil") ? nil : value
                continue
            }

            if payload.hasPrefix("SAVE:") {
                let value = payload.replacingOccurrences(of: "SAVE:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                current?.save = (value == "nil") ? nil : value
                continue
            }

            if payload.hasPrefix("META_WIDTH_BASE:") {
                let value = payload.replacingOccurrences(of: "META_WIDTH_BASE:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if value == "nil" {
                    current?.width = nil
                } else {
                    let scale = current?.width?.1 ?? 1.0
                    current?.width = (value, scale)
                }
                continue
            }

            if payload.hasPrefix("META_WIDTH_SCALE:") {
                let value = payload.replacingOccurrences(of: "META_WIDTH_SCALE:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if let parsed = Float(value) {
                    let base = current?.width?.0 ?? "MAIN"
                    current?.width = (base, parsed)
                }
                continue
            }

            if payload.hasPrefix("META_HEIGHT_BASE:") {
                let value = payload.replacingOccurrences(of: "META_HEIGHT_BASE:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if value == "nil" {
                    current?.height = nil
                } else {
                    let scale = current?.height?.1 ?? 1.0
                    current?.height = (value, scale)
                }
                continue
            }

            if payload.hasPrefix("META_HEIGHT_SCALE:") {
                let value = payload.replacingOccurrences(of: "META_HEIGHT_SCALE:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if let parsed = Float(value) {
                    let base = current?.height?.0 ?? "MAIN"
                    current?.height = (base, parsed)
                }
                continue
            }

            if payload.hasPrefix("META_WHEN:") {
                let value = payload.replacingOccurrences(of: "META_WHEN:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                current?.when = (value == "nil") ? nil : value
                continue
            }
        }

        if let current = current {
            shaders.append(current)
        }

        return shaders
    }

    private static func parseArrayLiteral(_ value: String) -> [String] {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else {
            return []
        }
        let body = String(trimmed.dropFirst().dropLast())
        if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return []
        }

        return body
            .split(separator: ",")
            .map { token in
                token
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\"", with: "")
            }
            .filter { !$0.isEmpty }
    }
}

final class A4KFilePipeline {
    private static let bufferCount = 2

    private let shaderFileName: String
    private let device: MTLDevice
    private let library: MTLLibrary
    private let shaders: [A4KShaderPass]
    private let targetOutputScale: Float

    // Stable per-frame context used by WHEN expressions.
    private var nativeWidth: Int = 0
    private var nativeHeight: Int = 0
    private var targetOutputWidth: Int = 0
    private var targetOutputHeight: Int = 0

    private var enabledShaders: [A4KShaderPass] = []
    private var enabledShaderIndices: [Int] = []
    private var pipelineStates: [MTLComputePipelineState] = []
    private var textureMap: [[String: MTLTexture]] = []

    private var nearestSamplerStates: [MTLSamplerState] = []
    private var linearSamplerStates: [MTLSamplerState] = []

    private var sizeMap: [String: (Float, Float)] = [:]
    private var outputW: Float = 0
    private var outputH: Float = 0
    private var textureInW: Float = 0
    private var textureInH: Float = 0
    private var bufferIndex = -1

    private var compiledInputWidth: Int = 0
    private var compiledInputHeight: Int = 0
    private var compiledNativeWidth: Int = 0
    private var compiledNativeHeight: Int = 0
    private var compiledTargetOutputWidth: Int = 0
    private var compiledTargetOutputHeight: Int = 0
    private var compiledAsNoOp: Bool = false

    init?(shaderFileName: String,
                    metalSource: String,
                    targetOutputScale: Float,
          device: MTLDevice,
          library: MTLLibrary) {
        self.shaderFileName = shaderFileName
        self.device = device
        self.library = library
                self.targetOutputScale = max(1.0, targetOutputScale)

        do {
                        self.shaders = try A4KShaderPass.parse(metalSource)
        } catch {
            NSLog("[Anime4KRuntime] Failed to parse GLSL %@: %@", shaderFileName, String(describing: error))
            return nil
        }

        if self.shaders.isEmpty {
            NSLog("[Anime4KRuntime] No shader passes parsed for %@", shaderFileName)
            return nil
        }
    }

    func recompileIfNeeded(inputWidth: Int, inputHeight: Int) -> Bool {
        if inputWidth == compiledInputWidth,
           inputHeight == compiledInputHeight,
           nativeWidth == compiledNativeWidth,
           nativeHeight == compiledNativeHeight,
           targetOutputWidth == compiledTargetOutputWidth,
           targetOutputHeight == compiledTargetOutputHeight,
           (compiledAsNoOp || (!enabledShaders.isEmpty && !pipelineStates.isEmpty)) {
            return true
        }
        return compile(inputWidth: inputWidth, inputHeight: inputHeight)
    }

    func updateFrameContext(nativeWidth: Int,
                            nativeHeight: Int,
                            targetOutputWidth: Int,
                            targetOutputHeight: Int) {
        self.nativeWidth = max(1, nativeWidth)
        self.nativeHeight = max(1, nativeHeight)
        self.targetOutputWidth = max(1, targetOutputWidth)
        self.targetOutputHeight = max(1, targetOutputHeight)
    }

    func encode(commandBuffer: MTLCommandBuffer, input: MTLTexture) -> MTLTexture? {
        guard !enabledShaders.isEmpty else {
            return input
        }

        bufferIndex = (bufferIndex + 1) % Self.bufferCount
        ensureSamplers(for: bufferIndex)

        if textureMap.count <= bufferIndex {
            textureMap.append([:])
        }

        var map = textureMap[bufferIndex]
        map["MAIN"] = input
        map["NATIVE"] = input

        guard ensureTexture(named: "output", width: Int(outputW), height: Int(outputH), in: &map) != nil else {
            NSLog("[Anime4KRuntime] Failed to create output texture for %@", shaderFileName)
            return nil
        }

        for idx in 0..<enabledShaders.count {
            let shader = enabledShaders[idx]
            let pipeline = pipelineStates[idx]

            var passOutputW = textureInW
            var passOutputH = textureInH
            if let hook = shader.hook {
                sizeMap["HOOKED"] = sizeMap[hook]
            }
            if let widthMultiplier = shader.width,
               let base = sizeMap[widthMultiplier.0] {
                passOutputW = base.0 * widthMultiplier.1
            }
            if let heightMultiplier = shader.height,
               let base = sizeMap[heightMultiplier.0] {
                passOutputH = base.1 * heightMultiplier.1
            }

            guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
                NSLog("[Anime4KRuntime] Failed to create encoder for %@", shaderFileName)
                return nil
            }

            encoder.setComputePipelineState(pipeline)
            if passOutputW >= textureInW {
                encoder.setSamplerState(nearestSamplerStates[bufferIndex], index: 0)
            } else {
                encoder.setSamplerState(linearSamplerStates[bufferIndex], index: 0)
            }

            var boundInputTextureIDs = Set<ObjectIdentifier>()

            for j in 0..<shader.inputTextureNames.count {
                var textureName = shader.inputTextureNames[j]
                if textureName == "HOOKED", let hook = shader.hook {
                    textureName = hook
                }

                if map[textureName] == nil {
                    if textureName == shader.save {
                        _ = ensureTexture(named: textureName,
                                          width: Int(passOutputW),
                                          height: Int(passOutputH),
                                          in: &map)
                    } else {
                        NSLog("[Anime4KRuntime] Missing texture %@ for %@", textureName, shaderFileName)
                        encoder.endEncoding()
                        return nil
                    }
                }

                guard let inputTexture = map[textureName] else {
                    encoder.endEncoding()
                    NSLog("[Anime4KRuntime] Failed to resolve input texture %@ for %@", textureName, shaderFileName)
                    return nil
                }

                encoder.setTexture(inputTexture, index: j)
                boundInputTextureIDs.insert(ObjectIdentifier(inputTexture))
            }

            let outputName = shader.outputTextureName
            guard let outputTexture = resolveOutputTexture(outputName: outputName,
                                                           shader: shader,
                                                           map: &map,
                                                           boundInputTextureIDs: boundInputTextureIDs,
                                                           width: Int(passOutputW),
                                                           height: Int(passOutputH)) else {
                encoder.endEncoding()
                NSLog("[Anime4KRuntime] Failed output texture %@ for %@", outputName, shaderFileName)
                return nil
            }

            encoder.setTexture(outputTexture, index: shader.inputTextureNames.count)

            let threadsPerThreadgroup = recommendedThreadgroupSize(for: pipeline)
            let threadsPerGrid = MTLSize(width: outputTexture.width,
                                         height: outputTexture.height,
                                         depth: 1)

            // Many translated Anime4K kernels do not guard gid against bounds,
            // so exact-grid dispatch is required to avoid out-of-range accesses.
            encoder.dispatchThreads(threadsPerGrid,
                                    threadsPerThreadgroup: threadsPerThreadgroup)
            encoder.endEncoding()
        }

        textureMap[bufferIndex] = map
        return map["output"]
    }

    private func compile(inputWidth: Int, inputHeight: Int) -> Bool {
        enabledShaders.removeAll()
        enabledShaderIndices.removeAll()
        pipelineStates.removeAll()
        sizeMap.removeAll()
        compiledAsNoOp = false

        textureInW = Float(inputWidth)
        textureInH = Float(inputHeight)
        outputW = textureInW
        outputH = textureInH

        let resolvedNativeW = nativeWidth > 0 ? nativeWidth : inputWidth
        let resolvedNativeH = nativeHeight > 0 ? nativeHeight : inputHeight
        let resolvedOutputW = targetOutputWidth > 0 ? targetOutputWidth : Int(round(Float(inputWidth) * targetOutputScale))
        let resolvedOutputH = targetOutputHeight > 0 ? targetOutputHeight : Int(round(Float(inputHeight) * targetOutputScale))

        sizeMap["MAIN"] = (textureInW, textureInH)
        sizeMap["NATIVE"] = (Float(resolvedNativeW), Float(resolvedNativeH))
        sizeMap["OUTPUT"] = (Float(max(1, resolvedOutputW)), Float(max(1, resolvedOutputH)))

        for (idx, shader) in shaders.enumerated() {
            if let when = shader.when,
               !evaluateWhenCondition(when, sizeMap: sizeMap) {
                continue
            }

            enabledShaders.append(shader)
            enabledShaderIndices.append(idx)

            outputW = textureInW
            outputH = textureInH

            if let hook = shader.hook {
                sizeMap["HOOKED"] = sizeMap[hook]
            }
            if let widthMultiplier = shader.width,
               let base = sizeMap[widthMultiplier.0] {
                outputW = base.0 * widthMultiplier.1
            }
            if let heightMultiplier = shader.height,
               let base = sizeMap[heightMultiplier.0] {
                outputH = base.1 * heightMultiplier.1
            }
            if let save = shader.save, save != "MAIN" {
                sizeMap[save] = (outputW, outputH)
            }

            let functionName = shader.entryFunctionName(passIndex: idx)
            guard let function = library.makeFunction(name: functionName) else {
                NSLog("[Anime4KRuntime] Missing function %@ in Anime4K.metallib", functionName)
                return false
            }

            do {
                let pipelineState = try device.makeComputePipelineState(function: function)
                pipelineStates.append(pipelineState)
            } catch {
                NSLog("[Anime4KRuntime] Failed pipeline %@: %@", functionName, String(describing: error))
                return false
            }
        }

        compiledInputWidth = inputWidth
        compiledInputHeight = inputHeight
        compiledNativeWidth = resolvedNativeW
        compiledNativeHeight = resolvedNativeH
        compiledTargetOutputWidth = max(1, resolvedOutputW)
        compiledTargetOutputHeight = max(1, resolvedOutputH)

        if enabledShaders.isEmpty {
            // Conditional pre/post stages (e.g. AutoDownscale) may be skipped
            // for a given output ratio. This is a valid no-op, not an error.
            compiledAsNoOp = true
            NSLog("[Anime4KRuntime] No enabled passes for %@ (skipping stage)", shaderFileName)
            return true
        }

        return true
    }

    private func ensureTexture(named name: String,
                               width: Int,
                               height: Int,
                               in map: inout [String: MTLTexture],
                               forceReplace: Bool = false) -> MTLTexture? {
        if !forceReplace,
           let existing = map[name],
           existing.width == width,
           existing.height == height,
           existing.pixelFormat == .rgba16Float {
            return existing
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: max(1, width),
            height: max(1, height),
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private

        let texture = device.makeTexture(descriptor: descriptor)
        texture?.label = "A4K_\(shaderFileName)_\(name)_\(width)x\(height)"
        map[name] = texture
        return texture
    }

    private func resolveOutputTexture(outputName: String,
                                      shader: A4KShaderPass,
                                      map: inout [String: MTLTexture],
                                      boundInputTextureIDs: Set<ObjectIdentifier>,
                                      width: Int,
                                      height: Int) -> MTLTexture? {
        let needsAliasSafeOutput = shader.binds.contains(outputName) ||
            shader.inputTextureNames.contains(outputName)

        if !needsAliasSafeOutput {
            if !isReusableTexture(map[outputName], width: width, height: height) {
                _ = ensureTexture(named: outputName,
                                  width: width,
                                  height: height,
                                  in: &map,
                                  forceReplace: true)
            }
            return map[outputName]
        }

        let primaryKey = outputName
        let alternateKey = "\(outputName)__alt"
        let previousPrimary = map[primaryKey]

        if isReusableTexture(previousPrimary, width: width, height: height),
           !isTextureBound(previousPrimary, boundInputTextureIDs: boundInputTextureIDs) {
            return previousPrimary
        }

        if let alternate = map[alternateKey],
           isReusableTexture(alternate, width: width, height: height),
           !isTextureBound(alternate, boundInputTextureIDs: boundInputTextureIDs) {
            map[primaryKey] = alternate
            if let previousPrimary,
               ObjectIdentifier(previousPrimary) != ObjectIdentifier(alternate),
               isReusableTexture(previousPrimary, width: width, height: height) {
                map[alternateKey] = previousPrimary
            }
            return alternate
        }

        _ = ensureTexture(named: alternateKey,
                          width: width,
                          height: height,
                          in: &map,
                          forceReplace: true)

        guard let created = map[alternateKey] else {
            return nil
        }

        map[primaryKey] = created
        if let previousPrimary,
           ObjectIdentifier(previousPrimary) != ObjectIdentifier(created),
           isReusableTexture(previousPrimary, width: width, height: height) {
            map[alternateKey] = previousPrimary
        }

        return created
    }

    private func isReusableTexture(_ texture: MTLTexture?, width: Int, height: Int) -> Bool {
        guard let texture else { return false }
        return texture.width == max(1, width) &&
            texture.height == max(1, height) &&
            texture.pixelFormat == .rgba16Float
    }

    private func isTextureBound(_ texture: MTLTexture?,
                                boundInputTextureIDs: Set<ObjectIdentifier>) -> Bool {
        guard let texture else { return false }
        return boundInputTextureIDs.contains(ObjectIdentifier(texture))
    }

    private func ensureSamplers(for index: Int) {
        if nearestSamplerStates.count > index,
           linearSamplerStates.count > index {
            return
        }

        let nearestDesc = MTLSamplerDescriptor()
        nearestDesc.minFilter = .nearest
        nearestDesc.magFilter = .nearest
        nearestDesc.sAddressMode = .clampToEdge
        nearestDesc.tAddressMode = .clampToEdge

        let linearDesc = MTLSamplerDescriptor()
        linearDesc.minFilter = .linear
        linearDesc.magFilter = .linear
        linearDesc.sAddressMode = .clampToEdge
        linearDesc.tAddressMode = .clampToEdge

        nearestSamplerStates.append(device.makeSamplerState(descriptor: nearestDesc)!)
        linearSamplerStates.append(device.makeSamplerState(descriptor: linearDesc)!)
    }

    private func recommendedThreadgroupSize(for pipeline: MTLComputePipelineState) -> MTLSize {
        let width = max(1, pipeline.threadExecutionWidth)
        let maxHeight = max(1, pipeline.maxTotalThreadsPerThreadgroup / width)

        // Cap workgroups near 256 threads to reduce register pressure and
        // sustained thermal load on heavy CNN passes while preserving throughput.
        let targetThreads = 256
        let preferredHeight = max(1, targetThreads / width)
        let height = min(maxHeight, preferredHeight)

        return MTLSize(width: width, height: height, depth: 1)
    }

    private func evaluateWhenCondition(_ when: String,
                                       sizeMap: [String: (Float, Float)]) -> Bool {
        let tokens = when.split(separator: " ").compactMap { token -> Substring? in
            if token == "WHEN" || token.isEmpty {
                return nil
            }
            return token
        }

        var stack: [Float] = []

        for token in tokens {
            let parts = token.split(separator: ".")
            if parts.count == 2 {
                let key = String(parts[0])
                if parts[1] == "w", let value = sizeMap[key]?.0 {
                    stack.append(value)
                    continue
                }
                if parts[1] == "h", let value = sizeMap[key]?.1 {
                    stack.append(value)
                    continue
                }
            }

            if ["+", "-", "*", "/", "<", ">"].contains(token) {
                guard stack.count >= 2 else { return false }
                let rhs = stack.removeLast()
                let lhs = stack.removeLast()
                switch token {
                case "+": stack.append(lhs + rhs)
                case "-": stack.append(lhs - rhs)
                case "*": stack.append(lhs * rhs)
                case "/": stack.append(lhs / max(rhs, 0.000001))
                case "<": stack.append(lhs < rhs ? 1 : 0)
                case ">": stack.append(lhs > rhs ? 1 : 0)
                default: break
                }
                continue
            }

            guard let value = Float(token) else {
                return false
            }
            stack.append(value)
        }

        guard stack.count == 1 else {
            return false
        }

        return stack[0] != 0
    }
}
