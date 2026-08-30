import Foundation

@main struct SessionLogTests {
    // 유닉스 초를 손으로 적으면 틀려도 눈에 안 보인다 — 항상 DateComponents로 만든다.
    static func makeDate(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ se: Int,
                          offsetSeconds: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d
        c.hour = h; c.minute = mi; c.second = se
        c.timeZone = TimeZone(secondsFromGMT: offsetSeconds)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal.date(from: c)!
    }

    static func main() {
        // 이 스위트는 도중에 SessionLog.url을 임시 경로로 바꿔 낀다. 이 줄보다 위에
        // 단언이 하나라도 있으면 그 사이에 실제 사용자 기록(~/Library/Application
        // Support/Molip/sessions.jsonl)에 쓰게 될 수 있다 — 그러니 반드시 맨 위.
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("molip-test-\(getpid())")
            .appendingPathComponent("sessions.jsonl")
        SessionLog.url = tmp

        // 2026-08-30 15:44:04 +09:00
        let start = makeDate(2026, 8, 30, 15, 44, 4, offsetSeconds: 9 * 3600)
        let s = Session(start: start, offsetSeconds: 9 * 3600, seconds: 3000, completed: true)

        T.eq("한 줄 형식", SessionLog.line(for: s),
             "{\"start\":\"2026-08-30T15:44:04+09:00\",\"seconds\":3000,\"completed\":true}")

        T.eq("되읽기", SessionLog.session(from: SessionLog.line(for: s)), s)

        // 오프셋 보존이 이 파일을 직접 쓰는 이유 전부다 — 양수/음수/30분 단위/UTC 네 갈래를
        // line(for:) → session(from:) 왕복으로 다 확인한다.
        let negative = Session(start: makeDate(2026, 8, 30, 1, 44, 4, offsetSeconds: -5 * 3600),
                                offsetSeconds: -5 * 3600, seconds: 100, completed: false)
        T.eq("왕복: 음수 오프셋", SessionLog.session(from: SessionLog.line(for: negative)), negative)

        let halfHour = Session(start: makeDate(2026, 8, 30, 19, 14, 4, offsetSeconds: 5 * 3600 + 30 * 60),
                                offsetSeconds: 5 * 3600 + 30 * 60, seconds: 200, completed: true)
        T.eq("왕복: 30분 단위 오프셋(인도)", SessionLog.session(from: SessionLog.line(for: halfHour)), halfHour)

        let utc = Session(start: makeDate(2026, 8, 30, 6, 44, 4, offsetSeconds: 0),
                           offsetSeconds: 0, seconds: 300, completed: false)
        T.eq("왕복: 오프셋 0 (Z로 기록)", SessionLog.session(from: SessionLog.line(for: utc)), utc)

        T.eq("오프셋 파싱", [
            SessionLog.offset(from: "2026-08-30T15:44:04+09:00"),
            SessionLog.offset(from: "2026-08-30T01:44:04-05:00"),
            SessionLog.offset(from: "2026-08-30T06:44:04Z"),
        ], [9 * 3600, -5 * 3600, 0])

        // 콜론 없는 +0900은 그럴듯해 보이지만 형식이 다르다 — 0(UTC)으로 잘못 읽지 말고
        // nil로 거부해야 나중에 시간대별 통계가 조용히 틀리지 않는다.
        T.eq("오프셋 파싱: 콜론 없는 오프셋은 nil", SessionLog.offset(from: "2026-08-30T15:44:04+0900"), nil)

        T.eq("깨진 줄은 nil", SessionLog.session(from: "{\"start\":\"2026-08"), nil)
        T.eq("빈 줄은 nil", SessionLog.session(from: ""), nil)

        // 콜론 없는 오프셋이 실려온 줄 전체도 세션으로 읽히면 안 된다 — 같은 이유로 통째로 버린다.
        T.eq("세션 읽기: 콜론 없는 오프셋은 nil",
             SessionLog.session(from: "{\"start\":\"2026-08-30T15:44:04+0900\",\"seconds\":10,\"completed\":true}"),
             nil)
        // 대조군: 형식이 맞으면 여전히 읽힌다.
        T.ok("세션 읽기: 정상 오프셋은 값을 반환", SessionLog.session(from: SessionLog.line(for: s)) != nil)

        // 파일 왕복.
        T.eq("없는 파일은 빈 배열", SessionLog.load(), [])

        let a = Session(start: start, offsetSeconds: 9 * 3600, seconds: 3000, completed: true)
        let b = Session(start: start.addingTimeInterval(7200),
                        offsetSeconds: 9 * 3600, seconds: 1620, completed: false)
        SessionLog.append(a)
        SessionLog.append(b)
        T.eq("두 줄 왕복", SessionLog.load(), [a, b])

        // append 도중 종료되면 마지막 줄이 잘릴 수 있다. 나머지는 살아야 한다.
        if let h = try? FileHandle(forWritingTo: tmp) {
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: Data("{\"start\":\"2026-08".utf8))
            try? h.close()
        }
        T.eq("잘린 마지막 줄은 버리고 나머지를 읽음", SessionLog.load(), [a, b])

        // 유효한 두 줄 사이에 깨진 줄 하나가 끼어도 앞뒤는 살아야 한다.
        let sandwiched = Data((SessionLog.line(for: a) + "\n").utf8)
            + Data(("이건 세션이 아니다\n").utf8)
            + Data((SessionLog.line(for: b) + "\n").utf8)
        try? sandwiched.write(to: tmp)
        T.eq("가운데 깨진 줄은 건너뛰고 앞뒤는 읽음", SessionLog.load(), [a, b])

        // 파일 전체가 처음부터 세션이 아니어도 죽지 않고 빈 배열을 낸다.
        try? Data("이 파일은 처음부터 세션이 아니다\n다음 줄도 마찬가지".utf8).write(to: tmp)
        T.eq("처음부터 못 읽는 파일은 빈 배열", SessionLog.load(), [])

        // Critical 회귀: 줄 하나에 깨진 UTF-8 바이트가 섞여도 나머지 줄은 읽혀야 한다.
        // String(contentsOf:encoding:.utf8)처럼 파일 전체를 먼저 디코드하면 이 바이트
        // 하나 때문에 디코드 자체가 실패해서 전체가 통째로 사라진다.
        var withBadByte = Data((SessionLog.line(for: a) + "\n").utf8)
        withBadByte.append(0xFF) // 어떤 UTF-8 시퀀스로도 이어지지 않는 바이트
        withBadByte.append(contentsOf: Data("\n".utf8))
        withBadByte.append(contentsOf: Data((SessionLog.line(for: b) + "\n").utf8))
        try? withBadByte.write(to: tmp)
        T.eq("깨진 UTF-8 바이트가 섞여도 나머지 줄은 읽음", SessionLog.load(), [a, b])

        // CRLF로 저장된 줄도 파싱되어야 한다 (\r는 트림으로 제거).
        let crlf = Data((SessionLog.line(for: a) + "\r\n" + SessionLog.line(for: b) + "\r\n").utf8)
        try? crlf.write(to: tmp)
        T.eq("CRLF 줄바꿈도 읽음", SessionLog.load(), [a, b])

        try? FileManager.default.removeItem(at: tmp.deletingLastPathComponent())

        T.finish()
    }
}
