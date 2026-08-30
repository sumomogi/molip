# 집중 기록과 인사이트 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 작업 세션을 JSONL 파일에 남기고, 요일 × 시간대로 모아 "언제 가장 잘 집중하는지"를 팝오버 세 번째 화면에서 한 문장으로 알려준다.

**Architecture:** `SessionLog`가 파일 형식을 아는 유일한 곳이고, `Insight`는 `[Session]`을 받아 표와 문장을 만드는 순수 함수다. `TimerEngine`은 파일을 만지지 않고 세션 종료를 콜백으로 내보내며, `AppDelegate`가 받아 적는다. 화면은 `HistoryView` 하나가 담당한다.

**Tech Stack:** Swift 5, SwiftUI, Foundation. Xcode 없이 `swiftc`만 쓴다. 외부 의존성 없음.

설계 문서: `docs/superpowers/specs/2026-08-30-focus-insight-design.md`

---

## 파일 구조

| 파일 | 책임 |
|---|---|
| `Sources/SessionLog.swift` | `Session` 타입, JSONL 한 줄 ↔ 값, 파일 추가·읽기 |
| `Sources/Insight.swift` | `[Session]` → 히트맵·최적 구간·주간 합계. 순수 함수 |
| `Sources/HistoryView.swift` | 팝오버 기록 화면 |
| `Sources/TimerEngine.swift` | (수정) 작업 시작 시각 보관, 종료를 콜백으로 알림 |
| `Sources/PopoverView.swift` | (수정) 화면 전환 `Bool` → `enum Screen`, 기록 버튼 |
| `Sources/Strings.swift` | (수정) 문자열 9개 추가 |
| `Sources/main.swift` | (수정) 콜백을 `SessionLog`에 연결, 종료 시 저장 |
| `tools/test.sh` | 테스트 실행기 |
| `tools/testsupport/Assert.swift` | 테스트 공용 단언 |
| `tools/tests/*.swift` | 스위트별 테스트 |

**의존 방향:** `HistoryView` → `Insight` → `Session`. `Insight`는 `Prefs`도 파일 시스템도 모른다. 그래서 가짜 세션 배열만으로 전부 검증된다.

---

### Task 1: 테스트 실행기

지금 이 저장소엔 테스트를 돌릴 방법이 없다. 순수 함수를 단독 실행 파일로 확인하는 방식(README가 `nextStep`에 대해 말하는 그 방식)을 스크립트로 굳힌다.

**Files:**
- Create: `tools/test.sh`
- Create: `tools/testsupport/Assert.swift`
- Create: `tools/tests/stepping.swift`
- Create: `tools/tests/setindex.swift`

- [ ] **Step 1: 공용 단언 만들기**

`tools/testsupport/Assert.swift`:

```swift
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
```

- [ ] **Step 2: 실행기 만들기**

`tools/test.sh`:

```bash
#!/bin/bash
# 테스트. tools/tests의 파일 하나가 스위트 하나다.
# 각 스위트는 main.swift를 뺀 앱 소스 전부와 함께 컴파일된다.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

SRC=$(ls Sources/*.swift | grep -v '/main\.swift$')

fail=0
for t in tools/tests/*.swift; do
    name=$(basename "$t" .swift)
    echo "── $name"
    swiftc -parse-as-library -o "$OUT/$name" $SRC tools/testsupport/*.swift "$t"
    "$OUT/$name" || fail=1
    echo
done

if [ "$fail" -eq 0 ]; then
    echo "모두 통과"
else
    echo "실패한 스위트가 있다"
    exit 1
fi
```

실행 권한을 준다:

```bash
chmod +x tools/test.sh
```

- [ ] **Step 3: 이미 고친 두 버그의 회귀 테스트를 옮겨 심기**

`tools/tests/stepping.swift`:

```swift
import Foundation

@main struct SteppingTests {
    static func main() {
        let work: ClosedRange<Int> = 1...90
        let long: ClosedRange<Int> = 1...60

        // 기본 50분에서 아래로 끝까지 내린 뒤 다시 올리면 5의 배수로 돌아와야 한다.
        var v = 50
        for _ in 0..<20 { v = Stepping.down(v, in: work, step: 5) }
        T.eq("최소까지 내린 값", v, 1)

        var seq: [Int] = []
        for _ in 0..<3 { v = Stepping.up(v, in: work, step: 5); seq.append(v) }
        T.eq("최소에서 위로 3번", seq, [5, 10, 15])

        T.eq("어긋난 6분 회복",
             [Stepping.up(6, in: work, step: 5), Stepping.down(6, in: work, step: 5)], [10, 5])
        T.eq("상한 도달",
             [Stepping.up(86, in: work, step: 5), Stepping.up(90, in: work, step: 5)], [90, 90])
        T.eq("하한 도달",
             [Stepping.down(5, in: work, step: 5), Stepping.down(1, in: work, step: 5)], [1, 1])
        T.eq("긴 휴식 양 끝",
             [Stepping.down(5, in: long, step: 5), Stepping.up(56, in: long, step: 5)], [1, 60])
        T.eq("step 1은 한 칸씩",
             [Stepping.up(1, in: long, step: 1), Stepping.down(60, in: long, step: 1)], [2, 59])

        // 어느 값에서 눌러도 범위를 벗어나지 않는다.
        var escaped = false
        for row in [(work, 5), (long, 5), (long, 1), (1...8, 1)] {
            for x in row.0 {
                if !row.0.contains(Stepping.up(x, in: row.0, step: row.1)) { escaped = true }
                if !row.0.contains(Stepping.down(x, in: row.0, step: row.1)) { escaped = true }
            }
        }
        T.ok("범위를 벗어나는 값 없음", !escaped)

        T.finish()
    }
}
```

`tools/tests/setindex.swift`:

