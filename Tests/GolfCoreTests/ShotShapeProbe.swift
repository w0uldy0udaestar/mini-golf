@testable import GolfCore
import XCTest

/// 샷 종류(M5-③) 탄도 프로브 — 상시 테스트. 평지 페어웨이에서 클럽별 캐리·정점·굴림을 재고, 종류 사이 차이가
/// "화면에서 읽히는" 크기로 유지되는지 지킨다 펀치가 약하지도 공짜 거리도 아닌지 지킨다 (2026-09-29 1차 판정 반영).
/// 표는 `swift test --filter ShotShapeProbe`로 출력
final class ShotShapeProbe: XCTestCase {
    struct Flight { let carry: Double, apex: Double, total: Double, roll: Double, air: Double }

    private func flat(wind: Double) -> Hole {
        Hole(
            par: 5, dist: 480, holeX: 480, worldW: 520,
            greenStart: 470, greenEnd: 490, apronStart: 460,
            segments: [Segment(from: 0, to: 520, type: .fairway)],
            elevation: [Double](repeating: 0, count: 522),
            waterRange: nil, greenSlope: 0, wind: wind
        )
    }

    private func fly(_ id: String, h: Double, shape: ShotShape, wind: Double = 0) -> Flight {
        let hole = flat(wind: wind)
        let club = ClubTable.all.first { $0.id == id }!
        var b = BallState(x: 10, y: 0)
        Ballistics.launch(&b, club: club, heightPct: h, lie: .fairway, dir: 1, shape: shape)
        var apex = 0.0, carry = 0.0, t = 0.0, air = 0.0
        while b.phase != .rest, t < 60 {
            let ev = Ballistics.step(&b, hole: hole)
            apex = max(apex, b.y)
            if case .bounce = ev, carry == 0 {
                carry = b.x - 10; air = t
            }
            t += Phys.dt
        }
        if carry == 0 {
            carry = b.x - 10
        }
        return Flight(carry: carry, apex: apex, total: b.x - 10, roll: b.x - 10 - carry, air: air)
    }

    func testShapeTable() throws {
        var rows: [String: [ShotShape: Flight]] = [:]
        for (id, h) in [
            ("DR", 1.0),
            ("3W", 1.0),
            ("5W", 1.0),
            ("3I", 1.0),
            ("5I", 1.0),
            ("7I", 1.0),
            ("7I", 0.6),
            ("9I", 1.0),
            ("PW", 1.0),
            ("PW", 0.6),
            ("SW", 1.0),
            ("SW", 0.5),
        ] {
            print("── \(id) h\(h)")
            var row: [ShotShape: Flight] = [:]
            for s in ShotShape.allCases {
                let r = fly(id, h: h, shape: s)
                let w = fly(id, h: h, shape: s, wind: -6)
                row[s] = r
                print(String(
                    format: "  %-8@ carry %5.1f apex %4.1f roll %5.1f total %5.1f air %.2fs | 맞바람6 total %5.1f",
                    s.rawValue, r.carry, r.apex, r.roll, r.total, r.air, w.total
                ))
            }
            rows["\(id) h\(h)"] = row
        }
        // 읽히는 차이의 하한 — 7I 풀샷 (미들 아이언이 기준 클럽)
        let i7 = try XCTUnwrap(rows["7I h1.0"])
        let base = try XCTUnwrap(i7[.standard]), punch = try XCTUnwrap(i7[.punch]), lob = try XCTUnwrap(i7[.lob])
        XCTAssertLessThan(punch.apex, base.apex * 0.65, "펀치 정점이 기본의 65% 아래가 아님 (\(punch.apex) vs \(base.apex))")
        XCTAssertGreaterThan(punch.roll, base.roll * 1.8, "펀치 굴림이 기본의 1.8배 이상이 아님")
        XCTAssertGreaterThan(lob.apex, base.apex * 1.08, "로브 정점이 기본보다 높지 않음 (\(lob.apex) vs \(base.apex))")
        XCTAssertLessThan(lob.total, base.total * 0.7, "로브 총거리가 기본의 70% 아래가 아님 (짧고 서야 한다)")
        XCTAssertLessThan(lob.roll, base.roll * 0.6, "로브 굴림이 기본보다 확실히 짧지 않음")
        // 맞바람 6m/s에서 펀치의 이점은 있어야 한다 (선택의 이유)
        let baseW = fly("7I", h: 1, shape: .standard, wind: -6), punchW = fly("7I", h: 1, shape: .punch, wind: -6)
        XCTAssertGreaterThan(punchW.total, baseW.total * 1.08, "맞바람에서 펀치 이점이 8% 미만")
        // 밸런스 가드 (전 클럽 풀샷): 펀치의 **캐리**는 기본을 넘지 않는다 — 더 가는 거리는 굴림뿐이고 굴림은 러프·경사가 먹는다
        // (1차 판정: 굴림 포함 총거리 +12% 가드는 실플레이에서 "약하다" — 절벽 티 DR 펀치 224 vs 기본 290m). 총거리는 +20% 안(평지 상한).
        // 약하지도 않아야 한다: 캐리 ≥ 기본의 80%(우드)·88%(아이언·웨지) — 드라이버 펀치가 캐리 63%로 떨어졌던 게 판정의 원인
        for (key, row) in rows where key.hasSuffix("h1.0") {
            let std = try XCTUnwrap(row[.standard]), pu = try XCTUnwrap(row[.punch])
            XCTAssertLessThanOrEqual(pu.carry, std.carry * 1.02, "\(key) 펀치 캐리가 기본을 넘음 (\(pu.carry) vs \(std.carry))")
            XCTAssertLessThan(
                pu.total,
                std.total * 1.20,
                "\(key) 펀치 총거리가 기본보다 20% 넘게 멀리 감 (\(pu.total) vs \(std.total))"
            )
            let floor = ["DR", "3W", "5W"].contains { key.hasPrefix($0) } ? 0.80 : 0.88
            XCTAssertGreaterThan(pu.carry, std.carry * floor, "\(key) 펀치가 약함 — 캐리 \(pu.carry) vs 기본 \(std.carry)")
            XCTAssertLessThan(pu.apex, std.apex * 0.72, "\(key) 펀치가 낮지 않음 (정점 \(pu.apex) vs \(std.apex))")
        }
        // 클램프 가드: 드라이버 펀치가 땅볼이 아니고, 샌드웨지 로브가 되감겨 제자리에 서지 않는다
        let dr = try XCTUnwrap(rows["DR h1.0"])
        XCTAssertGreaterThan(try XCTUnwrap(dr[.punch]?.apex), 5, "드라이버 펀치가 땅볼 (정점 \(dr[.punch]!.apex)m)")
        let sw = try XCTUnwrap(rows["SW h1.0"])
        XCTAssertGreaterThan(
            try XCTUnwrap(sw[.lob]?.total),
            try XCTUnwrap(sw[.standard]?.total) * 0.6,
            "샌드웨지 로브가 너무 짧음 (\(sw[.lob]!.total) vs \(sw[.standard]!.total))"
        )
    }
}
