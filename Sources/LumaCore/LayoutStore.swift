import Foundation

public struct LayoutFile: Codable, Equatable, Sendable {
    public var version: Int
    public var panels: [Panel]
    public var distance: Double
    public var smoothFollow: Bool
    public var lockedAxes: [Axis]

    public init(version: Int = 1, panels: [Panel], distance: Double, smoothFollow: Bool, lockedAxes: [Axis]) {
        self.version = version; self.panels = panels; self.distance = distance
        self.smoothFollow = smoothFollow; self.lockedAxes = lockedAxes
    }

    public static var `default`: LayoutFile {
        LayoutFile(panels: Preset.single.panels(sources: [], distance: 2), distance: 2,
                   smoothFollow: false, lockedAxes: [])
    }
}

public struct LayoutStore: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }

    public static func defaultURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LumaSpace/layout.json")
    }

    /// Missing file → default. Unreadable or unknown version → default, and the file is kept as `.bad`.
    public func load() -> LayoutFile {
        guard let data = try? Data(contentsOf: url) else { return .default }
        if var f = try? JSONDecoder().decode(LayoutFile.self, from: data), f.version == 1 {
            f.distance = f.distance.isFinite ? clamp(f.distance, SceneLimits.distance) : 2
            return f
        }
        let bad = URL(fileURLWithPath: url.path + ".bad")
        try? FileManager.default.removeItem(at: bad)
        try? FileManager.default.moveItem(at: url, to: bad)
        return .default
    }

    public func save(_ f: LayoutFile) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(f).write(to: url, options: .atomic)
    }
}