```swift
import Foundation

@main struct SetIndexTests {
    static func main() {
        // 실제 전이 규칙에 태워 한 세트를 끝까지 돌린다.
        func walk(_ size: Int) -> [String] {
            var out: [String] = []
            var phase: Phase = .idle
            var completed = 0

            func show(_ tag: String) {
                out.append("\(tag) \(TimerEngine.setIndex(completedInSet: completed, setSize: size))/\(size)")
            }

            show("대기")
            for _ in 0..<size {
                phase = .work
                show("작업")
                let s = TimerEngine.nextStep(after: .work, completedInSet: completed, setSize: size)
                phase = s.phase
                completed = s.completedInSet
                show(phase == .longRest ? "긴휴식" : "짧은휴식")
                let r = TimerEngine.nextStep(after: phase, completedInSet: completed, setSize: size)
                phase = r.phase
                completed = r.completedInSet
                show("대기")
            }
            return out
        }

        T.eq("2회 세트", walk(2),
             ["대기 1/2", "작업 1/2", "짧은휴식 2/2", "대기 2/2",
              "작업 2/2", "긴휴식 2/2", "대기 1/2"])
        T.eq("1회 세트", walk(1),
             ["대기 1/1", "작업 1/1", "긴휴식 1/1", "대기 1/1"])
        T.eq("3회 세트", walk(3),
             ["대기 1/3", "작업 1/3", "짧은휴식 2/3", "대기 2/3",
              "작업 2/3", "짧은휴식 3/3", "대기 3/3",
              "작업 3/3", "긴휴식 3/3", "대기 1/3"])

        T.finish()
    }
}
```

- [ ] **Step 4: 돌려서 통과 확인**

Run: `./tools/test.sh`

Expected: `stepping`과 `setindex` 두 스위트가 모두 `전부 통과`, 마지막 줄에 `모두 통과`.

- [ ] **Step 5: 커밋**

```bash
git add tools/
git commit -m "테스트 실행기와 회귀 테스트 두 벌"
```

---

### Task 2: Session 타입과 한 줄 직렬화

**Files:**
- Create: `Sources/SessionLog.swift`
- Create: `tools/tests/sessionlog.swift`

- [ ] **Step 1: 실패하는 테스트 먼저**

`tools/tests/sessionlog.swift`:

```swift
import Foundation

@main struct SessionLogTests {
    static func main() {
        // 2026-08-30 15:44:04 +09:00 을 명시적으로 만든다.
        // 유닉스 초를 손으로 적으면 틀려도 눈에 안 보인다.
        var c = DateComponents()
        c.year = 2026; c.month = 8; c.day = 30
        c.hour = 15; c.minute = 44; c.second = 4
        c.timeZone = TimeZone(secondsFromGMT: 9 * 3600)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = cal.date(from: c)!
        let s = Session(start: start, offsetSeconds: 9 * 3600, seconds: 3000, completed: true)

        T.eq("한 줄 형식", SessionLog.line(for: s),
             "{\"start\":\"2026-08-30T15:44:04+09:00\",\"seconds\":3000,\"completed\":true}")

        T.eq("되읽기", SessionLog.session(from: SessionLog.line(for: s)), s)

        T.eq("오프셋 파싱", [
            SessionLog.offset(from: "2026-08-30T15:44:04+09:00"),
            SessionLog.offset(from: "2026-08-30T01:44:04-05:00"),
            SessionLog.offset(from: "2026-08-30T06:44:04Z"),
        ], [9 * 3600, -5 * 3600, 0])

        T.eq("깨진 줄은 nil", SessionLog.session(from: "{\"start\":\"2026-08"), nil)
        T.eq("빈 줄은 nil", SessionLog.session(from: ""), nil)

        T.finish()
    }
}
```

- [ ] **Step 2: 돌려서 실패 확인**

Run: `./tools/test.sh`

Expected: 컴파일 실패 — `cannot find 'Session' in scope`.

- [ ] **Step 3: 최소 구현**

`Sources/SessionLog.swift`:

```swift
import Foundation

/// 작업 세션 한 건.
struct Session: Equatable {
    let start: Date
    /// 기록될 당시의 로컬 오프셋(초). 요일과 시간대를 이 값에 맞춰 센다.
    /// 사용자가 다른 시간대로 옮겨가도 과거 기록이 다시 쓰이지 않게 하려는 것이다.
    let offsetSeconds: Int
    let seconds: Int
    let completed: Bool
}

/// sessions.jsonl을 읽고 쓴다. 파일 형식을 아는 유일한 곳.
enum SessionLog {

    /// 테스트가 임시 경로로 바꿔 끼울 수 있도록 var로 둔다.
    static var url: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        return base.appendingPathComponent("Molip", isDirectory: true)
                   .appendingPathComponent("sessions.jsonl")
    }()

    // MARK: - 한 줄 ↔ 값

    /// JSON을 직접 쓴다. 값이 전부 숫자·불리언·형식이 고정된 날짜라 이스케이프할 것이 없고,
    /// 그 대신 파일에 어떤 글자가 들어가는지가 코드에 그대로 보인다.
    static func line(for s: Session) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(secondsFromGMT: s.offsetSeconds) ?? .current
        return "{\"start\":\"\(f.string(from: s.start))\",\"seconds\":\(s.seconds),\"completed\":\(s.completed)}"
    }

    private struct Row: Decodable {
        let start: String
        let seconds: Int
        let completed: Bool
    }

    static func session(from line: String) -> Session? {
        guard let data = line.data(using: .utf8),
              let row = try? JSONDecoder().decode(Row.self, from: data) else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        guard let date = f.date(from: row.start) else { return nil }
        return Session(start: date,
                       offsetSeconds: offset(from: row.start),
                       seconds: row.seconds,
                       completed: row.completed)
    }

    /// "2026-08-30T15:44:04+09:00" 끝에 붙은 오프셋을 초로. `Z`면 0.
    ///
    /// `JSONEncoder`의 `.iso8601` 전략은 UTC로 적어 이 정보를 잃는다. 그래서 쓰지 않는다.
    static func offset(from iso: String) -> Int {
        if iso.hasSuffix("Z") { return 0 }
        let tail = iso.suffix(6)                       // +09:00
        guard tail.count == 6,
              tail.hasPrefix("+") || tail.hasPrefix("-"),
              let h = Int(tail.dropFirst().prefix(2)),
              let m = Int(tail.suffix(2)) else { return 0 }
        return (tail.hasPrefix("-") ? -1 : 1) * (h * 3600 + m * 60)
    }
}
```

- [ ] **Step 4: 돌려서 통과 확인**

Run: `./tools/test.sh`

Expected: `sessionlog` 스위트가 `전부 통과`.

- [ ] **Step 5: 커밋**

```bash
git add Sources/SessionLog.swift tools/tests/sessionlog.swift
git commit -m "세션 기록 타입과 한 줄 직렬화"
```

---

### Task 3: 파일 추가와 읽기

**Files:**
- Modify: `Sources/SessionLog.swift`
- Modify: `tools/tests/sessionlog.swift`

- [ ] **Step 1: 실패하는 테스트 추가**

`tools/tests/sessionlog.swift`의 `T.finish()` 바로 앞에 넣는다:

