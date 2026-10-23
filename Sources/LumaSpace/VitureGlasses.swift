import Foundation
import QuartzCore
import IOKit
import IOKit.usb
import LumaCore
import os

// Bridge to the VITURE Glasses SDK (libglasses.dylib), loaded at runtime so the app
// builds and runs without it. Only the Gen1 (Luma) path is used: IMU pose callbacks.

private typealias Handle = UnsafeMutableRawPointer
private typealias PoseCallback = @convention(c) (UnsafeMutablePointer<Float>?, UInt64) -> Void
private typealias StateCallback = @convention(c) (Int32, Int32) -> Void

private let viturePoseMode: UInt8 = 1                    // VITURE_IMU_MODE_POSE
private let vitureFrequencies: [(UInt8, Int)] = [(4, 500), (3, 240), (2, 120)]  // VITURE_IMU_FREQUENCY_*
private let vitureSuccess: Int32 = 0

/// Resolved SDK entry points.
final class VitureLibrary: @unchecked Sendable {
    fileprivate let create: @convention(c) (Int32) -> Handle?
    fileprivate let initialize: @convention(c) (Handle, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Int32
    fileprivate let start: @convention(c) (Handle) -> Int32
    fileprivate let stop: @convention(c) (Handle) -> Int32
    fileprivate let shutdown: @convention(c) (Handle) -> Int32
    fileprivate let destroy: @convention(c) (Handle) -> Void
    fileprivate let registerState: @convention(c) (Handle, StateCallback?) -> Int32
    fileprivate let registerPose: @convention(c) (Handle, PoseCallback?) -> Int32
    fileprivate let openIMU: @convention(c) (Handle, UInt8, UInt8) -> Int32
    fileprivate let closeIMU: @convention(c) (Handle, UInt8) -> Int32
    fileprivate let isValid: @convention(c) (Int32) -> Int32
    fileprivate let supportsFrequency: @convention(c) (Int32, Int32, Int32) -> Int32
    fileprivate let marketName: @convention(c) (Int32, UnsafeMutablePointer<CChar>?, UnsafeMutablePointer<Int32>?) -> Int32
    fileprivate let getBrightness: @convention(c) (Handle) -> Int32
    fileprivate let setBrightness: @convention(c) (Handle, Int32) -> Int32
    fileprivate let getVolume: @convention(c) (Handle) -> Int32
    fileprivate let setVolume: @convention(c) (Handle, Int32) -> Int32
    fileprivate let valueMax: @convention(c) (Handle, Int32, UnsafeMutablePointer<Int32>?) -> Int32
    fileprivate let setDisplayMode: @convention(c) (Handle, Int32) -> Int32
    fileprivate let setLogLevel: @convention(c) (Int32) -> Void

    /// Where "Set Up VITURE SDK…" installs the libraries.
    static let installDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("LumaSpace/viture-sdk", isDirectory: true)

    /// Lookup order: $LUMA_SDK_PATH (file or folder), the app bundle's Frameworks, the installed SDK,
    /// ./vendor/viture-sdk/aarch64.
    static func load() -> VitureLibrary? {
        var candidates: [String] = []
        if let env = ProcessInfo.processInfo.environment["LUMA_SDK_PATH"] {
            candidates.append(env.hasSuffix(".dylib") ? env : (env as NSString).appendingPathComponent("libglasses.dylib"))
        }
        if let fw = Bundle.main.privateFrameworksPath {
            candidates.append((fw as NSString).appendingPathComponent("libglasses.dylib"))
        }
        candidates.append(installDir.appendingPathComponent("libglasses.dylib").path)
        candidates.append(FileManager.default.currentDirectoryPath + "/vendor/viture-sdk/aarch64/libglasses.dylib")
        loadReport = []
        for path in candidates {
            guard FileManager.default.fileExists(atPath: path) else {
                loadReport.append("\(path): not found")
                continue
            }
            // macOS kills the process when it loads a quarantined (browser-downloaded) dylib; skip it instead.
            if getxattr(path, "com.apple.quarantine", nil, 0, 0, 0) >= 0 {
                NSLog("LumaSpace: \(path) is quarantined; skipping (run scripts/bundle.sh, which bundles a cleared copy)")
                loadReport.append("\(path): quarantined, skipped")
                continue
            }
            guard let h = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
                let err = String(cString: dlerror())
                NSLog("LumaSpace: dlopen \(path) failed: \(err)")
                loadReport.append("\(path): dlopen failed: \(err)")
                continue
            }
            if let lib = VitureLibrary(h) {
                loadReport.append("\(path): loaded")
                return lib
            }
            loadReport.append("\(path): missing SDK symbols")
        }
        return nil
    }

    /// What `load()` found at each candidate path, for `--diagnose`.
    nonisolated(unsafe) static var loadReport: [String] = []

