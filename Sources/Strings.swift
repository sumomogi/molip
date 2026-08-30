import Foundation

enum Lang: String, CaseIterable {
    case ko, en, ja

    /// 선택 메뉴에 그대로 노출되는 이름. 각 언어 표기를 쓴다.
    var displayName: String {
        switch self {
        case .ko: return "한국어"
        case .en: return "English"
        case .ja: return "日本語"
        }
    }

    /// 처음 실행할 때는 시스템 언어를 따른다. 셋 중 없으면 영어.
    static var systemDefault: Lang {
        let code = Locale.preferredLanguages.first?.prefix(2).lowercased() ?? "en"
        return Lang(rawValue: String(code)) ?? .en
    }
}

/// 화면에 나가는 모든 문자열. 여기 없는 문자열은 UI에 없어야 한다.
enum L10n {

    enum Key: CaseIterable {
        // 단계
        case phaseIdle, phaseWork, phaseShortRest, phaseLongRest
        // 타이머 화면
        case start, stop, settings, set
        // 설정 화면
        case settingsTitle, work, shortRest, longRest, perSet
        case sound, hotkey, launchAtLogin, language
        case done, quit
        // 단위
        case unitMinutes, unitTimes
        // 알림
        case notifWorkDone, notifSetDone, notifRestDone
        case notifRestBody, notifReadyBody
    }

    static func s(_ key: Key) -> String {
        table[Prefs.language]?[key] ?? table[.en]?[key] ?? ""
    }

    static func s(_ key: Key, _ args: CVarArg...) -> String {
        String(format: s(key), arguments: args)
    }

    private static let table: [Lang: [Key: String]] = [

        .ko: [
            .phaseIdle: "대기", .phaseWork: "집중",
            .phaseShortRest: "휴식", .phaseLongRest: "긴 휴식",

            .start: "시작", .stop: "정지", .settings: "설정",
            .set: "세트 %d / %d",

            .settingsTitle: "설정",
            .work: "집중", .shortRest: "짧은 휴식",
            .longRest: "긴 휴식", .perSet: "세트당",
            .sound: "소리", .hotkey: "단축키", .launchAtLogin: "로그인 시 실행",
            .language: "언어",
            .done: "완료", .quit: "종료",

            .unitMinutes: "분", .unitTimes: "회",

            .notifWorkDone: "집중 완료",
            .notifSetDone: "세트 완료",
            .notifRestDone: "휴식 종료",
            .notifRestBody: "%d분 휴식이 시작됐습니다.",
            .notifReadyBody: "준비되면 시작하세요.",
        ],

        .en: [
            .phaseIdle: "Ready", .phaseWork: "Focus",
            .phaseShortRest: "Break", .phaseLongRest: "Long break",

            .start: "Start", .stop: "Stop", .settings: "Settings",
            .set: "Set %d of %d",

            .settingsTitle: "Settings",
            .work: "Focus", .shortRest: "Short break",
            .longRest: "Long break", .perSet: "Sessions per set",
            .sound: "Sound", .hotkey: "Shortcut", .launchAtLogin: "Open at login",
            .language: "Language",
            .done: "Done", .quit: "Quit",

            .unitMinutes: " min", .unitTimes: "",

            .notifWorkDone: "Focus complete",
            .notifSetDone: "Set complete",
            .notifRestDone: "Break over",
            .notifRestBody: "Take a %d-minute break.",
            .notifReadyBody: "Start whenever you're ready.",
        ],

        .ja: [
            .phaseIdle: "待機", .phaseWork: "集中",
            .phaseShortRest: "休憩", .phaseLongRest: "長い休憩",

            .start: "開始", .stop: "停止", .settings: "設定",
            .set: "セット %d / %d",

            .settingsTitle: "設定",
            .work: "集中", .shortRest: "短い休憩",
            .longRest: "長い休憩", .perSet: "セットあたり",
            .sound: "サウンド", .hotkey: "ショートカット", .launchAtLogin: "ログイン時に起動",
            .language: "言語",
            .done: "完了", .quit: "終了",

            .unitMinutes: "分", .unitTimes: "回",

            .notifWorkDone: "集中終了",
            .notifSetDone: "セット完了",
            .notifRestDone: "休憩終了",
            .notifRestBody: "%d分の休憩を始めます。",
            .notifReadyBody: "準備ができたら始めてください。",
        ],
    ]
}
