import Foundation
import VercelBarKit

// Lekki harness testowy (wzorzec skryba-tests; nie wymaga XCTest ani Xcode).

final class Runner {
    var passed = 0
    var failed = 0

    func suite(_ name: String) { print("\n▸ \(name)") }

    func check(_ condition: Bool, _ message: String) {
        if condition { passed += 1; print("  ✓ \(message)") }
        else { failed += 1; print("  ✗ \(message)") }
    }

    func equal<T: Equatable>(_ a: T, _ b: T, _ message: String) {
        check(a == b, "\(message)  [\(a) == \(b)]")
    }

    func finish() -> Never {
        print("\n— Wynik: \(passed) zaliczonych, \(failed) niezaliczonych —")
        fflush(stdout)
        exit(failed == 0 ? 0 : 1)
    }
}

let t = Runner()

t.suite("Harness")
t.check(true, "runner działa")

t.finish()
