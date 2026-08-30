import SwiftUI
import ServiceManagement

// MARK: - 공통 타이포

/// 팝오버 전체가 쓰는 타이포. 기록·마감 화면도 같은 크기를 써야 하므로
/// 파일 밖에서 보이게 둔다 — TextButton과 같은 이유다.
extension Font {
    /// 상태 라벨, 세트 표시
    static let caption11 = Font.system(size: 11, weight: .medium)
    /// 큰 시계
    static let clock = Font.system(size: 40, weight: .thin).monospacedDigit()
    /// 버튼, 설정 항목
    static let control = Font.system(size: 12)
}

// MARK: - 루트

struct RootView: View {
    @ObservedObject var engine: TimerEngine
    var onHotkeyToggle: (Bool) -> Void
    var onLanguageChange: () -> Void
    var onQuit: () -> Void

    enum Screen { case timer, settings, history }
    @State private var screen: Screen = .timer

    /// 기록 화면에 들어갈 때 한 번만 읽는다.
    /// RootView는 엔진을 관찰하므로, 여기서 바로 파일을 읽으면 타이머가 0.5초마다
    /// 틱할 때마다 디스크를 다시 긁는다.
    @State private var sessions: [Session] = []

    // 언어 키를 여기서 관찰한다. 바뀌면 아래 트리 전체가 다시 그려진다.
    @AppStorage(Prefs.Key.language) private var langRaw = Prefs.language.rawValue

    var body: some View {
        Group {
            switch screen {
            case .settings:
                SettingsView(engine: engine,
                             onHotkeyToggle: onHotkeyToggle,
                             onQuit: onQuit,
                             onClose: { screen = .timer })
            case .history:
                HistoryView(sessions: sessions,
                            onClose: { screen = .timer },
                            onSettings: { screen = .settings })
            case .timer:
                TimerView(engine: engine,
                          onHistory: { sessions = SessionLog.load(); screen = .history },
                          onSettings: { screen = .settings })
            }
        }
        .frame(width: 240)
        .padding(20)
        .onChange(of: langRaw) { _, _ in onLanguageChange() }
    }
}

// MARK: - 타이머 화면

private struct TimerView: View {
    @ObservedObject var engine: TimerEngine
    var onHistory: () -> Void
    var onSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            Text(engine.phase.label)
                .font(.caption11)
                .tracking(0.6)
                .foregroundStyle(.tertiary)

            Spacer().frame(height: 12)

            Text(engine.clock)
                .font(.clock)
                .foregroundStyle(.primary)

            Spacer().frame(height: 16)

            GaugeBar(progress: engine.progress, dimmed: engine.phase.isRest)

            Spacer().frame(height: 14)

            Text(L10n.s(.set, engine.setIndex, engine.setSize))
                .font(.caption11)
                .foregroundStyle(.secondary)

            Spacer().frame(height: 16)

            Divider()

            Spacer().frame(height: 12)

            HStack(spacing: 12) {
                TextButton(L10n.s(engine.isRunning ? .stop : .start), prominent: true) {
                    engine.toggle()
                }
                Spacer()
                TextButton(L10n.s(.history), action: onHistory)
                TextButton(L10n.s(.settings), action: onSettings)
            }
        }
    }
}

// MARK: - 설정 화면

private struct SettingsView: View {
    @ObservedObject var engine: TimerEngine
    var onHotkeyToggle: (Bool) -> Void
    var onQuit: () -> Void
    var onClose: () -> Void

    @State private var work      = Prefs.workMinutes
    @State private var shortRest = Prefs.shortRestMinutes
    @State private var longRest  = Prefs.longRestMinutes
    @State private var setSize   = Prefs.setSize
    @State private var sound     = Prefs.soundEnabled
    @State private var hotkey    = Prefs.hotkeyEnabled
    @State private var atLogin   = SMAppService.mainApp.status == .enabled
    @AppStorage(Prefs.Key.language) private var langRaw = Prefs.language.rawValue

