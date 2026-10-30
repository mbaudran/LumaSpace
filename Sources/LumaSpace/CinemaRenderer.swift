import AppKit
import LumaCore
import Metal
import os
import QuartzCore
import simd

/// Draws the cinema in side-by-side stereo: the screen floating in the dark, its light spilling
/// into a halo, haze, dust and a glossy floor. Each frame: picture → glow texture, scene pass (4×
/// MSAA, both eyes), bloom, composite onto the drawable.
@MainActor
final class CinemaRenderer {
    let device: MTLDevice
    var settings = CinemaSettings() { didSet { if settings != oldValue { layout = nil } } }
    var screenTexture: () -> MTLTexture? = { nil }
    /// Shown on the screen when the source is gone (the "Source unavailable" card).
    var fallbackTexture: () -> MTLTexture? = { nil }
    /// `LUMA_CINEMA=clip`: an animated test picture instead of `screenTexture`.
    var testClip = false

    private enum Blend { case opaque, additive, alpha }

    private let floorPipeline, haloPipeline, screenPipeline, dustPipeline: MTLRenderPipelineState
    private let glowPipeline, lightsPipeline, hazePipeline, bloomExtract, blurPipeline: MTLRenderPipelineState
    private let compositePipeline, clipPipeline: MTLRenderPipelineState
    private let depthWrite, depthTest: MTLDepthStencilState
    /// Ping-pong pair: each frame blends the picture into the other one (the smoothing).
    private let glow: [MTLTexture]
    private var glowIndex = 0
    private var glowCleared = false
    /// The colours of the 16 screen lights, worked out once per frame from the glow.
    private let lightColors: MTLTexture
    private var clipTexture: MTLTexture?

    private var targetSize = (width: 0, height: 0)
    private var sceneMSAA, sceneDepth, sceneResolved, bloomA, bloomB, haze: MTLTexture?

    private var layout: CinemaLayout?
    private var layoutAspect: Double?
    private var lights: [CinemaLight] = []
    private var dust = CinemaBox(center: .zero, size: Vec3(x: 1, y: 1, z: 1))
    private var floorBuffer, haloBuffer, screenBuffer: MTLBuffer?

    /// The theater environment's hall and seats; nil if its shaders failed (the void still works).
    private let theater: TheaterScene?
    /// The theater's house lights, easing towards what the ambience asks for.
    private var house = 1.0

    private let start = CACurrentMediaTime()
    private var lastFrame: Double?
    private let stats = ProcessInfo.processInfo.environment["LUMA_CINEMA_STATS"] == "1" ? GPUStats() : nil

    static let screenSegments = 64
    static let haloMargin = 2.5, haloGap = 0.4
    static let glowWidth = 256, glowHeight = 144
    static let sceneFormat = MTLPixelFormat.rgba16Float, samples = 4

