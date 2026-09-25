import Foundation

/// A deliberately small test harness. swift-testing cannot discover tests when
/// only CommandLineTools is installed, so GymPass uses this instead. It prints
/// a clear report and exits non-zero on failure.
public final class TestContext: @unchecked Sendable {
    public let name: String
    public private(set) var failures: [String] = []

    public init(name: String) {
        self.name = name
    }

    public func expect(_ condition: Bool, _ message: String = "expectation failed", file: StaticString = #fileID, line: UInt = #line) {
        if !condition {
            failures.append("\(file):\(line): \(message)")
        }
    }

    public func expectEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String = "", file: StaticString = #fileID, line: UInt = #line) {
        if lhs != rhs {
            failures.append("\(file):\(line): expected \(lhs) == \(rhs) \(message)")
        }
    }

    public func expectNotEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String = "", file: StaticString = #fileID, line: UInt = #line) {
        if lhs == rhs {
            failures.append("\(file):\(line): expected \(lhs) != \(rhs) \(message)")
        }
    }

    public func expectNotNil<T>(_ value: T?, _ message: String = "expected non-nil", file: StaticString = #fileID, line: UInt = #line) {
        if value == nil { failures.append("\(file):\(line): \(message)") }
    }

    public func expectNil<T>(_ value: T?, _ message: String = "expected nil", file: StaticString = #fileID, line: UInt = #line) {
        if value != nil { failures.append("\(file):\(line): \(message)") }
    }

    public func expectThrows(_ message: String = "expected a throw", file: StaticString = #fileID, line: UInt = #line, _ body: () throws -> Void) {
        do {
            try body()
            failures.append("\(file):\(line): \(message)")
        } catch {}
    }

    public func expectThrowsAsync(_ message: String = "expected a throw", file: StaticString = #fileID, line: UInt = #line, _ body: () async throws -> Void) async {
        do {
            try await body()
            failures.append("\(file):\(line): \(message)")
        } catch {}
    }
}

public struct TestCase: Sendable {
    public let name: String
    public let body: @Sendable (TestContext) async throws -> Void

    public init(_ name: String, _ body: @escaping @Sendable (TestContext) async throws -> Void) {
        self.name = name
        self.body = body
    }
}

public func allTestCases() -> [TestCase] {
    coreTestCases() + passTestCases() + persistenceTestCases() + serverTestCases() + refreshEngineTestCases()
}

enum TestSupport {
    static var fixturesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // GymPassTests
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // package root
            .appendingPathComponent("Tests/Fixtures", isDirectory: true)
    }

    static func identityData() throws -> Data {
        try Data(contentsOf: fixturesDirectory.appendingPathComponent("test-identity.p12"))
    }
}
