import Foundation

@main struct SetIndexTests {
    static func main() {
        // 실제 전이 규칙에 태워 한 세트를 끝까지 돌린다.
        func walk(_ size: Int) -> [String] {
            var out: [String] = []
            var phase: Phase = .idle
            var completed = 0

            func show(_ tag: String) {
                out.append("\(tag) \(TimerEngine.setIndex(completedInSet: completed, setSize: size))/\(size)")
            }

            show("대기")
            for _ in 0..<size {
                phase = .work
                show("작업")
                let s = TimerEngine.nextStep(after: .work, completedInSet: completed, setSize: size)
                phase = s.phase
                completed = s.completedInSet
                show(phase == .longRest ? "긴휴식" : "짧은휴식")
                let r = TimerEngine.nextStep(after: phase, completedInSet: completed, setSize: size)
                phase = r.phase
                completed = r.completedInSet
                show("대기")
            }
            return out
        }

        T.eq("2회 세트", walk(2),
             ["대기 1/2", "작업 1/2", "짧은휴식 2/2", "대기 2/2",
              "작업 2/2", "긴휴식 2/2", "대기 1/2"])
        T.eq("1회 세트", walk(1),
             ["대기 1/1", "작업 1/1", "긴휴식 1/1", "대기 1/1"])
        T.eq("3회 세트", walk(3),
             ["대기 1/3", "작업 1/3", "짧은휴식 2/3", "대기 2/3",
              "작업 2/3", "짧은휴식 3/3", "대기 3/3",
              "작업 3/3", "긴휴식 3/3", "대기 1/3"])

        T.finish()
    }
}
