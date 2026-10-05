import AppKit
import Carbon.HIToolbox
@testable import MiniGolf
import XCTest

/// 불러내기 단축키 (2026-10-05 M6): 키 입력 → 조합 판정·표시·저장 형식, Carbon 등록.
/// 실제 키를 눌러 게임이 불려 나오는지는 사람 손으로만 확인한다 — 테스트가 시스템에 키 이벤트를 보내면 쓰던 앱으로 샌다.
/// ⚠️ Carbon은 **다른 앱**과의 충돌을 알려 주지 않는다 — 여기서 확인하는 거절은 조합 규칙·시스템 단축키·같은 프로세스 중복뿐이다
final class HotkeyTests: XCTestCase {
    private let ctrlOpt = UInt32(controlKey | optionKey)
    private let all4 = UInt32(controlKey | optionKey | shiftKey | cmdKey)

    private func key(
        _ code: Int,
        _ chars: String,
        _ flags: NSEvent.ModifierFlags,
        repeating: Bool = false
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
            characters: chars, charactersIgnoringModifiers: chars, isARepeat: repeating, keyCode: UInt16(code)
        ))
    }

    private func rejection(_ code: Int, _ chars: String, _ flags: NSEvent.ModifierFlags) throws -> HotkeyCombo
        .Rejection? {
        if case let .failure(why) = try HotkeyCombo.classify(key(code, chars, flags)) {
            return why
        }
        return nil
    }

    func testPlainKeysPassThroughToTheDialog() throws {
        XCTAssertEqual(try rejection(kVK_ANSI_G, "g", []), .notACombo, "수식키 없는 글자")
        XCTAssertEqual(try rejection(kVK_ANSI_G, "G", [.shift]), .notACombo, "⇧만으로는 글자 입력")
        XCTAssertEqual(try rejection(kVK_Escape, "\u{1b}", []), .notACombo, "Esc는 대화상자의 취소로")
        XCTAssertEqual(try rejection(kVK_Return, "\r", []), .notACombo)
        XCTAssertEqual(try rejection(kVK_F5, "\u{F708}", []), .notACombo, "F1~F12 단독은 조합이 아니다")
    }

    /// 수식키 하나짜리(또는 ⌃·⌥ 없는 조합)는 다른 앱의 흔한 단축키 자리 — 받지 않는다 (리뷰: ⌘Q를 누르면 그게 전역 단축키로 저장됐다)
    func testSingleModifierCombosAreRejected() throws {
        XCTAssertEqual(try rejection(kVK_ANSI_Q, "q", [.command]), .tooFewModifiers)
        XCTAssertEqual(try rejection(kVK_ANSI_C, "c", [.command]), .tooFewModifiers)
        XCTAssertEqual(try rejection(kVK_ANSI_C, "c", [.control]), .tooFewModifiers, "⌃C = 터미널 인터럽트")
        XCTAssertEqual(try rejection(kVK_ANSI_E, "e", [.option]), .tooFewModifiers)
        XCTAssertEqual(try rejection(kVK_Space, " ", [.command]), .tooFewModifiers, "⌘Space = Spotlight")
        XCTAssertEqual(try rejection(kVK_ANSI_G, "g", [.command, .shift]), .tooFewModifiers, "⌘⇧는 앱 단축키의 표준 자리")
        XCTAssertEqual(try rejection(kVK_F5, "\u{F708}", [.command]), .tooFewModifiers)
        XCTAssertFalse(HotkeyCombo.isAllowed(keyCode: UInt32(kVK_ANSI_G), modifiers: 0))
        XCTAssertFalse(HotkeyCombo.isAllowed(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(cmdKey | shiftKey)))
        XCTAssertFalse(HotkeyCombo.isAllowed(keyCode: 99999, modifiers: ctrlOpt), "키 코드 범위 밖")
    }

    func testAllowedCombos() {
        let g = UInt32(kVK_ANSI_G)
        XCTAssertTrue(HotkeyCombo.isAllowed(keyCode: g, modifiers: ctrlOpt))
        XCTAssertTrue(HotkeyCombo.isAllowed(keyCode: g, modifiers: UInt32(controlKey | shiftKey)))
        XCTAssertTrue(HotkeyCombo.isAllowed(keyCode: g, modifiers: UInt32(optionKey | cmdKey)))
        XCTAssertTrue(HotkeyCombo.isAllowed(keyCode: g, modifiers: all4))
        XCTAssertTrue(HotkeyCombo.isAllowed(keyCode: UInt32(kVK_F13), modifiers: 0), "F13~F19는 단독 허용")
        XCTAssertTrue(HotkeyCombo.isAllowed(keyCode: UInt32(kVK_F19), modifiers: 0))
    }

    func testLabelAndDisplay() throws {
        // 시스템 단축키와 겹칠 일이 사실상 없는 네 수식키 조합으로 확인 (겹치면 그 기계에서는 건너뛴다)
        try XCTSkipIf(HotkeyCombo.isSystemShortcut(keyCode: UInt32(kVK_ANSI_G), modifiers: all4), "이 기계의 시스템 단축키와 겹침")
        let flags: NSEvent.ModifierFlags = [.command, .shift, .control, .option]
        let g = try XCTUnwrap(try HotkeyCombo(event: key(kVK_ANSI_G, "g", flags)))
        XCTAssertEqual(g.keyCode, UInt32(kVK_ANSI_G))
        XCTAssertEqual(g.modifiers, all4)
        XCTAssertEqual(g.display, "⌃⌥⇧⌘G", "수식키는 macOS 메뉴 순서로")
        // 한글 입력 상태에서는 같은 키가 "ㅎ"으로 들어온다 — 이름은 키 자리 기준이어야 한다 (리뷰)
        XCTAssertEqual(try HotkeyCombo(event: key(kVK_ANSI_G, "ㅎ", flags))?.label, "G")
        XCTAssertEqual(try HotkeyCombo(event: key(kVK_ANSI_2, "@", flags))?.label, "2", "⇧ 글자가 아니라 키 이름")
        XCTAssertEqual(try HotkeyCombo(event: key(kVK_Space, " ", flags))?.label, "Space")
        XCTAssertEqual(try HotkeyCombo(event: key(kVK_LeftArrow, "\u{F702}", flags))?.label, "←")
        XCTAssertEqual(HotkeyCombo(keyCode: UInt32(kVK_ANSI_G), modifiers: ctrlOpt, label: "G").display, "⌃⌥G")
    }

    func testStoredFormRoundTripsAndIsValidated() {
        let combo = HotkeyCombo(keyCode: UInt32(kVK_ANSI_G), modifiers: ctrlOpt, label: "G")
        XCTAssertEqual(HotkeyCombo(stored: combo.stored), combo)
        let comma = HotkeyCombo(keyCode: UInt32(kVK_ANSI_Comma), modifiers: ctrlOpt, label: ",") // 쉼표 키 — 구분자와 같은 글자
        XCTAssertEqual(HotkeyCombo(stored: comma.stored), comma)
        XCTAssertNil(HotkeyCombo(stored: ""))
        XCTAssertNil(HotkeyCombo(stored: "5,4096"))
        XCTAssertNil(HotkeyCombo(stored: "x,y,G"))
        // 손으로 고친 값도 같은 규칙으로 거른다 (리뷰: "5,0,G"가 수식키 없는 G를 전역으로 등록했다)
        XCTAssertNil(HotkeyCombo(stored: "5,0,G"), "수식키 없음")
        XCTAssertNil(HotkeyCombo(stored: "5,256,G"), "⌘ 하나")
        XCTAssertNil(HotkeyCombo(stored: "99999,6144,X"), "키 코드 범위 밖")
        XCTAssertNil(HotkeyCombo(stored: "5,6144,\n"), "이름이 제어 문자")
        XCTAssertNil(HotkeyCombo(stored: "5,\(6144 + 65536),G"), "모르는 수식키 비트")
    }

    /// macOS 시스템 단축키(Spotlight·입력 소스 전환 등)와 같은 조합은 등록 전에 거절한다
    func testSystemShortcutsAreRejected() throws {
        let system = HotkeyCombo.systemShortcuts()
        print("SYSHOTKEYS \(system.count) enabled")
        for s in system.prefix(40) {
            XCTAssertTrue(HotkeyCombo.isSystemShortcut(keyCode: s.keyCode, modifiers: s.modifiers))
        }
        // 조합 규칙은 통과하지만 시스템 단축키인 것이 있으면, 등록이 거절되는지까지 본다
        guard let clash = system.first(where: { HotkeyCombo.isAllowed(keyCode: $0.keyCode, modifiers: $0.modifiers) })
        else {
            throw XCTSkip("이 기계에는 조합 규칙을 통과하는 시스템 단축키가 없다 (목록 \(system.count)개)")
        }
        let center = HotkeyCenter()
        XCTAssertFalse(center.register(HotkeyCombo(keyCode: clash.keyCode, modifiers: clash.modifiers, label: "?")))
        XCTAssertNil(center.current)
    }

    /// 실제 등록: 잘 안 쓰는 조합(⌃⌥⇧⌘F18)을 잠깐 잡았다 놓는다. **같은 프로세스 안에서** 같은 조합을 두 번째로 잡으면 거절되고
    /// 첫 등록은 그대로여야 한다. (다른 앱이 쥔 조합은 Carbon이 거절하지 않는다 — 그건 테스트할 수 없고 문구로 알린다)
    func testRegisterRejectsDuplicateInProcessAndRestoresPrevious() throws {
        let a = HotkeyCenter(), b = HotkeyCenter()
        defer {
            a.unregister()
            b.unregister()
        }
        let rare = HotkeyCombo(keyCode: UInt32(kVK_F18), modifiers: all4, label: "F18")
        let other = HotkeyCombo(keyCode: UInt32(kVK_F17), modifiers: all4, label: "F17")
        try XCTSkipUnless(a.register(rare), "이 환경에서는 전역 단축키를 등록할 수 없다 (창 서버 없음?)")
        XCTAssertEqual(a.current, rare)
        XCTAssertFalse(b.register(rare), "같은 프로세스가 이미 잡은 조합은 거절")
        XCTAssertNil(b.current)
        XCTAssertTrue(b.register(other))
        XCTAssertFalse(b.register(rare), "거절되면")
        XCTAssertEqual(b.current, other, "이전 조합을 되살려 둔다")
        XCTAssertTrue(a.register(nil), "nil = 해제")
        XCTAssertNil(a.current)
        XCTAssertTrue(b.register(rare), "풀린 조합은 다시 잡힌다")
        XCTAssertFalse(
            a.register(HotkeyCombo(keyCode: UInt32(kVK_ANSI_Q), modifiers: UInt32(cmdKey), label: "Q")),
            "규칙에 어긋난 조합은 등록도 안 된다"
        )
    }

    /// 인스턴스가 사라지면 단축키와 핸들러를 거둔다 — 남은 핸들러는 죽은 포인터를 든 채 다음 단축키 이벤트를 먼저 받는다 (리뷰)
    func testCenterCleansUpOnDeinit() throws {
        let rare = HotkeyCombo(keyCode: UInt32(kVK_F16), modifiers: all4, label: "F16")
        do {
            let temp = HotkeyCenter()
            try XCTSkipUnless(temp.register(rare), "이 환경에서는 전역 단축키를 등록할 수 없다")
        }
        let next = HotkeyCenter()
        defer { next.unregister() }
        XCTAssertTrue(next.register(rare), "앞 인스턴스가 해제되며 조합을 놓았어야 한다")
    }

    /// 기록 대화상자의 키 처리: 보통 키는 통과, 규칙 위반은 소비하고 이유를 남기며 확정하지 않는다, 반복 입력은 무시
    func testRecorderHandlesKeysWithoutPickingBadCombos() throws {
        let recorder = HotkeyRecorder(current: nil)
        XCTAssertNotNil(try recorder.handle(key(kVK_ANSI_G, "g", [])), "보통 키는 대화상자로 넘긴다")
        XCTAssertNil(try recorder.handle(key(kVK_ANSI_Q, "q", [.command])), "⌘Q는 소비한다 (대화상자·앱으로 새지 않게)")
        XCTAssertNil(recorder.picked, "…하지만 확정하지 않는다")
        XCTAssertNotNil(recorder.lastNote, "이유를 알린다")
        let before = recorder.lastNote
        XCTAssertNil(try recorder.handle(key(kVK_ANSI_W, "w", [.command], repeating: true)))
        XCTAssertEqual(recorder.lastNote, before, "누르고 있는 동안의 반복 입력은 다시 판정하지 않는다")
    }
}
