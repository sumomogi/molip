import Foundation
import Combine

enum Phase {
    case idle, work, shortRest, longRest

    var label: String {
        switch self {
        case .idle:      return L10n.s(.phaseIdle)
        case .work:      return L10n.s(.phaseWork)
        case .shortRest: return L10n.s(.phaseShortRest)
        case .longRest:  return L10n.s(.phaseLongRest)
        }
    }

    var isRest: Bool { self == .shortRest || self == .longRest }
}

/// 순수 상태 머신 + 카운트다운. UI를 전혀 모른다.
final class TimerEngine: ObservableObject {

    @Published private(set) var phase: Phase = .idle
    /// 남은 초. 대기 상태에서는 다음 작업 세션의 길이를 담는다.
    @Published private(set) var remaining: TimeInterval = 0
    /// 현재 세트에서 끝낸 작업 세션 수.
    @Published private(set) var completedInSet: Int = 0

    /// 방금 끝난 단계를 인자로 전달. 알림과 소리는 이 콜백이 담당한다.
    var onComplete: ((Phase) -> Void)?

    /// 상태가 바뀔 때마다 불린다. 메뉴바 갱신용.
    /// @Published와 달리 값이 이미 갱신된 뒤에 불리는 것이 보장된다.
    var onUpdate: (() -> Void)?

    /// 작업 세션 하나가 끝날 때마다 불린다. 파일에 적는 일은 이 콜백을 받는 쪽이 한다.
    /// 엔진이 파일을 직접 만지면 파일 없이 검증할 수 없게 된다.
    var onWorkSessionEnded: ((Session) -> Void)?

    private var endDate: Date?
    private var ticker: Timer?
    /// 지금 돌고 있는 작업 세션이 시작된 시각. 작업이 아니면 nil.
    private var workStartedAt: Date?

    init() {
        remaining = TimeInterval(Prefs.workMinutes * 60)
    }

    // MARK: - 조회

    /// 현재 단계의 전체 길이(초).
    var total: TimeInterval {
        switch phase {
        case .idle, .work: return TimeInterval(Prefs.workMinutes * 60)
        case .shortRest:   return TimeInterval(Prefs.shortRestMinutes * 60)
        case .longRest:    return TimeInterval(Prefs.longRestMinutes * 60)
        }
    }

    /// 남은 비율. 1.0에서 시작해 0.0으로 줄어든다. 대기 상태는 0.
    var progress: Double {
        guard phase != .idle, total > 0 else { return 0 }
        return min(1, max(0, remaining / total))
    }

    var isRunning: Bool { phase != .idle }

    /// "세트 N / M"의 N.
    var setIndex: Int {
        Self.setIndex(completedInSet: completedInSet, setSize: Prefs.setSize)
    }

    /// 끝낸 작업 수 + 1 — 지금 하고 있거나 다음에 할 회차를 가리킨다.
    /// 그래서 작업이 끝나는 순간 숫자가 넘어가고, 이어지는 휴식은 다음 회차를 단다.
    /// 세트를 다 채우면 M을 넘지 않고 머물다가, 긴 휴식이 끝나며 1로 돌아온다.
    ///
    /// 단계마다 다른 기준을 쓰면(휴식은 방금 끝낸 회차, 대기는 다음 회차) 숫자가
    /// 작업 시작부터 휴식 종료까지 붙박여 있어 진행이 멈춘 것처럼 보인다.
    static func setIndex(completedInSet: Int, setSize: Int) -> Int {
        min(completedInSet + 1, setSize)
    }

    var setSize: Int { Prefs.setSize }

    /// mm:ss. 남은 시간은 올림해서 보여준다 — 50:00에서 시작해야 자연스럽다.
    var clock: String {
        let s = Int(ceil(max(0, remaining)))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    // MARK: - 전이 규칙 (순수 함수)

    /// 한 단계가 끝났을 때 다음 단계와 세트 진행도를 계산한다.
    /// 시간·타이머·설정 저장소와 무관해서 따로 검증할 수 있다.
    static func nextStep(after finished: Phase,
                         completedInSet: Int,
                         setSize: Int) -> (phase: Phase, completedInSet: Int) {
        switch finished {
        case .work:
            let done = completedInSet + 1
            // 세트를 다 채웠으면 긴 휴식, 아니면 짧은 휴식.
            return (done >= setSize ? .longRest : .shortRest, done)
        case .shortRest:
            // 세트 진행도는 유지한 채 대기로.
            return (.idle, completedInSet)
        case .longRest:
            // 세트를 마쳤으니 진행도 초기화.
            return (.idle, 0)
        case .idle:
            return (.idle, completedInSet)
        }
    }

    /// 기록할 길이. 벽시계로 흐른 시간을 쓰되 단계 길이를 넘지 않는다.
    /// 맥이 잠들어도 실제로 흐른 만큼이 남고, 시계가 튀어도 한 세션이 부풀지 않는다.
    static func recordedSeconds(elapsed: TimeInterval, cap: TimeInterval) -> TimeInterval {
        min(max(elapsed, 0), cap)
    }

    /// 너무 짧은 것은 남기지 않는다. 눌렀다 바로 끈 것까지 리듬으로 세면 그림이 흐려진다.
    static func worthRecording(seconds: Int) -> Bool { seconds >= 60 }

    // MARK: - 조작

    func toggle() {
        isRunning ? stop() : begin(.work)
    }

    /// 수동 정지. 세트 진행도까지 초기화한다.
    func stop() {
        endWorkSession(completed: false)
        ticker?.invalidate()
        ticker = nil
        endDate = nil
        phase = .idle
        completedInSet = 0
        remaining = TimeInterval(Prefs.workMinutes * 60)
        onUpdate?()
    }

    /// 설정에서 시간을 바꿨을 때, 돌고 있지 않다면 표시를 새 값으로 맞춘다.
    func refreshIdleClock() {
        guard phase == .idle else { return }
        remaining = TimeInterval(Prefs.workMinutes * 60)
        onUpdate?()
    }

    // MARK: - 내부

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

    private func begin(_ next: Phase) {
        phase = next
        if next == .work { workStartedAt = Date() }
        let seconds = total
        remaining = seconds
        endDate = Date().addingTimeInterval(seconds)

        ticker?.invalidate()
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        // .common 모드라야 메뉴 트래킹 중에도 멈추지 않는다.
        RunLoop.main.add(t, forMode: .common)
        ticker = t
        onUpdate?()
    }

    private func tick() {
        guard let end = endDate else { return }
        let left = end.timeIntervalSinceNow
        if left <= 0 {
            advance()
        } else {
            remaining = left
            onUpdate?()
        }
    }

    private func advance() {
        let finished = phase
        ticker?.invalidate()
        ticker = nil
        endDate = nil
        guard finished != .idle else { return }
        if finished == .work { endWorkSession(completed: true) }

        let step = Self.nextStep(after: finished,
                                 completedInSet: completedInSet,
                                 setSize: Prefs.setSize)
        completedInSet = step.completedInSet

        if step.phase == .idle {
            // 휴식이 끝나면 멈춘다. 자리를 비운 사이 다음 세션이 혼자 흘러가지 않도록.
            goIdle()
        } else {
            // 작업이 끝나면 휴식은 자동으로 시작된다.
            begin(step.phase)
        }

        // 새 단계가 자리 잡은 뒤에 알린다.
        // 알림 문구가 "다음 단계의 길이"를 참조하기 때문에 순서가 중요하다.
        onComplete?(finished)
    }

    private func goIdle() {
        phase = .idle
        remaining = TimeInterval(Prefs.workMinutes * 60)
        onUpdate?()
    }
}
