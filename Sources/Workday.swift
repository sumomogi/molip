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
