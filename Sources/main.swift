import AppKit
import SwiftUI

@main
struct Molip {
    static func main() {
        Prefs.registerDefaults()
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // Dock에 안 뜬다
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {

    private let engine = TimerEngine()
    private let notifier = Notifier()
    private let hotkey = Hotkey()

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!

    // 같은 그림을 다시 그리지 않기 위한 캐시
    private var lastFilled = -1
    private var lastDimmed = false

    /// 팝오버 바깥 클릭 감시자
    private var outsideClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 어제 이전에 찍힌 체크인은 버린다. Workday.isStale의 주석 참고.
        if let open = Prefs.checkedInAt, Workday.isStale(open, now: Date()) {
            Prefs.checkedInAt = nil
        }
        notifier.requestAuthorization()
        buildStatusItem()
        buildPopover()
        wireEngine()
        hotkey.install { [weak self] in self?.engine.toggle() }
        refreshStatusImage(force: true)
    }

    // MARK: - 조립

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: GaugeRenderer.barW + 8)
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover)
        updateToolTip()
    }

    private func buildPopover() {
        let root = RootView(
            engine: engine,
            onHotkeyToggle: { [weak self] on in self?.hotkey.setEnabled(on) },
            onLanguageChange: { [weak self] in self?.updateToolTip() },
            onQuit: { NSApp.terminate(nil) }
        )
        let hosting = NSHostingController(rootView: root)
        // 이걸 켜야 SwiftUI가 잰 크기가 팝오버에 먼저 전달된다.
        // 없으면 기본값 320x320으로 자리를 잡은 뒤 축소되면서 메뉴바에서 멀어진다.
        hosting.sizingOptions = [.preferredContentSize]

        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentViewController = hosting
    }

    private func wireEngine() {
        // 매 틱마다 메뉴바를 다시 볼지 판단한다.
        engine.onUpdate = { [weak self] in
            self?.refreshStatusImage()
            self?.updateToolTip()
        }

        // 한 단계가 끝난 순간에만 알림과 소리.
        engine.onComplete = { [weak self] finished in
            guard let self else { return }
            self.notifier.announce(
                finished: finished,
                next: self.engine.phase,
                minutes: Int(self.engine.total / 60)
            )
        }

        // 작업 세션이 끝날 때마다 파일에 한 줄 남긴다.
        engine.onWorkSessionEnded = { session in
            SessionLog.append(session)
        }
    }

    // MARK: - 메뉴바

    /// 채워진 칸 수나 강약이 바뀔 때만 이미지를 새로 만든다.
    /// 50분 세션 한 번에 열 번 남짓 그린다.
    private func refreshStatusImage(force: Bool = false) {
        let filled = GaugeRenderer.filledCount(engine.progress)
        let dimmed = engine.phase.isRest
        guard force || filled != lastFilled || dimmed != lastDimmed else { return }
        lastFilled = filled
        lastDimmed = dimmed
        statusItem.button?.image = GaugeRenderer.menuBarImage(
            progress: engine.progress,
            dimmed: dimmed
        )
    }

    /// 게이지는 숫자를 안 보여준다. 정확한 시간이 필요하면 아이콘에 마우스만 올리면 된다.
    private func updateToolTip() {
        statusItem.button?.toolTip = engine.isRunning
            ? "\(engine.phase.label) · \(engine.clock) · \(L10n.s(.set, engine.setIndex, engine.setSize))"
            : "\(engine.phase.label) · \(engine.clock)"
    }

    // MARK: - 팝오버

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            watchOutsideClicks()
        }
    }

    /// `.transient`는 앱이 활성 상태를 잃을 때 팝오버를 닫아준다.
    /// 그런데 이 앱은 accessory라 활성 앱이 되는 일이 자체가 없어서
    /// 다른 앱을 눌러도 그 신호가 오지 않는다. 바깥 클릭을 직접 본다.
    ///
    /// 전역 감시자는 다른 앱으로 가는 이벤트만 받는다.
    /// 팝오버 안쪽 클릭과 메뉴바 아이콘 클릭은 우리 앱 이벤트라 여기 안 걸린다.
    private func watchOutsideClicks() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            self?.closeIfClickedOutside()
        }
    }

    /// 활성 앱이 아니라서 전역 감시자가 우리 앱으로 가는 클릭까지 받는다.
    /// (활성 앱이었다면 AppKit이 걸러준다.) 그래서 좌표로 직접 판별한다.
    ///
    /// 두 곳은 바깥이 아니다:
    ///  - 팝오버 자신 — 여기서 닫으면 설정을 만질 수가 없다
    ///  - 메뉴바 아이콘 — togglePopover가 처리한다.
    ///    여기서 먼저 닫으면 이어서 버튼 동작이 다시 열어버린다.
    private func closeIfClickedOutside() {
        let point = NSEvent.mouseLocation   // 화면 좌표, 원점 좌하단

        // 팝오버 본체와, 그 위에 뜬 우리 앱 창(언어 팝업 메뉴 등)
        if NSApp.windows.contains(where: { $0.isVisible && $0.frame.contains(point) }) {
            return
        }
        if let button = statusItem.button, let host = button.window {
            let onScreen = host.convertToScreen(button.convert(button.bounds, to: nil))
            if onScreen.contains(point) { return }
        }
        popover.performClose(nil)
    }

    private func stopWatchingOutsideClicks() {
        guard let monitor = outsideClickMonitor else { return }
        NSEvent.removeMonitor(monitor)
        outsideClickMonitor = nil
    }

    /// 어떤 경로로 닫히든(바깥 클릭, esc, 아이콘 재클릭) 감시자를 정리한다.
    func popoverDidClose(_ notification: Notification) {
        stopWatchingOutsideClicks()
    }

    /// 작업 중에 앱을 끄면 그때까지 한 만큼은 남긴다.
    /// stop()이 세션을 닫으면서 onWorkSessionEnded를 부른다.
    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
    }
}
