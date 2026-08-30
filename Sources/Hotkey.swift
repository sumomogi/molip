import AppKit
import Carbon.HIToolbox

/// 전역 단축키 ⌃⌥F. 접근성 권한 없이 동작한다.
final class Hotkey {

    /// C 콜백은 컨텍스트를 못 잡으니 여기 둔다.
    private static var action: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// 화면에 표시할 이름.
    static let displayName = "⌃⌥F"

    func install(_ action: @escaping () -> Void) {
        Hotkey.action = action

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ in
                Hotkey.action?()
                return noErr
            },
            1, &spec, nil, &handlerRef
        )

        if Prefs.hotkeyEnabled { register() }
    }

    func setEnabled(_ on: Bool) {
        on ? register() : unregister()
    }

    private func register() {
        guard hotKeyRef == nil else { return }
        // 'MLIP'
        let id = EventHotKeyID(signature: OSType(0x4D4C4950), id: 1)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_F),
            UInt32(controlKey | optionKey),
            id,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    private func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }
}
