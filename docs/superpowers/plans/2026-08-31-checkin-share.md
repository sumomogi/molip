# 체크인과 공유 카드 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 사용자가 하루의 시작과 끝을 직접 찍고, 마감할 때 "근무 몇 시간 중 몰입 몇 시간"을 정사각 PNG로 만들어 클립보드에 올린다.

**Architecture:** `Workday`가 순수 계산(근무·몰입·비율)을 맡고, 열려 있는 체크인 시각 하나만 `UserDefaults`에 둔다. 근무 이력 파일은 만들지 않는다 — 몰입 시간은 기존 `sessions.jsonl`에서 구간을 걸러 계산한다. `ShareCard`가 PNG를 그리고, `CheckoutView`가 마감 화면을 그린다.

**Tech Stack:** Swift 5, SwiftUI, AppKit(`NSBitmapImageRep`, `NSPasteboard`). Xcode 없이 `swiftc`만. 외부 의존성 없음. 네트워크 코드 없음.

설계 문서: `docs/superpowers/specs/2026-08-31-checkin-share-design.md`

---

## 파일 구조

| 파일 | 책임 |
|---|---|
| `Sources/Workday.swift` | 근무·몰입·비율 계산, 오래된 체크인 판정. 순수 함수 |
| `Sources/ShareCard.swift` | 정사각 PNG 그리기, 클립보드에 올리기 |
| `Sources/CheckoutView.swift` | 마감 화면 |
| `Sources/Prefs.swift` | (수정) `checkedInAt` 키 하나 |
| `Sources/Strings.swift` | (수정) 문자열 7개 × 3언어 |
| `Sources/PopoverView.swift` | (수정) 근무 줄, `.checkout` 화면 |
| `Sources/main.swift` | (수정) 시작할 때 오래된 체크인 버리기 |
| `tools/tests/workday.swift` | 계산 검증 |
| `tools/tests/sharecard.swift` | PNG 렌더 검증 |

**의존 방향:** `CheckoutView` → `ShareCard` → `Workday` → `Session`. `Workday`는 파일도 UserDefaults도 모른다 — 그래서 가짜 세션 배열만으로 전부 검증된다.

---

### Task 0: 공통 타이포를 파일 밖에서 쓸 수 있게

앞선 브랜치의 최종 리뷰에서 나온 항목이다. `Font.caption11` / `Font.control`이
`PopoverView.swift`에 `private extension Font`로 묶여 있어 `HistoryView`가 폰트를
리터럴로 다시 적었다. 같은 문제를 `TextButton`에서는 풀었는데(주석까지 달아서)
폰트에서는 놓쳤다. 이번에 만들 `CheckoutView`와 근무 줄도 같은 폰트를 쓰므로
지금 푼다.

**Files:**
- Modify: `Sources/PopoverView.swift`
- Modify: `Sources/HistoryView.swift`

- [ ] **Step 1: private 벗기기**

`Sources/PopoverView.swift`의 `private extension Font`를 아래로 바꾼다:

```swift
/// 팝오버 전체가 쓰는 타이포. 기록·마감 화면도 같은 크기를 써야 하므로
/// 파일 밖에서 보이게 둔다 — TextButton과 같은 이유다.
extension Font {
```

- [ ] **Step 2: HistoryView의 리터럴을 바꾸기**

`Sources/HistoryView.swift`에서 폰트 리터럴을 공통 타이포로 바꾼다:

- `.font(.system(size: 11, weight: .medium))` → `.font(.caption11)`
- `.font(.system(size: 12))` → `.font(.control)`

`Heatmap` 안의 `size: 9` 두 곳은 그대로 둔다 — 격자 전용 크기라 공통 타이포에 없다.
필요하면 공통 타이포에 항목을 더하지 말고 그 자리에 두는 편이 낫다.

- [ ] **Step 3: 확인**

Run: `./tools/test.sh && ./build.sh`

Expected: 모든 스위트 통과, `빌드 완료`.

`grep -n "system(size: 11\|system(size: 12" Sources/HistoryView.swift` 가 아무것도
찾지 못해야 한다.

- [ ] **Step 4: 커밋**

```bash
git add Sources/PopoverView.swift Sources/HistoryView.swift
git commit -m "공통 타이포를 팝오버 전체가 쓰도록 공개"
```

---

### Task 1: 근무·몰입 계산

**Files:**
- Create: `Sources/Workday.swift`
- Create: `tools/tests/workday.swift`

