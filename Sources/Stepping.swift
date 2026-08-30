import Foundation

/// 스테퍼가 값을 옮기는 규칙. 값은 언제나 step의 배수에 머물고 범위의 양 끝만 예외다.
///
/// 값에 step을 더한 뒤 범위로 잘라내면, 범위의 끝이 step의 배수가 아닐 때
/// (작업 시간은 1...90인데 5분 단위) 값이 한 번 잘리는 순간부터 1, 6, 11처럼
/// 어긋난 격자에 갇힌다. 더하지 않고 다음 배수로 옮겨서 그 상황을 없앤다.
/// 이미 어긋나게 저장된 값도 한 번 누르면 배수로 돌아온다.
enum Stepping {

    /// v보다 큰 첫 배수. 범위를 넘으면 위쪽 끝.
    static func up(_ v: Int, in range: ClosedRange<Int>, step: Int) -> Int {
        clamp(v / step * step + step, in: range)
    }

    /// v보다 작은 첫 배수. 범위를 벗어나면 아래쪽 끝.
    static func down(_ v: Int, in range: ClosedRange<Int>, step: Int) -> Int {
        let floored = v / step * step       // v 이하의 배수
        return clamp(floored == v ? v - step : floored, in: range)
    }

    private static func clamp(_ v: Int, in r: ClosedRange<Int>) -> Int {
        v < r.lowerBound ? r.lowerBound : (v > r.upperBound ? r.upperBound : v)
    }
}
