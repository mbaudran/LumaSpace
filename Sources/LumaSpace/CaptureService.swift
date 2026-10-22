import AppKit
import CoreVideo
import LumaCore
@preconcurrency import Metal
@preconcurrency import ScreenCaptureKit

/// One running SCStream; keeps the newest frame as a Metal texture.
private final class StreamBox: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let key: SourceKey
    private(set) var stream: SCStream!
    private let cache: CVMetalTextureCache
    private let lock = NSLock()
    private var latest: (CVMetalTexture, MTLTexture)?
    var onStop: (@Sendable (SourceKey) -> Void)?

    init(key: SourceKey, filter: SCContentFilter, config: SCStreamConfiguration, cache: CVMetalTextureCache) {
        self.key = key
        self.cache = cache
        super.init()
        // Delegate is needed so system-initiated stops (screen lock, "Stop sharing") reach didStopWithError.
        stream = SCStream(filter: filter, configuration: config, delegate: self)
    }

    var texture: MTLTexture? { lock.lock(); defer { lock.unlock() }; return latest?.1 }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sb.isValid,
              let info = (CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]])?.first,
              let raw = info[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,
              let pb = sb.imageBuffer else { return }
        var cvTex: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(nil, cache, pb, nil, .bgra8Unorm,
                                                  CVPixelBufferGetWidth(pb), CVPixelBufferGetHeight(pb), 0, &cvTex)
        guard let cvTex, let tex = CVMetalTextureGetTexture(cvTex) else { return }
        lock.lock(); latest = (cvTex, tex); lock.unlock()
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("LumaSpace: capture stopped for \(key): \(error.localizedDescription)")
        onStop?(key)
    }
}

/// Captures displays and windows for panels with ScreenCaptureKit.
@MainActor
final class CaptureService {
    private let device: MTLDevice
    private var cache: CVMetalTextureCache?
    private var streams: [SourceKey: StreamBox] = [:]
    private var content: SCShareableContent?
    /// Called on the main actor when a running stream dies (window closed, display unplugged).
    var onSourceLost: (SourceKey) -> Void = { _ in }
    var glassesDisplayID: UInt32?
    /// Live virtual screens (serial → display id). They show up as panels of their own, not as offered displays.
    var virtualDisplayIDs: [UInt32: CGDirectDisplayID] = [:]
    /// Sources whose stream failed to start are retried at most every 10 s.
    private let retry = RetryGate<SourceKey>(delay: 10)

    init(device: MTLDevice) {
        self.device = device
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
    }

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Refreshes shareable content. Returns what can be offered and every key that still exists.
    func refresh() async -> (offered: [PanelSource], existing: Set<SourceKey>) {
        guard let c = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) else {
            return ([], [])
        }
        content = c
        let virtual = Set(virtualDisplayIDs.values)
        let displays = c.displays.filter { !virtual.contains($0.displayID) }.map { d in
            DisplayInfo(id: d.displayID, name: Self.displayName(d.displayID))
        }
        let windows = c.windows.map { w in
            WindowInfo(id: w.windowID, app: w.owningApplication?.applicationName ?? "", title: w.title ?? "",
                       ownerPID: w.owningApplication?.processID ?? 0, layer: w.windowLayer, onScreen: w.isOnScreen)
        }
        let offered = offeredSources(displays: displays, windows: windows, glassesDisplayID: glassesDisplayID,
                                     ownPID: ProcessInfo.processInfo.processIdentifier)
        var existing = Set(c.displays.filter { $0.displayID != glassesDisplayID }.map { SourceKey.display($0.displayID) })
        existing.formUnion(c.windows.map { SourceKey.window($0.windowID) })
        let shared = Set(c.displays.map(\.displayID))
        existing.formUnion(virtualDisplayIDs.filter { shared.contains($0.value) }.keys.map { SourceKey.virtualScreen($0) })
        return (offered, existing)
    }

    static func displayName(_ id: CGDirectDisplayID) -> String {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }?.localizedName ?? "Display \(id)"
    }

    func texture(for key: SourceKey) -> MTLTexture? { streams[key]?.texture }

    /// Width / height of a source, from the last shareable-content refresh.
    func aspect(of key: SourceKey) -> Double? {
        let size: CGSize? = switch key {
        case .display, .virtualScreen:
            content?.displays.first { $0.displayID == displayID(for: key) }.map { CGSize(width: $0.width, height: $0.height) }
        case .window(let id): content?.windows.first { $0.windowID == id }?.frame.size
        }
        guard let size, size.height > 0 else { return nil }
        return Double(size.width / size.height)
    }

    private func displayID(for key: SourceKey) -> CGDirectDisplayID? {
        switch key {
        case .display(let id): id
        case .virtualScreen(let serial): virtualDisplayIDs[serial]
        case .window: nil
        }
    }

    /// Starts a stream for every available panel source and stops streams nothing uses.
    func sync(panels: [Panel]) {
        let wanted = Set(panels.filter(\.available).compactMap(\.source.key))
        for (key, box) in streams where !wanted.contains(key) {
            box.stream.stopCapture { _ in }
            streams[key] = nil
        }
        guard let content, let cache else { return }
        // Exclude the whole app, not a window list: windows created later (the glasses output,
        // palette, picker) must never appear inside a display capture.
        let me = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let now = CACurrentMediaTime()
        for key in wanted where streams[key] == nil && retry.allowed(key, now: now) {
            let filter: SCContentFilter
            let size: CGSize
            switch key {
            case .display, .virtualScreen:
                guard let d = content.displays.first(where: { $0.displayID == displayID(for: key) }) else { continue }
                filter = SCContentFilter(display: d, excludingApplications: me, exceptingWindows: [])
                size = CGSize(width: d.width, height: d.height)
            case .window(let id):
                guard let w = content.windows.first(where: { $0.windowID == id }) else { continue }
                filter = SCContentFilter(desktopIndependentWindow: w)
                size = w.frame.size
            }
            let config = SCStreamConfiguration()
            let scale = Double(filter.pointPixelScale)
            var px = CGSize(width: size.width * scale, height: size.height * scale)
            if px.width > 2560 { px = CGSize(width: 2560, height: px.height * 2560 / px.width) }
            config.width = max(2, Int(px.width))
            config.height = max(2, Int(px.height))
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
            config.showsCursor = true
            config.queueDepth = 4
            let box = StreamBox(key: key, filter: filter, config: config, cache: cache)
            box.onStop = { [weak self] k in
                Task { @MainActor in
                    self?.streams[k] = nil
                    self?.retry.failed(k, now: CACurrentMediaTime())
                    self?.onSourceLost(k)
                }
            }
            do {
                try box.stream.addStreamOutput(box, type: .screen, sampleHandlerQueue: DispatchQueue(label: "luma.capture"))
            } catch {
                NSLog("LumaSpace: cannot add stream output: \(error)")
                continue
            }
            streams[key] = box
            box.stream.startCapture { [weak self] err in
                Task { @MainActor in
                    guard let err else { self?.retry.succeeded(key); return }
                    NSLog("LumaSpace: capture failed for \(key): \(err.localizedDescription)")
                    self?.streams[key] = nil
                    self?.retry.failed(key, now: CACurrentMediaTime())
                    self?.onSourceLost(key)
                }
            }
        }
    }
}