```swift
        // 파일 왕복. 임시 경로로 바꿔 끼운다.
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("molip-test-\(getpid())")
            .appendingPathComponent("sessions.jsonl")
        SessionLog.url = tmp

        T.eq("없는 파일은 빈 배열", SessionLog.load(), [])

        let a = Session(start: start, offsetSeconds: 9 * 3600, seconds: 3000, completed: true)
        let b = Session(start: start.addingTimeInterval(7200),
                        offsetSeconds: 9 * 3600, seconds: 1620, completed: false)
        SessionLog.append(a)
        SessionLog.append(b)
        T.eq("두 줄 왕복", SessionLog.load(), [a, b])

        // append 도중 종료되면 마지막 줄이 잘릴 수 있다. 나머지는 살아야 한다.
        if let h = try? FileHandle(forWritingTo: tmp) {
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: Data("{\"start\":\"2026-08".utf8))
            try? h.close()
        }
        T.eq("잘린 마지막 줄은 버리고 나머지를 읽음", SessionLog.load(), [a, b])

        try? FileManager.default.removeItem(at: tmp.deletingLastPathComponent())
```

- [ ] **Step 2: 돌려서 실패 확인**

Run: `./tools/test.sh`

Expected: 컴파일 실패 — `type 'SessionLog' has no member 'append'`.

- [ ] **Step 3: 최소 구현**

`Sources/SessionLog.swift`의 `offset(from:)` 뒤, 닫는 중괄호 앞에 넣는다:

```swift

    // MARK: - 파일

    /// 한 줄 덧붙인다. 디렉터리가 없으면 만든다.
    static func append(_ s: Session) {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = Data((line(for: s) + "\n").utf8)
        if let h = try? FileHandle(forWritingTo: url) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }

    /// 읽을 수 없는 줄은 건너뛴다. 쓰다 만 마지막 줄 하나 때문에 전체를 잃지 않는다.
    static func load() -> [Session] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { session(from: String($0)) }
    }
```

- [ ] **Step 4: 돌려서 통과 확인**

Run: `./tools/test.sh`

Expected: `sessionlog` 스위트가 `전부 통과`.

- [ ] **Step 5: 커밋**

```bash
git add Sources/SessionLog.swift tools/tests/sessionlog.swift
git commit -m "세션 기록 파일 추가와 읽기"
```

---

### Task 4: 세션을 요일·시간대 칸에 넣기

**Files:**
- Create: `Sources/Insight.swift`
- Create: `tools/tests/insight.swift`

- [ ] **Step 1: 실패하는 테스트 먼저**

`tools/tests/insight.swift`:

```swift
import Foundation

@main struct InsightTests {
    static func main() {
        // 2026-08-31은 월요일.
        func at(_ iso: String) -> Session {
            SessionLog.session(from: "{\"start\":\"\(iso)\",\"seconds\":1500,\"completed\":true}")!
        }

        T.eq("월요일 09시", Insight.slot(of: at("2026-08-31T09:10:00+09:00")).weekday, 0)
        T.eq("일요일", Insight.slot(of: at("2026-09-06T09:10:00+09:00")).weekday, 6)
        T.eq("토요일", Insight.slot(of: at("2026-09-05T09:10:00+09:00")).weekday, 5)

        T.eq("09시는 세 번째 시간대", Insight.slot(of: at("2026-08-31T09:10:00+09:00")).band, 3)
        T.eq("00시는 첫 시간대", Insight.slot(of: at("2026-08-31T00:10:00+09:00")).band, 0)
        T.eq("23시는 마지막 시간대", Insight.slot(of: at("2026-08-31T23:10:00+09:00")).band, 7)

        // 같은 순간이라도 기록될 때의 오프셋을 따른다.
        T.eq("오프셋을 따라 시간대가 갈림", [
            Insight.slot(of: at("2026-08-31T09:10:00+09:00")).band,
            Insight.slot(of: at("2026-08-31T09:10:00-05:00")).band,
        ], [3, 3])
        T.eq("같은 절대 시각, 다른 오프셋", [
            Insight.slot(of: at("2026-08-31T09:00:00+09:00")).band,   // 09시
            Insight.slot(of: at("2026-08-31T00:00:00Z")).band,        // 같은 순간, 00시로 적힘
        ], [3, 0])

        T.finish()
    }
}
```

- [ ] **Step 2: 돌려서 실패 확인**

Run: `./tools/test.sh`

Expected: 컴파일 실패 — `cannot find 'Insight' in scope`.

- [ ] **Step 3: 최소 구현**

`Sources/Insight.swift`:

```swift
import Foundation

/// 기록에서 뽑아낸 것. 화면은 이 값만 읽는다.
/// 파일도 설정도 모르는 순수한 계산이라 가짜 세션 배열만으로 전부 검증된다.
enum Insight {

    /// 시간대 한 칸의 길이(시간). 24를 나누어떨어져야 한다.
    static let bandHours = 3
    static let bandCount = 24 / bandHours

    /// 세션이 들어갈 칸. weekday는 월요일이 0, band는 00시가 0.
    static func slot(of s: Session) -> (weekday: Int, band: Int) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: s.offsetSeconds) ?? .current
        let c = cal.dateComponents([.weekday, .hour], from: s.start)
        // Calendar의 weekday는 일요일이 1. 화면은 월요일부터 시작한다.
        return (((c.weekday ?? 1) + 5) % 7, (c.hour ?? 0) / bandHours)
    }
}
```

- [ ] **Step 4: 돌려서 통과 확인**

Run: `./tools/test.sh`

Expected: `insight` 스위트가 `전부 통과`.

- [ ] **Step 5: 커밋**

```bash
git add Sources/Insight.swift tools/tests/insight.swift
git commit -m "세션을 요일·시간대 칸에 넣는 규칙"
```

---

### Task 5: 히트맵 만들기 — 창 자르기, 농도, 빈 행 감추기

**Files:**
- Modify: `Sources/Insight.swift`
- Modify: `tools/tests/insight.swift`

- [ ] **Step 1: 실패하는 테스트 추가**

`tools/tests/insight.swift`의 `T.finish()` 앞에 넣는다:

