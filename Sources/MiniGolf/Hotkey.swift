import AppKit
import Carbon.HIToolbox
import GolfCore

// ═══════════════════════════════════════════════════════════════
// 불러내기 단축키 (2026-10-05, M6 — IDEAS "활성화 단축키 사용자 설정")
// 어느 앱에 있든 한 번에 게임을 불러내고(키보드 회수·재개), 다시 누르면 쉬게 한다 = 메뉴바 ⛳️ 좌클릭과 같은 토글.
// 2026-08-14에 고정 단축키(⌥⌘G → ⌃⌥⌘G → ⌃⇧G)가 다른 앱과 충돌을 되풀이해 제거됐다 — 그래서 **기본값이 없고** 사용자가
// ⛳️ 메뉴에서 직접 정한다. 등록은 Carbon RegisterEventHotKey(접근성 권한 불필요).
//
// ⚠️ Carbon은 다른 앱과의 충돌을 알려 주지 않는다 (리뷰 실측 2026-10-05 — CarbonEvents.h: "The same hot key can be registered by
// multiple applications", 다른 프로세스가 쥔 조합도 noErr). 등록된 조합은 **모든 앱에서 게임이 먼저 받는다**. 그래서 방어는 셋뿐이다:
// ① 조합 규칙 — ⌃ 또는 ⌥를 포함해 수식키 둘 이상(⌘C·⌘Q·⌃C 같은 한 개짜리는 거절), F13~F19만 단독 허용
// ② macOS 시스템 단축키(Spotlight·입력 소스 전환·Mission Control 등)와 겹치면 거절 — `CopySymbolicHotKeys`
// ③ 대화상자가 "다른 앱의 같은 단축키는 가려진다"고 사실대로 알린다
// ═══════════════════════════════════════════════════════════════

