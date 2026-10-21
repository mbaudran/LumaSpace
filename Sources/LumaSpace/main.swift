import AppKit

// `LumaSpace --probe-sdk` loads the VITURE SDK, lists glasses and exits (no UI).
if CommandLine.arguments.contains("--probe-sdk") {
    if let lib = VitureLibrary.load() {
        let pids = findVitureDevicePIDs(isValid: { lib.isProductIDValid($0) })
        print("sdk: loaded, devices: \(pids.count)\(pids.isEmpty ? "" : " " + pids.map { String(format: "0x%04X", $0) }.joined(separator: ","))")
    } else {
        print("sdk: missing")
    }
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let controller = AppController()
    app.delegate = controller
    app.setActivationPolicy(.accessory)
    app.run()
}
