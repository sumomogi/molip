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