/// 키 조합 하나. modifiers는 Carbon 비트(cmdKey·optionKey·controlKey·shiftKey), label은 키 이름("G"·"F5"·"Space")
struct HotkeyCombo: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let label: String

    static let prefKey = "summonHotkey"
    static let modifierMask = UInt32(cmdKey | optionKey | controlKey | shiftKey)

    /// 조합으로 받지 않는 이유
    enum Rejection: Error, Equatable {
        case notACombo // ⌘·⌥·⌃이 없는 보통 키 입력 — 대화상자에 넘긴다 (Esc·Return)
        case tooFewModifiers // 수식키가 모자라다 — 다른 앱의 흔한 단축키 자리
        case systemShortcut // macOS 시스템 단축키와 같다
    }

    /// 글자가 아닌 키의 이름 (charactersIgnoringModifiers가 제어 문자·사설 영역이라 표로)
    private static let specialNames: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Escape: "⎋",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15",
        kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19",
    ]

    /// 글자·숫자·기호 키의 이름 — 키 자리(ANSI 자판) 기준. 입력 소스에서 읽으면 한글 상태에서 ⌃⌥G가 "⌃⌥ㅎ"로, ⌃⇧2가 "⌃⇧@"로 적힌다
    private static let ansiNames: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E", kVK_ANSI_F: "F",
        kVK_ANSI_G: "G",
        kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_M: "M",
        kVK_ANSI_N: "N",
        kVK_ANSI_O: "O", kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U",
        kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X", kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4", kVK_ANSI_5: "5",
        kVK_ANSI_6: "6",
        kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
        kVK_ANSI_Backslash: "\\",
        kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/",
        kVK_ANSI_Grave: "`",
    ]

    private static let freeFunctionKeys: Set<Int> = [kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19]

    init(keyCode: UInt32, modifiers: UInt32, label: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.label = label
    }

    /// 조합 규칙 (머리말 ①): ⌃ 또는 ⌥를 포함해 수식키 둘 이상. F13~F19는 쓰는 앱이 없어 단독도 허용
    static func isAllowed(keyCode: UInt32, modifiers: UInt32) -> Bool {
        guard keyCode <= 0x7F else { return false }
        if freeFunctionKeys.contains(Int(keyCode)) {
            return true
        }
        let mods = modifiers & modifierMask
        return mods.nonzeroBitCount >= 2 && mods & UInt32(controlKey | optionKey) != 0
    }

    /// 켜져 있는 macOS 시스템 단축키 목록 (키 코드, 수식키) — Spotlight·입력 소스 전환·Mission Control·스크린샷 등
    static func systemShortcuts() -> [(keyCode: UInt32, modifiers: UInt32)] {
        var unmanaged: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&unmanaged) == noErr, let list = unmanaged?.takeRetainedValue() as? [[String: Any]]
        else { return [] }
        return list.compactMap { entry in
            guard entry[kHISymbolicHotKeyEnabled as String] as? Bool == true,
                  let code = entry[kHISymbolicHotKeyCode as String] as? Int,
                  let mods = entry[kHISymbolicHotKeyModifiers as String] as? Int,
                  code >= 0, code <= 0x7F
            else { return nil }
            return (UInt32(code), UInt32(truncatingIfNeeded: mods) & modifierMask)
        }
    }

    static func isSystemShortcut(keyCode: UInt32, modifiers: UInt32) -> Bool {
        systemShortcuts().contains { $0.keyCode == keyCode && $0.modifiers == modifiers & modifierMask }
    }

    /// 키 입력을 조합으로 읽는다 — 받을 수 없으면 그 이유
    static func classify(_ event: NSEvent) -> Result<HotkeyCombo, Rejection> {
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
        let hasCommandish = mods & UInt32(cmdKey | optionKey | controlKey) != 0
        guard hasCommandish || freeFunctionKeys.contains(code) else { return .failure(.notACombo) }
        guard isAllowed(keyCode: UInt32(code), modifiers: mods) else { return .failure(.tooFewModifiers) }
        let name = specialNames[code] ?? ansiNames[code] ?? event.charactersIgnoringModifiers?.uppercased() ?? ""
        guard isPrintable(name) else { return .failure(.notACombo) }
        guard !isSystemShortcut(keyCode: UInt32(code), modifiers: mods) else { return .failure(.systemShortcut) }
        return .success(HotkeyCombo(keyCode: UInt32(code), modifiers: mods, label: name))
    }

    init?(event: NSEvent) {
        guard case let .success(combo) = Self.classify(event) else { return nil }
        self = combo
    }

    /// 키 이름으로 쓸 수 있는가 — 제어 문자·공백·사설 영역(기능 키의 내부 글리프)이 없어야 한다
    private static func isPrintable(_ name: String) -> Bool {
        !name.isEmpty && name.unicodeScalars
            .allSatisfy { $0.value > 0x20 && $0.value != 0x7F && !(0xF700 ... 0xF8FF).contains($0.value) }
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

    /// 저장값도 같은 규칙으로 거른다 — 손으로 고친 값("5,0,G" = 수식키 없는 G)이 전역 키로 등록되지 않게. 시스템 단축키 대조는
    /// 등록 시점(`HotkeyCenter.register`)에 다시 한다 (저장 뒤에 사용자가 시스템 단축키를 바꿨을 수 있다)
    init?(stored: String) {
        let parts = stored.split(separator: ",", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, let code = UInt32(parts[0]), let mods = UInt32(parts[1]),
              Self.isAllowed(keyCode: code, modifiers: mods), mods & ~Self.modifierMask == 0,
              Self.isPrintable(String(parts[2]))
        else { return nil }
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
    private static var nextID: UInt32 = 1

    private let id: UInt32
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private(set) var current: HotkeyCombo?
    var onPress: (() -> Void)?

    init() {
        id = Self.nextID
        Self.nextID += 1
    }

    deinit { // 테스트가 만드는 인스턴스도 핸들러를 남기지 않는다 — 남으면 죽은 포인터를 든 채 다음 단축키 이벤트를 먼저 받는다 (리뷰)
        unregister()
        if let handler {
            RemoveEventHandler(handler)
        }
    }

    /// 조합을 등록한다(이전 것은 해제). nil이면 해제만. 규칙에 어긋나거나 시스템 단축키와 겹치거나 등록에 실패하면 false —
    /// 이전 조합을 되살려 둔다. ⚠️ 다른 앱이 같은 조합을 쓰고 있어도 true다 (Carbon은 알려 주지 않는다 — 파일 머리말)
    @discardableResult
    func register(_ combo: HotkeyCombo?) -> Bool {
        let previous = current
        unregister()
        guard let combo else { return true }
        var newRef: EventHotKeyRef?
        var status = OSStatus(paramErr)
        if HotkeyCombo.isAllowed(keyCode: combo.keyCode, modifiers: combo.modifiers),
           !HotkeyCombo.isSystemShortcut(keyCode: combo.keyCode, modifiers: combo.modifiers) {
            installHandlerIfNeeded()
            status = RegisterEventHotKey(
                combo.keyCode, combo.modifiers, EventHotKeyID(signature: OSType(0x4D47_4C46), id: id), // 'MGLF'
                GetApplicationEventTarget(), 0, &newRef
            )
        }
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
            { _, event, userData -> OSStatus in
                guard let userData, let event else { return OSStatus(eventNotHandledErr) }
                let center = Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
                var pressed = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &pressed
                )
                guard status == noErr,
                      pressed.id == center.id else { return OSStatus(eventNotHandledErr) } // 내 단축키가 아니면 다음 핸들러로
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
    private(set) var lastNote: String?

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
            "어느 앱에 있든 게임을 불러내고, 다시 누르면 쉬게 합니다.\n\n이 창이 떠 있는 동안 원하는 키 조합을 누르세요.\n⌃ 또는 ⌥를 포함해 수식키 두 개 이상 (예: ⌃⌥G)\n\n고른 조합은 다른 앱에서도 게임이 먼저 받습니다 — 평소 쓰지 않는 조합을 고르세요.",
            "Summons the game from any app, and rests it when pressed again.\n\nPress the key combo you want while this window is open.\nTwo or more modifiers including ⌃ or ⌥ (e.g. ⌃⌥G)\n\nThe game will receive this combo ahead of every other app — pick one you don't otherwise use."
        ) + "\n\n" + now + (note.map { "\n" + $0 } ?? "")
    }

    private func show(note: String) {
        lastNote = note
        alert.informativeText = prompt(note: note)
        NSSound.beep()
    }

    /// 대화상자가 떠 있는 동안의 키 입력 처리. 반환 nil = 소비. 조합이 아니면(수식키 없는 Esc·Return) 대화상자에 넘긴다
    func handle(_ event: NSEvent) -> NSEvent? {
        let result = HotkeyCombo.classify(event)
        if case .failure(.notACombo) = result {
            return event
        }
        guard !event.isARepeat else { return nil } // 누르고 있는 동안의 반복 입력 — 한 번만 판정한다
        switch result {
        case .failure(.tooFewModifiers):
            show(note: L(
                "수식키가 모자랍니다 — ⌘C·⌘Q처럼 다른 앱이 쓰는 자리입니다. ⌃ 또는 ⌥를 포함해 두 개 이상 눌러 주세요.",
                "Not enough modifiers — combos like ⌘C or ⌘Q belong to other apps. Use two or more, including ⌃ or ⌥."
            ))
        case .failure(.systemShortcut):
            show(note: L(
                "macOS 시스템 단축키와 같습니다. 다른 조합을 눌러 주세요.",
                "That is a macOS system shortcut. Try another combo."
            ))
        case .failure(.notACombo):
            break
        case let .success(combo):
            if HotkeyCenter.shared.register(combo) {
                picked = combo
                NSApp.stopModal(withCode: .OK)
            } else {
                show(note: L(
                    "\(combo.display)를 등록하지 못했습니다. 다른 조합을 눌러 주세요.",
                    "Could not register \(combo.display). Try another combo."
                ))
            }
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
