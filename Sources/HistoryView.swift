import SwiftUI

/// 팝오버 기록 화면. 집계는 전부 Insight가 하고 여기서는 그리기만 한다.
struct HistoryView: View {
    var onClose: () -> Void
    var onSettings: () -> Void

    private let result: Insight.Result
    private let weekSeconds: Int

    init(sessions: [Session], now: Date = Date(),
         onClose: @escaping () -> Void, onSettings: @escaping () -> Void) {
        self.result = Insight.make(sessions: sessions, now: now)
        self.weekSeconds = Insight.weekSeconds(sessions: sessions, now: now, timeZone: .current)
        self.onClose = onClose
        self.onSettings = onSettings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            Text(L10n.s(.history))
                .font(.system(size: 11, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(.tertiary)

            Spacer().frame(height: 14)

            if result.rows.isEmpty {
                Text(L10n.s(.historyEmpty))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                Heatmap(rows: result.rows)
                Spacer().frame(height: 14)
                sentence
            }

            Spacer().frame(height: 16)

            HStack {
                Text(L10n.s(.weekTotal))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Self.duration(weekSeconds))
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }

            Spacer().frame(height: 12)
            Divider()
            Spacer().frame(height: 12)

            HStack {
                TextButton(L10n.s(.done), prominent: true, action: onClose)
                Spacer()
                TextButton(L10n.s(.settings), action: onSettings)
            }
        }
    }

    @ViewBuilder private var sentence: some View {
        if let best = result.best {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.s(.historyBest, Self.weekdayName(best.weekday), best.bandStartHour))
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                Text(L10n.s(.historyAdvice))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(L10n.s(.historyNotEnough))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    /// 요일 이름만은 Strings 표에 넣지 않고 시스템에서 가져온다.
    /// 21개 항목을 손으로 관리하는 대신 선택된 언어의 로케일을 넘긴다.
    /// README의 "문자열은 전부 표에" 규칙에 대한 의도적 예외다.
    static func weekdayName(_ mondayBased: Int, short: Bool = false) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: Prefs.language.rawValue)
        let symbols = short ? f.shortWeekdaySymbols! : f.weekdaySymbols!
        return symbols[(mondayBased + 1) % 7]     // 표의 0번은 일요일
    }

    static func duration(_ seconds: Int) -> String {
        let m = seconds / 60
        return m >= 60 ? L10n.s(.durationHM, m / 60, m % 60) : L10n.s(.durationM, m)
    }
}

/// 요일 × 시간대 격자. 색은 쓰지 않고 알파로만 강약을 준다 — 게이지와 같은 언어다.
private struct Heatmap: View {
    let rows: [Insight.Row]

    private static let alpha: [Double] = [0.15, 0.35, 0.65, 1.0]
    private let cell: CGFloat = 14
    private let gap: CGFloat = 3
    private let gutter: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: gap) {
            HStack(spacing: gap) {
                Spacer().frame(width: gutter)
                ForEach(0..<7, id: \.self) { i in
                    Text(HistoryView.weekdayName(i, short: true).prefix(1))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .frame(width: cell)
                }
            }
            ForEach(rows, id: \.bandStartHour) { row in
                HStack(spacing: gap) {
                    Text(String(format: "%02d", row.bandStartHour))
                        .font(.system(size: 9))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .frame(width: gutter, alignment: .trailing)
                    ForEach(Array(row.levels.enumerated()), id: \.offset) { _, level in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.primary.opacity(Self.alpha[level]))
                            .frame(width: cell, height: cell)
                    }
                }
            }
        }
    }
}
