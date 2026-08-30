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

        // 컷오프 정확히 그 순간의 세션도 포함해야 한다 (>= 이므로).
        let cutoff = now.addingTimeInterval(-Double(Insight.windowDays) * 86400)
        let onCutoff = Session(start: cutoff, offsetSeconds: 9 * 3600, seconds: 100, completed: true)
        T.eq("컷오프 순간도 창 안", Insight.make(sessions: [onCutoff], now: now).sessionCount, 1)

        // 반복되는 습관이 어쩌다 한 번의 긴 세션에 가려지면 안 된다 —
        // 평일 아침 50분씩 5번 + 일요일 4시간 1번.
        let routine = [sess("2026-08-31T09:00:00+09:00", 3000), // 월
                       sess("2026-09-01T09:00:00+09:00", 3000), // 화
                       sess("2026-09-02T09:00:00+09:00", 3000), // 수
                       sess("2026-09-03T09:00:00+09:00", 3000), // 목
                       sess("2026-09-04T09:00:00+09:00", 3000), // 금
                       sess("2026-09-06T09:00:00+09:00", 14400)] // 일, 4시간짜리 한 번
        let routineRow = Insight.make(sessions: routine, now: now).rows[0]
        T.ok("반복 습관이 이상치 하나에 눌리지 않는다",
             routineRow.levels[0...4].allSatisfy { $0 > 1 })

        // 같은 칸이라도 기록 당시 오프셋이 다른 세션들을 합산해야 한다.
        let mixedOffsets = [sess("2026-08-31T09:00:00+09:00", 1000),
                            sess("2026-08-31T09:30:00-05:00", 2000)]
        T.eq("오프셋이 달라도 같은 칸이면 합산", Insight.make(sessions: mixedOffsets, now: now).rows[0].levels[0], 3)

        // 새 사용자의 첫 화면 — 빈 배열이 죽지 않고 빈 결과를 낸다.
        let empty = Insight.make(sessions: [], now: now)
        T.eq("빈 배열은 빈 행", empty.rows, [])
        T.eq("빈 배열은 0건", empty.sessionCount, 0)

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

        // 합계가 가장 큰 칸이라도 세션이 2번뿐이면 후보에서 빠지고,
        // 세션이 꾸준히 쌓인 다른 칸이 뽑혀야 한다 — 합계로 먼저 줄 세우고
        // 나서 문턱에 걸면, 어쩌다 길게 두 번 한 칸 때문에 앱이 통째로 침묵하게 된다.
        var thinPeakVsSteady = [sess("2026-08-25T15:30:00+09:00", 6000),
                                 sess("2026-09-01T15:30:00+09:00", 6000)]        // 화 15시, 합 12000, 2세션
        for d in [22, 29] { thinPeakVsSteady.append(sess("2026-07-\(d)T09:30:00+09:00", 1000)) }
        for d in [5, 12, 19, 26] { thinPeakVsSteady.append(sess("2026-08-\(d)T09:30:00+09:00", 1000)) }
        thinPeakVsSteady.append(sess("2026-09-02T09:30:00+09:00", 1000))         // 수 09시, 합 7000, 7세션
        thinPeakVsSteady.append(sess("2026-08-27T00:30:00+09:00", 100))          // 목 00시, 1세션 — 그냥 채우기용

        let steady = Insight.make(sessions: thinPeakVsSteady, now: later)
        T.eq("얇은 최댓값 대신 세션이 쌓인 칸 요일", steady.best?.weekday, 2)     // 수요일
        T.eq("얇은 최댓값 대신 세션이 쌓인 칸 시간", steady.best?.bandStartHour, 9)

        // 같은 요일 안에서 두 시간대가 합계로 동점이면 이른 시간대가 이긴다.
        var sameWeekdayTied: [Session] = []
        for date in ["2026-08-25", "2026-09-01", "2026-09-08"] {
            sameWeekdayTied.append(sess("\(date)T06:30:00+09:00", 1200))         // 화 06시, 합 3600
            sameWeekdayTied.append(sess("\(date)T15:30:00+09:00", 1200))         // 화 15시, 합 3600
        }
        for date in ["2026-08-21", "2026-08-28", "2026-09-04", "2026-09-11"] {
            sameWeekdayTied.append(sess("\(date)T21:30:00+09:00", 10))           // 금 21시, 채우기용
        }
        let sameWeekday = Insight.make(sessions: sameWeekdayTied, now: later)
        T.eq("같은 요일 동점은 이른 시간대", sameWeekday.best?.weekday, 1)        // 화요일
        T.eq("같은 요일 동점 — 이른 밴드", sameWeekday.best?.bandStartHour, 6)

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

        T.finish()
    }
}