    private init?(_ h: UnsafeMutableRawPointer) {
        func sym<T>(_ name: String, _: T.Type = T.self) -> T? {
            guard let p = dlsym(h, name) else {
                NSLog("LumaSpace: VITURE SDK is missing symbol \(name)")
                return nil
            }
            return unsafeBitCast(p, to: T.self)
        }
        guard let create: @convention(c) (Int32) -> Handle? = sym("xr_device_provider_create"),
              let initialize: @convention(c) (Handle, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Int32 = sym("xr_device_provider_initialize"),
              let start: @convention(c) (Handle) -> Int32 = sym("xr_device_provider_start"),
              let stop: @convention(c) (Handle) -> Int32 = sym("xr_device_provider_stop"),
              let shutdown: @convention(c) (Handle) -> Int32 = sym("xr_device_provider_shutdown"),
              let destroy: @convention(c) (Handle) -> Void = sym("xr_device_provider_destroy"),
              let registerState: @convention(c) (Handle, StateCallback?) -> Int32 = sym("xr_device_provider_register_state_callback"),
              let registerPose: @convention(c) (Handle, PoseCallback?) -> Int32 = sym("xr_device_provider_register_imu_pose_callback"),
              let openIMU: @convention(c) (Handle, UInt8, UInt8) -> Int32 = sym("xr_device_provider_open_imu"),
              let closeIMU: @convention(c) (Handle, UInt8) -> Int32 = sym("xr_device_provider_close_imu"),
              let isValid: @convention(c) (Int32) -> Int32 = sym("xr_device_provider_is_product_id_valid"),
              let supportsFrequency: @convention(c) (Int32, Int32, Int32) -> Int32 = sym("xr_device_provider_is_product_support_imu_frequency"),
              let marketName: @convention(c) (Int32, UnsafeMutablePointer<CChar>?, UnsafeMutablePointer<Int32>?) -> Int32 = sym("xr_device_provider_get_market_name"),
              let getBrightness: @convention(c) (Handle) -> Int32 = sym("xr_device_provider_get_brightness_level"),
              let setBrightness: @convention(c) (Handle, Int32) -> Int32 = sym("xr_device_provider_set_brightness_level"),
              let getVolume: @convention(c) (Handle) -> Int32 = sym("xr_device_provider_get_volume_level"),
              let setVolume: @convention(c) (Handle, Int32) -> Int32 = sym("xr_device_provider_set_volume_level"),
              let valueMax: @convention(c) (Handle, Int32, UnsafeMutablePointer<Int32>?) -> Int32 = sym("xr_device_provider_get_value_max"),
              let setDisplayMode: @convention(c) (Handle, Int32) -> Int32 = sym("xr_device_provider_set_display_mode"),
              let setLogLevel: @convention(c) (Int32) -> Void = sym("xr_device_provider_set_log_level")
        else { return nil }
        self.create = create; self.initialize = initialize; self.start = start; self.stop = stop
        self.shutdown = shutdown; self.destroy = destroy; self.registerState = registerState
        self.registerPose = registerPose; self.openIMU = openIMU; self.closeIMU = closeIMU
        self.isValid = isValid; self.supportsFrequency = supportsFrequency; self.marketName = marketName
        self.getBrightness = getBrightness; self.setBrightness = setBrightness
        self.getVolume = getVolume; self.setVolume = setVolume; self.valueMax = valueMax
        self.setDisplayMode = setDisplayMode; self.setLogLevel = setLogLevel
        setLogLevel(1)  // errors only
    }

    func isProductIDValid(_ pid: Int32) -> Bool { isValid(pid) == 1 }

    func name(of pid: Int) -> String {
        var buf = [CChar](repeating: 0, count: 128)
        var len: Int32 = 128
        guard marketName(Int32(pid), &buf, &len) == vitureSuccess else { return "VITURE glasses" }
        let s = String(decoding: buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return s.isEmpty ? "VITURE glasses" : s
    }
}

/// VITURE USB devices currently attached (VID 0x35CA), deduplicated, in discovery order.
func findVitureDevicePIDs(isValid: (Int32) -> Bool) -> [Int] {
    findVitureUSBDevices().map(\.pid).filter { isValid(Int32($0)) }
}

/// Every USB device with VITURE's vendor id (0x35CA), whether or not the SDK accepts its product id.
func findVitureUSBDevices() -> [(pid: Int, name: String)] {
    var found: [(pid: Int, name: String)] = []
    func number(_ s: io_service_t, _ key: String) -> Int? {
        (IORegistryEntryCreateCFProperty(s, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber)?.intValue
    }
    // Apple silicon registers USB devices as IOUSBHostDevice; older macOS also answers to IOUSBDevice.
    for cls in ["IOUSBHostDevice", kIOUSBDeviceClassName] {
        guard let match = IOServiceMatching(cls) else { continue }
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, match, &it) == KERN_SUCCESS else { continue }
        defer { IOObjectRelease(it) }
        while case let s = IOIteratorNext(it), s != 0 {
            defer { IOObjectRelease(s) }
            guard number(s, "idVendor") == 0x35CA, let pid = number(s, "idProduct"),
                  !found.contains(where: { $0.pid == pid }) else { continue }
            let name = IORegistryEntryCreateCFProperty(s, "USB Product Name" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String
            found.append((pid, name ?? "?"))
        }
    }
    return found
}

/// Pose and button state written by SDK threads, read by the renderer.
private final class SDKState: @unchecked Sendable {
    static let shared = SDKState()
    let pose = OSAllocatedUnfairLock(initialState: Quat.identity)
    /// CACurrentMediaTime of the newest pose sample; nil until the first one arrives.
    let lastSample = OSAllocatedUnfairLock<Double?>(initialState: nil)
    let onState = OSAllocatedUnfairLock<(@Sendable (Int32, Int32) -> Void)?>(initialState: nil)
}

private let posCallback: PoseCallback = { data, _ in
    guard let d = data else { return }
    let q = renderQuat(fromNWU: Double(d[3]), Double(d[4]), Double(d[5]), Double(d[6])).normalized
    SDKState.shared.pose.withLock { $0 = q }
    let now = CACurrentMediaTime()
    SDKState.shared.lastSample.withLock { $0 = now }
}

private let stateCallback: StateCallback = { id, value in
    SDKState.shared.onState.withLock { $0 }?(id, value)
}

/// Real VITURE glasses (Gen1 / Luma) driven through the SDK.
@MainActor
final class VitureGlasses: GlassesLink {
    let pid: Int
    let status: GlassesStatus
    var onEvent: ((GlassesEvent) -> Void)?
    private let lib: VitureLibrary
    private var handle: Handle?
    private var imuOpen = false
    let connectedAt = CACurrentMediaTime()

    init?(library lib: VitureLibrary, pid: Int) {
        self.lib = lib
        self.pid = pid
        status = .connected(name: lib.name(of: pid))
        SDKState.shared.pose.withLock { $0 = .identity }
        SDKState.shared.lastSample.withLock { $0 = nil }
        guard let h = lib.create(Int32(pid)) else { return nil }
        handle = h
        let cache = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LumaSpace/sdk-cache")
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        var rc = cache.path.withCString { lib.initialize(h, nil, $0) }
        guard rc == vitureSuccess else { NSLog("LumaSpace: SDK initialize failed (\(rc))"); teardown(); return nil }
        _ = lib.registerPose(h, posCallback)
        _ = lib.registerState(h, stateCallback)
        rc = lib.start(h)
        guard rc == vitureSuccess else { NSLog("LumaSpace: SDK start failed (\(rc))"); teardown(); return nil }
        let freq = vitureFrequencies.first { lib.supportsFrequency(Int32(pid), Int32(viturePoseMode), Int32($0.0)) == 1 }
        rc = lib.openIMU(h, viturePoseMode, freq?.0 ?? 2)
        guard rc == vitureSuccess else { NSLog("LumaSpace: open IMU failed (\(rc))"); teardown(); return nil }
        imuOpen = true
        NSLog("LumaSpace: connected \(status.text), IMU \(freq?.1 ?? 120) Hz")
        SDKState.shared.onState.withLock {
            $0 = { [weak self] id, value in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        switch id {
                        case 0: self?.onEvent?(.levelChanged(.brightness, Int(value)))  // VITURE_CALLBACK_ID_BRIGHTNESS
                        case 1: self?.onEvent?(.levelChanged(.volume, Int(value)))      // VITURE_CALLBACK_ID_VOLUME
                        default: break
                        }
                    }
                }
            }
        }
    }

    nonisolated func rawOrientation() -> Quat { SDKState.shared.pose.withLock { $0 } }

    /// Seconds since the last pose sample, or nil if none has arrived yet.
    var sampleAge: Double? {
        SDKState.shared.lastSample.withLock { $0 }.map { CACurrentMediaTime() - $0 }
    }

    func level(_ k: LevelKind) -> Int? {
        guard let h = handle else { return nil }
        let v = k == .brightness ? lib.getBrightness(h) : lib.getVolume(h)
        return v >= 0 ? Int(v) : nil
    }

    func maxLevel(_ k: LevelKind) -> Int? {
        guard let h = handle else { return nil }
        var m: Int32 = 0
        return lib.valueMax(h, k == .brightness ? 0 : 1, &m) == vitureSuccess ? Int(m) : nil  // VITURE_VALUE_ID_*
    }

    func setLevel(_ k: LevelKind, _ v: Int) {
        guard let h = handle else { return }
        let v = Int32(min(max(v, 0), maxLevel(k) ?? 8))
        _ = k == .brightness ? lib.setBrightness(h, v) : lib.setVolume(h, v)
    }

    func setRate(_ r: DisplayRate) {
        guard let h = handle else { return }
        let mode: Int32 = switch r {  // VITURE_DISPLAY_MODE_1920_1080_*
        case .hz60: 0x31
        case .hz90: 0x33
        case .hz120: 0x34
        }
        let rc = lib.setDisplayMode(h, mode)
        if rc != vitureSuccess { NSLog("LumaSpace: set display mode failed (\(rc))") }
    }

    func stop() { teardown() }

    private func teardown() {
        SDKState.shared.onState.withLock { $0 = nil }
        SDKState.shared.lastSample.withLock { $0 = nil }
        guard let h = handle else { return }
        if imuOpen { _ = lib.closeIMU(h, viturePoseMode); imuOpen = false }
        _ = lib.stop(h)
        _ = lib.shutdown(h)
        lib.destroy(h)
        handle = nil
    }
}
