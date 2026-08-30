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
