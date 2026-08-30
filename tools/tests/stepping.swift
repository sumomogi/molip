import Foundation

@main struct SteppingTests {
    static func main() {
        let work: ClosedRange<Int> = 1...90
        let long: ClosedRange<Int> = 1...60

        // 기본 50분에서 아래로 끝까지 내린 뒤 다시 올리면 5의 배수로 돌아와야 한다.
        var v = 50
        for _ in 0..<20 { v = Stepping.down(v, in: work, step: 5) }
        T.eq("최소까지 내린 값", v, 1)

        var seq: [Int] = []
        for _ in 0..<3 { v = Stepping.up(v, in: work, step: 5); seq.append(v) }
        T.eq("최소에서 위로 3번", seq, [5, 10, 15])

        T.eq("어긋난 6분 회복",
             [Stepping.up(6, in: work, step: 5), Stepping.down(6, in: work, step: 5)], [10, 5])
        T.eq("상한 도달",
             [Stepping.up(86, in: work, step: 5), Stepping.up(90, in: work, step: 5)], [90, 90])
        T.eq("하한 도달",
             [Stepping.down(5, in: work, step: 5), Stepping.down(1, in: work, step: 5)], [1, 1])
        T.eq("긴 휴식 양 끝",
             [Stepping.down(5, in: long, step: 5), Stepping.up(56, in: long, step: 5)], [1, 60])
        T.eq("step 1은 한 칸씩",
             [Stepping.up(1, in: long, step: 1), Stepping.down(60, in: long, step: 1)], [2, 59])

        // 어느 값에서 눌러도 범위를 벗어나지 않는다.
        var escaped = false
        for row in [(work, 5), (long, 5), (long, 1), (1...8, 1)] {
            for x in row.0 {
                if !row.0.contains(Stepping.up(x, in: row.0, step: row.1)) { escaped = true }
                if !row.0.contains(Stepping.down(x, in: row.0, step: row.1)) { escaped = true }
            }
        }
        T.ok("범위를 벗어나는 값 없음", !escaped)

        T.finish()
    }
}
