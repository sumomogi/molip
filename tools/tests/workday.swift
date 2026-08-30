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

        // 오래된 체크인 판정. 달력은 서울 기준으로 고정해 기기 설정에 흔들리지 않게 한다.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!

        T.ok("같은 날이면 살아있다",
             !Workday.isStale(at("2026-08-31T09:00:00+09:00"),
                              now: at("2026-08-31T23:59:00+09:00"), calendar: cal))
        T.ok("전날이면 버린다",
             Workday.isStale(at("2026-08-30T23:00:00+09:00"),
                             now: at("2026-08-31T00:30:00+09:00"), calendar: cal))

        T.finish()
    }
}
