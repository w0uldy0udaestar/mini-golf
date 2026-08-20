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
                XCTAssertEqual(
                    h.ground(at: h.teeX + 3) - h.ground(at: h.teeX - 3), 0, accuracy: 0.4,
                    "티 주변은 평평해야 함" // 절대 표고는 내리막 티샷(teeLift)으로 0이 아닐 수 있다
                )
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

    // ── 탱탱볼 스킵 회귀 방지 (2026-08-14 실플레이 판정) ──

    func testShotsSettleWithoutEndlessSkipping() {
        // 얕은 재바운스마다 β를 풀로 적용하면 수평→수직 펌핑으로 공이 끝없이 스킵한다.
        // 풀샷 런이 캐리 대비 비정상적으로 길지 않고, 시뮬레이션 시한(60s) 안에 정지해야 한다
        for id in ["DR", "7I", "SW"] {
            let r = simulate(club: club(id))
            XCTAssertGreaterThan(r.carry, 10, "\(id) 캐리 비정상")
            XCTAssertLessThan(r.total, r.carry * 1.8 + 20, "\(id) 런이 비정상적으로 김 (스킵 펌핑 의심)")
        }
    }

    // ── 전략 배치 (클럽 거리 앵커) ──

    func testClubAnchorsAreOrderedAndSane() {
        let dr = CourseStrategy.total(of: "DR")
        XCTAssertGreaterThan(dr, CourseStrategy.total(of: "3W"), "드라이버가 3우드보다 짧음")
        XCTAssertGreaterThan(CourseStrategy.total(of: "3W"), CourseStrategy.total(of: "7I"), "3우드가 7아이언보다 짧음")
        XCTAssertTrue((150 ... 330).contains(dr), "드라이버 토탈 \(dr)m 비정상")
        XCTAssertLessThan(CourseStrategy.carry(of: "DR"), dr, "캐리가 토탈보다 김")
    }

    func testHazardsClusterAtTeeShotLandingAndSpareLayupZone() {
        let dr = CourseStrategy.total(of: "DR")
        var inBand = 0, par45 = 0, layupViolations = 0
        for seed in 1 ... 30 {
            // 표준 지형 경로 회귀 (클래식 모드용 보존) — 시그니처는 아키타입이 시련을 직접 배치
            var rand = SeededRandom(seed: UInt32(seed))
            let holes = [4, 4, 4, 4, 5, 5].map { CourseGenerator.makeHole(par: $0, rand: &rand) }
            for h in holes {
                par45 += 1
                func fromTee(_ x: Double) -> Double {
                    abs(x - h.teeX)
                } // 미러 정규화
                // 생성기와 같은 앵커: 이 홀의 합리적 최대 티샷 (그린 60m 앞 상한)
                let anchor = min(dr, h.dist - 60)
                let hazards = h.segments.filter { $0.type == .bunker || $0.type == .water }
                for seg in hazards {
                    let a = fromTee(seg.from), b = fromTee(seg.to)
                    let center = (min(a, b) + max(a, b)) / 2
                    if center > anchor - 60, center < anchor + 30 {
                        inBand += 1
                        break
                    }
                }
                // 안전선 보장: 티 직후~레이업 지대는 항상 깨끗하다
                for seg in hazards {
                    let a = fromTee(seg.from), b = fromTee(seg.to)
                    if min(a, b) < min(0.92 * dr, h.dist - 60) - 62, max(a, b) > 30 {
                        layupViolations += 1
                    }
                }
            }
        }
        XCTAssertEqual(layupViolations, 0, "레이업 안전 지대에 해저드가 있음")
        XCTAssertGreaterThan(
            Double(inBand) / Double(par45), 0.45,
            "낙하 지대 해저드 비율이 너무 낮음 (\(inBand)/\(par45))"
        )
    }

    // ── 지형 다이나믹 ──

    func testTerrainDynamicButBounded() {
        // 표준 지형 경로 회귀 (전 홀 다이나믹 전환 후 프로덕션 미사용 — 클래식 모드용 보존).
        // 경계: 노드 클램프 -10~15 + 워터 딥(-1.2)·벙커 딥(-0.9)·그린 슬로프(±약 2.1) 여유분
        var maxRange = 0.0
        for seed in 1 ... 30 {
            var rand = SeededRandom(seed: UInt32(seed))
            let holes = [3, 4, 4, 4, 5].map { CourseGenerator.makeHole(par: $0, rand: &rand) }
            for h in holes {
                let lo = h.elevation.min() ?? 0
                let hi = h.elevation.max() ?? 0
                XCTAssertGreaterThan(lo, -13, "표고 하한 초과 (\(lo))")
                XCTAssertLessThan(hi, 20, "표고 상한 초과 (\(hi))")
                maxRange = max(maxRange, hi - lo)
            }
        }
        XCTAssertGreaterThan(maxRange, 12, "지형 기복이 심심함 (최대 낙차 \(maxRange)m)")
    }

    // ── 시그니처 홀 (화면 세로 전체를 쓰는 다이나믹 코스) ──

    func testSignatureHoles() throws {
        var perRoundCounts: [Int] = []
        var kindsSeen = Set<SignatureKind>()
        var maxRelRange = 0.0
        for seed in 1 ... 60 {
            let course = CourseGenerator.makeCourse(seed: UInt32(seed))
            let sigs = course.filter { $0.signature != nil }
            perRoundCounts.append(sigs.count)
            // 전 홀 다이나믹 (2026-08-20 사용자 판정 2차: "모든 홀 전부")
            XCTAssertEqual(sigs.count, 9, "모든 홀이 시그니처여야 함 (\(sigs.count))")
            let roundKinds = Set(sigs.compactMap(\.signature))
            XCTAssertGreaterThanOrEqual(roundKinds.count, 3, "라운드 내 아키타입 다양성 부족: \(roundKinds)")
            for h in sigs {
                try kindsSeen.insert(XCTUnwrap(h.signature))
                let budget = 0.34 * h.worldW
                let lo = h.elevation.min() ?? 0
                let hi = h.elevation.max() ?? 0
                // 예산 내 (워터 딥 -1.2·벙커 딥 -0.9 여유 +3)
                XCTAssertGreaterThan(lo, -budget - 3, "\(h.signature!): 하한 초과 (\(lo))")
                XCTAssertLessThan(hi, budget + 5, "\(h.signature!): 상한 초과 (\(hi))")
                // 실제로 다이나믹한지 — 낙차가 예산의 40% 이상
                maxRelRange = max(maxRelRange, (hi - lo) / budget)
                XCTAssertGreaterThan(hi - lo, budget * 0.30, "\(h.signature!): 낙차가 심심함 (\(hi - lo))")
                // 경사 상한: cos 보간 라이저 최대 ≈0.95 + 보간 여유
                for x in stride(from: 2.0, to: h.worldW - 2, by: 1.0) {
                    XCTAssertLessThan(abs(h.slope(at: x)), 1.15, "\(h.signature!): 경사 초과 @\(x)")
                }
                // 그린은 설 수 있어야 함 (브레이크 2~6%만)
                XCTAssertLessThan(abs(h.slope(at: h.holeX - 2)), 0.09, "\(h.signature!): 그린이 가파름")
                // 티 주변 평탄 (티샷 스탠스)
                XCTAssertLessThan(abs(h.slope(at: h.teeX)), 0.06, "\(h.signature!): 티가 가파름")
            }
        }
        XCTAssertEqual(kindsSeen, Set(SignatureKind.allCases), "일부 아키타입이 안 나옴: \(kindsSeen)")
        XCTAssertGreaterThan(maxRelRange, 0.6, "최대 낙차가 예산 대비 작음 (\(maxRelRange))")
    }

    /// 관찰 도구: 시드별 라운드 구성 출력 — --demo --seed N 시각 검증용
    func testSignatureSeedDiscovery() {
        var found: [String] = []
        for seed in 1 ... 12 {
            let c = CourseGenerator.makeCourse(seed: UInt32(seed))
            let row = c.map { h in h.signature.map { "\($0.rawValue)(파\(h.par))" } ?? "평지(파\(h.par))" }
            found.append("seed \(seed): " + row.joined(separator: " · "))
        }
        print("SIGNATURE-SEEDS:\n" + found.joined(separator: "\n"))
        XCTAssertFalse(found.isEmpty)
    }

    func testSignatureHoleRisersAreRough() {
        // 라이저(급경사면)는 러프여야 공이 굴러 내려와 트레드에 선다
        // (미러 홀은 teeX가 오른쪽 — 방향 무관하게 전 구간 스캔)
        for seed in 1 ... 30 {
            for h in CourseGenerator.makeCourse(seed: UInt32(seed)) where h.signature != nil {
                var checked = 0
                for x in stride(from: 2.0, to: h.worldW - 2, by: 2.0) where abs(h.slope(at: x)) > 0.5 {
                    let s = h.surface(at: x)
                    XCTAssertTrue(
                        s == .rough || s == .water,
                        "\(h.signature!): 급경사(\(h.slope(at: x)))가 \(s) @\(x)"
                    )
                    checked += 1
                }
                XCTAssertGreaterThan(checked, 0, "\(h.signature!): 급경사 구간이 없음")
            }
        }
    }

    // ── 장애물 (나무·바위) ──

    private func obstacleHole(_ obstacles: [Obstacle]) -> Hole {
        Hole(
            par: 4, dist: 300, holeX: 350, worldW: 400,
            greenStart: 338, greenEnd: 358, apronStart: 333,
            segments: [Segment(from: 0, to: 400, type: .fairway)],
            elevation: [Double](repeating: 0, count: 402),
            waterRange: nil, greenSlope: 0, obstacles: obstacles
        )
    }

    func testCanopySwallowsFlight() {
        let tree = Obstacle(kind: .tree, x: 100, size: 3.5)
        let h = obstacleHole([tree])
        var b = BallState(x: 90, y: tree.canopyCenterY(above: 0), vx: 35, vy: 0, spin: 5000, phase: .fly)
        var hitLeaves = false
        var t = 0.0
        while b.phase != .rest, t < 20 {
            if case .bounce(_, .rough) = Ballistics.step(&b, hole: h) {
                hitLeaves = true
            }
            t += Phys.dt
        }
        XCTAssertTrue(hitLeaves, "캐노피 히트 이벤트가 없음")
        XCTAssertLessThan(abs(b.x - tree.x), 12, "잎에 맞은 공은 나무 근처에 떨어져야 함")
    }

    func testPunchPassesUnderCanopy() {
        // 낮은 펀치 탄도는 캐노피 밑(트렁크 옆)을 스쳐 지나간다 — 극복 샷의 존재 증명
        let tree = Obstacle(kind: .tree, x: 100, size: 3.5)
        let h = obstacleHole([tree])
        var b = BallState(x: 80, y: 0.5, vx: 40, vy: 1.5, spin: 1500, phase: .fly)
        var t = 0.0
        while b.phase != .rest, t < 20 {
            _ = Ballistics.step(&b, hole: h)
            t += Phys.dt
        }
        XCTAssertGreaterThan(b.x, tree.x + 15, "펀치가 나무를 통과하지 못함")
    }

    func testRockReflectsRollingBall() {
        let h = obstacleHole([Obstacle(kind: .rock, x: 100, size: 1.2)])
        var b = BallState(x: 94, y: 0, vx: 6, phase: .roll)
        var sawWall = false
        var t = 0.0
        while b.phase != .rest, t < 20 {
            if case .wall = Ballistics.step(&b, hole: h) {
                sawWall = true
            }
            t += Phys.dt
        }
        XCTAssertTrue(sawWall, "바위 반사 이벤트가 없음")
        XCTAssertLessThan(b.x, 101, "굴러온 공이 바위를 뚫고 지나감")
    }

    func testObstaclesPlacedOnSaneGround() {
        var seen = 0
        for seed in 1 ... 30 {
            for h in CourseGenerator.makeCourse(seed: UInt32(seed)) {
                for ob in h.obstacles {
                    seen += 1
                    let s = h.surface(at: ob.x)
                    XCTAssertTrue(
                        s == .fairway || s == .rough || s == .apron,
                        "장애물이 \(s)에 배치됨 (x \(ob.x))"
                    )
                    XCTAssertTrue(ob.x > 5 && ob.x < h.worldW - 5, "장애물이 코스 밖")
                }
            }
        }
        XCTAssertGreaterThan(seen, 20, "30시드에서 장애물이 너무 적음 (\(seen))")
    }

    // ── 경사 라이 (3eccc4f 복원) ──

    func testSlopeLieTiltsLaunchAndCostsSpeed() {
        let c = club("7I")
        func launched(slope: Double) -> BallState {
            var b = BallState(x: 0, y: 0)
            Ballistics.launch(&b, club: c, heightPct: 0.8, lie: .fairway, dir: 1, slope: slope)
            return b
        }
        let flat = launched(slope: 0)
        let up = launched(slope: 0.15)
        let down = launched(slope: -0.15)
        XCTAssertGreaterThan(atan2(up.vy, up.vx), atan2(flat.vy, flat.vx) + 0.05, "오르막 라이가 더 뜨지 않음")
        XCTAssertLessThan(atan2(down.vy, down.vx), atan2(flat.vy, flat.vx) - 0.05, "내리막 라이가 더 낮지 않음")
        XCTAssertLessThan(hypot(up.vx, up.vy), hypot(flat.vx, flat.vy), "경사 라이 스피드 손실 없음")
    }

    // ── V자 골짜기 정지 보장 (QA 소크 비종결 6/3206 회귀 방지) ──

    func testBallRestsInSteepValley() {
        var elev = [Double](repeating: 0, count: 102)
        for i in 0 ..< elev.count { // 40% 경사 V자 — 정지 조건(마찰 ≥ 경사 중력)이 성립 불가
            elev[i] = abs(Double(i) - 50) * 0.4
        }
        let h = Hole(
            par: 4, dist: 70, holeX: 95, worldW: 100,
            greenStart: 90, greenEnd: 98, apronStart: 88,
            segments: [Segment(from: 0, to: 100, type: .fairway)], elevation: elev,
            waterRange: nil, greenSlope: 0
        )
        var b = BallState(x: 45, y: h.ground(at: 45), vx: 5, phase: .roll)
        var t = 0.0
        while b.phase != .rest, t < 60 {
            _ = Ballistics.step(&b, hole: h)
            t += Phys.dt
        }
        XCTAssertEqual(b.phase, .rest, "가파른 골짜기에서 공이 영원히 진동함 (저속 정지 가드 회귀)")
        XCTAssertLessThan(abs(b.x - 50), 6, "골짜기 바닥 근처에서 멈추지 않음 (x \(b.x))")
    }

    // ── 펀치샷 (벽 백스윙 제한) ──

    func testPunchLowersTrajectoryAndSpin() {
        let c = club("7I")
        var normal = BallState(x: 0, y: 0)
        var punch = BallState(x: 0, y: 0)
        Ballistics.launch(&normal, club: c, heightPct: 0.55, lie: .fairway, dir: 1)
        Ballistics.launch(&punch, club: c, heightPct: 0.55, lie: .fairway, dir: 1, punch: 1)
        XCTAssertLessThan(
            atan2(punch.vy, punch.vx), atan2(normal.vy, normal.vx) - 0.1,
            "펀치샷 탄도가 낮아지지 않음"
        )
        XCTAssertEqual(punch.spin / normal.spin, 0.6, accuracy: 0.001, "펀치샷 스핀 -40% 불일치")
        XCTAssertEqual(
            hypot(punch.vx, punch.vy), hypot(normal.vx, normal.vy), accuracy: 0.001,
            "펀치샷은 파워를 잃지 않아야 함"
        )
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
