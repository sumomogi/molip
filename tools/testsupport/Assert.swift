import Foundation

/// 테스트 공용. 실패를 세어두고 마지막에 종료 코드로 알린다.
enum T {
    static var failures = 0

    static func eq<V: Equatable>(_ name: String, _ got: V, _ want: V) {
        if got == want {
            print("PASS  \(name)")
        } else {
            failures += 1
            print("FAIL  \(name)")
            print("      got  \(got)")
            print("      want \(want)")
        }
    }

    static func ok(_ name: String, _ condition: Bool) {
        eq(name, condition, true)
    }

    static func finish() -> Never {
        print(failures == 0 ? "전부 통과" : "실패 \(failures)건")
        exit(failures == 0 ? 0 : 1)
    }
}
