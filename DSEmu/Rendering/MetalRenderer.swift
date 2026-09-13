import Metal
import MetalKit
import QuartzCore

final class MetalRenderer {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let samplerState: MTLSamplerState
    private let texture: MTLTexture
    private let vertexBuffer: MTLBuffer

    private weak var metalLayer: CAMetalLayer?

    static let dsWidth = 256
    static let dsHeight = 192

    init?(metalLayer: CAMetalLayer) {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        self.device = device
        self.metalLayer = metalLayer

        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true

        guard let queue = device.makeCommandQueue() else { return nil }
        self.commandQueue = queue

        // Create texture for DS screen (256x192 BGRA)
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: Self.dsWidth,
            height: Self.dsHeight,
            mipmapped: false)
        texDesc.usage = .shaderRead
        guard let tex = device.makeTexture(descriptor: texDesc) else { return nil }
        self.texture = tex

        // Nearest-neighbor sampler for crisp pixel art
        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .nearest
        samplerDesc.magFilter = .nearest
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: samplerDesc) else { return nil }
        self.samplerState = sampler

        // Fullscreen quad vertices: (x, y, u, v)
        let vertices: [Float] = [
            -1,  1, 0, 0,  // top-left
            -1, -1, 0, 1,  // bottom-left
             1,  1, 1, 0,  // top-right
             1, -1, 1, 1,  // bottom-right
        ]
        guard let vbuf = device.makeBuffer(bytes: vertices,
                                           length: vertices.count * MemoryLayout<Float>.size,
                                           options: .storageModeShared) else { return nil }
        self.vertexBuffer = vbuf

        // Compile this tiny shader at runtime so the project does not depend on
        // Xcode's optional command-line Metal toolchain being installed.
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;
        struct VertexOut { float4 position [[position]]; float2 texCoord; };
        vertex VertexOut dsVertexShader(uint vertexID [[vertex_id]],
                                        constant float4* vertices [[buffer(0)]]) {
            VertexOut out;
            float4 v = vertices[vertexID];
            out.position = float4(v.xy, 0.0, 1.0);
            out.texCoord = v.zw;
            return out;
        }
        fragment half4 dsFragmentShader(VertexOut in [[stage_in]],
                                        texture2d<half> tex [[texture(0)]],
                                        sampler samp [[sampler(0)]]) {
            return tex.sample(samp, in.texCoord);
        }
        """
        guard let library = try? device.makeLibrary(source: shaderSource, options: nil) else { return nil }
        let pipelineDesc = MTLRenderPipelineDescriptor()
        pipelineDesc.vertexFunction = library.makeFunction(name: "dsVertexShader")
        pipelineDesc.fragmentFunction = library.makeFunction(name: "dsFragmentShader")
        pipelineDesc.colorAttachments[0].pixelFormat = metalLayer.pixelFormat

        guard let pipeline = try? device.makeRenderPipelineState(descriptor: pipelineDesc) else { return nil }
        self.pipelineState = pipeline
    }

    func updateTexture(with pixels: UnsafePointer<UInt32>) {
        let region = MTLRegionMake2D(0, 0, Self.dsWidth, Self.dsHeight)
        texture.replace(region: region,
                        mipmapLevel: 0,
                        withBytes: pixels,
                        bytesPerRow: Self.dsWidth * 4)
    }

    func draw() {
        guard let layer = metalLayer,
              let drawable = layer.nextDrawable(),
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let passDesc = MTLRenderPassDescriptor()
        passDesc.colorAttachments[0].texture = drawable.texture
        passDesc.colorAttachments[0].loadAction = .clear
        passDesc.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        passDesc.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDesc) else { return }

        // Calculate viewport for 4:3 aspect ratio with letterboxing
        let drawableW = Double(drawable.texture.width)
        let drawableH = Double(drawable.texture.height)
        let dsAspect = Double(Self.dsWidth) / Double(Self.dsHeight)
        let drawableAspect = drawableW / drawableH

        var vpX: Double = 0
        var vpY: Double = 0
        var vpW: Double = drawableW
        var vpH: Double = drawableH

        if drawableAspect > dsAspect {
            // Wider than 4:3 — pillarbox
            vpW = drawableH * dsAspect
            vpX = (drawableW - vpW) / 2
        } else {
            // Taller than 4:3 — letterbox
            vpH = drawableW / dsAspect
            vpY = (drawableH - vpH) / 2
        }

        encoder.setViewport(MTLViewport(originX: vpX, originY: vpY,
                                        width: vpW, height: vpH,
                                        znear: 0, zfar: 1))
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentSamplerState(samplerState, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
