import AppKit

@MainActor
enum OutputWindow {
    static func preview() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 720),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        w.title = "LumaSpace — Simulator"
        w.contentAspectRatio = NSSize(width: 16, height: 9)
        w.isReleasedWhenClosed = false
        w.center()
        return w
    }

    static func fullscreen(on screen: NSScreen) -> NSWindow {
        let w = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
        w.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.isReleasedWhenClosed = false
        w.backgroundColor = .black
        w.setFrame(screen.frame, display: true)
        return w
    }

    static func glassesScreen() -> NSScreen? {
        NSScreen.screens.first { $0.localizedName.range(of: "VITURE", options: .caseInsensitive) != nil }
    }
}
