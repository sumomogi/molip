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
}
