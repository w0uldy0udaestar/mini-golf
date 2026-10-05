@testable import MiniGolf
import XCTest

/// 관찰 플래그 파싱 — 실플레이(인자 없음)는 전부 기본값, 하위 플래그 하나로 관찰 모드, 값은 클램프·정규화
final class DemoOptionsTests: XCTestCase {
    func testNoArgumentsIsAllDefaults() {
        let d = DemoOptions(arguments: ["MiniGolf"])
        XCTAssertEqual(d, DemoOptions(), "인자 없는 실플레이는 전 필드가 기본값")
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
        XCTAssertTrue(DemoOptions(arguments: ["MiniGolf", "--demo"]).active)
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
        XCTAssertEqual(DemoOptions(arguments: ["x", "--demo-power", "0.01"]).power, 0.05, "파워 하한")
        XCTAssertEqual(DemoOptions(arguments: ["x", "--demo-hour", "27"]).hour, 3, "시각은 24로 랩")
    }

    func testShapeFlagParsesAndFallsBack() {
        XCTAssertEqual(DemoOptions(arguments: ["MiniGolf", "--demo-shape", "lob"]).shape, .lob)
        XCTAssertEqual(DemoOptions(arguments: ["MiniGolf", "--demo-shape", "punch"]).shape, .punch)
        XCTAssertNil(DemoOptions(arguments: ["MiniGolf", "--demo-shape", "flop"]).shape, "모르는 값은 nil → 기본 샷")
        XCTAssertNil(DemoOptions(arguments: ["MiniGolf", "--demo-shape"]).shape, "값 없음은 nil")
        XCTAssertNil(DemoOptions(arguments: ["MiniGolf"]).shape)
    }

    func testM6FlagsParse() {
        let d = DemoOptions(arguments: [
            "MiniGolf", "--weather", "rain", "--mission", "noDriver", "--lang", "en", "--demo-range", "--demo-notice",
        ])
        XCTAssertEqual(d.weather, .rain)
        XCTAssertEqual(d.mission, .noDriver)
        XCTAssertEqual(d.lang, .en)
        XCTAssertTrue(d.rangeStart)
        XCTAssertTrue(d.noticeForce)
        XCTAssertTrue(d.active, "--demo-* 가 하나라도 있으면 관찰 모드")
        // 날씨·언어만 고른 실플레이는 관찰 모드가 아니다 (기록이 쌓이고 키보드를 잡는다)
        let play = DemoOptions(arguments: ["MiniGolf", "--weather", "gale", "--lang", "ko"])
        XCTAssertFalse(play.active)
        XCTAssertEqual(play.weather, .gale)
        XCTAssertNil(DemoOptions(arguments: ["MiniGolf", "--weather", "snow"]).weather, "모르는 날씨는 무시 → 시드가 정한다")
        let trick = DemoOptions(arguments: ["MiniGolf", "--gimmick", "volcano"])
        XCTAssertEqual(trick.gimmick, .volcano)
        XCTAssertFalse(trick.active, "장치만 고른 실플레이는 관찰 모드가 아니다")
        XCTAssertNil(DemoOptions(arguments: ["MiniGolf", "--gimmick", "windmill"]).gimmick)
        XCTAssertNil(DemoOptions(arguments: ["MiniGolf", "--lang", "fr"]).lang)
        XCTAssertNil(DemoOptions(arguments: ["MiniGolf"]).mission)
    }

    func testMalformedOrMissingValuesFallBack() {
        let d = DemoOptions(arguments: ["MiniGolf", "--seed", "abc", "--surprise", "unicorn", "--demo-power"])
        XCTAssertNil(d.seed)
        XCTAssertNil(d.surpriseKind)
        XCTAssertNil(d.power, "값 없는 마지막 플래그는 무시")
        XCTAssertTrue(d.active)
    }
}