- [ ] **Step 1: 실패하는 테스트 먼저**

`tools/tests/workday.swift`:

```swift
import Foundation

@main struct WorkdayTests {
    static func main() {
        func sess(_ iso: String, _ seconds: Int) -> Session {
            SessionLog.session(from: "{\"start\":\"\(iso)\",\"seconds\":\(seconds),\"completed\":true}")!
        }
        func at(_ iso: String) -> Date { sess(iso, 60).start }

        let inAt  = at("2026-08-31T09:00:00+09:00")
        let outAt = at("2026-08-31T17:00:00+09:00")     // 8시간 = 28800초

        let sessions = [
            sess("2026-08-31T08:30:00+09:00", 1800),    // 체크인 전 — 제외
            sess("2026-08-31T09:00:00+09:00", 3000),    // 체크인과 같은 시각 — 포함
            sess("2026-08-31T13:00:00+09:00", 3000),    // 구간 안 — 포함
            sess("2026-08-31T18:00:00+09:00", 3000),    // 체크아웃 후 — 제외
        ]

        let d = Workday.make(checkedIn: inAt, checkedOut: outAt, sessions: sessions)
        T.eq("근무 초", d.workSeconds, 28800)
        T.eq("몰입 초는 구간 안만", d.focusSeconds, 6000)
        T.eq("비율", Int((d.ratio * 100).rounded()), 21)

        // 세션이 하나도 없는 하루
        let empty = Workday.make(checkedIn: inAt, checkedOut: outAt, sessions: [])
        T.eq("세션 0이면 몰입 0", empty.focusSeconds, 0)
        T.eq("세션 0이면 비율 0", empty.ratio, 0)

        // 체크인 직후 체크아웃 — 0으로 나누지 않는다
        let instant = Workday.make(checkedIn: inAt, checkedOut: inAt, sessions: sessions)
        T.eq("근무 0초면 비율 0", instant.ratio, 0)

        // 몰입이 근무보다 길어도 1.0에서 멈춘다
        let short = Workday.make(checkedIn: inAt,
                                 checkedOut: at("2026-08-31T09:10:00+09:00"),
                                 sessions: sessions)
        T.eq("비율은 1.0을 넘지 않는다", short.ratio, 1.0)

        // 거꾸로 찍힌 시각도 음수 근무가 되지 않는다
        let reversed = Workday.make(checkedIn: outAt, checkedOut: inAt, sessions: [])
        T.eq("역전된 시각은 근무 0", reversed.workSeconds, 0)

        T.finish()
    }
}
```

- [ ] **Step 2: 돌려서 실패 확인**

Run: `./tools/test.sh`

Expected: 컴파일 실패 — `cannot find 'Workday' in scope`.

- [ ] **Step 3: 구현**

`Sources/Workday.swift`:

```swift
import Foundation

/// 하루의 근무와 몰입. 체크인·체크아웃 시각과 세션 배열만 있으면 나머지는 계산이다.
/// 파일도 설정 저장소도 모른다 — 그래서 가짜 배열만으로 검증된다.
struct Workday: Equatable {
    let checkedIn: Date
    let checkedOut: Date
    let workSeconds: Int
    let focusSeconds: Int

    /// 몰입이 근무에서 차지하는 비율. 0...1.
    ///
    /// 1.0에서 자른다. 체크인을 늦게 찍었거나 시계가 튀면 몰입이 근무보다 길어질 수
    /// 있는데, 101%는 사람을 혼란스럽게 할 뿐이다.
    var ratio: Double {
        guard workSeconds > 0 else { return 0 }
        return min(1, Double(focusSeconds) / Double(workSeconds))
    }

    /// 세션은 **시작 시각**이 구간 안에 있으면 통째로 센다.
    /// 끝에 걸친 세션을 잘라 세지 않는 이유는, 체크아웃이 먼저 돌고 있던 세션을
    /// 닫기 때문에 그런 세션이 실제로는 생기지 않아서다.
    static func make(checkedIn: Date, checkedOut: Date, sessions: [Session]) -> Workday {
        let elapsed = checkedOut.timeIntervalSince(checkedIn)
        let work = max(0, Int(elapsed.rounded()))
        let focus = sessions
            .filter { $0.start >= checkedIn && $0.start <= checkedOut }
            .reduce(0) { $0 + $1.seconds }
        return Workday(checkedIn: checkedIn, checkedOut: checkedOut,
                       workSeconds: work, focusSeconds: focus)
    }

    /// 어제 이전에 찍힌 체크인은 버린다.
    ///
    /// "근무 31시간"이라 적힌 카드를 공개적으로 올리는 것보다 그날 숫자를 잃는 편이 낫다.
    /// 자정을 넘겨 일하고 그 사이 앱까지 재시작한 경우에만 손해를 본다.
    static func isStale(_ checkedIn: Date, now: Date, calendar: Calendar = .current) -> Bool {
        !calendar.isDate(checkedIn, inSameDayAs: now)
    }

    /// h:mm. 카드와 마감 화면의 큰 숫자에 쓴다.
    static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 3600, (seconds % 3600) / 60)
    }
}
```

