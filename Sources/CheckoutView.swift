import SwiftUI

/// 마감 화면. 복사하기 전에 숫자를 눈으로 보고, 공유하지 않고 닫을 수도 있어야 한다.
struct CheckoutView: View {
    let day: Workday
    var onClose: () -> Void

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            Text(L10n.s(.closing))
                .font(.caption11)
                .tracking(0.6)
                .foregroundStyle(.tertiary)

            Spacer().frame(height: 14)

            Text(Workday.clock(day.workSeconds))
                .font(.clock)
                .foregroundStyle(.primary)

            Text(L10n.s(.onDuty))
                .font(.caption11)
                .tracking(0.6)
                .foregroundStyle(.tertiary)

            Spacer().frame(height: 16)

            RatioBar(ratio: day.ratio)

            Spacer().frame(height: 10)

            Text("\(L10n.s(.phaseWork)) \(Workday.clock(day.focusSeconds)) · \(Int((day.ratio * 100).rounded()))%")
                .font(.control)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Spacer().frame(height: 14)

            Text("\(Self.hm(day.checkedIn)) – \(Self.hm(day.checkedOut))")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.tertiary)

            Spacer().frame(height: 12)
            Divider()
            Spacer().frame(height: 12)

            HStack {
                TextButton(L10n.s(.done), prominent: true, action: onClose)
                Spacer()
                TextButton(L10n.s(copied ? .copied : .copyImage)) {
                    ShareCard.copyToPasteboard(day)
                    copied = true
                }
            }
        }
    }

    private static func hm(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: Prefs.language.rawValue)
        f.setLocalizedDateFormatFromTemplate("Hm")
        return f.string(from: d)
    }
}

/// 마감 화면의 가로 막대. 게이지와 같은 알파 언어를 쓴다.
private struct RatioBar: View {
    let ratio: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule().fill(Color.primary)
                    .frame(width: max(geo.size.width * CGFloat(min(max(ratio, 0), 1)), 0))
            }
        }
        .frame(height: 10)
    }
}