```swift
        func sess(_ iso: String, _ seconds: Int) -> Session {
            SessionLog.session(from: "{\"start\":\"\(iso)\",\"seconds\":\(seconds),\"completed\":true}")!
        }
        let now = sess("2026-09-06T20:00:00+09:00", 60).start   // 일요일 저녁

        // 월 09시대에 크게, 화 15시대에 작게.
        var data = [sess("2026-08-31T09:00:00+09:00", 3000),
                    sess("2026-09-01T15:00:00+09:00", 600)]

        let r = Insight.make(sessions: data, now: now)
        T.eq("빈 행은 감춘다", r.rows.map(\.bandStartHour), [9, 15])
        T.eq("가장 큰 칸은 최고 농도", r.rows[0].levels[0], 3)
        T.eq("1/3 이하는 낮은 농도", r.rows[1].levels[1], 1)
        T.eq("빈 칸은 0", r.rows[0].levels[3], 0)
        T.eq("창 안 세션 수", r.sessionCount, 2)

        // 57일 전 세션은 창 밖.
        data.append(sess("2026-07-11T09:00:00+09:00", 3000))
        T.eq("8주보다 오래된 것은 뺀다", Insight.make(sessions: data, now: now).sessionCount, 2)
```

- [ ] **Step 2: 돌려서 실패 확인**

Run: `./tools/test.sh`

Expected: 컴파일 실패 — `type 'Insight' has no member 'make'`.

- [ ] **Step 3: 최소 구현**

`Sources/Insight.swift`의 `slot(of:)` 뒤, 닫는 중괄호 앞에 넣는다:

```swift

    /// 집계 범위. 습관이 바뀌면 화면도 따라 바뀌게 최근 것만 본다.
    static let windowDays = 56

    /// 화면에 그릴 한 행.
    struct Row: Equatable {
        let bandStartHour: Int
        /// 월~일 7칸. 각 칸은 농도 단계 0...3.
        let levels: [Int]
    }

    struct Result: Equatable {
        let rows: [Row]
        let sessionCount: Int
    }

    static func make(sessions: [Session], now: Date) -> Result {
        let cutoff = now.addingTimeInterval(-Double(windowDays) * 86400)
        let window = sessions.filter { $0.start >= cutoff }

        // [시간대][요일] 합계 초
        var totals = Array(repeating: Array(repeating: 0, count: 7), count: bandCount)
        for s in window {
            let p = slot(of: s)
            totals[p.band][p.weekday] += s.seconds
        }

        let peak = totals.flatMap { $0 }.max() ?? 0
        var rows: [Row] = []
        for band in 0..<bandCount where totals[band].contains(where: { $0 > 0 }) {
            rows.append(Row(bandStartHour: band * bandHours,
                            levels: totals[band].map { level($0, peak: peak) }))
        }
        return Result(rows: rows, sessionCount: window.count)
    }

    /// 가장 큰 칸과 견준 비율로 네 단계. 색은 쓰지 않고 이 단계로 알파만 준다.
    static func level(_ seconds: Int, peak: Int) -> Int {
        guard seconds > 0, peak > 0 else { return 0 }
        let r = Double(seconds) / Double(peak)
        if r > 2.0 / 3.0 { return 3 }
        if r > 1.0 / 3.0 { return 2 }
        return 1
    }
```

- [ ] **Step 4: 돌려서 통과 확인**

Run: `./tools/test.sh`

Expected: `insight` 스위트가 `전부 통과`.

- [ ] **Step 5: 커밋**

```bash
git add Sources/Insight.swift tools/tests/insight.swift
git commit -m "히트맵 집계 — 최근 8주, 네 단계 농도, 빈 행 감추기"
```

---

### Task 6: 최적 구간과 침묵 기준

**Files:**
- Modify: `Sources/Insight.swift`
- Modify: `tools/tests/insight.swift`

- [ ] **Step 1: 실패하는 테스트 추가**

`tools/tests/insight.swift`의 `T.finish()` 앞에 넣는다:

```swift
        // 조건을 넘기려면 창 안 10세션, 그리고 최다 칸에 3세션이 필요하다.
        // 2026-08-25 / 09-01 / 09-08 은 모두 화요일이다.
        let later = sess("2026-09-13T20:00:00+09:00", 60).start

        var many = [sess("2026-08-25T15:30:00+09:00", 3000),
                    sess("2026-09-01T15:30:00+09:00", 3000),
                    sess("2026-09-08T15:30:00+09:00", 3000)]
        for d in 0..<7 { many.append(sess("2026-09-0\(1 + d)T09:30:00+09:00", 60)) }

        let full = Insight.make(sessions: many, now: later)
        T.eq("최다 칸 요일", full.best?.weekday, 1)          // 화요일
        T.eq("최다 칸 시간", full.best?.bandStartHour, 15)

        // 9세션이면 침묵. 최다 칸은 여전히 3세션이다.
        T.eq("세션이 모자라면 문장 없음",
             Insight.make(sessions: Array(many.prefix(9)), now: later).best, nil)

        // 세션 수는 충분해도 최다 칸이 2세션이면 침묵.
        var thin = [sess("2026-09-01T15:30:00+09:00", 3000),
                    sess("2026-09-08T15:30:00+09:00", 3000)]
        for d in 0..<9 { thin.append(sess("2026-09-0\(1 + d)T06:30:00+09:00", 60)) }
        T.eq("최다 칸이 얇으면 문장 없음", Insight.make(sessions: thin, now: later).best, nil)

        // 동점이면 이른 요일, 그다음 이른 시간대.
        var tied = [sess("2026-08-25T18:30:00+09:00", 1200),
                    sess("2026-09-01T18:30:00+09:00", 1200),
                    sess("2026-09-08T18:30:00+09:00", 1200)]   // 화 18시, 합 3600
        tied += [sess("2026-08-26T15:30:00+09:00", 1200),
                 sess("2026-09-02T15:30:00+09:00", 1200),
                 sess("2026-09-09T15:30:00+09:00", 1200)]      // 수 15시, 합 3600
        for d in 0..<4 { tied.append(sess("2026-09-0\(1 + d)T06:30:00+09:00", 60)) }

        let t = Insight.make(sessions: tied, now: later)
        T.eq("동점이면 이른 요일", t.best?.weekday, 1)
        T.eq("동점 요일의 시간대", t.best?.bandStartHour, 18)
```

- [ ] **Step 2: 돌려서 실패 확인**

Run: `./tools/test.sh`

Expected: 컴파일 실패 — `value of type 'Insight.Result' has no member 'best'`.

- [ ] **Step 3: 구현**

`Sources/Insight.swift`에서 `Result`를 바꾸고 상수와 선택 규칙을 더한다.

`Result` 선언을 통째로 아래로 바꾼다:

```swift
    struct Best: Equatable {
        let weekday: Int
        let bandStartHour: Int
    }

    struct Result: Equatable {
        let rows: [Row]
        let best: Best?
        let sessionCount: Int
    }

    /// 문장을 내기 전에 넘겨야 하는 두 문턱.
    /// 두 번 집중한 것을 두고 "화요일이 최적입니다"라고 단언하면 앱을 못 믿게 된다.
    static let minSessions = 10
    static let minBestSessions = 3
```