- [ ] **Step 4: 돌려서 통과 확인**

Run: `./tools/test.sh`

Expected: `workday` 스위트가 `전부 통과`.

- [ ] **Step 5: 커밋**

```bash
git add Sources/Workday.swift tools/tests/workday.swift
git commit -m "근무·몰입 계산과 오래된 체크인 판정"
```

---

### Task 2: 체크인 상태 저장

**Files:**
- Modify: `Sources/Prefs.swift`
- Modify: `tools/tests/workday.swift`

- [ ] **Step 1: 실패하는 테스트 추가**

`tools/tests/workday.swift`의 `T.finish()` 앞에 넣는다:

```swift
        // 오래된 체크인 판정. 달력은 서울 기준으로 고정해 기기 설정에 흔들리지 않게 한다.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!

        T.ok("같은 날이면 살아있다",
             !Workday.isStale(at("2026-08-31T09:00:00+09:00"),
                              now: at("2026-08-31T23:59:00+09:00"), calendar: cal))
        T.ok("전날이면 버린다",
             Workday.isStale(at("2026-08-30T23:00:00+09:00"),
                             now: at("2026-08-31T00:30:00+09:00"), calendar: cal))
```

- [ ] **Step 2: 돌려서 실패 확인**

Run: `./tools/test.sh`

Expected: 이미 Task 1에서 `isStale`을 만들었으므로 이 두 줄은 바로 통과한다. 통과하지 않으면 `isStale`의 기준이 잘못된 것이므로 멈추고 보고한다.

- [ ] **Step 3: Prefs에 키 더하기**

`Sources/Prefs.swift`의 `enum Key` 안에 더한다:

```swift
        static let checkedIn = "checkedInAt"
```

`hotkeyEnabled` 아래에 더한다:

```swift
    /// 열려 있는 체크인 시각. 체크아웃하면 지운다.
    /// 하루가 열려 있는지 여부가 이 값 하나로 표현된다.
    static var checkedInAt: Date? {
        get { d.object(forKey: Key.checkedIn) as? Date }
        set {
            if let v = newValue { d.set(v, forKey: Key.checkedIn) }
            else { d.removeObject(forKey: Key.checkedIn) }
        }
    }
```

`registerDefaults()`에는 넣지 않는다 — 기본값이 "없음"이어야 한다.

- [ ] **Step 4: 시작할 때 오래된 체크인 버리기**

`Sources/main.swift`의 `applicationDidFinishLaunching`에서 `notifier.requestAuthorization()` 위에 넣는다:

```swift
        // 어제 이전에 찍힌 체크인은 버린다. Workday.isStale의 주석 참고.
        if let open = Prefs.checkedInAt, Workday.isStale(open, now: Date()) {
            Prefs.checkedInAt = nil
        }
```

- [ ] **Step 5: 돌려서 통과 확인**

Run: `./tools/test.sh && ./build.sh`

Expected: 모든 스위트 통과, `빌드 완료`.

- [ ] **Step 6: 커밋**

```bash
git add Sources/Prefs.swift Sources/main.swift tools/tests/workday.swift
git commit -m "체크인 시각 저장과 시작 시 정리"
```

---

### Task 3: 문자열 일곱 개

**Files:**
- Modify: `Sources/Strings.swift`

- [ ] **Step 1: 키 더하기**

`enum Key`의 `// 기록 화면` 블록 아래에 더한다:

```swift
        // 체크인·마감
        case checkIn, checkOut, onDuty, closing, copyImage, copied
        case cardSummary
```

- [ ] **Step 2: 세 언어 채우기**

`.ko` 표의 `.durationM` 줄 아래:

