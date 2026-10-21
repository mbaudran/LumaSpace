import Foundation

// Minimal check runner: XCTest and swift-testing are unavailable with Command Line Tools only.

nonisolated(unsafe) private var passed = 0
nonisolated(unsafe) private var failed = 0
nonisolated(unsafe) private var currentFailures: [String] = []

struct CheckFailure: Error { let message: String }

func check(_ name: String, _ body: () throws -> Void) {
    currentFailures = []
    do {
        try body()
    } catch {
        currentFailures.append("threw \(error)")
    }
    if currentFailures.isEmpty {
        passed += 1
    } else {
        failed += 1
        print("FAIL \(name)")
        for f in currentFailures { print("     \(f)") }
    }
}

func expect(_ cond: Bool, _ msg: String = "", file: StaticString = #fileID, line: UInt = #line) {
    if !cond { currentFailures.append("\(file):\(line) expectation failed \(msg)") }
}

func expectEqual<T: Equatable>(_ a: T, _ b: T, _ msg: String = "", file: StaticString = #fileID, line: UInt = #line) {
    if a != b { currentFailures.append("\(file):\(line) \(a) != \(b) \(msg)") }
}

func expectNear(_ a: Double, _ b: Double, tol: Double = 1e-6, _ msg: String = "", file: StaticString = #fileID, line: UInt = #line) {
    if !(abs(a - b) <= tol) { currentFailures.append("\(file):\(line) \(a) !≈ \(b) (tol \(tol)) \(msg)") }
}

func finishChecks() -> Never {
    print("\(passed) passed, \(failed) failed")
    exit(failed > 0 ? 1 : 0)
}
