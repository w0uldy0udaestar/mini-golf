@testable import MiniGolf
import XCTest

/// 기록 저장 포맷 호환 (2026-10-05 M6): 새 항목이 옛 기록을 깨지 않고, 새 모자가 옛 버전의 디코딩을 깨지 않는다
final class RecordsTests: XCTestCase {
    private func decode(_ json: String) throws -> Records {
        try JSONDecoder().decode(Records.self, from: Data(json.utf8))
    }

    func testDecodesPreM6Records() throws {
        let r = try decode("""
        {"roundsCompleted":3,"holesPlayed":40,"totalStrokes":170,"bestRound":-1,"holeInOnes":0,"eagles":2,"birdies":9,
         "waterBalls":4,"showpiecesSeen":5,"badges":["firstRound","firstBirdie","bumperBank"],"hat":"straw"}
        """)
        XCTAssertEqual(r.holesPlayed, 40)
        XCTAssertEqual(r.badges, [.firstRound, .firstBirdie], "사라진 배지 이름은 건너뛴다")
        XCTAssertEqual(r.hat, .straw)
        XCTAssertEqual(r.missionsCleared, 0)
    }

    /// 라이벌(2026-10-05 추가 → 같은 날 삭제)이 쓰던 키가 남은 저장본도 나머지 기록은 그대로 읽고, 다시 저장하면 그 키는 사라진다
    func testIgnoresRemovedRivalKeys() throws {
        let r = try decode("""
        {"roundsCompleted":3,"holesPlayed":40,"totalStrokes":170,"birdies":9,"missionsCleared":2,"hat":"none","hatV2":"visor",
         "rivalWon":5,"rivalLost":3,"rivalTied":1,"totalPar":160,"recentOver":[0,1,-1,4]}
        """)
        XCTAssertEqual(r.holesPlayed, 40)
        XCTAssertEqual(r.totalStrokes, 170)
        XCTAssertEqual(r.missionsCleared, 2)
        XCTAssertEqual(r.hat, .visor)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(r)) as? [String: Any])
        for key in ["rivalWon", "rivalLost", "rivalTied", "totalPar", "recentOver"] {
            XCTAssertNil(obj[key], "\(key)")
        }
    }

    func testNewHatStaysReadableByOldVersions() throws {
        var r = Records()
        r.missionsCleared = 3
        r.hat = .visor
        let data = try JSONEncoder().encode(r)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        // 0.8.9 이하는 `hat` 키를 그때의 Hat 열거형으로 읽는다 — 거기 없는 이름이면 기록 전체가 초기화된다
        let legacyNames = ["none", "straw", "propeller", "top", "crown"]
        XCTAssertTrue(try legacyNames.contains(XCTUnwrap(obj["hat"] as? String)), "옛 키에는 옛 버전이 아는 모자만")
        XCTAssertEqual(obj["hatV2"] as? String, "visor")
        XCTAssertEqual(try JSONDecoder().decode(Records.self, from: data).hat, .visor, "새 버전은 새 키를 읽는다")
        for hat in Hat.allCases where hat != .visor {
            XCTAssertEqual(hat.legacy, hat)
        }
    }

    func testUnknownHatNameDoesNotLoseRecords() throws {
        let r = try decode(#"{"holesPlayed":12,"totalStrokes":50,"hat":"none","hatV2":"sombrero"}"#)
        XCTAssertEqual(r.holesPlayed, 12, "모르는 모자 이름이어도 나머지 기록은 읽는다")
        XCTAssertEqual(r.hat, .none)
    }

    func testVisorUnlocksByMissionsNotBadges() {
        var r = Records()
        XCTAssertFalse(r.unlockedHats.contains(.visor))
        r.missionsCleared = Hat.visorMissions
        XCTAssertTrue(r.unlockedHats.contains(.visor))
        XCTAssertFalse(r.unlockedHats.contains(.straw), "배지 모자는 여전히 배지 수로")
        r.badges = [.firstRound, .firstBirdie]
        XCTAssertEqual(r.unlockedHats.last, .straw, "배지 모자 자동 착용은 마지막 원소를 본다 — 선바이저가 뒤에 오면 안 된다")
    }
}
