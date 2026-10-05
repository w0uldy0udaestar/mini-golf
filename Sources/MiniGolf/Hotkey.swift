import AppKit
import Carbon.HIToolbox
import GolfCore

// ═══════════════════════════════════════════════════════════════
// 불러내기 단축키 (2026-10-05, M6 — IDEAS "활성화 단축키 사용자 설정")
// 어느 앱에 있든 한 번에 게임을 불러내고(키보드 회수·재개), 다시 누르면 쉬게 한다 = 메뉴바 ⛳️ 좌클릭과 같은 토글.
// 2026-08-14에 고정 단축키(⌥⌘G → ⌃⌥⌘G → ⌃⇧G)가 다른 앱과 충돌을 되풀이해 제거됐다 — 그래서 **기본값이 없고** 사용자가
// ⛳️ 메뉴에서 직접 정한다. 등록은 Carbon RegisterEventHotKey(접근성 권한 불필요, 다른 곳이 이미 쓰는 조합은 등록 단계에서 거절된다).
// ═══════════════════════════════════════════════════════════════

/// 키 조합 하나. modifiers는 Carbon 비트(cmdKey·optionKey·controlKey·shiftKey), label은 기록 당시의 키 이름("G"·"F5"·"Space")
struct HotkeyCombo: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let label: String

    static let prefKey = "summonHotkey"

    /// 글자가 아닌 키의 이름 (charactersIgnoringModifiers가 제어 문자·사설 영역이라 표로)
    private static let specialNames: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Escape: "⎋",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15",
        kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19",
    ]

    init(keyCode: UInt32, modifiers: UInt32, label: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.label = label
    }

    /// 키 입력 → 조합. ⌘·⌥·⌃ 중 하나는 있어야 한다 — ⇧만으로는 글자 입력과 구분이 안 되고, 수식키 없는 키를 전역으로 잡으면
    /// 그 키를 어디서도 못 쓴다. F1~F19만 수식키 없이 허용
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var mods: UInt32 = 0
        if flags.contains(.command) {
            mods |= UInt32(cmdKey)
        }
        if flags.contains(.option) {
            mods |= UInt32(optionKey)
        }
        if flags.contains(.control) {
            mods |= UInt32(controlKey)
        }
        if flags.contains(.shift) {
            mods |= UInt32(shiftKey)
        }
        let code = Int(event.keyCode)
        let isFunctionKey = Self.specialNames[code]?.hasPrefix("F") == true
        guard mods & UInt32(cmdKey | optionKey | controlKey) != 0 || isFunctionKey else { return nil }
        let name = Self.specialNames[code] ?? event.charactersIgnoringModifiers?.uppercased() ?? ""
        guard !name.isEmpty,
              name.unicodeScalars.allSatisfy({ $0.value >= 0x20 && !(0xF700 ... 0xF8FF).contains($0.value) })
        else { return nil }
        self.init(keyCode: UInt32(code), modifiers: mods, label: name)
    }

    /// "⌃⌥⇧⌘G" — macOS 메뉴와 같은 순서
    var display: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 {
            s += "⌃"
        }
        if modifiers & UInt32(optionKey) != 0 {
            s += "⌥"
        }
        if modifiers & UInt32(shiftKey) != 0 {
            s += "⇧"
        }
        if modifiers & UInt32(cmdKey) != 0 {
            s += "⌘"
        }
        return s + label
    }

    // ── 저장 (UserDefaults, "keyCode,modifiers,label") ──

    var stored: String {
        "\(keyCode),\(modifiers),\(label)"
    }

    init?(stored: String) {
        let parts = stored.split(separator: ",", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, let code = UInt32(parts[0]), let mods = UInt32(parts[1]),
              !parts[2].isEmpty else { return nil }
        self.init(keyCode: code, modifiers: mods, label: String(parts[2]))
    }

    static var saved: HotkeyCombo? {
        get { UserDefaults.standard.string(forKey: prefKey).flatMap(HotkeyCombo.init(stored:)) }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.stored, forKey: prefKey)
            } else {
                UserDefaults.standard.removeObject(forKey: prefKey)
            }
        }
    }
}