`make(sessions:now:)`에서 세션 수를 함께 세고 `best`를 계산하도록 바꾼다. 함수 전체를 아래로 교체한다:

```swift
    static func make(sessions: [Session], now: Date) -> Result {
        let cutoff = now.addingTimeInterval(-Double(windowDays) * 86400)
        let window = sessions.filter { $0.start >= cutoff }

        // [시간대][요일]의 합계 초와 세션 수
        var totals = Array(repeating: Array(repeating: 0, count: 7), count: bandCount)
        var counts = Array(repeating: Array(repeating: 0, count: 7), count: bandCount)
        for s in window {
            let p = slot(of: s)
            totals[p.band][p.weekday] += s.seconds
            counts[p.band][p.weekday] += 1
        }

        let peak = totals.flatMap { $0 }.max() ?? 0
        var rows: [Row] = []
        for band in 0..<bandCount where totals[band].contains(where: { $0 > 0 }) {
            rows.append(Row(bandStartHour: band * bandHours,
                            levels: totals[band].map { level($0, peak: peak) }))
        }

        return Result(rows: rows,
                      best: best(totals: totals, counts: counts, sessionCount: window.count),
                      sessionCount: window.count)
    }

    /// 합계가 가장 큰 칸. 동점이면 이른 요일, 그다음 이른 시간대.
    private static func best(totals: [[Int]], counts: [[Int]], sessionCount: Int) -> Best? {
        guard sessionCount >= minSessions else { return nil }

        var pick: (weekday: Int, band: Int, seconds: Int)?
        // 요일을 바깥에서 돌아 먼저 만난 쪽이 이기게 한다.
        for weekday in 0..<7 {
            for band in 0..<bandCount {
                let seconds = totals[band][weekday]
                guard seconds > 0 else { continue }
                if pick == nil || seconds > pick!.seconds {
                    pick = (weekday, band, seconds)
                }
            }
        }

        guard let p = pick, counts[p.band][p.weekday] >= minBestSessions else { return nil }
        return Best(weekday: p.weekday, bandStartHour: p.band * bandHours)
    }
```

- [ ] **Step 4: 돌려서 통과 확인**

Run: `./tools/test.sh`

Expected: `insight` 스위트가 `전부 통과`.

- [ ] **Step 5: 커밋**

```bash
git add Sources/Insight.swift tools/tests/insight.swift
git commit -m "최적 구간 선택과, 근거가 얇으면 말하지 않는 기준"
```

---

### Task 7: 이번 주 합계

**Files:**
- Modify: `Sources/Insight.swift`
- Modify: `tools/tests/insight.swift`

- [ ] **Step 1: 실패하는 테스트 추가**

`tools/tests/insight.swift`의 `T.finish()` 앞에 넣는다:

```swift
        // 주는 월요일에 시작한다. 일요일 23시와 그다음 월요일 00시는 다른 주다.
        let seoul = TimeZone(secondsFromGMT: 9 * 3600)!
        let weekData = [sess("2026-08-31T09:00:00+09:00", 1800),   // 월
                        sess("2026-09-06T23:30:00+09:00", 600),    // 일 (같은 주)
                        sess("2026-09-07T00:30:00+09:00", 900)]    // 다음 월 (다른 주)

        T.eq("이번 주 합계",
             Insight.weekSeconds(sessions: weekData, now: now, timeZone: seoul), 2400)
        T.eq("다음 주로 넘어가면 다시 센다",
             Insight.weekSeconds(sessions: weekData,
                                 now: sess("2026-09-07T10:00:00+09:00", 60).start,
                                 timeZone: seoul), 900)
```

- [ ] **Step 2: 돌려서 실패 확인**

Run: `./tools/test.sh`

Expected: 컴파일 실패 — `type 'Insight' has no member 'weekSeconds'`.

- [ ] **Step 3: 구현**

`Sources/Insight.swift`의 닫는 중괄호 앞에 넣는다:

```swift

    /// 이번 주에 집중한 시간(초). 주는 월요일에 시작한다.
    ///
    /// 히트맵과 달리 여기서는 현재 시간대를 쓴다. "이번 주"는 지금 어디에 있느냐의
    /// 문제이지, 그때 어디에 있었느냐의 문제가 아니다.
    static func weekSeconds(sessions: [Session], now: Date, timeZone: TimeZone) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        cal.firstWeekday = 2                     // 월요일. 로케일에 맡기면 화면과 어긋난다.
        guard let week = cal.dateInterval(of: .weekOfYear, for: now) else { return 0 }
        return sessions
            .filter { week.contains($0.start) }
            .reduce(0) { $0 + $1.seconds }
    }
```

- [ ] **Step 4: 돌려서 통과 확인**

Run: `./tools/test.sh`

Expected: `insight` 스위트가 `전부 통과`.

- [ ] **Step 5: 커밋**

```bash
git add Sources/Insight.swift tools/tests/insight.swift
git commit -m "이번 주 집중 시간 합계"
```

---

### Task 8: 엔진이 세션 종료를 알리게 하기

**Files:**
- Modify: `Sources/TimerEngine.swift`
- Create: `tools/tests/recording.swift`

- [ ] **Step 1: 실패하는 테스트 먼저**

`tools/tests/recording.swift`:

```swift
import Foundation

@main struct RecordingTests {
    static func main() {
        // 길이 계산만 따로 확인한다. 타이머를 1분 돌리지 않고 규칙을 본다.
        let cap = 3000.0   // 50분

        T.eq("완주는 그대로", Int(TimerEngine.recordedSeconds(elapsed: 3000, cap: cap)), 3000)
        T.eq("중간에 멈추면 흐른 만큼", Int(TimerEngine.recordedSeconds(elapsed: 1620, cap: cap)), 1620)
        T.eq("단계 길이를 넘지 않는다", Int(TimerEngine.recordedSeconds(elapsed: 9999, cap: cap)), 3000)
        T.eq("음수는 0", Int(TimerEngine.recordedSeconds(elapsed: -5, cap: cap)), 0)

        T.ok("60초 미만은 버린다", !TimerEngine.worthRecording(seconds: 59))
        T.ok("60초는 남긴다", TimerEngine.worthRecording(seconds: 60))

        T.finish()
    }
}
```

- [ ] **Step 2: 돌려서 실패 확인**

Run: `./tools/test.sh`

Expected: 컴파일 실패 — `type 'TimerEngine' has no member 'recordedSeconds'`.

