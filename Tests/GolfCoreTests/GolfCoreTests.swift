@testable import GolfCore
import XCTest

final class GolfCoreTests: XCTestCase {
    /// ── 헬퍼: 평지에서 풀샷 시뮬레이션 → (캐리, 총거리, 정점) ──
    private func simulate(
        club: Club,
        heightPct: Double = 1.0,
        from x0: Double = 50
    ) -> (carry: Double, total: Double, apex: Double) {
        let hole = Hole.flatTest()
        var b = BallState(x: x0, y: 0)
        Ballistics.launch(&b, club: club, heightPct: heightPct, lie: .fairway, dir: 1)
        var apex = 0.0
        var carry: Double? = nil
        var t = 0.0
        while b.phase != .rest, t < 60 {
            let wasFly = b.phase == .fly
            _ = Ballistics.step(&b, hole: hole)
            t += Phys.dt
            apex = max(apex, b.y)
            if carry == nil, wasFly, b.y <= 0.001 {
                carry = b.x - x0
            }
        }
        return (carry ?? 0, b.x - x0, apex)
    }

    private func club(_ id: String) -> Club {
        ClubTable.all.first { $0.id == id }!
    }

    // ── 탄도 ──

    func testDriverCarryInRealisticRange() {
        let r = simulate(club: club("DR"))
        XCTAssertGreaterThan(r.carry, 240, "드라이버 캐리가 너무 짧음")
        XCTAssertLessThan(r.carry, 300, "드라이버 캐리가 너무 김")
    }

    func testClubCarryMonotonicallyDecreases() {
        let order = ["DR", "3W", "5W", "3I", "4I", "5I", "6I", "7I", "8I", "9I", "PW", "SW"]
        let carries = order.map { simulate(club: club($0)).carry }
        for i in 1 ..< carries.count {
            XCTAssertLessThan(carries[i], carries[i - 1], "\(order[i]) 캐리가 \(order[i - 1])보다 김")
        }
    }

    func testLoftIncreasesLaunchAngle() {
        // 같은 파워라면 로프트가 클수록 발사각(vy/vx)이 커야 한다
        var prev = -1.0
        for id in ["DR", "5I", "9I", "SW"] {
            var b = BallState(x: 0, y: 0)
            Ballistics.launch(&b, club: club(id), heightPct: 1, lie: .fairway, dir: 1)
            let ratio = b.vy / b.vx
            XCTAssertGreaterThan(ratio, prev)
            prev = ratio
        }
    }

    func testBackspinCheckOnWedge() {
        let sw = simulate(club: club("SW"))
        let dr = simulate(club: club("DR"))
        XCTAssertLessThan(sw.total - sw.carry, 4, "샌드웨지는 백스핀으로 착지 후 거의 멈춰야 함")
        XCTAssertGreaterThan(dr.total - dr.carry, 10, "드라이버는 롤아웃이 있어야 함")
    }

    // ── 퍼팅: 립아웃 3구간 ──

    private func rollToCup(speed: Double) -> (event: StepEvent, finalX: Double) {
        let hole = Hole.flatTest(worldW: 300, holeX: 150)
        var b = BallState(x: 148, y: 0, vx: speed, phase: .roll)
        var t = 0.0
        while b.phase != .rest, t < 30 {
            let e = Ballistics.step(&b, hole: hole)
            if e == .holed {
                return (.holed, b.x)
            }
            t += Phys.dt
        }
        return (.none, b.x)
    }

    func testPuttCaptureWhenSlow() {
        XCTAssertEqual(rollToCup(speed: 2.5).event, .holed)
    }

    func testPuttLipOutWhenSlightlyFast() {
        let r = rollToCup(speed: 4.5)
        XCTAssertEqual(r.event, .none, "살짝 과속은 립아웃")
        XCTAssertLessThan(abs(r.finalX - 150), 2.0, "립아웃은 컵 근처 탭인 거리에 멈춰야 함")
    }

