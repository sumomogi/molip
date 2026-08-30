import Foundation

@main struct StringsTests {
    static func main() {
        // 한 언어에서만 번역이 빠지는 사고를 막는다.
        // s(key, lang:)는 그 언어에 없으면 영어로 대신 채운다 — 그 폴백 때문에
        // isEmpty로 보면 "누락됐지만 영어 값이 있는" 경우를 못 잡는다.
        // raw(key, lang:)는 폴백 없이 그 언어 표에 실제로 등록됐는지만 본다.
        for lang in Lang.allCases {
            let missing = L10n.Key.allCases.filter { L10n.raw($0, lang: lang) == nil }
            T.eq("\(lang.rawValue) 빠진 문자열", missing.map { "\($0)" }, [])
        }
        T.finish()
    }
}
