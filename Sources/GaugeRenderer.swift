import AppKit
import SwiftUI

/// 메뉴바와 팝오버가 함께 쓰는 세그먼트 게이지.
/// 칸 수를 여기서 바꾸면 두 곳이 같이 바뀐다.
enum GaugeRenderer {

    static let segments = 10

    // 메뉴바 치수. 3pt + 1pt 간격이라 1x/2x 어디서도 픽셀에 딱 맞는다.
    private static let segW: CGFloat = 3
    private static let segGap: CGFloat = 1
    private static let barH: CGFloat = 6
    private static let imageH: CGFloat = 16

    static var barW: CGFloat {
        CGFloat(segments) * segW + CGFloat(segments - 1) * segGap   // 39pt
    }

    /// 남은 비율(1.0 → 0.0)을 채워진 칸 수로. 0보다 크면 최소 한 칸은 남긴다.
    static func filledCount(_ progress: Double) -> Int {
        guard progress > 0 else { return 0 }
        return max(1, min(segments, Int(ceil(progress * Double(segments)))))
    }

    /// 템플릿 이미지로 그린다. 색은 macOS가 라이트/다크에 맞춰 알아서 칠하고,
    /// 우리는 알파값으로만 강약을 준다.
    static func menuBarImage(progress: Double, dimmed: Bool) -> NSImage {
        let size = NSSize(width: barW, height: imageH)
        let img = NSImage(size: size, flipped: false) { _ in
            let filled = filledCount(progress)
            let onAlpha: CGFloat = dimmed ? 0.40 : 1.00
            let offAlpha: CGFloat = dimmed ? 0.10 : 0.20
            let y = (imageH - barH) / 2

            for i in 0..<segments {
                let x = CGFloat(i) * (segW + segGap)
                let rect = NSRect(x: x, y: y, width: segW, height: barH)
                let path = NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1)
                NSColor.black
                    .withAlphaComponent(i < filled ? onAlpha : offAlpha)
                    .setFill()
                path.fill()
            }
            return true
        }
        img.isTemplate = true
        return img
    }
}

/// 팝오버용. 메뉴바와 같은 칸 수, 폭만 늘어난다.
struct GaugeBar: View {
    let progress: Double
    let dimmed: Bool
    var height: CGFloat = 4

    var body: some View {
        let filled = GaugeRenderer.filledCount(progress)
        HStack(spacing: 2) {
            ForEach(0..<GaugeRenderer.segments, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Color.primary.opacity(alpha(lit: i < filled)))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: height)
    }

    private func alpha(lit: Bool) -> Double {
        if lit  { return dimmed ? 0.40 : 0.85 }
        else    { return dimmed ? 0.08 : 0.14 }
    }
}