    func testPuttPassesWhenTooFast() {
        let r = rollToCup(speed: 7.0)
        XCTAssertEqual(r.event, .none)
        XCTAssertGreaterThan(r.finalX - 150, 3.0, "명백한 과속은 지나가야 함")
    }

    func testPutterTapIn() {
        let hole = Hole.flatTest(worldW: 300, holeX: 150)
        var b = BallState(x: 149.2, y: 0) // 0.8m 탭인
        Ballistics.launch(&b, club: club("PT"), heightPct: 0, lie: .green, dir: 1)
        var holed = false
        var t = 0.0
        while b.phase != .rest, t < 10 {
            if Ballistics.step(&b, hole: hole) == .holed {
                holed = true; break
            }
            t += Phys.dt
        }
        XCTAssertTrue(holed, "백스윙 0% 퍼터로 탭인이 가능해야 함")
    }

    // ── 코스 생성 ──

    func testCourseParSum36AndDistances() throws {
        for seed: UInt32 in [1, 7, 42, 12345] {
            let course = CourseGenerator.makeCourse(seed: seed)
            XCTAssertEqual(course.count, 9)
            XCTAssertEqual(course.reduce(0) { $0 + $1.par }, 36)
            for h in course {
                let range = try XCTUnwrap(CourseGenerator.distRange[h.par])
                XCTAssertTrue(range.contains(h.dist), "파\(h.par) 거리 \(h.dist)가 화이트 티 범위 밖")
            }
        }
    }

    func testCourseSegmentsContiguous() throws {
        for seed: UInt32 in [1, 7, 42, 12345] {
            for h in CourseGenerator.makeCourse(seed: seed) {
                XCTAssertEqual(h.segments.first?.from, 0)
                for i in 1 ..< h.segments.count {
                    XCTAssertEqual(h.segments[i].from, h.segments[i - 1].to, accuracy: 0.001, "세그먼트 사이 틈")
                }
                XCTAssertEqual(try XCTUnwrap(h.segments.last?.to), h.worldW, accuracy: 0.001)
            }
        }
    }

    // ── 지형 물리 ──

    private func findHole(where predicate: (Hole) -> Bool) -> Hole? {
        for seed: UInt32 in 1 ... 60 {
            if let h = CourseGenerator.makeCourse(seed: seed).first(where: predicate) {
                return h
            }
        }
        return nil
    }

    func testGreenBreakAffectsRoll() {
        guard let h = findHole(where: { abs($0.greenSlope) > 0.035 }) else {
            return XCTFail("브레이크 큰 그린을 못 찾음")
        }
        let slopeSign: Double = h.greenSlope > 0 ? 1 : -1 // 오르막 = 표고가 증가하는 방향
        func rollDist(from x0: Double, v: Double) -> Double {
            var b = BallState(x: x0, y: h.ground(at: x0), vx: v, phase: .roll, lipped: true)
            var t = 0.0
            while b.phase != .rest, t < 30 {
                _ = Ballistics.step(&b, hole: h); t += Phys.dt
            }
            return abs(b.x - x0)
        }
        // 컵에서 양방향으로 굴려 둘 다 그린 안에 머물게 한다 (그린 밖 마찰 오염·립아웃 배제)
        let uphill = rollDist(from: h.holeX + slopeSign * 1.5, v: slopeSign * 2)
        let downhill = rollDist(from: h.holeX - slopeSign * 1.5, v: -slopeSign * 2)
        XCTAssertGreaterThan(downhill, uphill * 1.5, "내리막 퍼팅이 오르막보다 확연히 멀리 가야 함")
    }

    func testBunkerPlugsBall() throws {
        guard let h = findHole(where: { hole in hole.segments.contains { $0.type == .bunker } }) else {
            return XCTFail("벙커 있는 홀을 못 찾음")
        }
        let bunker = try XCTUnwrap(h.segments.first { $0.type == .bunker })
        var b = BallState(x: bunker.from + 0.5, y: h.ground(at: bunker.from + 0.5), vx: 6, phase: .roll, lipped: true)
        var t = 0.0
        while b.phase != .rest, t < 10 {
            _ = Ballistics.step(&b, hole: h); t += Phys.dt
        }
        XCTAssertLessThan(b.x - bunker.from, 5, "벙커는 공을 잡아야 함")
    }

