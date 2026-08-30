import AppKit
import UserNotifications

/// 알림과 소리. 문구는 조용한 톤으로 — 재촉하지 않는다.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {

    private var granted = false
    private var available: Bool { Bundle.main.bundleIdentifier != nil }

    func requestAuthorization() {
        guard available else { return }
        // 대리자를 반드시 먼저 건다. 아래 willPresent 참고.
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { [weak self] ok, _ in
                self?.granted = ok
            }
    }

    /// 앱이 활성 상태일 때 알림을 어떻게 보여줄지 시스템이 여기에 물어본다.
    /// 대리자가 없으면 시스템은 "아무것도 보여주지 말라"로 받아들여 조용히 삼킨다.
    ///
    /// 메뉴바 앱이라 평소엔 활성이 될 일이 없지만, 팝오버를 열면 그 창이 키 윈도가
    /// 되면서 활성이 된다. 즉 타이머를 보고 있는 동안 끝난 세션의 알림만 사라졌다.
    ///
    /// 소리는 announce에서 NSSound로 이미 냈으므로 여기서는 빼야 두 번 울리지 않는다.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                    @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
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