- [ ] **Step 3: 구현**

`Sources/TimerEngine.swift`의 `onUpdate` 선언 바로 아래에 콜백과 상태를 더한다:

```swift
    /// 작업 세션 하나가 끝날 때마다 불린다. 파일에 적는 일은 이 콜백을 받는 쪽이 한다.
    /// 엔진이 파일을 직접 만지면 파일 없이 검증할 수 없게 된다.
    var onWorkSessionEnded: ((Session) -> Void)?
```

`private var endDate: Date?` 아래에 더한다:

```swift
    /// 지금 돌고 있는 작업 세션이 시작된 시각. 작업이 아니면 nil.
    private var workStartedAt: Date?
```

`nextStep` 아래, `// MARK: - 조작` 위에 순수 함수 둘을 더한다:

```swift
    /// 기록할 길이. 벽시계로 흐른 시간을 쓰되 단계 길이를 넘지 않는다.
    /// 맥이 잠들어도 실제로 흐른 만큼이 남고, 시계가 튀어도 한 세션이 부풀지 않는다.
    static func recordedSeconds(elapsed: TimeInterval, cap: TimeInterval) -> TimeInterval {
        min(max(elapsed, 0), cap)
    }

    /// 너무 짧은 것은 남기지 않는다. 눌렀다 바로 끈 것까지 리듬으로 세면 그림이 흐려진다.
    static func worthRecording(seconds: Int) -> Bool { seconds >= 60 }
```

`begin(_:)`의 `phase = next` 바로 아래에 더한다:

```swift
        if next == .work { workStartedAt = Date() }
```

`stop()`의 첫 줄로 넣는다 (`ticker?.invalidate()` 앞):

```swift
        endWorkSession(completed: false)
```

`advance()`의 `guard finished != .idle else { return }` 바로 아래에 넣는다:

```swift
        if finished == .work { endWorkSession(completed: true) }
```

`// MARK: - 내부` 아래, `begin(_:)` 앞에 더한다:

```swift
    /// 돌고 있던 작업 세션을 닫고 알린다. 작업 중이 아니었으면 아무 일도 하지 않는다.
    private func endWorkSession(completed: Bool) {
        guard let started = workStartedAt else { return }
        workStartedAt = nil
        let length = Self.recordedSeconds(elapsed: Date().timeIntervalSince(started),
                                          cap: TimeInterval(Prefs.workMinutes * 60))
        let seconds = Int(length.rounded())
        guard Self.worthRecording(seconds: seconds) else { return }
        onWorkSessionEnded?(Session(start: started,
                                    offsetSeconds: TimeZone.current.secondsFromGMT(for: started),
                                    seconds: seconds,
                                    completed: completed))
    }
```

- [ ] **Step 4: 돌려서 통과 확인**

Run: `./tools/test.sh`

Expected: `recording` 스위트가 `전부 통과`, 다른 스위트도 그대로 통과.

- [ ] **Step 5: 빌드 확인**

Run: `./build.sh`

Expected: `서명 검증 통과`, `빌드 완료`.

- [ ] **Step 6: 커밋**

```bash
git add Sources/TimerEngine.swift tools/tests/recording.swift
git commit -m "작업 세션이 끝날 때 콜백으로 알리기"
```

---

### Task 9: 문자열 아홉 개

**Files:**
- Modify: `Sources/Strings.swift`

- [ ] **Step 1: 키 더하기**

`enum Key`의 `// 알림` 블록 아래에 더한다:

```swift
        // 기록 화면
        case history, historyBest, historyAdvice, historyNotEnough, historyEmpty
        case weekTotal, durationHM, durationM
```

- [ ] **Step 2: 세 언어 모두 채우기**

`.ko` 표의 `.notifReadyBody` 줄 아래에 더한다:

```swift
            .history: "기록",
            .historyBest: "%1$@ %2$d시 전후에 가장 오래 집중했습니다.",
            .historyAdvice: "그 시간에 중요한 일을 두세요.",
            .historyNotEnough: "아직 기록이 적습니다.",
            .historyEmpty: "아직 기록이 없습니다.",
            .weekTotal: "이번 주",
            .durationHM: "%d시간 %d분",
            .durationM: "%d분",
```

`.en` 표의 같은 자리에 더한다:

```swift
            .history: "History",
            .historyBest: "You focus longest around %2$d:00 on %1$@.",
            .historyAdvice: "Put your important work there.",
            .historyNotEnough: "Not enough recorded yet.",
            .historyEmpty: "Nothing recorded yet.",
            .weekTotal: "This week",
            .durationHM: "%dh %dm",
            .durationM: "%dm",
```

`.ja` 표의 같은 자리에 더한다:

```swift
            .history: "記録",
            .historyBest: "%1$@の%2$d時前後がいちばん長く集中できています。",
            .historyAdvice: "その時間に大事な仕事を置いてみてください。",
            .historyNotEnough: "記録がまだ少なめです。",
            .historyEmpty: "まだ記録がありません。",
            .weekTotal: "今週",
            .durationHM: "%d時間%d分",
            .durationM: "%d分",
```

문장에 `%1$@`, `%2$d` 위치 지정자를 쓰는 이유는 영어의 어순이 달라서다.
`L10n.s`가 `CVarArg`를 받으므로 `%@`에 문자열을 넘길 수 있다.

- [ ] **Step 3: 언어를 지정해 꺼내는 조회 더하기**

전수 검사가 사용자의 언어 설정을 건드리면 안 된다. `Sources/Strings.swift`의
`static func s(_ key: Key) -> String`를 아래로 바꾼다:

```swift
    static func s(_ key: Key) -> String { s(key, lang: Prefs.language) }

    /// 언어를 직접 지정해 꺼낸다. 전수 검사가 설정을 바꾸지 않게 하려는 것이다.
    static func s(_ key: Key, lang: Lang) -> String {
        table[lang]?[key] ?? table[.en]?[key] ?? ""
    }
```

인자에 이름이 붙어 있어 기존 가변 인자 버전과 헷갈리지 않는다.

- [ ] **Step 4: 빠진 번역이 없는지 확인**

`tools/tests/strings.swift`를 만든다:

```swift
import Foundation

@main struct StringsTests {
    static func main() {
        // 한 언어에서만 번역이 빠지는 사고를 막는다.
        for lang in Lang.allCases {
            let missing = L10n.Key.allCases.filter { L10n.s($0, lang: lang).isEmpty }
            T.eq("\(lang.rawValue) 빠진 문자열", missing.map { "\($0)" }, [])
        }
        T.finish()
    }
}
```

