import AppKit

/// 공유용 정사각 카드. 앱과 같은 언어로 — 색 없이 명도만 쓴다.
///
/// 여기서만은 시스템 시맨틱 컬러를 쓰지 않고 값을 고정한다. 내보낸 이미지에는
/// 따라갈 라이트/다크가 없고, 받는 쪽 화면이 어떻든 같게 보여야 하기 때문이다.
enum ShareCard {

    static let side = 1080

    private static let ink = NSColor.black
    private static let paper = NSColor.white

    /// 헤드리스에서도 그려지도록 lockFocus 대신 비트맵에 직접 그린다.
    static func png(for day: Workday) -> Data? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        draw(day)
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .png, properties: [:])
    }

    private static func draw(_ day: Workday) {
        let s = CGFloat(side)
        let margin: CGFloat = 96

        paper.setFill()
        NSRect(x: 0, y: 0, width: s, height: s).fill()

        // 좌표 원점은 좌하단이다. 위에서부터 쌓기 위해 y를 내려가며 잡는다.
        //
        // 내용의 자연 높이는 40+190+40+26+38 = 334pt이고 쓸 수 있는 세로는 888pt다.
        // 남는 554pt를 한 곳에 몰면 카드 아래가 통째로 비어 잘린 것처럼 보인다.
        // 라벨은 자기 숫자에 붙이고(18·22pt), 나머지를 큰 간격 셋으로 나눈다.
        var y = s - margin

        y -= 40
        text(dateLine(day.checkedIn), at: NSPoint(x: margin, y: y),
             size: 34, weight: .medium, alpha: 0.55)

        y -= 350
        text(Workday.clock(day.focusSeconds), at: NSPoint(x: margin, y: y),
             size: 190, weight: .thin, alpha: 1.0)

        y -= 58
        text(L10n.s(.phaseWork), at: NSPoint(x: margin, y: y),
             size: 40, weight: .medium, alpha: 0.55)

        y -= 216
        bar(ratio: day.ratio, at: NSPoint(x: margin, y: y), width: s - margin * 2)

        y -= 60
        let work = duration(day.workSeconds)
        let pct = Int((day.ratio * 100).rounded())
        text(L10n.s(.cardSummary, work, pct), at: NSPoint(x: margin, y: y),
             size: 38, weight: .regular, alpha: 0.55)

        // 오른쪽 아래 워드마크. 앱 이름이라 번역하지 않는다.
        let mark = "몰입"
        let markSize = measure(mark, size: 34, weight: .medium)
        text(mark, at: NSPoint(x: s - margin - markSize.width, y: margin),
             size: 34, weight: .medium, alpha: 0.25)
    }

    /// 채운 만큼과 빈 만큼을 알파로만 나눈다. 게이지와 같은 방식이다.
    private static func bar(ratio: Double, at origin: NSPoint, width: CGFloat) {
        let height: CGFloat = 26
        ink.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: NSRect(x: origin.x, y: origin.y, width: width, height: height),
                     xRadius: height / 2, yRadius: height / 2).fill()

        let filled = width * CGFloat(min(max(ratio, 0), 1))
        guard filled > 0 else { return }
        ink.withAlphaComponent(1.0).setFill()
        NSBezierPath(roundedRect: NSRect(x: origin.x, y: origin.y, width: max(filled, height), height: height),
                     xRadius: height / 2, yRadius: height / 2).fill()
    }

    private static func attributes(size: CGFloat, weight: NSFont.Weight, alpha: CGFloat)
        -> [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: size, weight: weight),
         .foregroundColor: ink.withAlphaComponent(alpha)]
    }

    private static func text(_ s: String, at p: NSPoint, size: CGFloat,
                             weight: NSFont.Weight, alpha: CGFloat) {
        s.draw(at: p, withAttributes: attributes(size: size, weight: weight, alpha: alpha))
    }

    private static func measure(_ s: String, size: CGFloat, weight: NSFont.Weight) -> NSSize {
        s.size(withAttributes: attributes(size: size, weight: weight, alpha: 1))
    }

    /// 선택된 언어로 날짜와 요일. 요일 이름과 같은 이유로 시스템에서 가져온다.
    private static func dateLine(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: Prefs.language.rawValue)
        f.setLocalizedDateFormatFromTemplate("yMMMdEEE")
        return f.string(from: date)
    }

    private static func duration(_ seconds: Int) -> String {
        let m = seconds / 60
        return m >= 60 ? L10n.s(.durationHM, m / 60, m % 60) : L10n.s(.durationM, m)
    }

    /// 클립보드에 이미지로 올린다. 어디에 올릴지는 사용자 손에 남는다.
    /// 공유 시트를 쓰지 않는 이유는 설계 문서에 적어뒀다.
    @discardableResult
    static func copyToPasteboard(_ day: Workday) -> Bool {
        guard let png = png(for: day), let image = NSImage(data: png) else { return false }
        let pb = NSPasteboard.general
        pb.clearContents()
        return pb.writeObjects([image])
    }
}