    private var langBinding: Binding<Lang> {
        Binding(get: { Lang(rawValue: langRaw) ?? .systemDefault },
                set: { langRaw = $0.rawValue })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            Text(L10n.s(.settingsTitle))
                .font(.caption11)
                .tracking(0.6)
                .foregroundStyle(.tertiary)

            Spacer().frame(height: 14)

            NumberRow(title: L10n.s(.work),      value: $work,      range: 1...90, step: 5)
            NumberRow(title: L10n.s(.shortRest), value: $shortRest, range: 1...60, step: 1)
            NumberRow(title: L10n.s(.longRest),  value: $longRest,  range: 1...60, step: 5)
            NumberRow(title: L10n.s(.perSet),    value: $setSize,   range: 1...8,  step: 1,
                      unit: L10n.s(.unitTimes))

            Spacer().frame(height: 10)
            Divider()
            Spacer().frame(height: 10)

            SwitchRow(title: L10n.s(.sound), isOn: $sound)
            SwitchRow(title: "\(L10n.s(.hotkey)) \(Hotkey.displayName)", isOn: $hotkey)
            SwitchRow(title: L10n.s(.launchAtLogin), isOn: $atLogin)
            LanguageRow(title: L10n.s(.language), selection: langBinding)

            Spacer().frame(height: 12)
            Divider()
            Spacer().frame(height: 12)

            HStack {
                TextButton(L10n.s(.done), prominent: true, action: onClose)
                Spacer()
                TextButton(L10n.s(.quit), action: onQuit)
            }
        }
        .onChange(of: work)      { _, v in Prefs.workMinutes = v;      engine.refreshIdleClock() }
        .onChange(of: shortRest) { _, v in Prefs.shortRestMinutes = v }
        .onChange(of: longRest)  { _, v in Prefs.longRestMinutes = v }
        .onChange(of: setSize)   { _, v in Prefs.setSize = v }
        .onChange(of: sound)     { _, v in Prefs.soundEnabled = v }
        .onChange(of: hotkey)    { _, v in Prefs.hotkeyEnabled = v; onHotkeyToggle(v) }
        .onChange(of: atLogin)   { _, v in setLoginItem(v) }
    }

    private func setLoginItem(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else  { try SMAppService.mainApp.unregister() }
        } catch {
            // 등록에 실패하면 스위치를 실제 상태로 되돌린다.
            atLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

// MARK: - 부품

private struct NumberRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    var unit: String = L10n.s(.unitMinutes)

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.control)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(value)\(unit)")
                .font(.control)
                .monospacedDigit()
                .foregroundStyle(.primary)
            // 화살표를 nil로 두면 그 방향만 비활성으로 그려진다. 범위 끝에서의
            // 생김새는 Stepper(value:in:step:)와 같고, 값 계산만 Stepping이 맡는다.
            Stepper("",
                    onIncrement: value < range.upperBound
                        ? { value = Stepping.up(value, in: range, step: step) } : nil,
                    onDecrement: value > range.lowerBound
                        ? { value = Stepping.down(value, in: range, step: step) } : nil)
                .labelsHidden()
                .controlSize(.small)
        }
        .frame(height: 22)
    }
}

/// 다른 행들과 같은 골격. 오른쪽 컨트롤만 팝업 메뉴다.
private struct LanguageRow: View {
    let title: String
    @Binding var selection: Lang

    var body: some View {
        HStack {
            Text(title)
                .font(.control)
                .foregroundStyle(.secondary)
            Spacer()
            Picker("", selection: $selection) {
                ForEach(Lang.allCases, id: \.self) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .fixedSize()
        }
        .frame(height: 22)
    }
}

private struct SwitchRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(title)
                .font(.control)
                .foregroundStyle(.secondary)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        .frame(height: 22)
    }
}

/// 테두리 없는 텍스트 버튼. 눌림 상태는 명도로만 표시한다.
/// 기록 화면도 같은 버튼을 쓰므로 파일 밖에서 보이게 둔다.
struct TextButton: View {
    let title: String
    var prominent: Bool = false
    let action: () -> Void

    @State private var hovering = false

    init(_ title: String, prominent: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.prominent = prominent
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.control)
                .foregroundStyle(prominent ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .opacity(hovering ? 0.6 : 1.0)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(title)
    }
}
