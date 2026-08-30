import Foundation

@main struct RecordingTests {
    static func main() {
        // 길이 계산만 따로 확인한다. 타이머를 1분 돌리지 않고 규칙을 본다.
        let cap = 3000.0   // 50분

        T.eq("완주는 그대로", Int(TimerEngine.recordedSeconds(elapsed: 3000, cap: cap)), 3000)
        T.eq("중간에 멈추면 흐른 만큼", Int(TimerEngine.recordedSeconds(elapsed: 1620, cap: cap)), 1620)
        T.eq("단계 길이를 넘지 않는다", Int(TimerEngine.recordedSeconds(elapsed: 9999, cap: cap)), 3000)
        T.eq("음수는 0", Int(TimerEngine.recordedSeconds(elapsed: -5, cap: cap)), 0)

        T.ok("60초 미만은 버린다", !TimerEngine.worthRecording(seconds: 59))
        T.ok("60초는 남긴다", TimerEngine.worthRecording(seconds: 60))

        // 반올림이 문턱보다 먼저다. 59.6초는 60초가 되어 기록에 남는다 — 알고 두는 동작이다.
        T.ok("59.6초는 반올림되어 남는다",
             TimerEngine.worthRecording(seconds: Int(TimerEngine.recordedSeconds(elapsed: 59.6, cap: cap).rounded())))
        T.ok("59.4초는 버려진다",
             !TimerEngine.worthRecording(seconds: Int(TimerEngine.recordedSeconds(elapsed: 59.4, cap: cap).rounded())))

        T.finish()
    }
}