/// 전역 단축키 등록 — 한 번에 하나만
final class HotkeyCenter {
    static let shared = HotkeyCenter()
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private(set) var current: HotkeyCombo?
    var onPress: (() -> Void)?

    /// 조합을 등록한다(이전 것은 해제). nil이면 해제만. 다른 앱·시스템이 이미 쓰는 조합이면 false — 이전 조합을 되살려 둔다
    @discardableResult
    func register(_ combo: HotkeyCombo?) -> Bool {
        let previous = current
        unregister()
        guard let combo else { return true }
        installHandlerIfNeeded()
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combo.keyCode, combo.modifiers, EventHotKeyID(signature: OSType(0x4D47_4C46), id: 1), // 'MGLF'
            GetApplicationEventTarget(), 0, &newRef
        )
        guard status == noErr, let newRef else {
            if let previous, previous != combo {
                register(previous)
            }
            return false
        }
        ref = newRef
        current = combo
        return true
    }

    func unregister() {
        if let ref {
            UnregisterEventHotKey(ref)
        }
        ref = nil
        current = nil
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let center = Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { center.onPress?() }
                return noErr
            },
            1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler
        )
    }
}

/// 단축키 기록 대화상자: 열어 두고 원하는 조합을 누르면 그 자리에서 등록을 시도한다
final class HotkeyRecorder {
    enum Outcome: Equatable { case set(HotkeyCombo), cleared, cancelled }

    private let alert = NSAlert()
    private let current: HotkeyCombo?
    private(set) var picked: HotkeyCombo?

    init(current: HotkeyCombo?) {
        self.current = current
        alert.messageText = L("불러내기 단축키", "Summon shortcut")
        alert.informativeText = prompt(note: nil)
        alert.addButton(withTitle: L("취소", "Cancel")).keyEquivalent = "\u{1b}"
        if current != nil {
            alert.addButton(withTitle: L("단축키 지우기", "Remove shortcut"))
        }
    }

    private func prompt(note: String?) -> String {
        let now = current.map { L("지금: \($0.display)", "Current: \($0.display)") } ?? L("지금: 없음", "Current: none")
        return L(
            "어느 앱에 있든 게임을 불러내고, 다시 누르면 쉬게 합니다.\n\n이 창이 떠 있는 동안 원하는 키 조합을 누르세요.\n(⌘ · ⌥ · ⌃ 중 하나 이상 포함)",
            "Summons the game from any app, and rests it when pressed again.\n\nPress the key combo you want while this window is open.\n(Include at least one of ⌘ · ⌥ · ⌃)"
        ) + "\n\n" + now + (note.map { "\n" + $0 } ?? "")
    }

    /// 대화상자가 떠 있는 동안의 키 입력 처리. 반환 nil = 소비. 조합이 아니면(수식키 없는 Esc·Return) 대화상자에 넘긴다
    func handle(_ event: NSEvent) -> NSEvent? {
        guard let combo = HotkeyCombo(event: event) else { return event }
        if HotkeyCenter.shared.register(combo) {
            picked = combo
            NSApp.stopModal(withCode: .OK)
        } else {
            alert.informativeText = prompt(note: L(
                "\(combo.display)는 이미 다른 곳에서 쓰고 있습니다. 다른 조합을 눌러 주세요.",
                "\(combo.display) is already taken. Try another combo."
            ))
            NSSound.beep()
        }
        return nil
    }

    /// 대화상자를 띄우고 결과를 돌려준다. `.set`이면 이미 등록까지 끝난 상태 (저장은 호출측)
    func run(activate: Bool = true) -> Outcome {
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return handle(event)
        }
        if activate { // 관찰(--demo-hotkey-ui)은 사용자의 키보드를 가져가지 않는다
            NSApp.activate(ignoringOtherApps: true)
        }
        let code = alert.runModal()
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        alert.window.orderOut(nil)
        if let picked {
            return .set(picked)
        }
        return code == .alertSecondButtonReturn ? .cleared : .cancelled
    }

    /// 관찰용: 대화상자 창 (캡처 대상)
    var window: NSWindow {
        alert.window
    }
}