    func testWaterReturnsEvent() throws {
        guard let h = findHole(where: { $0.waterRange != nil }) else {
            return XCTFail("워터 있는 홀을 못 찾음")
        }
        let wr = try XCTUnwrap(h.waterRange)
        var b = BallState(x: wr.lowerBound - 3, y: h.ground(at: wr.lowerBound - 3), vx: 8, phase: .roll, lipped: true)
        var event = StepEvent.none
        var t = 0.0
        while b.phase != .rest, t < 10 {
            event = Ballistics.step(&b, hole: h)
            if event == .water {
                break
            }
            t += Phys.dt
        }
        XCTAssertEqual(event, .water)
    }

    // ── 연출 이벤트 (M3 사운드·이펙트용) ──

    func testBounceEventOnLanding() {
        let hole = Hole.flatTest()
        var b = BallState(x: 50, y: 0)
        Ballistics.launch(&b, club: club("7I"), heightPct: 1, lie: .fairway, dir: 1)
        var sawBounce = false
        var t = 0.0
        while b.phase != .rest, t < 60 {
            if case let .bounce(speed, surface) = Ballistics.step(&b, hole: hole) {
                XCTAssertGreaterThan(speed, 0)
                XCTAssertEqual(surface, .fairway)
                sawBounce = true
            }
            t += Phys.dt
        }
        XCTAssertTrue(sawBounce, "착지 시 bounce 이벤트가 나와야 함")
    }

    func testLipOutEmitsEvent() {
        let hole = Hole.flatTest(worldW: 300, holeX: 150)
        var b = BallState(x: 148, y: 0, vx: 4.5, phase: .roll)
        var saw = false
        var t = 0.0
        while b.phase != .rest, t < 30 {
            if Ballistics.step(&b, hole: hole) == .lipOut {
                saw = true
            }
            t += Phys.dt
        }
        XCTAssertTrue(saw, "립아웃 시 lipOut 이벤트가 나와야 함")
    }

    // ── 좌우 미러 홀 ──

    func testMirroredHolesAppearAndKeepIntegrity() {
        var sawLeftToRight = false, sawRightToLeft = false
        for seed in 1 ... 10 {
            for h in CourseGenerator.makeCourse(seed: UInt32(seed)) {
                if h.holeX > h.teeX {
                    sawLeftToRight = true
                } else {
                    sawRightToLeft = true
                }
                XCTAssertEqual(h.surface(at: h.teeX), .tee, "티 지점 라이가 티가 아님")
                XCTAssertEqual(abs(h.holeX - h.teeX), h.dist, accuracy: 0.001, "티-홀 거리 보존 실패")
                XCTAssertEqual(h.ground(at: h.teeX), 0, accuracy: 0.6, "티 주변은 평지여야 함")
            }
        }
        XCTAssertTrue(sawLeftToRight, "왼→오 홀이 하나도 없음")
        XCTAssertTrue(sawRightToLeft, "오→왼(미러) 홀이 하나도 없음")
    }

    // ── 스핀 물리 (2026-08-14 리서치 반영) ──

    func testPartialSwingSpinNotInflated() {
        // 상대 스핀(spin/v0)이 부분 스윙에서 풀스윙보다 커지지 않는다 — 구식 (0.6+0.4h)의
        // '살살 칠수록 스핀이 더 먹는' 역전 제거. 풀샷 절대 스핀은 리서치 이전과 동일 (밸런스 보존)
        let c = club("7I")
        func launched(_ h: Double) -> BallState {
            var b = BallState(x: 0, y: 0)
            Ballistics.launch(&b, club: c, heightPct: h, lie: .fairway, dir: 1)
            return b
        }
        let full = launched(1.0)
        let fullRatio = full.spin / hypot(full.vx, full.vy)
        for h in [0.1, 0.3, 0.5, 0.8] {
            let b = launched(h)
            XCTAssertLessThanOrEqual(b.spin / hypot(b.vx, b.vy), fullRatio * 1.001, "h=\(h)에서 상대 스핀 역전")
        }
        XCTAssertEqual(full.spin, c.spin, accuracy: 0.001, "풀샷 스핀이 클럽 기본값과 달라짐")
    }

