import AppKit
import Carbon.HIToolbox
@testable import MiniGolf
import XCTest

/// 불러내기 단축키 (2026-10-05 M6): 키 입력 → 조합 판정·표시·저장 형식, Carbon 등록·충돌 감지.
/// 실제 키를 눌러 게임이 불려 나오는지는 사람 손으로만 확인한다 — 테스트가 시스템에 키 이벤트를 보내면 쓰던 앱으로 샌다
final class HotkeyTests: XCTestCase {
    private func key(_ code: Int, _ chars: String, _ flags: NSEvent.ModifierFlags) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
            characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: UInt16(code)
        ))
    }

    func testComboNeedsARealModifier() throws {
        XCTAssertNil(try HotkeyCombo(event: key(kVK_ANSI_G, "g", [])), "수식키 없는 글자는 조합이 아니다")
        XCTAssertNil(try HotkeyCombo(event: key(kVK_ANSI_G, "G", [.shift])), "⇧만으로는 글자 입력과 구분이 안 된다")
        XCTAssertNil(try HotkeyCombo(event: key(kVK_Escape, "\u{1b}", [])), "Esc는 대화상자의 취소로 넘어가야 한다")
        XCTAssertNil(try HotkeyCombo(event: key(kVK_Return, "\r", [])))
        let g = try XCTUnwrap(try HotkeyCombo(event: key(kVK_ANSI_G, "g", [.control, .option])))
        XCTAssertEqual(g.keyCode, UInt32(kVK_ANSI_G))
        XCTAssertEqual(g.modifiers, UInt32(controlKey | optionKey))
        XCTAssertEqual(g.display, "⌃⌥G")
        let all = try XCTUnwrap(try HotkeyCombo(event: key(kVK_Space, " ", [.command, .shift, .control, .option])))
        XCTAssertEqual(all.display, "⌃⌥⇧⌘Space", "수식키는 macOS 메뉴 순서로")
        XCTAssertEqual(try HotkeyCombo(event: key(kVK_F5, "\u{F708}", []))?.display, "F5", "F키는 수식키 없이 허용")
        XCTAssertEqual(try HotkeyCombo(event: key(kVK_LeftArrow, "\u{F702}", [.command]))?.display, "⌘←")
    }

    func testStoredFormRoundTrips() {
        let combo = HotkeyCombo(keyCode: 5, modifiers: UInt32(controlKey | optionKey), label: "G")
        XCTAssertEqual(HotkeyCombo(stored: combo.stored), combo)
        let comma = HotkeyCombo(keyCode: 43, modifiers: UInt32(cmdKey), label: ",") // 쉼표 키 — 구분자와 같은 글자
        XCTAssertEqual(HotkeyCombo(stored: comma.stored), comma)
        XCTAssertNil(HotkeyCombo(stored: ""))
        XCTAssertNil(HotkeyCombo(stored: "5,4096"))
        XCTAssertNil(HotkeyCombo(stored: "x,y,G"))
    }

    /// 실제 등록: 잘 안 쓰는 조합(⌃⌥⇧⌘F18)을 잠깐 잡았다 놓는다. 같은 조합을 두 번째로 잡으면 거절되고 첫 등록은 그대로여야 한다
    func testRegisterDetectsConflictAndRestoresPrevious() {
        let a = HotkeyCenter(), b = HotkeyCenter()
        defer {
            a.unregister()
            b.unregister()
        }
        let rare = HotkeyCombo(
            keyCode: UInt32(kVK_F18),
            modifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey),
            label: "F18"
        )
        let other = HotkeyCombo(
            keyCode: UInt32(kVK_F17),
            modifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey),
            label: "F17"
        )
        XCTAssertTrue(a.register(rare))
        XCTAssertEqual(a.current, rare)
        XCTAssertFalse(b.register(rare), "이미 잡힌 조합은 거절")
        XCTAssertNil(b.current)
        XCTAssertTrue(b.register(other))
        XCTAssertFalse(b.register(rare), "거절되면")
        XCTAssertEqual(b.current, other, "이전 조합을 되살려 둔다")
        XCTAssertTrue(a.register(nil), "nil = 해제")
        XCTAssertNil(a.current)
        XCTAssertTrue(b.register(rare), "풀린 조합은 다시 잡힌다")
    }
}
