import Foundation

/// 작업 세션 한 건.
struct Session: Equatable {
    let start: Date
    /// 기록될 당시의 로컬 오프셋(초). 요일과 시간대를 이 값에 맞춰 센다.
    /// 사용자가 다른 시간대로 옮겨가도 과거 기록이 다시 쓰이지 않게 하려는 것이다.
    let offsetSeconds: Int
    let seconds: Int
    let completed: Bool
}

/// sessions.jsonl을 읽고 쓴다. 파일 형식을 아는 유일한 곳.
enum SessionLog {

    /// 테스트가 임시 경로로 바꿔 끼울 수 있도록 var로 둔다.
    static var url: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        return base.appendingPathComponent("Molip", isDirectory: true)
                   .appendingPathComponent("sessions.jsonl")
    }()

    // MARK: - 한 줄 ↔ 값

    /// JSON을 직접 쓴다. 값이 전부 숫자·불리언·형식이 고정된 날짜라 이스케이프할 것이 없고,
    /// 그 대신 파일에 어떤 글자가 들어가는지가 코드에 그대로 보인다.
    static func line(for s: Session) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        // 오프셋은 ±18시간을 넘지 않아 TimeZone(secondsFromGMT:)가 nil을 낼 일이 없다.
        // ?? .current는 도달하지 않는 방어 코드일 뿐, 의미 있는 대체값이 아니다.
        f.timeZone = TimeZone(secondsFromGMT: s.offsetSeconds) ?? .current
        return "{\"start\":\"\(f.string(from: s.start))\",\"seconds\":\(s.seconds),\"completed\":\(s.completed)}"
    }

    private struct Row: Decodable {
        let start: String
        let seconds: Int
        let completed: Bool
    }

    static func session(from line: String) -> Session? {
        guard let data = line.data(using: .utf8),
              let row = try? JSONDecoder().decode(Row.self, from: data) else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        // 오프셋을 못 믿으면 날짜를 못 믿는 것과 같다 — 나중에 요일·시간대별 통계가
        // 전부 이 값에 얹혀서, 그럴듯한 0(UTC 오독)이 nil보다 더 나쁘다.
        guard let date = f.date(from: row.start),
              let off = offset(from: row.start) else { return nil }
        return Session(start: date,
                       offsetSeconds: off,
                       seconds: row.seconds,
                       completed: row.completed)
    }

    /// "2026-08-30T15:44:04+09:00" 끝에 붙은 오프셋을 초로. `Z`면 0.
    /// `±HH:MM` 형식(콜론 포함)이 아니면 nil — 굳이 관대하게 읽어서 잘못된 0을
    /// 만들 바엔 그 줄을 버리는 편이 낫다.
    ///
    /// 형식만 맞고 값이 말이 안 되는 경우(`+99:99`)도 같은 이유로 nil이어야 한다.
    /// 실제 UTC 오프셋은 ±18시간을 넘지 않고 분은 60 미만이다 — 아니면 오타를
    /// 조용히 삼켜 엉뚱한 요일·시간대로 통계를 뒤섞는다.
    ///
    /// `JSONEncoder`의 `.iso8601` 전략은 UTC로 적어 이 정보를 잃는다. 그래서 쓰지 않는다.
    static func offset(from iso: String) -> Int? {
        if iso.hasSuffix("Z") { return 0 }
        let tail = iso.suffix(6)                       // +09:00
        guard tail.count == 6,
              (tail.hasPrefix("+") || tail.hasPrefix("-")),
              tail[tail.index(tail.startIndex, offsetBy: 3)] == ":",
              let h = Int(tail.dropFirst().prefix(2)),
              let m = Int(tail.suffix(2)),
              h <= 18, m < 60 else { return nil }
        return (tail.hasPrefix("-") ? -1 : 1) * (h * 3600 + m * 60)
    }

    // MARK: - 파일

    /// 한 줄 덧붙인다. 디렉터리가 없으면 만든다.
    ///
    /// O_APPEND로 연다. seekToEnd 후 write는 두 번의 시스템 콜이라 그 사이에 다른
    /// 쓰기가 끼면 한 줄이 통째로 덮인다. O_APPEND는 커널이 파일 끝에 붙여주므로
    /// 자리를 다투지 않고, 실패할 seek 자체가 없다. O_CREAT가 있어 파일이 없을 때의
    /// 별도 분기도 필요 없다.
    static func append(_ s: Session) {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard fd >= 0 else { return }
        let h = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? h.close() }
        try? h.write(contentsOf: Data((line(for: s) + "\n").utf8))
    }

    /// 읽을 수 없는 줄은 건너뛴다. 쓰다 만 마지막 줄 하나 때문에 전체를 잃지 않는다.
    ///
    /// 파일 전체를 String으로 먼저 디코드하면 안 된다. 깨진 바이트 하나로 디코드가
    /// 통째로 실패해서 몇 년치 기록이 한꺼번에 사라진다. 바이트로 먼저 줄을 가르고
    /// 줄마다 따로 디코드해야 손실이 그 한 줄에서 멈춘다.
    static func load() -> [Session] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return data.split(separator: 0x0A).compactMap {
            session(from: String(decoding: $0, as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