    func testBounceBackupAndRelease() {
        // 그린 바운스: 고스핀 웨지는 뒤로 감기고(백업), 저스핀 드라이브는 전진(릴리스) —
        // (5/7, 2/7) 접지 해에서 두 상태가 같은 식으로 나온다 (리서치 §5-4 검산 케이스)
        let green = Hole(
            par: 3, dist: 100, holeX: 250, worldW: 300,
            greenStart: 0, greenEnd: 300, apronStart: 0,
            segments: [Segment(from: 0, to: 300, type: .green)],
            elevation: [Double](repeating: 0, count: 302),
            waterRange: nil, greenSlope: 0
        )
        var wedge = BallState(
            x: 100, y: 0.05, vx: 26 * cos(58 * .pi / 180), vy: -26 * sin(58 * .pi / 180),
            spin: 11000, spinSign: 1, phase: .fly
        )
        _ = Ballistics.step(&wedge, hole: green)
        XCTAssertLessThan(wedge.vx, 0, "고스핀 웨지가 첫 바운스에서 뒤로 감기지 않음")
        var drive = BallState(
            x: 100, y: 0.05, vx: 45 * cos(38 * .pi / 180), vy: -45 * sin(38 * .pi / 180),
            spin: 2200, spinSign: 1, phase: .fly
        )
        _ = Ballistics.step(&drive, hole: green)
        XCTAssertGreaterThan(drive.vx, 5, "저스핀 드라이브가 전진하지 않음")
    }

    // ── 미스샷 (풀파워 리스크) ──

    func testMishitReducesPowerSpinAndLiftsLaunchAngle() {
        let c = club("7I")
        var clean = BallState(x: 0, y: 0)
        var miss = BallState(x: 0, y: 0)
        Ballistics.launch(&clean, club: c, heightPct: 1, lie: .fairway, dir: 1)
        Ballistics.launch(&miss, club: c, heightPct: 1, lie: .fairway, dir: 1, mishit: 1)
        XCTAssertEqual(hypot(miss.vx, miss.vy) / hypot(clean.vx, clean.vy), 0.88, accuracy: 0.001) // 파워 -12%
        XCTAssertEqual(miss.spin / clean.spin, 0.7, accuracy: 0.001) // 스핀 -30%
        let dAngle = (atan2(miss.vy, miss.vx) - atan2(clean.vy, clean.vx)) * 180 / .pi
        XCTAssertEqual(dAngle, 4, accuracy: 0.05) // 발사각 +4°
    }

    func testMishitZeroIsIdentity() {
        let c = club("DR")
        var a = BallState(x: 0, y: 0)
        var b = BallState(x: 0, y: 0)
        Ballistics.launch(&a, club: c, heightPct: 0.7, lie: .tee, dir: 1)
        Ballistics.launch(&b, club: c, heightPct: 0.7, lie: .tee, dir: 1, mishit: 0)
        XCTAssertEqual(a.vx, b.vx)
        XCTAssertEqual(a.vy, b.vy)
        XCTAssertEqual(a.spin, b.spin)
    }

    // ── 결정론 ──

    func testCourseGenerationIsDeterministic() {
        let a = CourseGenerator.makeCourse(seed: 99)
        let b = CourseGenerator.makeCourse(seed: 99)
        for (ha, hb) in zip(a, b) {
            XCTAssertEqual(ha.holeX, hb.holeX)
            XCTAssertEqual(ha.greenSlope, hb.greenSlope)
            XCTAssertEqual(ha.segments.count, hb.segments.count)
        }
    }
}
