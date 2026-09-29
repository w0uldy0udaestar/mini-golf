@testable import GolfCore
import XCTest

/// 샷 종류(M5-③) 탄도 프로브 — 상시 테스트. 평지 페어웨이에서 클럽별 캐리·정점·굴림을 재고, 종류 사이 차이가
/// "화면에서 읽히는" 크기로 유지되는지 지킨다 (2026-09-29 계측 기준: 7I 풀샷 정점 기본 57m·펀치 33m·런닝 17m·로브 66m).
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
            ("3I", 1.0),
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
        let base = try XCTUnwrap(i7[.standard]), punch = try XCTUnwrap(i7[.punch]), run = try XCTUnwrap(i7[.running]),
            lob = try XCTUnwrap(i7[.lob])
        XCTAssertLessThan(punch.apex, base.apex * 0.65, "펀치 정점이 기본의 65% 아래가 아님 (\(punch.apex) vs \(base.apex))")
        XCTAssertGreaterThan(punch.roll, base.roll * 1.8, "펀치 굴림이 기본의 1.8배 이상이 아님")
        XCTAssertLessThan(run.apex, punch.apex * 0.6, "런닝 정점이 펀치의 60% 아래가 아님 (\(run.apex) vs \(punch.apex))")
        XCTAssertGreaterThan(run.roll, punch.roll * 1.4, "런닝 굴림이 펀치의 1.4배 이상이 아님")
        XCTAssertGreaterThan(lob.apex, base.apex * 1.08, "로브 정점이 기본보다 높지 않음 (\(lob.apex) vs \(base.apex))")
        XCTAssertLessThan(lob.total, base.total * 0.7, "로브 총거리가 기본의 70% 아래가 아님 (짧고 서야 한다)")
        XCTAssertLessThan(lob.roll, base.roll * 0.6, "로브 굴림이 기본보다 확실히 짧지 않음")
        // 밸런스 가드 (전 클럽 풀샷): 펀치·런닝이 평지에서 기본보다 12% 넘게 멀리 가면 늘 낮게 치는 게 정답이 된다 —
        // 웨지는 풍선 탄도라 같은 배율이면 +36%였다(리뷰 F2) → speedScale(for:)을 클럽군별로 (부분 스윙은 파워 오차 안이라 표만)
        for (key, row) in rows where key.hasSuffix("h1.0") {
            let std = try XCTUnwrap(row[.standard])
            XCTAssertLessThan(
                try XCTUnwrap(row[.punch]?.total),
                std.total * 1.12,
                "\(key) 펀치가 기본보다 12% 넘게 멀리 감 (\(row[.punch]!.total) vs \(std.total))"
            )
            XCTAssertLessThan(
                try XCTUnwrap(row[.running]?.total),
                std.total * 1.12,
                "\(key) 런닝이 기본보다 12% 넘게 멀리 감 (\(row[.running]!.total) vs \(std.total))"
            )
        }
        // 맞바람 6m/s에서 낮은 샷의 이점은 있어야 한다 (선택의 이유)
        let baseW = fly("7I", h: 1, shape: .standard, wind: -6), punchW = fly("7I", h: 1, shape: .punch, wind: -6)
        XCTAssertGreaterThan(punchW.total, baseW.total * 1.08, "맞바람에서 펀치 이점이 8% 미만")
        // 클램프 가드: 드라이버 낮은 샷이 땅을 구르는 로프트가 아니고, 샌드웨지 로브가 되감겨 제자리에 서지 않는다
        let dr = try XCTUnwrap(rows["DR h1.0"])
        XCTAssertGreaterThan(try XCTUnwrap(dr[.punch]?.apex), 5, "드라이버 펀치가 땅볼 (정점 \(dr[.punch]!.apex)m)")
        XCTAssertLessThan(
            try XCTUnwrap(dr[.running]?.total),
            try XCTUnwrap(dr[.standard]?.total),
            "드라이버 런닝이 기본 드라이브보다 멀리 감"
        )
        let sw = try XCTUnwrap(rows["SW h1.0"])
        XCTAssertGreaterThan(
            try XCTUnwrap(sw[.lob]?.total),
            try XCTUnwrap(sw[.standard]?.total) * 0.6,
            "샌드웨지 로브가 너무 짧음 (\(sw[.lob]!.total) vs \(sw[.standard]!.total))"
        )
    }
}
