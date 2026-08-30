import Foundation
import AppKit

@main struct ShareCardTests {
    static func main() {
        func at(_ iso: String) -> Date {
            SessionLog.session(from: "{\"start\":\"\(iso)\",\"seconds\":60,\"completed\":true}")!.start
        }
        let day = Workday(checkedIn: at("2026-08-31T09:00:00+09:00"),
                          checkedOut: at("2026-08-31T17:12:00+09:00"),
                          workSeconds: 29520, focusSeconds: 15000)

        guard let png = ShareCard.png(for: day) else {
            T.ok("PNG가 만들어진다", false)
            T.finish()
        }
        T.ok("PNG가 만들어진다", true)

        let rep = NSBitmapImageRep(data: png)
        T.eq("가로", rep?.pixelsWide, 1080)
        T.eq("세로", rep?.pixelsHigh, 1080)

        // 배경만 있는 빈 카드가 아닌지 — 배경과 다른 픽셀이 있어야 한다.
        var drawn = false
        if let rep {
            let bg = rep.colorAt(x: 4, y: 4)
            outer: for x in stride(from: 0, to: 1080, by: 17) {
                for y in stride(from: 0, to: 1080, by: 17) {
                    if let c = rep.colorAt(x: x, y: y), c != bg { drawn = true; break outer }
                }
            }
        }
        T.ok("빈 카드가 아니다", drawn)

        T.finish()
    }
}
