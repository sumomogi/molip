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
