import AppKit

// `LumaSpace --install-sdk <zip|folder|dylib>` installs the VITURE SDK, like "Set Up VITURE SDK…".
if let i = CommandLine.arguments.firstIndex(of: "--install-sdk") {
    guard i + 1 < CommandLine.arguments.count else { print("usage: LumaSpace --install-sdk <VITURE SDK zip>"); exit(2) }
    do {
        try SDKInstaller.install(from: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
        print("installed the VITURE SDK into \(VitureLibrary.installDir.path)")
        exit(0)
    } catch {
        print("error: \(error.localizedDescription)")
        exit(1)
    }
}

// `LumaSpace --diagnose` (alias `--probe-sdk`) reports the SDK, USB devices and displays, then exits (no UI).
if CommandLine.arguments.contains("--diagnose") || CommandLine.arguments.contains("--probe-sdk") {
    let lib = VitureLibrary.load()
    print("sdk: \(lib == nil ? "missing" : "loaded")")
    for line in VitureLibrary.loadReport { print("  \(line)") }
    let usb = findVitureUSBDevices()
    print("usb: \(usb.count) VITURE device(s)")
    for d in usb {
        let accepted = lib.map { $0.isProductIDValid(Int32(d.pid)) ? "accepted by SDK (\($0.name(of: d.pid)))" : "REJECTED by SDK" }
        print("  " + String(format: "0x%04X", d.pid) + " \(d.name) — \(accepted ?? "SDK not loaded")")
    }
    print("displays:")
    for s in NSScreen.screens {
        let id = OutputWindow.displayID(of: s) ?? 0
        print("  \(s.localizedName) \(Int(s.frame.width))x\(Int(s.frame.height))\(CGDisplayIsInMirrorSet(id) != 0 ? " (mirrored)" : "")")
    }
    print("glasses display: \(OutputWindow.usableGlassesScreen()?.localizedName ?? "none usable")")
    let others = NSWorkspace.shared.runningApplications.compactMap(\.localizedName)
        .filter { $0.range(of: "spacewalker", options: .caseInsensitive) != nil }
    print("spacewalker running: \(others.isEmpty ? "no" : "YES — quit it")")
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let controller = AppController()
    app.delegate = controller
    app.setActivationPolicy(.accessory)
    app.run()
}