    init?(device: MTLDevice, colorPixelFormat: MTLPixelFormat) {
        self.device = device
        do {
            let lib = try device.makeLibrary(source: cinemaShaderSource + theaterShaderSource, options: nil)
            theater = TheaterScene(device: device, library: lib)
            func pipeline(_ v: String, _ f: String, format: MTLPixelFormat = Self.sceneFormat, scene: Bool = false,
                          blend: Blend = .opaque) throws -> MTLRenderPipelineState {
                let d = MTLRenderPipelineDescriptor()
                d.vertexFunction = lib.makeFunction(name: v)
                d.fragmentFunction = lib.makeFunction(name: f)
                let ca = d.colorAttachments[0]!
                ca.pixelFormat = format
                if scene {
                    d.rasterSampleCount = Self.samples
                    d.depthAttachmentPixelFormat = .depth32Float
                }
                switch blend {
                case .opaque: break
                case .additive:
                    ca.isBlendingEnabled = true
                    ca.sourceRGBBlendFactor = .one; ca.destinationRGBBlendFactor = .one
                    ca.sourceAlphaBlendFactor = .zero; ca.destinationAlphaBlendFactor = .one
                case .alpha:
                    ca.isBlendingEnabled = true
                    ca.sourceRGBBlendFactor = .sourceAlpha; ca.destinationRGBBlendFactor = .oneMinusSourceAlpha
                    ca.sourceAlphaBlendFactor = .one; ca.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                }
                return try device.makeRenderPipelineState(descriptor: d)
            }
            floorPipeline = try pipeline("sceneVertex", "floorFragment", scene: true)
            haloPipeline = try pipeline("sceneVertex", "haloFragment", scene: true, blend: .additive)
            screenPipeline = try pipeline("sceneVertex", "screenFragment", scene: true, blend: .alpha)
            dustPipeline = try pipeline("dustVertex", "dustFragment", scene: true, blend: .additive)
            glowPipeline = try pipeline("fullscreenVertex", "glowFragment")
            lightsPipeline = try pipeline("fullscreenVertex", "lightsFragment")
            hazePipeline = try pipeline("fullscreenVertex", "hazeFragment")
            bloomExtract = try pipeline("fullscreenVertex", "bloomExtractFragment")
            blurPipeline = try pipeline("fullscreenVertex", "blurFragment")
            compositePipeline = try pipeline("fullscreenVertex", "compositeFragment", format: colorPixelFormat)
            clipPipeline = try pipeline("fullscreenVertex", "clipFragment", format: .bgra8Unorm)
        } catch {
            NSLog("LumaSpace: cinema shader setup failed: \(error)")
            return nil
        }
        func depthState(_ compare: MTLCompareFunction, write: Bool) -> MTLDepthStencilState? {
            let d = MTLDepthStencilDescriptor()
            d.depthCompareFunction = compare
            d.isDepthWriteEnabled = write
            return device.makeDepthStencilState(descriptor: d)
        }
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Self.sceneFormat, width: Self.glowWidth,
                                                          height: Self.glowHeight, mipmapped: true)
        td.usage = [.renderTarget, .shaderRead]
        td.storageMode = .private
        // One texel per screen light, then the picture's average colour.
        let ld = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Self.sceneFormat, width: cinemaLightColumns * cinemaLightRows + 1,
                                                          height: 1, mipmapped: false)
        ld.usage = [.renderTarget, .shaderRead]
        ld.storageMode = .private
        guard let w = depthState(.less, write: true), let t = depthState(.less, write: false),
              let g0 = device.makeTexture(descriptor: td), let g1 = device.makeTexture(descriptor: td),
              let lc = device.makeTexture(descriptor: ld) else { return nil }
        depthWrite = w; depthTest = t
        glow = [g0, g1]
        lightColors = lc
    }

    func encode(into pass: MTLRenderPassDescriptor, drawableSize: CGSize, head: Quat, commandBuffer cmd: MTLCommandBuffer) {
        let now = CACurrentMediaTime(), elapsed = now - start
        let dt = lastFrame.map { now - $0 } ?? 0
        lastFrame = now
        if testClip { renderClip(time: elapsed, cmd: cmd) }
        let tex = testClip ? clipTexture : screenTexture() ?? fallbackTexture()
        let aspect = tex.map { Double($0.width) / Double(max($0.height, 1)) }
        if layout == nil || layoutAspect != aspect { rebuild(aspect: aspect) }
        let w = Int(drawableSize.width), h = Int(drawableSize.height)
        guard w > 1, h > 0, makeTargets(width: w, height: h), let layout, let floorBuffer, let haloBuffer, let screenBuffer,
              let sceneMSAA, let sceneDepth, let sceneResolved, let bloomA, let bloomB, let haze else { return }
        if !glowCleared { clearGlow(cmd: cmd) }
        if let tex { updateGlow(from: tex, blend: glowBlend(dt: dt), cmd: cmd) }
        let glowTex = glow[glowIndex]
        let inTheater = settings.environment == .theater && theater != nil
        let strength = settings.ambience.strength(in: inTheater ? .theater : .void)
        house += (houseLightTarget(strength.house, elapsed: elapsed) - house) * glowBlend(dt: dt, tau: 1.2)
        let fade = cinemaFade(elapsed: elapsed)
        let ea = eyeAspect(drawableWidth: w, drawableHeight: h)
        let proj = perspective(fovY: Float(verticalFOV(aspect: ea)), aspect: Float(ea), near: 0.05, far: 100)
        let eyes = Eye.allCases.map { eye in
            let vp = eyeViewport(eye, drawableWidth: w, drawableHeight: h)
            let pos = layout.viewer + eyeOffset(eye, head: head, ipd: settings.ipd)
            return (viewport: vp, uniforms: uniforms(viewProj: proj * head.conjugate.matrix * translation(pos * -1), eye: pos,
                                                     time: elapsed, fade: fade, dustPixels: Float(vp.height) / 2 * proj.columns.1.y))
        }
        var u = eyes[0].uniforms
        fullscreen(lightsPipeline, into: lightColors, textures: [glowTex], bytes: u, cmd: cmd)
        if inTheater { theater?.prepare(cmd: cmd, uniforms: u) }

        let sp = MTLRenderPassDescriptor()
        sp.colorAttachments[0].texture = sceneMSAA
        sp.colorAttachments[0].resolveTexture = sceneResolved
        sp.colorAttachments[0].loadAction = .clear
        sp.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        sp.colorAttachments[0].storeAction = .multisampleResolve
        sp.depthAttachment.texture = sceneDepth
        sp.depthAttachment.loadAction = .clear
        sp.depthAttachment.clearDepth = 1
        sp.depthAttachment.storeAction = .dontCare
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: sp) else { return }
        for (vp, eu) in eyes where vp.width > 0 && vp.height > 0 {
            u = eu
            enc.setViewport(MTLViewport(originX: Double(vp.x), originY: 0, width: Double(vp.width), height: Double(vp.height),
                                        znear: 0, zfar: 1))
            enc.setScissorRect(MTLScissorRect(x: vp.x, y: 0, width: vp.width, height: vp.height))
            let length = u.count * MemoryLayout<Float>.stride
            func draw(_ p: MTLRenderPipelineState, _ depth: MTLDepthStencilState, _ buffer: MTLBuffer?,
                      _ textures: [MTLTexture], _ type: MTLPrimitiveType, _ count: Int) {
                enc.setRenderPipelineState(p)
                enc.setDepthStencilState(depth)
                enc.setVertexBuffer(buffer, offset: 0, index: 0)
                enc.setVertexBytes(&u, length: length, index: buffer == nil ? 0 : 1)
                enc.setVertexTexture(textures[0], index: 0)
                enc.setFragmentBytes(&u, length: length, index: 0)
                for (i, t) in textures.enumerated() { enc.setFragmentTexture(t, index: i) }
                enc.drawPrimitives(type: type, vertexStart: 0, vertexCount: count)
            }
            let strip = (Self.screenSegments + 1) * 2
            if inTheater, let theater {
                theater.draw(enc, uniforms: &u, depth: depthWrite, lights: lightColors)
            } else {
                draw(floorPipeline, depthWrite, floorBuffer, [glowTex, lightColors], .triangle, 6)
                if strength.halo > 0 { draw(haloPipeline, depthTest, haloBuffer, [glowTex], .triangleStrip, strip) }
            }
            if let tex { draw(screenPipeline, depthWrite, screenBuffer, [tex], .triangleStrip, strip) }
            if strength.dust > 0 { draw(dustPipeline, depthTest, nil, [lightColors], .point, dustCount) }
        }
        enc.endEncoding()

        // The haze is smooth, so it's drawn at a quarter of the size and added when compositing.
        if strength.haze > 0 || strength.beam > 0 {
            let hp = MTLRenderPassDescriptor()
            hp.colorAttachments[0].texture = haze
            hp.colorAttachments[0].loadAction = .dontCare
            hp.colorAttachments[0].storeAction = .store
            guard let he = cmd.makeRenderCommandEncoder(descriptor: hp) else { return }
            he.setRenderPipelineState(hazePipeline)
            he.setFragmentTexture(lightColors, index: 0)
            he.setFragmentTexture(glowTex, index: 1)
            for (eye, (_, eu)) in zip(Eye.allCases, eyes) {
                let vp = eyeViewport(eye, drawableWidth: haze.width, drawableHeight: haze.height)
                he.setViewport(MTLViewport(originX: Double(vp.x), originY: 0, width: Double(vp.width), height: Double(vp.height),
                                           znear: 0, zfar: 1))
                var b = eu
                he.setFragmentBytes(&b, length: b.count * MemoryLayout<Float>.stride, index: 0)
                he.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            }
            he.endEncoding()
        }

        if strength.bloom > 0 {
            fullscreen(bloomExtract, into: bloomA, textures: [sceneResolved], cmd: cmd)
            for _ in 0..<2 {
                fullscreen(blurPipeline, into: bloomB, textures: [bloomA], bytes: [1, 0], cmd: cmd)
                fullscreen(blurPipeline, into: bloomA, textures: [bloomB], bytes: [0, 1], cmd: cmd)
            }
        }
        guard let out = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }
        out.setRenderPipelineState(compositePipeline)
        out.setFragmentTexture(sceneResolved, index: 0)
        // With bloom or haze off their textures aren't written this frame; the scene stands in, weighted by 0.
        out.setFragmentTexture(strength.bloom > 0 ? bloomA : sceneResolved, index: 1)
        out.setFragmentTexture(strength.haze > 0 || strength.beam > 0 ? haze : sceneResolved, index: 2)
        out.setFragmentBytes(&u, length: u.count * MemoryLayout<Float>.stride, index: 0)
        out.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        out.endEncoding()
        if let stats { cmd.addCompletedHandler { cb in stats.record(cb.gpuEndTime - cb.gpuStartTime) } }
    }

    private func uniforms(viewProj m: simd_float4x4, eye: Vec3, time: Double, fade: Double, dustPixels: Float) -> [Float] {
        guard let l = layout else { return [] }
        let inTheater = settings.environment == .theater && theater != nil
        let s = settings.ambience.strength(in: inTheater ? .theater : .void)
        var u: [Float] = []
        for c in [m, m.inverse] { for v in [c.columns.0, c.columns.1, c.columns.2, c.columns.3] { u += [v.x, v.y, v.z, v.w] } }
        let dustMin = dust.center - dust.size * 0.5
        u += [eye.x, eye.y, eye.z, time,
              l.screenAxisZ, l.screenRadius, l.screenHalfAngle, l.screenHeight * 0.035,
              l.screenTop, l.screenHeight, l.screenWidth, l.floorY,
              s.halo, s.haze, s.reflection, s.dust,
              s.bloom, fade, Double(dustPixels), 0,
              dustMin.x, dustMin.y, dustMin.z, 0,
              dust.size.x, dust.size.y, dust.size.z, 0].map { Float($0) }
        for li in lights { u += [li.position.x, li.position.y, li.position.z, li.u].map { Float($0) } }
        for li in lights { u += [li.normal.x, li.normal.y, li.normal.z, li.v].map { Float($0) } }
        let lo = l.room.center - l.room.size * 0.5, hi = l.room.center + l.room.size * 0.5
        let p = l.projector ?? .zero
        u += [lo.x, lo.y, lo.z, inTheater ? 1 : 0,
              hi.x, hi.y, hi.z, house,
              l.floorNormal.x, l.floorNormal.y, l.floorNormal.z, l.floorOffset,
              p.x, p.y, p.z, l.projector == nil ? 0 : s.beam].map { Float($0) }
        let sv = theater?.shadowViewProj ?? matrix_identity_float4x4
        for v in [sv.columns.0, sv.columns.1, sv.columns.2, sv.columns.3] { u += [v.x, v.y, v.z, v.w] }
        return u
    }

    /// (Re)creates the off-screen targets when the drawable changes size; false if Metal refused.
    private func makeTargets(width w: Int, height h: Int) -> Bool {
        if targetSize == (w, h), sceneMSAA != nil { return true }
        func texture(_ format: MTLPixelFormat, _ w: Int, _ h: Int, msaa: Bool) -> MTLTexture? {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: w, height: h, mipmapped: false)
            d.usage = msaa ? .renderTarget : [.renderTarget, .shaderRead]
            if msaa {
                d.textureType = .type2DMultisample
                d.sampleCount = Self.samples
                // Apple GPUs keep MSAA samples in tile memory; nothing goes to RAM but the resolve.
                d.storageMode = device.supportsFamily(.apple1) ? .memoryless : .private
            } else {
                d.storageMode = .private
            }
            return device.makeTexture(descriptor: d)
        }
        sceneMSAA = texture(Self.sceneFormat, w, h, msaa: true)
        sceneDepth = texture(.depth32Float, w, h, msaa: true)
        sceneResolved = texture(Self.sceneFormat, w, h, msaa: false)
        bloomA = texture(Self.sceneFormat, max(w / 4, 2), max(h / 4, 1), msaa: false)
        bloomB = texture(Self.sceneFormat, max(w / 4, 2), max(h / 4, 1), msaa: false)
        haze = texture(Self.sceneFormat, max(w / 4, 2), max(h / 4, 1), msaa: false)
        targetSize = (w, h)
        return sceneMSAA != nil && sceneDepth != nil && sceneResolved != nil && bloomA != nil && bloomB != nil && haze != nil
    }

    private func fullscreen(_ p: MTLRenderPipelineState, into target: MTLTexture, textures: [MTLTexture],
                            bytes: [Float] = [], cmd: MTLCommandBuffer) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.setRenderPipelineState(p)
        for (i, t) in textures.enumerated() { enc.setFragmentTexture(t, index: i) }
        if !bytes.isEmpty {
            var b = bytes
            enc.setFragmentBytes(&b, length: b.count * MemoryLayout<Float>.stride, index: 0)
        }
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    /// Blends the picture into the other glow texture and builds its mipmaps.
    private func updateGlow(from tex: MTLTexture, blend: Double, cmd: MTLCommandBuffer) {
        let prev = glow[glowIndex], next = glow[1 - glowIndex]
        fullscreen(glowPipeline, into: next, textures: [tex, prev], bytes: [Float(blend)], cmd: cmd)
        guard let blit = cmd.makeBlitCommandEncoder() else { return }
        blit.generateMipmaps(for: next)
        blit.endEncoding()
        glowIndex = 1 - glowIndex
    }

    /// The glow textures start black, so the first frames fade up from darkness instead of garbage.
    private func clearGlow(cmd: MTLCommandBuffer) {
        for t in glow {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = t
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            pass.colorAttachments[0].storeAction = .store
            cmd.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
        }
        glowCleared = true
    }

    private func renderClip(time: Double, cmd: MTLCommandBuffer) {
        if clipTexture == nil {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 1920, height: 1080, mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]
            d.storageMode = .private
            clipTexture = device.makeTexture(descriptor: d)
        }
        guard let clipTexture else { return }
        fullscreen(clipPipeline, into: clipTexture, textures: [], bytes: [Float(time)], cmd: cmd)
    }

    private func rebuild(aspect: Double?) {
        let l = cinemaLayout(settings, sourceAspect: aspect)
        layout = l
        layoutAspect = aspect
        lights = screenLights(l)
        dust = dustBox(l)

        // 6 floats per vertex: position, then two values the fragment shader reads as uv.
        func buffer(_ v: [Double]) -> MTLBuffer? {
            let f = v.map { Float($0) }
            return device.makeBuffer(bytes: f, length: f.count * MemoryLayout<Float>.stride)
        }
        let y = l.floorY
        let corners = [(-60.0, 20.0), (60, 20), (60, -80), (-60, 20), (60, -80), (-60, -80)]
        floorBuffer = buffer(corners.flatMap { [$0.0, y, $0.1, 0, 0, 0] })

        // The screen and the halo curve around the same axis; the halo sits a little behind.
        var screen: [Double] = [], halo: [Double] = []
        let n = Self.screenSegments, r = l.screenRadius, axis = l.screenAxisZ
        let haloR = r + Self.haloGap, haloHalf = l.screenWidth / 2 + Self.haloMargin
        let haloTop = l.screenTop + Self.haloMargin, haloBottom = max(l.floorY, l.screenBottom - Self.haloMargin)
        for i in 0...n {
            let t = Double(i) / Double(n)
            let a = (t * 2 - 1) * l.screenHalfAngle
            let x = r * sin(a), z = axis - r * cos(a)
            screen += [x, l.screenTop, z, t, 0, 0, x, l.screenBottom, z, t, 1, 0]
            let s = (t * 2 - 1) * haloHalf, ha = s / r  // arc metres measured on the screen
            let hx = haloR * sin(ha), hz = axis - haloR * cos(ha)
            halo += [hx, haloTop, hz, s, haloTop, 0, hx, haloBottom, hz, s, haloBottom, 0]
        }
        screenBuffer = buffer(screen)
        haloBuffer = buffer(halo)
    }

    /// SMPTE-style colour bars, for checking the cinema without a capture source (`LUMA_CINEMA=test`).
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

/// `LUMA_CINEMA_STATS=1`: logs the mean GPU time of the cinema's frames once a second.
final class GPUStats: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: (sum: 0.0, count: 0, since: CACurrentMediaTime()))

    func record(_ seconds: Double) {
        let now = CACurrentMediaTime()
        let report: (Double, Int)? = state.withLock { s in
            s.sum += seconds; s.count += 1
            guard now - s.since >= 1 else { return nil }
            defer { s = (0, 0, now) }
            return (s.sum / Double(s.count), s.count)
        }
        if let (mean, frames) = report {
            NSLog("LumaSpace: cinema GPU \(String(format: "%.2f", mean * 1000)) ms/frame over \(frames) frames")
        }
    }
}