```swift
            .checkIn: "체크인",
            .checkOut: "체크아웃",
            .onDuty: "근무",
            .closing: "마감",
            .copyImage: "이미지 복사",
            .copied: "복사됨",
            .cardSummary: "근무 %1$@ 중 %2$d%%",
```

`.en` 표의 같은 자리:

```swift
            .checkIn: "Check in",
            .checkOut: "Check out",
            .onDuty: "On duty",
            .closing: "Wrap up",
            .copyImage: "Copy image",
            .copied: "Copied",
            .cardSummary: "%2$d%% of %1$@ on duty",
```

`.ja` 표의 같은 자리:

```swift
            .checkIn: "チェックイン",
            .checkOut: "チェックアウト",
            .onDuty: "勤務",
            .closing: "締め",
            .copyImage: "画像をコピー",
            .copied: "コピーしました",
            .cardSummary: "勤務 %1$@ のうち %2$d%%",
```

기존 `.work`("집중")를 재사용하지 않는다. 그건 설정 화면의 집중 길이 라벨이고,
`onDuty`는 다른 대상이다.

`%%`는 `String(format:)`에서 퍼센트 기호 하나로 풀린다.

- [ ] **Step 3: 돌려서 통과 확인**

Run: `./tools/test.sh`

Expected: `strings` 스위트가 세 언어 모두 통과. 한 언어라도 빠지면 `L10n.raw` 검사가 그 키 이름을 찍으며 실패한다.

- [ ] **Step 4: `%%`가 실제로 풀리는지 확인**

임시 확인용으로 아래를 돌려 결과를 눈으로 본다 (커밋하지 않는다):

```bash
D=$(mktemp -d); cat > "$D/main.swift" <<'SWIFT'
import Foundation
print(String(format: "근무 %1$@ 중 %2$d%%", "8시간 12분", 51))
print(String(format: "%2$d%% of %1$@ on duty", "8h 12m", 51))
SWIFT
swiftc -wmo -o "$D/drv" "$D/main.swift" && "$D/drv"; rm -rf "$D"
```

Expected: `근무 8시간 12분 중 51%` 와 `51% of 8h 12m on duty`.

- [ ] **Step 5: 커밋**

```bash
git add Sources/Strings.swift
git commit -m "체크인·마감 문자열"
```

---

### Task 4: 공유 카드 그리기

**Files:**
- Create: `Sources/ShareCard.swift`
- Create: `tools/tests/sharecard.swift`

- [ ] **Step 1: 실패하는 테스트 먼저**

`tools/tests/sharecard.swift`:

```swift
import Foundation
import AppKit

@main struct ShareCardTests {
    static func main() {
        func at(_ iso: String) -> Date {
            SessionLog.session(from: "{\"start\":\"\(iso)\",\"seconds\":60,\"completed\":true}")!.start
        }
        let day = Workday(checkedIn: at("2026-08-31T09:00:00+09:00"),
                          checkedOut: at("2026-08-31T17:12:00+09:00"),
                          workSeconds: 29520, focusSeconds: 15000)

        guard let png = ShareCard.png(for: day) else {
            T.ok("PNG가 만들어진다", false)
            T.finish()
        }
        T.ok("PNG가 만들어진다", true)

        let rep = NSBitmapImageRep(data: png)
        T.eq("가로", rep?.pixelsWide, 1080)
        T.eq("세로", rep?.pixelsHigh, 1080)

        // 배경만 있는 빈 카드가 아닌지 — 배경과 다른 픽셀이 있어야 한다.
        var drawn = false
        if let rep {
            let bg = rep.colorAt(x: 4, y: 4)
            outer: for x in stride(from: 0, to: 1080, by: 17) {
                for y in stride(from: 0, to: 1080, by: 17) {
                    if let c = rep.colorAt(x: x, y: y), c != bg { drawn = true; break outer }
                }
            }
        }
        T.ok("빈 카드가 아니다", drawn)

        T.finish()
    }
}
```

- [ ] **Step 2: 돌려서 실패 확인**

Run: `./tools/test.sh`

Expected: 컴파일 실패 — `cannot find 'ShareCard' in scope`.

- [ ] **Step 3: 구현**

`Sources/ShareCard.swift`:

