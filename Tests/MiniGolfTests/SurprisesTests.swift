import Foundation
@testable import MiniGolf
import XCTest

/// 서프라이즈 3차 — 정각 뻐꾸기의 시계 창(정각 ±30초)과 종류 테이블 불변식
final class SurprisesTests: XCTestCase {
    private func date(_ h: Int, _ m: Int, _ s: Int) throws -> Date {
        var c = DateComponents()
        (c.year, c.month, c.day, c.hour, c.minute, c.second) = (2026, 9, 23, h, m, s)
        return try XCTUnwrap(Calendar.current.date(from: c))
    }

    func testNearHourWindowIsThirtySecondsEachSide() throws {
        XCTAssertEqual(try GameScene.nearHour(date(15, 0, 0)), 15)
        XCTAssertEqual(try GameScene.nearHour(date(15, 0, 30)), 15)
        XCTAssertNil(try GameScene.nearHour(date(15, 0, 31)))
        XCTAssertEqual(try GameScene.nearHour(date(14, 59, 30)), 15) // 59분 30초부터는 다음 정각
        XCTAssertNil(try GameScene.nearHour(date(14, 59, 29)))
        XCTAssertEqual(try GameScene.nearHour(date(23, 59, 45)), 0) // 자정은 0시 (12시간제 12번)
        XCTAssertNil(try GameScene.nearHour(date(9, 30, 0)))
    }

    func testThirdBatchKindsFollowTierHookRules() {
        let third: [SurpriseKind] = [.sprinkler, .windReverse, .caddie, .cuckoo, .dog]
        XCTAssertEqual(SurpriseKind.allCases.count, 17)
        XCTAssertEqual(third.map(\.tier), [.common, .rare, .common, .epic, .common])
        XCTAssertEqual(third.map(\.hook), [.inFlight, .inFlight, .aimStart, .clock, .ballRest])
        // 강아지만 씬을 점유 — 나머지는 비행·조준 위에 얹힌다
        XCTAssertEqual(third.filter(\.ownsScene), [.dog])
    }
}
