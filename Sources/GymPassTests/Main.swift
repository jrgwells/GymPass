import Foundation
import Darwin

@main
struct GymPassTestRunner {
    static func main() async {
        let cases = allTestCases()
        print("GymPass test suite — \(cases.count) tests\n")
        var passed = 0
        var failed = 0
        var failureLog: [String] = []

        for testCase in cases {
            let context = TestContext(name: testCase.name)
            do {
                try await testCase.body(context)
            } catch {
                context.expect(false, "threw: \(error)")
            }
            if context.failures.isEmpty {
                passed += 1
                print("PASS  \(testCase.name)")
            } else {
                failed += 1
                print("FAIL  \(testCase.name)")
                for failure in context.failures {
                    print("        \(failure)")
                    failureLog.append("\(testCase.name): \(failure)")
                }
            }
        }

        print("\n\(passed) passed, \(failed) failed")
        if failed > 0 {
            exit(1)
        }
    }
}
