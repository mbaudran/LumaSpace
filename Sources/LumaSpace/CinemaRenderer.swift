import AppKit
import LumaCore
import Metal
import simd

/// Draws the theater in side-by-side stereo: each eye into its half of the drawable.
@MainActor
final class CinemaRenderer {
    let device: MTLDevice
    var settings = CinemaSettings() { didSet { if settings != oldValue { layout = nil } } }
    var screenTexture: () -> MTLTexture? = { nil }
    /// Shown on the screen when the source is gone (the "Source unavailable" card).
    var fallbackTexture: () -> MTLTexture? = { nil }

    private let room: MTLRenderPipelineState
    private let screen: MTLRenderPipelineState
    private let downsample: MTLRenderPipelineState
    private let depth: MTLDepthStencilState
    private let lightTexture: MTLTexture
    private var layout: CinemaLayout?
    private var layoutAspect: Double?
    private var roomBuffer: MTLBuffer?
    private var roomVertexCount = 0
    private var screenBuffer: MTLBuffer?
    private var lights: [(pos: SIMD4<Float>, normal: SIMD4<Float>)] = []

    static let screenSegments = 64
    static let lightGain: Float = 14, lightFalloff: Float = 0.04
    static let seatColor = Vec3(x: 0.45, y: 0.06, z: 0.08)

