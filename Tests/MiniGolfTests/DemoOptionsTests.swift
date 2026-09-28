@testable import MiniGolf
import XCTest

/// 관찰 플래그 파싱 — 실플레이(인자 없음)는 전부 기본값, 하위 플래그 하나로 관찰 모드, 값은 클램프·정규화
final class DemoOptionsTests: XCTestCase {
    func testNoArgumentsIsAllDefaults() {
        let d = DemoOptions(arguments: ["MiniGolf"])
        XCTAssertFalse(d.active)
        XCTAssertNil(d.seed)
        XCTAssertNil(d.power)
        XCTAssertNil(d.hour)
        XCTAssertNil(d.surpriseKind)
        XCTAssertEqual(d.startHole, 1)
        XCTAssertEqual(d.motionCursorStart, 0)
    }

    func testAnyDemoFlagActivatesObservationMode() {
        let d = DemoOptions(arguments: ["MiniGolf", "--demo-pickup"])
        XCTAssertTrue(d.active)
        XCTAssertTrue(d.pickupForce)
        XCTAssertFalse(DemoOptions(arguments: ["MiniGolf", "--seed", "19"]).active, "--seed만으로는 관찰 모드가 아니다")
    }

    func testValuesParseClampAndNormalize() {
        let d = DemoOptions(arguments: [
            "MiniGolf", "--demo-power", "1.7", "--demo-hour", "-3", "--seed", "19", "--motion-cursor", "-2",
            "--surprise", "nap", "--demo-mood", "sad", "--demo-hole", "4", "--screen", "1",
        ])
        XCTAssertEqual(d.power, 1)
        XCTAssertEqual(d.hour, 21)
        XCTAssertEqual(d.seed, 19)
        XCTAssertEqual(d.motionCursorStart, 0)
        XCTAssertEqual(d.surpriseKind, .nap)
        XCTAssertEqual(d.mood, .sad)
        XCTAssertEqual(d.startHole, 4)
        XCTAssertEqual(d.screenIndex, 1)
    }

    func testMalformedOrMissingValuesFallBack() {
        let d = DemoOptions(arguments: ["MiniGolf", "--seed", "abc", "--surprise", "unicorn", "--demo-power"])
        XCTAssertNil(d.seed)
        XCTAssertNil(d.surpriseKind)
        XCTAssertNil(d.power, "값 없는 마지막 플래그는 무시")
        XCTAssertTrue(d.active)
    }
}
