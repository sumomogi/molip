import AppKit
import UserNotifications

/// 알림과 소리. 문구는 조용한 톤으로 — 재촉하지 않는다.
final class Notifier {

    private var granted = false
    private var available: Bool { Bundle.main.bundleIdentifier != nil }

    func requestAuthorization() {
        guard available else { return }
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { [weak self] ok, _ in
                self?.granted = ok
            }
    }

    /// - Parameters:
    ///   - finished: 방금 끝난 단계
    ///   - next: 이어서 들어간 단계
    ///   - minutes: next의 길이(분)
    func announce(finished: Phase, next: Phase, minutes: Int) {
        if Prefs.soundEnabled {
            NSSound(named: finished == .work ? "Submarine" : "Tink")?.play()
        }

        let title: String
        let body: String

        switch finished {
        case .work:
            title = L10n.s(next == .longRest ? .notifSetDone : .notifWorkDone)
            body  = L10n.s(.notifRestBody, minutes)
        case .shortRest, .longRest:
            title = L10n.s(.notifRestDone)
            body  = L10n.s(.notifReadyBody)
        case .idle:
            return
        }

        post(title: title, body: body)
    }

    private func post(title: String, body: String) {
        guard available, granted else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        // 소리는 위에서 NSSound로 직접 냈다. 여기서 또 내면 겹친다.
        content.sound = nil

        let req = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }
}