```swift
import AppKit

/// 공유용 정사각 카드. 앱과 같은 언어로 — 색 없이 명도만 쓴다.
///
/// 여기서만은 시스템 시맨틱 컬러를 쓰지 않고 값을 고정한다. 내보낸 이미지에는
/// 따라갈 라이트/다크가 없고, 받는 쪽 화면이 어떻든 같게 보여야 하기 때문이다.
enum ShareCard {

    static let side = 1080

    private static let ink = NSColor.black
    private static let paper = NSColor.white

    /// 헤드리스에서도 그려지도록 lockFocus 대신 비트맵에 직접 그린다.
    static func png(for day: Workday) -> Data? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        draw(day)
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .png, properties: [:])
    }

    private static func draw(_ day: Workday) {
        let s = CGFloat(side)
        let margin: CGFloat = 96

        paper.setFill()
        NSRect(x: 0, y: 0, width: s, height: s).fill()

        // 좌표 원점은 좌하단이다. 위에서부터 쌓기 위해 y를 내려가며 잡는다.
        var y = s - margin

        y -= 40
        text(dateLine(day.checkedIn), at: NSPoint(x: margin, y: y),
             size: 34, weight: .medium, alpha: 0.55)

        y -= 210
        text(Workday.clock(day.focusSeconds), at: NSPoint(x: margin, y: y),
             size: 190, weight: .thin, alpha: 1.0)

        y -= 60
        text(L10n.s(.phaseWork), at: NSPoint(x: margin, y: y),
             size: 40, weight: .medium, alpha: 0.55)

        y -= 150
        bar(ratio: day.ratio, at: NSPoint(x: margin, y: y), width: s - margin * 2)

        y -= 70
        let work = duration(day.workSeconds)
        let pct = Int((day.ratio * 100).rounded())
        text(L10n.s(.cardSummary, work, pct), at: NSPoint(x: margin, y: y),
             size: 38, weight: .regular, alpha: 0.55)

        // 오른쪽 아래 워드마크. 앱 이름이라 번역하지 않는다.
        let mark = "몰입"
        let markSize = measure(mark, size: 34, weight: .medium)
        text(mark, at: NSPoint(x: s - margin - markSize.width, y: margin),
             size: 34, weight: .medium, alpha: 0.25)
    }

    /// 채운 만큼과 빈 만큼을 알파로만 나눈다. 게이지와 같은 방식이다.
    private static func bar(ratio: Double, at origin: NSPoint, width: CGFloat) {
        let height: CGFloat = 26
        ink.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: NSRect(x: origin.x, y: origin.y, width: width, height: height),
                     xRadius: height / 2, yRadius: height / 2).fill()

        let filled = width * CGFloat(min(max(ratio, 0), 1))
        guard filled > 0 else { return }
        ink.withAlphaComponent(1.0).setFill()
        NSBezierPath(roundedRect: NSRect(x: origin.x, y: origin.y, width: max(filled, height), height: height),
                     xRadius: height / 2, yRadius: height / 2).fill()
    }

    private static func attributes(size: CGFloat, weight: NSFont.Weight, alpha: CGFloat)
        -> [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: size, weight: weight),
         .foregroundColor: ink.withAlphaComponent(alpha)]
    }

    private static func text(_ s: String, at p: NSPoint, size: CGFloat,
                             weight: NSFont.Weight, alpha: CGFloat) {
        s.draw(at: p, withAttributes: attributes(size: size, weight: weight, alpha: alpha))
    }

    private static func measure(_ s: String, size: CGFloat, weight: NSFont.Weight) -> NSSize {
        s.size(withAttributes: attributes(size: size, weight: weight, alpha: 1))
    }

    /// 선택된 언어로 날짜와 요일. 요일 이름과 같은 이유로 시스템에서 가져온다.
    private static func dateLine(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: Prefs.language.rawValue)
        f.setLocalizedDateFormatFromTemplate("yMMMdEEE")
        return f.string(from: date)
    }

    private static func duration(_ seconds: Int) -> String {
        let m = seconds / 60
        return m >= 60 ? L10n.s(.durationHM, m / 60, m % 60) : L10n.s(.durationM, m)
    }
}
```

- [ ] **Step 4: 돌려서 통과 확인**

Run: `./tools/test.sh`

Expected: `sharecard` 스위트가 `전부 통과`.

- [ ] **Step 5: 눈으로 한 번 보기**

임시로 PNG를 뽑아 실제로 열어본다:

