import Foundation

public struct DisplayInfo: Sendable {
    public var id: UInt32
    public var name: String
    public init(id: UInt32, name: String) { self.id = id; self.name = name }
}

public struct WindowInfo: Sendable {
    public var id: UInt32
    public var app: String
    public var title: String
    public var ownerPID: Int32
    public var layer: Int
    public var onScreen: Bool
    public init(id: UInt32, app: String, title: String, ownerPID: Int32, layer: Int, onScreen: Bool) {
        self.id = id; self.app = app; self.title = title; self.ownerPID = ownerPID; self.layer = layer; self.onScreen = onScreen
    }
}

/// Sources the user may put on a panel. Never offers the glasses display or LumaSpace's own
/// windows — capturing either would show the output inside itself.
public func offeredSources(displays: [DisplayInfo], windows: [WindowInfo], glassesDisplayID: UInt32?,
                           ownPID: Int32) -> [PanelSource] {
    let ds = displays.filter { $0.id != glassesDisplayID }.map { PanelSource.display(id: $0.id, name: $0.name) }
    let ws = windows
        .filter { $0.ownerPID != ownPID && $0.layer == 0 && !$0.title.isEmpty && $0.onScreen }
        .sorted { ($0.app.localizedLowercase, $0.title.localizedLowercase) < ($1.app.localizedLowercase, $1.title.localizedLowercase) }
        .map { PanelSource.window(id: $0.id, app: $0.app, title: $0.title) }
    return ds + ws
}