    init?(device: MTLDevice, colorPixelFormat: MTLPixelFormat) {
        self.device = device
        do {
            let lib = try device.makeLibrary(source: cinemaShaderSource, options: nil)
            func pipeline(_ v: String, _ f: String, format: MTLPixelFormat, depth: Bool) throws -> MTLRenderPipelineState {
                let d = MTLRenderPipelineDescriptor()
                d.vertexFunction = lib.makeFunction(name: v)
                d.fragmentFunction = lib.makeFunction(name: f)
                d.colorAttachments[0].pixelFormat = format
                if depth { d.depthAttachmentPixelFormat = .depth32Float }
                return try device.makeRenderPipelineState(descriptor: d)
            }
            room = try pipeline("roomVertex", "roomFragment", format: colorPixelFormat, depth: true)
            screen = try pipeline("screenVertex", "screenFragment", format: colorPixelFormat, depth: true)
            downsample = try pipeline("fullscreenVertex", "downsampleFragment", format: .rgba8Unorm, depth: false)
        } catch {
            NSLog("LumaSpace: cinema shader setup failed: \(error)")
            return nil
        }
        let ds = MTLDepthStencilDescriptor()
        ds.depthCompareFunction = .less
        ds.isDepthWriteEnabled = true
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 64, height: 32, mipmapped: true)
        td.usage = [.renderTarget, .shaderRead]
        td.storageMode = .private
        guard let depth = device.makeDepthStencilState(descriptor: ds),
              let light = device.makeTexture(descriptor: td) else { return nil }
        self.depth = depth
        lightTexture = light
    }

    func encode(into pass: MTLRenderPassDescriptor, drawableSize: CGSize, head: Quat, commandBuffer cmd: MTLCommandBuffer) {
        let tex = screenTexture() ?? fallbackTexture()
        let aspect = tex.map { Double($0.width) / Double(max($0.height, 1)) }
        if layout == nil || layoutAspect != aspect { rebuild(aspect: aspect) }
        guard let layout, let roomBuffer, let screenBuffer else { return }
        if let tex { updateLight(from: tex, cmd: cmd) }

        guard let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.setDepthStencilState(depth)
        let w = Int(drawableSize.width), h = Int(drawableSize.height)
        let proj = perspective(fovY: Float(verticalFOV(aspect: eyeAspect(drawableWidth: w, drawableHeight: h))),
                               aspect: Float(eyeAspect(drawableWidth: w, drawableHeight: h)), near: 0.05, far: 50)
        for eye in Eye.allCases {
            let vp = eyeViewport(eye, drawableWidth: w, drawableHeight: h)
            guard vp.width > 0, vp.height > 0 else { continue }
            enc.setViewport(MTLViewport(originX: Double(vp.x), originY: 0, width: Double(vp.width), height: Double(vp.height),
                                        znear: 0, zfar: 1))
            enc.setScissorRect(MTLScissorRect(x: vp.x, y: 0, width: vp.width, height: vp.height))
            let eyePos = layout.viewer + eyeOffset(eye, head: head, ipd: settings.ipd)
            var u = uniforms(viewProj: proj * head.conjugate.matrix * translation(eyePos * -1))
            let length = u.count * MemoryLayout<Float>.stride

            enc.setRenderPipelineState(room)
            enc.setVertexBuffer(roomBuffer, offset: 0, index: 0)
            enc.setVertexBytes(&u, length: length, index: 1)
            enc.setFragmentBytes(&u, length: length, index: 0)
            enc.setFragmentTexture(lightTexture, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: roomVertexCount)

            if let tex {
                enc.setRenderPipelineState(screen)
                enc.setVertexBuffer(screenBuffer, offset: 0, index: 0)
                enc.setVertexBytes(&u, length: length, index: 1)
                enc.setFragmentTexture(tex, index: 0)
                enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: (Self.screenSegments + 1) * 2)
            }
        }
        enc.endEncoding()
    }

    private func uniforms(viewProj m: simd_float4x4) -> [Float] {
        var u: [Float] = []
        for c in [m.columns.0, m.columns.1, m.columns.2, m.columns.3] { u += [c.x, c.y, c.z, c.w] }
        for l in lights { u += [l.pos.x, l.pos.y, l.pos.z, l.pos.w] }
        for l in lights { u += [l.normal.x, l.normal.y, l.normal.z, l.normal.w] }
        return u + [Float(settings.lights.ambient), Self.lightGain, Self.lightFalloff, 0]
    }

    /// Box-filters the picture into the 64×32 light texture and builds its mipmaps.
    private func updateLight(from tex: MTLTexture, cmd: MTLCommandBuffer) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = lightTexture
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.setRenderPipelineState(downsample)
        enc.setFragmentTexture(tex, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        guard let blit = cmd.makeBlitCommandEncoder() else { return }
        blit.generateMipmaps(for: lightTexture)
        blit.endEncoding()
    }

    private func rebuild(aspect: Double?) {
        let l = cinemaLayout(settings, sourceAspect: aspect)
        layout = l
        layoutAspect = aspect

        var v: [Float] = []
        func tri(_ ps: [Vec3], _ n: Vec3, _ albedo: Vec3) {
            for p in ps { v += [p.x, p.y, p.z, n.x, n.y, n.z, albedo.x, albedo.y, albedo.z].map { Float($0) } }
        }
        func quad(_ c: Vec3, right: Vec3, up: Vec3, _ n: Vec3, _ albedo: Vec3) {
            let a = c - right - up, b = c + right - up, d = c + right + up, e = c - right + up
            tri([a, b, d, a, d, e], n, albedo)
        }
        func box(_ b: CinemaBox, _ albedo: Vec3) {
            let hx = Vec3(x: b.size.x / 2, y: 0, z: 0), hy = Vec3(x: 0, y: b.size.y / 2, z: 0)
            let hz = Vec3(x: 0, y: 0, z: b.size.z / 2)
            for s in [1.0, -1.0] {
                quad(b.center + hx * s, right: hz, up: hy, Vec3(x: s, y: 0, z: 0), albedo)
                quad(b.center + hy * s, right: hx, up: hz, Vec3(x: 0, y: s, z: 0), albedo)
                quad(b.center + hz * s, right: hx, up: hy, Vec3(x: 0, y: 0, z: s), albedo)
            }
        }
        for s in l.surfaces {
            quad(s.center, right: s.up.cross(s.normal) * (s.width / 2), up: s.up * (s.height / 2), s.normal, s.albedo)
        }
        for r in l.risers { box(r, l.surfaces[0].albedo) }
        // Each seat box becomes a cushion (lower half) and a thin backrest at its back.
        for seat in l.seats {
            let bottom = seat.center.y - seat.size.y / 2
            box(CinemaBox(center: Vec3(x: seat.center.x, y: bottom + seat.size.y / 4, z: seat.center.z),
                          size: Vec3(x: seat.size.x, y: seat.size.y / 2, z: seat.size.z)), Self.seatColor)
            box(CinemaBox(center: Vec3(x: seat.center.x, y: seat.center.y, z: seat.center.z + seat.size.z / 2 - 0.06),
                          size: Vec3(x: seat.size.x, y: seat.size.y, z: 0.12)), Self.seatColor)
        }
        roomVertexCount = v.count / 9
        roomBuffer = device.makeBuffer(bytes: v, length: v.count * MemoryLayout<Float>.stride)

        // The screen curves around a vertical axis through the default seat row.
        let axisZ = l.screenCenter.z + l.screenRadius, half = l.screenWidth / 2 / l.screenRadius
        let bottom = l.screenCenter.y - l.screenHeight / 2, top = l.screenCenter.y + l.screenHeight / 2
        var sv: [Float] = []
        for i in 0...Self.screenSegments {
            let t = Double(i) / Double(Self.screenSegments), a = -half + 2 * half * t
            let x = l.screenRadius * sin(a), z = axisZ - l.screenRadius * cos(a)
            sv += [x, bottom, z, t, 1, x, top, z, t, 0].map { Float($0) }
        }
        screenBuffer = device.makeBuffer(bytes: sv, length: sv.count * MemoryLayout<Float>.stride)
        lights = (0..<8).map { i in
            let a = -half + 2 * half * (Double(i) + 0.5) / 8
            return (SIMD4(Float(l.screenRadius * sin(a)), Float(l.screenCenter.y), Float(axisZ - l.screenRadius * cos(a)), 1),
                    SIMD4(Float(-sin(a)), 0, Float(cos(a)), 0))
        }
    }

    /// SMPTE-style colour bars, for checking the theater without a capture source (`LUMA_CINEMA=test`).
    static func testPattern(device: MTLDevice) -> MTLTexture? {
        let w = 1920, h = 1080
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        let bars: [(CGFloat, CGFloat, CGFloat)] = [(0.75, 0.75, 0.75), (0.75, 0.75, 0), (0, 0.75, 0.75), (0, 0.75, 0),
                                                   (0.75, 0, 0.75), (0.75, 0, 0), (0, 0, 0.75)]
        let bw = CGFloat(w) / CGFloat(bars.count)
        for (i, c) in bars.enumerated() {
            ctx.setFillColor(CGColor(red: c.0, green: c.1, blue: c.2, alpha: 1))
            ctx.fill(CGRect(x: CGFloat(i) * bw, y: CGFloat(h) * 0.25, width: bw + 1, height: CGFloat(h) * 0.75))
        }
        ctx.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h / 4))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: w / 2 - 200, y: h / 16, width: 400, height: h / 8))
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        guard let tex = device.makeTexture(descriptor: desc), let data = ctx.data else { return nil }
        tex.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: data, bytesPerRow: w * 4)
        return tex
    }
}