```bash
D=$(mktemp -d); cat > "$D/main.swift" <<'SWIFT'
import Foundation
let day = Workday(checkedIn: Date(), checkedOut: Date().addingTimeInterval(29520),
                  workSeconds: 29520, focusSeconds: 15000)
if let png = ShareCard.png(for: day) {
    try? png.write(to: URL(fileURLWithPath: "/tmp/molip-card.png"))
    print("wrote /tmp/molip-card.png", png.count, "bytes")
}
SWIFT
SRC=$(ls Sources/*.swift | grep -v '/main\.swift$')
swiftc -wmo -o "$D/drv" $SRC "$D/main.swift" && "$D/drv"; rm -rf "$D"
```

`/tmp/molip-card.png`를 남겨두고 보고에 경로를 적는다. 사람이 열어볼 것이다.

- [ ] **Step 6: 커밋**

```bash
git add Sources/ShareCard.swift tools/tests/sharecard.swift
git commit -m "공유 카드 — 무채색 정사각 PNG"
```

---

### Task 5: 타이머 화면의 근무 줄

**Files:**
- Modify: `Sources/PopoverView.swift`

- [ ] **Step 1: 근무 줄 부품 만들기**

`Sources/PopoverView.swift`의 `// MARK: - 부품` 아래에 더한다:

```swift
/// 근무 상태 한 줄. 설정 행들과 같은 골격 — 왼쪽 라벨, 오른쪽 컨트롤.
///
/// 아래 버튼 줄이 이미 셋이라 넷째를 넣으면 영어에서 240pt를 넘긴다.
/// 그래서 근무는 자기 줄을 갖는다.
private struct DutyRow: View {
    let checkedInAt: Date?
    let now: Date
    var onToggle: () -> Void

    var body: some View {
        HStack {
            if let inAt = checkedInAt {
                Text("\(L10n.s(.onDuty)) \(Workday.clock(max(0, Int(now.timeIntervalSince(inAt)))))")
                    .font(.control)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Spacer()
            TextButton(L10n.s(checkedInAt == nil ? .checkIn : .checkOut), action: onToggle)
        }
        .frame(height: 22)
    }
}
```

- [ ] **Step 2: 타이머 화면에 끼우기**

`TimerView`에 프로퍼티를 더한다 (`var onHistory` 위):

```swift
    let checkedInAt: Date?
    /// 분이 바뀔 때만 갱신된다. 초 단위로 움직이면 곁눈에 걸린다.
    let dutyTick: Date
    var onDutyToggle: () -> Void
```

`TimerView`의 `Text(L10n.s(.set, ...))` 블록과 그 아래 `Spacer().frame(height: 16)` 사이,
즉 세트 표시 다음에 넣는다:

```swift
            Spacer().frame(height: 10)

            DutyRow(checkedInAt: checkedInAt, now: dutyTick, onToggle: onDutyToggle)
```

- [ ] **Step 3: RootView에서 상태 잇기**

`RootView`에 더한다:

```swift
    @State private var checkedInAt: Date? = Prefs.checkedInAt
    /// 근무 시간 표시를 분 단위로만 갱신하기 위한 시계.
    @State private var dutyTick = Date()
```

`Screen` 열거형에 `checkout`을 더한다:

```swift
    enum Screen { case timer, settings, history, checkout }
```

`.timer` 분기를 아래로 바꾼다:

```swift
            case .timer:
                TimerView(engine: engine,
                          checkedInAt: checkedInAt,
                          dutyTick: dutyTick,
                          onDutyToggle: toggleDuty,
                          onHistory: { sessions = SessionLog.load(); screen = .history },
                          onSettings: { screen = .settings })
```

`RootView`에 메서드를 더한다:

```swift
    /// 체크인은 그 자리에서 열고, 체크아웃은 마감 화면으로 넘긴다.
    private func toggleDuty() {
        if checkedInAt == nil {
            let now = Date()
            Prefs.checkedInAt = now
            checkedInAt = now
        } else {
            engine.stop()                 // 돌고 있던 세션을 먼저 닫아 오늘 몫에 넣는다
            sessions = SessionLog.load()
            checkedOutAt = Date()
            screen = .checkout
        }
    }
```

그리고 마감에 필요한 상태를 더한다:

```swift
    @State private var checkedOutAt = Date()
```

`body`의 `.onChange` 아래에 1분짜리 시계를 붙인다:

```swift
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { t in
            dutyTick = t
        }
```

