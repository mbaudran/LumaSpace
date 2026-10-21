import Foundation

public enum GlassesChoice: Equatable, Sendable {
    case real(pid: Int)
    case simulated(reason: String)
}

public func chooseGlasses(libraryLoaded: Bool, devicePIDs: [Int]) -> GlassesChoice {
    guard libraryLoaded else { return .simulated(reason: "VITURE SDK not found") }
    guard let pid = devicePIDs.first else { return .simulated(reason: "Glasses not connected") }
    return .real(pid: pid)
}
