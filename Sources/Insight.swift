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

    /// 집계 범위. 습관이 바뀌면 화면도 따라 바뀌게 최근 것만 본다.
    static let windowDays = 56

    /// 화면에 그릴 한 행.
    struct Row: Equatable {
        let bandStartHour: Int
        /// 월~일 7칸. 각 칸은 농도 단계 0...3.
        let levels: [Int]
    }

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

        let densityReference = reference(of: totals.flatMap { $0 })
        var rows: [Row] = []
        for band in 0..<bandCount where totals[band].contains(where: { $0 > 0 }) {
            rows.append(Row(bandStartHour: band * bandHours,
                            levels: totals[band].map { level($0, reference: densityReference) }))
        }
        return Result(rows: rows,
                      best: best(totals: totals, counts: counts, sessionCount: window.count),
                      sessionCount: window.count)
    }

    /// 세션이 충분히 쌓인 칸 중에서 합계가 가장 큰 칸. 동점이면 이른 요일, 그다음 이른 시간대.
    ///
    /// 후보를 먼저 거른 뒤에 고른다. 합계로 먼저 뽑고 나서 그 칸만 문턱에 걸어보면,
    /// 어쩌다 길게 한 번 한 칸이 합계가 크다는 이유로 뽑히고 문턱에서 떨어지면서,
    /// 정작 꾸준히 집중해온 칸이 있는데도 앱이 아무 말도 못 하게 된다.
    private static func best(totals: [[Int]], counts: [[Int]], sessionCount: Int) -> Best? {
        guard sessionCount >= minSessions else { return nil }

        var pick: (weekday: Int, band: Int, seconds: Int)?
        // 요일을 바깥에서 돌아 먼저 만난 쪽이 이기게 한다.
        for weekday in 0..<7 {
            for band in 0..<bandCount where counts[band][weekday] >= minBestSessions {
                let seconds = totals[band][weekday]
                if seconds > (pick?.seconds ?? 0) { pick = (weekday, band, seconds) }
            }
        }

        guard let p = pick else { return nil }
        return Best(weekday: p.weekday, bandStartHour: p.band * bandHours)
    }

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

    /// 농도의 기준값. 0이 아닌 칸들을 정렬해 상위 25% 지점을 쓴다.
    ///
    /// 가장 큰 칸을 기준으로 삼으면 어쩌다 한 번 4시간을 돌린 칸 하나가 나머지를
    /// 전부 최저 단계로 눌러버린다. 정작 보여줘야 할 반복되는 습관이 지워진다.
    static func reference(of cells: [Int]) -> Int {
        let nonZero = cells.filter { $0 > 0 }.sorted()
        guard !nonZero.isEmpty else { return 0 }
        let rank = Int((Double(nonZero.count) * 0.75).rounded(.up))
        return nonZero[min(rank, nonZero.count) - 1]
    }

    /// 기준값과 견준 비율로 네 단계. 기준을 넘는 칸은 전부 최고 단계다.
    static func level(_ seconds: Int, reference: Int) -> Int {
        guard seconds > 0, reference > 0 else { return 0 }
        let r = Double(seconds) / Double(reference)
        if r >= 1.0 { return 3 }
        if r > 2.0 / 3.0 { return 2 }
        return 1
    }
}