`import Combine`이 필요하면 파일 맨 위에 더한다.

- [ ] **Step 4: 빌드**

Run: `./build.sh`

Expected: `.checkout` 분기가 없어 `switch must be exhaustive` 오류가 난다. 다음 작업에서 채운다.
임시로 `case .checkout: EmptyView()`를 넣어 빌드를 통과시키고, 다음 작업에서 교체한다.

- [ ] **Step 5: 돌려서 확인하고 커밋**

Run: `./tools/test.sh && ./build.sh`

```bash
git add Sources/PopoverView.swift
git commit -m "타이머 화면에 근무 줄"
```

---

### Task 6: 마감 화면

**Files:**
- Create: `Sources/CheckoutView.swift`
- Modify: `Sources/PopoverView.swift`

- [ ] **Step 1: 화면 만들기**

`Sources/CheckoutView.swift`:

```swift
import SwiftUI

/// 마감 화면. 복사하기 전에 숫자를 눈으로 보고, 공유하지 않고 닫을 수도 있어야 한다.
struct CheckoutView: View {
    let day: Workday
    var onClose: () -> Void

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            Text(L10n.s(.closing))
                .font(.system(size: 11, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(.tertiary)

            Spacer().frame(height: 14)

            Text(Workday.clock(day.workSeconds))
                .font(.system(size: 40, weight: .thin).monospacedDigit())
                .foregroundStyle(.primary)

            Text(L10n.s(.onDuty))
                .font(.system(size: 11, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(.tertiary)

            Spacer().frame(height: 16)

            RatioBar(ratio: day.ratio)

            Spacer().frame(height: 10)

            Text("\(L10n.s(.phaseWork)) \(Workday.clock(day.focusSeconds)) · \(Int((day.ratio * 100).rounded()))%")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Spacer().frame(height: 14)

            Text("\(Self.hm(day.checkedIn)) – \(Self.hm(day.checkedOut))")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.tertiary)

            Spacer().frame(height: 12)
            Divider()
            Spacer().frame(height: 12)

            HStack {
                TextButton(L10n.s(.done), prominent: true, action: onClose)
                Spacer()
                TextButton(L10n.s(copied ? .copied : .copyImage)) {
                    ShareCard.copyToPasteboard(day)
                    copied = true
                }
            }
        }
    }

    private static func hm(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: Prefs.language.rawValue)
        f.setLocalizedDateFormatFromTemplate("Hm")
        return f.string(from: d)
    }
}

/// 마감 화면의 가로 막대. 게이지와 같은 알파 언어를 쓴다.
private struct RatioBar: View {
    let ratio: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule().fill(Color.primary)
                    .frame(width: max(geo.size.width * CGFloat(min(max(ratio, 0), 1)), 0))
            }
        }
        .frame(height: 10)
    }
}
```

- [ ] **Step 2: 클립보드에 올리는 함수 더하기**

`Sources/ShareCard.swift`의 닫는 중괄호 앞에 더한다:

```swift

    /// 클립보드에 이미지로 올린다. 어디에 올릴지는 사용자 손에 남는다.
    /// 공유 시트를 쓰지 않는 이유는 설계 문서에 적어뒀다.
    @discardableResult
    static func copyToPasteboard(_ day: Workday) -> Bool {
        guard let png = png(for: day), let image = NSImage(data: png) else { return false }
        let pb = NSPasteboard.general
        pb.clearContents()
        return pb.writeObjects([image])
    }
```

- [ ] **Step 3: 팝오버에 연결**

`Sources/PopoverView.swift`의 `case .checkout: EmptyView()`를 아래로 바꾼다:

```swift
            case .checkout:
                CheckoutView(day: Workday.make(checkedIn: checkedOutFrom,
                                               checkedOut: checkedOutAt,
                                               sessions: sessions),
                             onClose: {
                                 Prefs.checkedInAt = nil
                                 checkedInAt = nil
                                 screen = .timer
                             })
```

`toggleDuty()`에서 체크아웃 분기에 시작 시각을 남긴다. `checkedOutFrom` 상태를 더한다:

```swift
    @State private var checkedOutFrom = Date()
```

그리고 `toggleDuty()`의 `else` 분기 첫 줄에 넣는다:

```swift
            checkedOutFrom = checkedInAt ?? Date()
```

**체크인은 마감 화면을 닫을 때 비운다.** 체크아웃을 누른 뒤 마감 화면을 보는 동안에는
아직 값이 남아 있어야 카드를 다시 그릴 수 있다.

