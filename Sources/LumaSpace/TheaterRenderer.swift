import AppKit
import ImageIO
import LumaCore
import Metal
import simd

/// The theater's part of a cinema frame: its hall, seats and armrests, their textures, and the
/// seats' shadow map (drawn once: nothing in the hall moves).
@MainActor
final class TheaterScene {
    private struct Mesh {
        let buffer: MTLBuffer
        let count: Int
        let offsets: MTLBuffer
        let instances: Int
    }

    private let pipeline: MTLRenderPipelineState
    private let shadowPipeline: MTLRenderPipelineState
    private let shadowDepth: MTLDepthStencilState
    private let room, seats, arms: Mesh
    /// Albedo, normal and roughness texture arrays (leather, fabric, carpet); nil if the files are missing.
    private let maps: [MTLTexture]?
    private var mapsReady = false
    private let shadowMap: MTLTexture
    private var shadowDrawn = false
    /// Seen from behind the screen, looking at the seats.
    let shadowViewProj: simd_float4x4

    static let shadowSize = 2048
    static let materials = ["leather", "fabric", "carpet"]

    init?(device: MTLDevice, library: MTLLibrary) {
        do {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = library.makeFunction(name: "theaterVertex")
            d.fragmentFunction = library.makeFunction(name: "theaterFragment")
            d.colorAttachments[0].pixelFormat = CinemaRenderer.sceneFormat
            d.rasterSampleCount = CinemaRenderer.samples
            d.depthAttachmentPixelFormat = .depth32Float
            pipeline = try device.makeRenderPipelineState(descriptor: d)
            let s = MTLRenderPipelineDescriptor()
            s.vertexFunction = library.makeFunction(name: "theaterShadowVertex")
            s.depthAttachmentPixelFormat = .depth32Float
            shadowPipeline = try device.makeRenderPipelineState(descriptor: s)
        } catch {
            NSLog("LumaSpace: theater shader setup failed: \(error)")
            return nil
        }
        func mesh(_ v: [TheaterVertex], at positions: [Vec3]) -> Mesh? {
            let f: [Float] = v.flatMap { x in
                [x.position.x, x.position.y, x.position.z, x.normal.x, x.normal.y, x.normal.z, x.u, x.v,
                 Double(x.material.rawValue), x.ao].map { Float($0) }
            }
            let o: [SIMD4<Float>] = positions.map { SIMD4(Float($0.x), Float($0.y), Float($0.z), 0) }
            guard let b = device.makeBuffer(bytes: f, length: f.count * MemoryLayout<Float>.stride),
                  let ob = device.makeBuffer(bytes: o, length: o.count * MemoryLayout<SIMD4<Float>>.stride) else { return nil }
            return Mesh(buffer: b, count: v.count, offsets: ob, instances: positions.count)
        }
        let sd = MTLDepthStencilDescriptor()
        sd.depthCompareFunction = .less
        sd.isDepthWriteEnabled = true
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: Self.shadowSize,
                                                          height: Self.shadowSize, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]
        td.storageMode = .private
        guard let room = mesh(theaterRoomMesh(), at: [.zero]), let seats = mesh(theaterSeatMesh(), at: theaterSeatPositions()),
              let arms = mesh(theaterArmMesh(), at: theaterArmPositions()),
              let depth = device.makeDepthStencilState(descriptor: sd), let map = device.makeTexture(descriptor: td) else { return nil }
        self.room = room; self.seats = seats; self.arms = arms
        shadowDepth = depth
        shadowMap = map
        maps = Self.loadMaps(device: device)
        if maps == nil { NSLog("LumaSpace: theater textures not found; using plain colours") }
        let eye = SIMD3<Float>(0, 3.4, -14), target = SIMD3<Float>(0, 2.2, 4)
        shadowViewProj = perspective(fovY: 50 * .pi / 180, aspect: 1.3, near: 5, far: 40) * lookAt(eye: eye, target: target)
    }

    /// The first frame draws the shadow map and builds the texture mipmaps.
    func prepare(cmd: MTLCommandBuffer, uniforms: [Float]) {
        if !mapsReady, let maps, let blit = cmd.makeBlitCommandEncoder() {
            for t in maps { blit.generateMipmaps(for: t) }
            blit.endEncoding()
            mapsReady = true
        }
        guard !shadowDrawn else { return }
        let pass = MTLRenderPassDescriptor()
        pass.depthAttachment.texture = shadowMap
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1
        pass.depthAttachment.storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.setRenderPipelineState(shadowPipeline)
        enc.setDepthStencilState(shadowDepth)
        var u = uniforms
        enc.setVertexBytes(&u, length: u.count * MemoryLayout<Float>.stride, index: 1)
        for m in [seats, arms] {
            enc.setVertexBuffer(m.buffer, offset: 0, index: 0)
            enc.setVertexBuffer(m.offsets, offset: 0, index: 2)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: m.count, instanceCount: m.instances)
        }
        enc.endEncoding()
        shadowDrawn = true
    }

    func draw(_ enc: MTLRenderCommandEncoder, uniforms u: inout [Float], depth: MTLDepthStencilState, lights: MTLTexture) {
        enc.setRenderPipelineState(pipeline)
        enc.setDepthStencilState(depth)
        let length = u.count * MemoryLayout<Float>.stride
        enc.setVertexBytes(&u, length: length, index: 1)
        enc.setFragmentBytes(&u, length: length, index: 0)
        var textured: Float = maps != nil && mapsReady ? 1 : 0
        enc.setFragmentBytes(&textured, length: MemoryLayout<Float>.stride, index: 1)
        if let maps { for (i, t) in maps.enumerated() { enc.setFragmentTexture(t, index: i) } }
        enc.setFragmentTexture(shadowMap, index: 3)
        enc.setFragmentTexture(lights, index: 4)
        // Nearest things first, so the hall behind the seats is skipped by the depth test.
        for m in [seats, arms, room] {
            enc.setVertexBuffer(m.buffer, offset: 0, index: 0)
            enc.setVertexBuffer(m.offsets, offset: 0, index: 2)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: m.count, instanceCount: m.instances)
        }
    }

    /// The folder with the theater's textures: in the app bundle, or `Resources/Theater` when run
    /// from the source folder (`swift run`).
    static func resourceFolder() -> URL? {
        let candidates = [Bundle.main.resourceURL?.appendingPathComponent("Theater"),
                          URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/Theater")]
        return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("leather_color.jpg").path) }
    }

    /// One 1024² array per kind (albedo in sRGB), a layer per material, in `materials` order.
    private static func loadMaps(device: MTLDevice) -> [MTLTexture]? {
        guard let folder = resourceFolder() else { return nil }
        let size = 1024
        var out: [MTLTexture] = []
        for (kind, format) in [("color", MTLPixelFormat.rgba8Unorm_srgb), ("normal", .rgba8Unorm), ("roughness", .rgba8Unorm)] {
            let d = MTLTextureDescriptor()
            d.textureType = .type2DArray
            d.pixelFormat = format
            d.width = size; d.height = size
            d.arrayLength = materials.count
            d.mipmapLevelCount = Int(log2(Double(size))) + 1
            d.usage = .shaderRead
            guard let tex = device.makeTexture(descriptor: d) else { return nil }
            for (layer, name) in materials.enumerated() {
                let url = folder.appendingPathComponent("\(name)_\(kind).jpg")
                guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let img = CGImageSourceCreateImageAtIndex(src, 0, nil),
                      let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
                    NSLog("LumaSpace: couldn't read \(url.lastPathComponent)")
                    return nil
                }
                ctx.draw(img, in: CGRect(x: 0, y: 0, width: size, height: size))
                guard let data = ctx.data else { return nil }
                tex.replace(region: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0, slice: layer,
                            withBytes: data, bytesPerRow: size * 4, bytesPerImage: size * size * 4)
            }
            out.append(tex)
        }
        return out
    }
}

/// A view matrix looking from `eye` at `target`, y up (right-handed, looking down −z).
func lookAt(eye: SIMD3<Float>, target: SIMD3<Float>) -> simd_float4x4 {
    let f = simd_normalize(target - eye), r = simd_normalize(simd_cross(f, SIMD3(0, 1, 0))), u = simd_cross(r, f)
    return simd_float4x4(columns: (SIMD4(r.x, u.x, -f.x, 0), SIMD4(r.y, u.y, -f.y, 0), SIMD4(r.z, u.z, -f.z, 0),
                                   SIMD4(-simd_dot(r, eye), -simd_dot(u, eye), simd_dot(f, eye), 1)))
}