- [ ] **Step 5: 돌려서 통과 확인**

Run: `./tools/test.sh`

Expected: `strings` 스위트가 세 언어 모두 `빠진 문자열 []`로 통과.

- [ ] **Step 6: 커밋**

```bash
git add Sources/Strings.swift tools/tests/strings.swift
git commit -m "기록 화면 문자열과 세 언어 전수 검사"
```

---

### Task 10: 기록 화면

**Files:**
- Create: `Sources/HistoryView.swift`

- [ ] **Step 1: 화면 만들기**

`Sources/HistoryView.swift`:

```swift
import SwiftUI

/// 팝오버 기록 화면. 집계는 전부 Insight가 하고 여기서는 그리기만 한다.
struct HistoryView: View {
    var onClose: () -> Void
    var onSettings: () -> Void

    private let result: Insight.Result
    private let weekSeconds: Int

    init(sessions: [Session], now: Date = Date(),
         onClose: @escaping () -> Void, onSettings: @escaping () -> Void) {
        self.result = Insight.make(sessions: sessions, now: now)
        self.weekSeconds = Insight.weekSeconds(sessions: sessions, now: now, timeZone: .current)
        self.onClose = onClose
        self.onSettings = onSettings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            Text(L10n.s(.history))
                .font(.system(size: 11, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(.tertiary)

            Spacer().frame(height: 14)

            if result.rows.isEmpty {
                Text(L10n.s(.historyEmpty))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                Heatmap(rows: result.rows)
                Spacer().frame(height: 14)
                sentence
            }

            Spacer().frame(height: 16)

            HStack {
                Text(L10n.s(.weekTotal))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Self.duration(weekSeconds))
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }

            Spacer().frame(height: 12)
            Divider()
            Spacer().frame(height: 12)

            HStack {
                TextButton(L10n.s(.done), prominent: true, action: onClose)
                Spacer()
                TextButton(L10n.s(.settings), action: onSettings)
            }
        }
    }

    @ViewBuilder private var sentence: some View {
        if let best = result.best {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.s(.historyBest, Self.weekdayName(best.weekday), best.bandStartHour))
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                Text(L10n.s(.historyAdvice))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(L10n.s(.historyNotEnough))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    /// 요일 이름만은 Strings 표에 넣지 않고 시스템에서 가져온다.
    /// 21개 항목을 손으로 관리하는 대신 선택된 언어의 로케일을 넘긴다.
    /// README의 "문자열은 전부 표에" 규칙에 대한 의도적 예외다.
    static func weekdayName(_ mondayBased: Int, short: Bool = false) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: Prefs.language.rawValue)
        let symbols = short ? f.shortWeekdaySymbols! : f.weekdaySymbols!
        return symbols[(mondayBased + 1) % 7]     // 표의 0번은 일요일
    }

    static func duration(_ seconds: Int) -> String {
        let m = seconds / 60
        return m >= 60 ? L10n.s(.durationHM, m / 60, m % 60) : L10n.s(.durationM, m)
    }
}

/// 요일 × 시간대 격자. 색은 쓰지 않고 알파로만 강약을 준다 — 게이지와 같은 언어다.
private struct Heatmap: View {
    let rows: [Insight.Row]

    private static let alpha: [Double] = [0.15, 0.35, 0.65, 1.0]
    private let cell: CGFloat = 14
    private let gap: CGFloat = 3
    private let gutter: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: gap) {
            HStack(spacing: gap) {
                Spacer().frame(width: gutter)
                ForEach(0..<7, id: \.self) { i in
                    Text(HistoryView.weekdayName(i, short: true).prefix(1))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .frame(width: cell)
                }
            }
            ForEach(rows, id: \.bandStartHour) { row in
                HStack(spacing: gap) {
                    Text(String(format: "%02d", row.bandStartHour))
                        .font(.system(size: 9))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .frame(width: gutter, alignment: .trailing)
                    ForEach(Array(row.levels.enumerated()), id: \.offset) { _, level in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.primary.opacity(Self.alpha[level]))
                            .frame(width: cell, height: cell)
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 2: 빌드 확인**

Run: `./build.sh`

Expected: `빌드 완료`. `TextButton`은 `PopoverView.swift`에 `private`으로 있으므로 여기서 컴파일 오류가 난다.

- [ ] **Step 3: TextButton을 파일 밖에서 쓸 수 있게 하기**

`Sources/PopoverView.swift`에서 `private struct TextButton: View`를 아래로 바꾼다:

```swift
/// 테두리 없는 텍스트 버튼. 눌림 상태는 명도로만 표시한다.
/// 기록 화면도 같은 버튼을 쓰므로 파일 밖에서 보이게 둔다.
struct TextButton: View {
```

- [ ] **Step 4: 빌드 확인**

Run: `./build.sh`

Expected: `서명 검증 통과`, `빌드 완료`.

- [ ] **Step 5: 커밋**

```bash
git add Sources/HistoryView.swift Sources/PopoverView.swift
git commit -m "기록 화면 — 요일×시간대 격자와 한 문장"
```

---

### Task 11: 팝오버에 기록 화면 붙이기

**Files:**
- Modify: `Sources/PopoverView.swift`

- [ ] **Step 1: 화면 전환을 열거형으로 바꾸기**

`RootView`의 `@State private var showingSettings = false`를 아래로 바꾼다:

```swift
    enum Screen { case timer, settings, history }
    @State private var screen: Screen = .timer