- [ ] **Step 4: 빌드하고 설치**

Run: `./tools/test.sh && ./build.sh && ./install.sh`

Expected: 모든 스위트 통과, `실행 중 (PID ...)`.

- [ ] **Step 5: 커밋**

```bash
git add Sources/CheckoutView.swift Sources/ShareCard.swift Sources/PopoverView.swift
git commit -m "마감 화면과 클립보드 복사"
```

---

### Task 7: 문서

**Files:**
- Modify: `README.md`

- [ ] **Step 1: 구성 표에 더하기**

`### 구성` 표의 `| HistoryView.swift | 기록 화면 |` 아래에 더한다:

```markdown
| `Workday.swift` | 근무·몰입 계산. 순수 함수 |
| `ShareCard.swift` | 공유용 정사각 PNG |
| `CheckoutView.swift` | 마감 화면 |
```

- [ ] **Step 2: 절 더하기**

`### 언어` 절 앞에 더한다. 아래 내용을 **코드와 대조해 사실을 확인한 뒤** 적는다:

```markdown
### 체크인

하루의 시작과 끝은 사용자가 직접 찍는다. 자동으로 잡지 않는다 — 커피 내리고
메일 보는 시간도 근무이고, 그 경계는 앱이 알 수 없다.

열려 있는 체크인 시각 하나만 `UserDefaults`에 둔다. 근무 이력 파일은 만들지 않는다.
몰입 시간은 `sessions.jsonl`에서 그 구간에 시작한 세션을 걸러 더한다.

체크아웃을 잊고 앱을 다시 켜면, 어제 이전에 찍힌 체크인은 조용히 버린다.
"근무 31시간"이라 적힌 카드를 올리는 것보다 그날 숫자를 잃는 편이 낫다.

마감 화면에서 `이미지 복사`를 누르면 1080×1080 PNG가 클립보드에 올라간다.
공유 시트를 쓰지 않는다 — 요즘 macOS 공유 시트에는 SNS가 거의 없고, 클립보드는
어디에든 붙일 수 있으며 올리기 전에 내용을 한 번 더 보게 된다.

네트워크 코드도 API 키도 없다.
```

- [ ] **Step 3: 앞 기능에서 빠진 두 줄 채우기**

최종 리뷰에서 나온 README 누락이다. `### 기록` 절에 더한다:

```markdown
작업 중에 앱을 끄면 그때까지 한 만큼이 `completed: false`로 남는다.

`completed`는 인사이트 계산에 쓰지 않는다. 파일을 직접 열어 보는 사람을 위해
남기는 값이다 — 끝까지 간 세션과 중간에 끊은 세션을 눈으로 구분할 수 있어야 한다.
```

두 문장 모두 코드와 대조해 사실을 확인한 뒤 적는다
(`Sources/main.swift`의 `applicationWillTerminate`, 그리고 `Insight`가
`completed`를 읽는지 `grep`으로 확인).

- [ ] **Step 4: 알아둘 것에 한 줄**

`## 알아둘 것`에 더한다:

```markdown
**카드 색은 고정값이다.** 앱 안에서는 시스템 시맨틱 컬러만 쓰지만, 내보낸 이미지에는
따라갈 라이트/다크가 없다. 받는 쪽 화면이 어떻든 같게 보여야 하므로 `ShareCard`에서만
흑백을 직접 지정한다.
```

- [ ] **Step 5: 확인하고 커밋**

Run: `./tools/test.sh && ./build.sh`

```bash
git add README.md
git commit -m "체크인 기능 문서화"
```

---

## 자기 점검 결과

| 설계 항목 | 담당 Task |
|---|---|
| 근무·몰입·비율 계산, 경계 | 1 |
| 비율 상한, 0으로 나누기 | 1 |
| 오래된 체크인 판정 | 1, 2 |
| 체크인 상태 저장, 시작 시 정리 | 2 |
| 문자열 세 언어 | 3 |
| 카드 그리기, 고정 색 | 4 |
| 타이머 화면 근무 줄, 분 단위 갱신 | 5 |
| 마감 화면, 복사됨 표시 | 6 |
| 클립보드 | 6 |
| 문서 | 7 |
| 공통 타이포 공개 (앞 리뷰 지적) | 0 |
| README 누락 두 줄 (앞 리뷰 지적) | 7 |
