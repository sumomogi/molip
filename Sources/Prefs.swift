import Foundation

/// UserDefaults 래퍼. 다른 조각들은 키 문자열을 몰라도 된다.
enum Prefs {
    private static let d = UserDefaults.standard

    enum Key {
        static let work = "workMinutes"
        static let shortRest = "shortRestMinutes"
        static let longRest = "longRestMinutes"
        static let setSize = "workIntervalsInSet"
        static let sound = "soundEnabled"
        static let hotkey = "hotkeyEnabled"
        static let language = "language"
    }

    /// 최초 실행 시 기본값. 이미 값이 있으면 건드리지 않는다.
    static func registerDefaults() {
        d.register(defaults: [
            Key.work: 50,
            Key.shortRest: 10,
            Key.longRest: 30,
            Key.setSize: 2,
            Key.sound: true,
            Key.hotkey: true,
        ])
    }

    static var workMinutes: Int {
        get { clamp(d.integer(forKey: Key.work), 1, 90) }
        set { d.set(newValue, forKey: Key.work) }
    }
    static var shortRestMinutes: Int {
        get { clamp(d.integer(forKey: Key.shortRest), 1, 60) }
        set { d.set(newValue, forKey: Key.shortRest) }
    }
    static var longRestMinutes: Int {
        get { clamp(d.integer(forKey: Key.longRest), 1, 60) }
        set { d.set(newValue, forKey: Key.longRest) }
    }
    static var setSize: Int {
        get { clamp(d.integer(forKey: Key.setSize), 1, 8) }
        set { d.set(newValue, forKey: Key.setSize) }
    }
    static var soundEnabled: Bool {
        get { d.bool(forKey: Key.sound) }
        set { d.set(newValue, forKey: Key.sound) }
    }
    static var hotkeyEnabled: Bool {
        get { d.bool(forKey: Key.hotkey) }
        set { d.set(newValue, forKey: Key.hotkey) }
    }

    /// 저장된 값이 없으면 시스템 언어를 따른다.
    static var language: Lang {
        get { Lang(rawValue: d.string(forKey: Key.language) ?? "") ?? .systemDefault }
        set { d.set(newValue.rawValue, forKey: Key.language) }
    }

    private static func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int {
        v < lo ? lo : (v > hi ? hi : v)
    }
}