    /// 기록 화면에 들어갈 때 한 번만 읽는다.
    /// RootView는 엔진을 관찰하므로, 여기서 바로 파일을 읽으면 타이머가 0.5초마다
    /// 틱할 때마다 디스크를 다시 긁는다.
    @State private var sessions: [Session] = []
```

`RootView`의 `body` 안 `Group { ... }` 전체를 아래로 바꾼다:

```swift
        Group {
            switch screen {
            case .settings:
                SettingsView(engine: engine,
                             onHotkeyToggle: onHotkeyToggle,
                             onQuit: onQuit,
                             onClose: { screen = .timer })
            case .history:
                HistoryView(sessions: sessions,
                            onClose: { screen = .timer },
                            onSettings: { screen = .settings })
            case .timer:
                TimerView(engine: engine,
                          onHistory: { sessions = SessionLog.load(); screen = .history },
                          onSettings: { screen = .settings })
            }
        }
```

- [ ] **Step 2: 타이머 화면에 기록 버튼 더하기**

`TimerView`의 `var onSettings: () -> Void` 위에 더한다:

```swift
    var onHistory: () -> Void
```

`TimerView` 맨 아래 `HStack { ... }`을 아래로 바꾼다:

```swift
            HStack(spacing: 12) {
                TextButton(L10n.s(engine.isRunning ? .stop : .start), prominent: true) {
                    engine.toggle()
                }
                Spacer()
                TextButton(L10n.s(.history), action: onHistory)
                TextButton(L10n.s(.settings), action: onSettings)
            }
```

- [ ] **Step 3: 빌드하고 실제로 눌러보기**

Run: `./build.sh && ./install.sh`

Expected: `실행 중 (PID ...)`.

메뉴바 아이콘을 눌러 팝오버를 연다. 확인할 것:

| 동작 | 기대 |
|---|---|
| 아래 버튼 | `시작` 왼쪽, `기록` `설정` 오른쪽 |
| `기록` 누르기 | 기록 화면으로 전환, 아직 데이터가 없으면 "아직 기록이 없습니다." |
| 타이머를 돌린 채 `기록` 열어두기 | 화면이 멈춰 있고 디스크를 다시 읽지 않는다 |
| 기록 화면의 `설정` | 설정 화면으로 전환 |
| 설정의 `완료` | 타이머 화면으로 |
| 팝오버 폭 | 240pt 그대로, 가로로 잘리는 것 없음 |

- [ ] **Step 4: 커밋**

```bash
git add Sources/PopoverView.swift
git commit -m "팝오버에 기록 화면 붙이기"
```

---

### Task 12: 기록을 실제로 파일에 적기

**Files:**
- Modify: `Sources/main.swift`

- [ ] **Step 1: 콜백 연결**

`wireEngine()`의 `engine.onComplete = { ... }` 블록 아래에 더한다:

```swift
        // 작업 세션이 끝날 때마다 파일에 한 줄 남긴다.
        engine.onWorkSessionEnded = { session in
            SessionLog.append(session)
        }
```

- [ ] **Step 2: 종료할 때도 남기기**

`popoverDidClose(_:)` 아래, 클래스 닫는 중괄호 앞에 더한다:

```swift

    /// 작업 중에 앱을 끄면 그때까지 한 만큼은 남긴다.
    /// stop()이 세션을 닫으면서 onWorkSessionEnded를 부른다.
    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
    }
```

- [ ] **Step 3: 빌드하고 실제로 기록되는지 보기**

Run: `./build.sh && ./install.sh`

작업 시간을 1분으로 내리고(설정에서 아래 화살표) 한 세션을 끝까지 돌린 뒤:

Run: `cat ~/Library/Application\ Support/Molip/sessions.jsonl`

Expected: 한 줄이 있고 `"seconds":60`, `"completed":true`, `start`에 `+09:00`처럼 오프셋이 붙어 있다.

이어서 새 세션을 시작하고 30초 뒤 `정지`를 누른다.

Run: `cat ~/Library/Application\ Support/Molip/sessions.jsonl | wc -l`

Expected: `1` — 60초 미만이라 남지 않는다.

다시 시작하고 70초쯤 지난 뒤 `정지`를 누른다.

Run: `tail -1 ~/Library/Application\ Support/Molip/sessions.jsonl`

Expected: `"completed":false`인 줄이 붙어 있다.

확인이 끝나면 작업 시간을 원래대로 되돌린다.

- [ ] **Step 4: 커밋**

```bash
git add Sources/main.swift
git commit -m "세션을 파일에 적고, 종료할 때도 남기기"
```

---

### Task 13: 문서와 마무리

**Files:**
- Modify: `README.md`

- [ ] **Step 1: 구성 표에 새 파일 더하기**

`README.md`의 `### 구성` 표에서 `| Notifier.swift | 알림 + 시스템 사운드 |` 아래에 더한다:

```markdown
| `SessionLog.swift` | 세션 기록 파일 읽고 쓰기 |
| `Insight.swift` | 기록 → 히트맵·최적 구간. 순수 함수 |
| `HistoryView.swift` | 기록 화면 |
```

- [ ] **Step 2: 기록 절 더하기**

`### 언어` 절 바로 앞에 더한다:

```markdown
### 기록

작업 세션만 `~/Library/Application Support/Molip/sessions.jsonl`에 한 줄씩 쌓는다.
휴식은 남기지 않는다. 60초 미만도 버린다 — 눌렀다 바로 끈 것까지 세면 그림이 흐려진다.

```
{"start":"2026-08-30T15:44:04+09:00","seconds":3000,"completed":true}
```

`start`에 로컬 오프셋을 붙여 적고, 요일과 시간대는 그 오프셋으로 센다.
다른 시간대로 옮겨가도 과거 기록이 다시 쓰이지 않는다.
`JSONEncoder`의 `.iso8601` 전략은 UTC로 적어 이 정보를 잃으므로 쓰지 않는다.

인사이트는 최근 8주만 본다. 습관이 바뀌면 화면도 따라 바뀐다.

문장은 두 문턱을 넘어야 나온다 — 창 안에 10세션 이상, 그리고 가장 큰 칸에 3세션 이상.
두 번 집중한 것을 두고 "화요일이 최적입니다"라고 단언하면 앱을 못 믿게 된다.
```

- [ ] **Step 3: 테스트 실행 방법 적기**

`README.md` 맨 위 실행 블록을 아래로 바꾼다:

```markdown
```
./build.sh       # 컴파일 → 번들 조립 → 애드혹 서명
./install.sh     # /Applications에 설치하고 실행
./tools/test.sh  # 순수 함수 테스트
```
```

- [ ] **Step 4: 전체 확인**

Run: `./tools/test.sh && ./build.sh`

Expected: 모든 스위트 통과, `빌드 완료`.

- [ ] **Step 5: 커밋**

```bash
git add README.md
git commit -m "기록 기능 문서화"
```

---

## 자기 점검 결과

설계 문서의 각 절이 계획에 들어갔는지 확인했다.

| 설계 항목 | 담당 Task |
|---|---|
| JSONL 형식, 오프셋 보존 | 2 |
| 파일 추가·읽기, 깨진 줄 | 3 |
| 기록 지점 넷, 60초 문턱 | 8, 12 |
| 버킷 7×8, 오프셋 기준 | 4 |
| 8주 창, 농도 4단계, 빈 행 숨김 | 5 |
| 최적 구간, 침묵 기준, 동점 | 6 |
| 이번 주 합계, 월요일 시작 | 7 |
| 화면과 버튼 | 10, 11 |
| 문자열 세 언어, 요일 예외 | 9, 10 |
| 검증 표 일곱 항목 | 4~7의 테스트 |
