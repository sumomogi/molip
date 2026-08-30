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

        T.finish()
    }
}
