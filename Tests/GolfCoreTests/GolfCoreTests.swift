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
                // 파 범위는 유효거리(수평 + k·순낙차) 기준 — 내리막은 수평이 길고 오르막은 짧다 (2026-09-17)
                let eff = h.dist + CourseGenerator.effectiveBonus(netRise: h.ground(at: h.holeX) - h.ground(at: h.teeX))
                XCTAssertTrue(
                    (range.lowerBound - 12 ... range.upperBound + 12).contains(eff),
                    "파\(h.par) 유효거리 \(eff)가 범위 밖 (수평 \(h.dist))"
                )
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
        for seed in 1 ... 150 {
            let course = CourseGenerator.makeCourse(seed: UInt32(seed))
            let sigs = course.filter { $0.signature != nil }
            perRoundCounts.append(sigs.count)
            // 전 홀 다이나믹 (2026-08-20 사용자 판정 2차: "모든 홀 전부")
            XCTAssertEqual(sigs.count, 9, "모든 홀이 시그니처여야 함 (\(sigs.count))")
            let roundKinds = Set(sigs.compactMap(\.signature))
            // 덱 8종에서 파4·5 7홀이 중복 없이 뽑으므로 항상 ≥ 7 — 덱 회귀(중복 허용·종류 누락)를 잡는다 (리뷰 n4)
            XCTAssertGreaterThanOrEqual(roundKinds.count, 7, "라운드 내 아키타입 다양성 부족: \(roundKinds)")
            for h in sigs {
                try kindsSeen.insert(XCTUnwrap(h.signature))
                let lo = h.elevation.min() ?? 0
                let hi = h.elevation.max() ?? 0
                // 절대 상한 (2026-09-17 탄도 기준 재예산 — 워터 딥 -1.2·벙커 딥 -0.9 여유 +3)
                XCTAssertGreaterThan(lo, -CourseGenerator.elevClamp - 3, "\(h.signature!): 하한 초과 (\(lo))")
                XCTAssertLessThan(hi, CourseGenerator.elevClamp + 5, "\(h.signature!): 상한 초과 (\(hi))")
                // 실제로 다이나믹한지 — 아키타입 최소 낙차(파3 8m·협곡 10m·그 외 12m 이상)
                XCTAssertGreaterThan(hi - lo, 8, "\(h.signature!): 낙차가 심심함 (\(hi - lo))")
                // 유효거리(수평 + k·순낙차)는 파 거리 범위 안 — 내리막이 파를 무너뜨리지 않는다
                let net = h.ground(at: h.holeX) - h.ground(at: h.teeX)
                let eff = h.dist + CourseGenerator.effectiveBonus(netRise: net)
                let range = try XCTUnwrap(CourseGenerator.distRange[h.par])
                XCTAssertGreaterThan(
                    eff,
                    range.lowerBound - 12,
                    "\(h.signature!) 파\(h.par): 유효거리 짧음 (\(eff), 낙차 \(net))"
                )
                XCTAssertLessThan(eff, range.upperBound + 12, "\(h.signature!) 파\(h.par): 유효거리 김 (\(eff), 낙차 \(net))")
                // 경사 상한: cos 보간 라이저 최대 ≈0.95 + 보간 여유
                for x in stride(from: 2.0, to: h.worldW - 2, by: 1.0) {
                    XCTAssertLessThan(abs(h.slope(at: x)), 1.15, "\(h.signature!): 경사 초과 @\(x)")
                }
                // 그린은 설 수 있어야 함 (브레이크 2~6%만)
                XCTAssertLessThan(
                    abs(h.slope(at: h.holeX - 2)),
                    0.09,
                    "\(h.signature!): 그린이 가파름 seed \(seed) 파\(h.par) cup \(h.holeX)"
                )
                // 티 주변 평탄 (티샷 스탠스)
                XCTAssertLessThan(abs(h.slope(at: h.teeX)), 0.06, "\(h.signature!): 티가 가파름")
            }
        }
        XCTAssertEqual(kindsSeen, Set(SignatureKind.allCases), "일부 아키타입이 안 나옴: \(kindsSeen)")
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
                    // 벙커 턱은 정당한 급경사 (모래 구덩이 가장자리 — 라이저가 아니다)
                    let nearBunker = h.segments.contains {
                        $0.type == .bunker && x >= $0.from - 2.5 && x <= $0.to + 2.5
                    }
                    XCTAssertTrue(
                        s == .rough || s == .water || nearBunker,
                        "\(h.signature!): 급경사(\(h.slope(at: x)))가 \(s) @\(x)"
                    )
                    checked += 1
                }
                XCTAssertGreaterThan(checked, 0, "\(h.signature!): 급경사 구간이 없음")
            }
        }
    }

    // ── 등반 가능성 (2026-08-21 오르막 완화 — "올리는 게 불가능" 재발 방지) ──

    func testClimbabilityInvariant() {
        // 클럽 탄도 정점이 지형 상한을 여유 있게 넘어야 오르막이 플레이 가능하다
        let sw = simulate(club: club("SW"))
        let i7 = simulate(club: club("7I"))
        XCTAssertGreaterThan(sw.apex, 40, "SW 정점(\(sw.apex))이 협곡 깊이 상한 38m를 못 넘음")
        XCTAssertGreaterThan(i7.apex, 25, "7I 정점(\(i7.apex))이 산정 라이저 상한 20m를 여유 있게 못 넘음")
        // 생성 코스의 실제 지형이 상한을 지키는지
        for seed in 1 ... 30 {
            for h in CourseGenerator.makeCourse(seed: UInt32(seed)) {
                guard let sig = h.signature else { continue }
                if sig == .canyon {
                    let floor = h.elevation.min() ?? 0
                    let rim = h.ground(at: h.teeX)
                    XCTAssertLessThanOrEqual(
                        rim - floor,
                        CourseGenerator.maxCanyonDepth + 3.5,
                        "협곡 탈출 불가 깊이 (\(rim - floor))"
                    )
                }
                if sig == .valley { // 계곡 바닥에서 그린 림까지 — 사면(≤ 8) + 절벽(≤ 8)으로 오른다 (M5-④)
                    let floor = h.elevation.min() ?? 0
                    let rim = h.ground(at: h.holeX)
                    // 구조 등반 ≤ 18 위에 바닥 골(rolls −2.2)·굴곡(−0.67)·그린 브레이크(+2.0)·윗단 턱(+1.0)이 얹힌다 → 이론 최대 ≈ 24, 600시드 실측
                    // 21.1 (리뷰 m2)
                    XCTAssertLessThanOrEqual(
                        rim - floor,
                        18 + 6,
                        "계곡 등반 불가 깊이 (\(rim - floor)) — 사면 ≤ 8 + 절벽 ≤ 10 + 부속 ≤ 6"
                    )
                }
                if sig != .canyon { // 오르막 라이저 한 단 ≤ maxRiser — 산정뿐 아니라 능선·계곡·숲의 오르막도 (협곡 반대편 라이저는 depth+rim ≤ 21이라 별도)
                    // '한 샷으로 넘어야 하는' 가파른 상승(경사 >0.3) 연속 구간의 낙차만 측정
                    // — 완경사 저지대는 걸어가 별도 샷이 가능하므로 라이저가 아니다
                    // 홀 진행 방향으로 잰다 — 미러 홀은 배열 순서가 반대라 절벽(내리막)이 오르막으로 읽힌다 (M5-④에서 전 종류로 넓히며 발견)
                    let path = h.holeX >= h.teeX ? h.elevation : Array(h.elevation.reversed())
                    var maxRiser = 0.0
                    var runStart = path[0]
                    var climbing = false
                    for i in 1 ..< path.count {
                        let d = path[i] - path[i - 1]
                        if d > 0.3 {
                            if !climbing {
                                climbing = true
                                runStart = path[i - 1]
                            }
                            maxRiser = max(maxRiser, path[i] - runStart)
                        } else {
                            climbing = false
                        }
                    }
                    XCTAssertLessThanOrEqual(
                        maxRiser,
                        CourseGenerator.maxRiser + 1.5,
                        "\(sig) 오르막 라이저가 상한 초과 (\(maxRiser)) seed \(seed)"
                    )
                }
            }
        }
    }

    // ── 급경사 정착 금지 (2026-09-17 협곡 탈출 불가 원인) ──

    func testBallSettlesOffSteepRiser() {
        // 평지 → x 100~133에 20m 라이저(cos 보간, 중앙 경사 ≈0.95) → 평지
        var elev = [Double](repeating: 0, count: 10002)
        for i in 0 ..< elev.count {
            let u = min(1, max(0, (Double(i) - 100) / 33))
            elev[i] = 20 * (0.5 - 0.5 * cos(u * .pi))
        }
        let hole = Hole(
            par: 4, dist: 9974, holeX: 9999, worldW: 10000, greenStart: 9987, greenEnd: 10007, apronStart: 9982,
            segments: [Segment(from: 0, to: 10000, type: .rough)], elevation: elev, waterRange: nil, greenSlope: 0
        )
        var b = BallState(x: 112, y: hole.ground(at: 112)) // 라이저 중턱
        XCTAssertGreaterThan(abs(hole.slope(at: b.x)), 0.5)
        let water = Ballistics.settleOffSteepSlope(&b, hole: hole)
        XCTAssertFalse(water)
        XCTAssertLessThanOrEqual(
            abs(hole.slope(at: b.x)),
            Ballistics.settleTail + 0.05,
            "바닥(settleTail)까지 내려와야 함 (\(b.x))"
        )
        XCTAssertLessThan(b.x, 112, "내리막(발치) 쪽으로 내려와야 함")
        XCTAssertEqual(b.y, hole.ground(at: b.x), accuracy: 1e-9)
        // 완경사에 있는 공은 그대로
        var c = BallState(x: 50, y: 0)
        XCTAssertFalse(Ballistics.settleOffSteepSlope(&c, hole: hole))
        XCTAssertEqual(c.x, 50)
    }

    // ── 바람 (2026-08-21 재미 확장 4번) ──

    private func carryWithWind(_ wind: Double) -> Double {
        let hole = Hole.flatTest(wind: wind)
        var b = BallState(x: 50, y: 0)
        Ballistics.launch(&b, club: club("DR"), heightPct: 1, lie: .fairway, dir: 1)
        var t = 0.0
        while b.phase == .fly, t < 60 {
            _ = Ballistics.step(&b, hole: hole)
            t += Phys.dt
        }
        return b.x - 50
    }

    func testTailwindCarriesFartherHeadwindShorter() {
        let calm = carryWithWind(0)
        let tail = carryWithWind(6)
        let head = carryWithWind(-6)
        XCTAssertGreaterThan(tail, calm + 8, "뒷바람 6m/s는 캐리를 눈에 띄게 늘려야 함")
        XCTAssertLessThan(head, calm - 8, "맞바람 6m/s는 캐리를 눈에 띄게 줄여야 함")
    }

    func testWindDoesNotAffectPutting() {
        let calm = Hole.flatTest(worldW: 300, holeX: 290)
        let windy = Hole.flatTest(worldW: 300, holeX: 290, wind: 7)
        func rollDist(_ hole: Hole) -> Double {
            var b = BallState(x: 50, y: 0, vx: 6, phase: .roll, lipped: true)
            var t = 0.0
            while b.phase != .rest, t < 30 {
                _ = Ballistics.step(&b, hole: hole)
                t += Phys.dt
            }
            return b.x - 50
        }
        XCTAssertEqual(rollDist(calm), rollDist(windy), accuracy: 0.001, "굴림(퍼팅)은 바람 무영향")
    }

    func testCourseWindWithinRange() {
        for seed in 1 ... 30 {
            for h in CourseGenerator.makeCourse(seed: UInt32(seed)) {
                XCTAssertLessThanOrEqual(abs(h.wind), 7.0, "바람 상한 초과 (\(h.wind))")
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

    /// 트레드 굴곡 (2026-09-28): 티~에이프런의 비라이저·비수면 지면 중 |경사| ≥ 0.05가 충분히 있어야 경사 라이가 체감된다.
    /// 티런은 평탄. 급경사(> 0.3)는 라이저로 보고 분모에서 뺀다
    func testTreadsAreUndulatedButTeeFlat() {
        var sloped = 0, total = 0
        for seed: UInt32 in 1 ... 40 {
            for h in CourseGenerator.makeCourse(seed: seed) {
                let d = h.holeX >= h.teeX ? 1.0 : -1.0 // 미러 홀은 티가 오른쪽 — 홀 방향으로 스캔 (리뷰 2026-09-28)
                for k in 1 ..< 9 { // 티런은 평탄
                    XCTAssertLessThan(
                        abs(h.slope(at: h.teeX + d * Double(k))),
                        0.02,
                        "티런에 굴곡 @\(h.teeX + d * Double(k))"
                    )
                }
                var x = h.teeX + d * 10
                while d > 0 ? x < h.greenStart - 12 : x > h.greenEnd + 12 {
                    let s = abs(h.slope(at: x))
                    if h.surface(at: x) != .water, s <= 0.3 { // 라이저(급경사) 밖만 센다 — 필터이지 단언이 아니다
                        total += 1
                        if s >= 0.05 {
                            sloped += 1
                        }
                    }
                    x += d
                }
            }
        }
        let share = Double(sloped) / Double(max(1, total))
        XCTAssertGreaterThan(share, 0.40, "경사 라이 지면 비율이 낮음 (\(share)) — 굴곡이 사라졌나")
        XCTAssertLessThan(share, 0.80, "평지가 거의 없음 (\(share)) — 굴곡 과다")
    }

    /// 급경사 언덕 사면 (2026-09-28): 40시드×9홀 중 경사 0.18~0.30이 12m 이상 이어지는 사면이 있는 홀이 충분해야 한다
    func testSlopeLieRampsExist() {
        var withRamp = 0, holes = 0
        for seed: UInt32 in 1 ... 40 {
            for h in CourseGenerator.makeCourse(seed: seed) {
                holes += 1
                var run = 0, best = 0
                let d = h.holeX >= h.teeX ? 1.0 : -1.0
                var x = h.teeX + d
                while d > 0 ? x < h.greenStart : x > h.greenEnd {
                    let s = abs(h.slope(at: x))
                    run = s >= 0.18 && s <= 0.30 && h.surface(at: x) != .water ? run + 1 : 0
                    best = max(best, run)
                    x += d
                }
                if best >= 12 {
                    withRamp += 1
                }
            }
        }
        let share = Double(withRamp) / Double(holes)
        print(String(format: "RAMPS holes with ≥12m steep-hill stretch (0.18~0.30): %.0f%%", share * 100))
        XCTAssertGreaterThan(share, 0.45, "비탈 라이 구간이 있는 홀이 적음 (\(share))")
    }

    /// 저속 잔디 걸림·정지 마찰 (2026-09-28, 리뷰 #1로 재작성 — 구 규칙과 갈리는 경사에서만 단언한다):
    /// 경사 0.25 페어웨이의 1.4 m/s 크립은 구 규칙(상수 감속 0.12 m/s²)이면 8m 흘러내리고 신 규칙(저속 걸림)이면 2m 안에 선다.
    /// 경사 0.28은 구 정지 한계(0.26) 밖·신 한계(0.34) 안이라 신 규칙만 선다. 그린·에이프런은 걸림이 없어 굴림 거리 = v²/(2·roll)
    func testLowSpeedGripStopsCreepOnSlopeButNotOnGreen() {
        func slopeHole(_ s: Double, type: Surface) -> Hole {
            var elev = [Double](repeating: 0, count: 202)
            for i in 0 ..< elev.count {
                elev[i] = 40 - Double(i) * s
            }
            return Hole(
                par: 4, dist: 150, holeX: 190, worldW: 200, greenStart: 185, greenEnd: 195, apronStart: 183,
                segments: [Segment(from: 0, to: 200, type: type)], elevation: elev, waterRange: nil, greenSlope: 0
            )
        }
        func roll(_ hole: Hole, from x0: Double, v: Double) -> BallState {
            var b = BallState(x: x0, y: hole.ground(at: x0), vx: v, vy: 0, phase: .roll)
            var t = 0.0
            while b.phase != .rest, t < 60 {
                _ = Ballistics.step(&b, hole: hole)
                t += Phys.dt
            }
            return b
        }
        let creep = roll(slopeHole(0.25, type: .fairway), from: 50, v: 1.4)
        XCTAssertEqual(creep.phase, .rest, "경사 0.25에서 멈추지 않음")
        XCTAssertLessThan(creep.x - 50, 2.0, "느린 공이 비탈을 흘러내림 (\(creep.x - 50)m — 구 규칙 ≈ 8m)")
        let hold = roll(slopeHole(0.28, type: .fairway), from: 50, v: 0.3)
        XCTAssertEqual(hold.phase, .rest, "경사 0.28에서 정지 마찰이 버티지 못함")
        XCTAssertLessThan(hold.x - 50, 1.0, "정지 마찰 범위에서 흘러내림 (\(hold.x - 50)m)")
        XCTAssertEqual(abs(slopeHole(0.28, type: .fairway).slope(at: hold.x)), 0.28, accuracy: 0.02, "비탈 위에 서야 한다")
        for type in [Surface.green, .apron] { // 걸림 없음
            let flat = slopeHole(0, type: type)
            let p = roll(flat, from: 50, v: 2.0)
            XCTAssertEqual(p.x - 50, 2.0 * 2.0 / (2 * type.roll), accuracy: 0.25, "\(type) 굴림 거리가 바뀜 (\(p.x - 50))")
        }
    }

    /// 언덕 사면 불변식 (2026-09-28 리뷰 제안): 홀 쪽 내리막 직선 사면(0.18~0.30, 6m+ 일정)은 전부 러프, 사면 ±8m 안 벙커 없음,
    /// 8m 이상 오르막 절벽 발치 20m 안 벙커 없음(SW 정점 9m 소프트락)
    func testHillsideInvariants() {
        var descending = 0, ascending = 0
        for seed: UInt32 in 1 ... 40 {
            for h in CourseGenerator.makeCourse(seed: seed) {
                let d = h.holeX >= h.teeX ? 1.0 : -1.0
                var x = h.teeX + d * 10
                var runStart: Double? = nil
                func closeRun(at xEnd: Double) {
                    guard let x0 = runStart else { return }
                    runStart = nil
                    guard abs(xEnd - x0) >= 6 else { return }
                    let lo = min(x0, xEnd), hi = max(x0, xEnd)
                    let down = h.slope(at: (lo + hi) / 2) * d < 0 // 홀 쪽 내리막
                    if down {
                        descending += 1
                        var xs = lo + 1
                        while xs < hi - 1 {
                            XCTAssertEqual(h.surface(at: xs), .rough, "내리막 사면이 러프가 아님 seed \(seed) @\(xs)")
                            xs += 1
                        }
                    }
                    var xb = lo - 8
                    while xb <= hi + 8 {
                        XCTAssertNotEqual(h.surface(at: xb), .bunker, "사면 ±8m 안 벙커 seed \(seed) @\(xb)")
                        xb += 1
                    }
                }
                while d > 0 ? x < h.greenStart : x > h.greenEnd {
                    let s = h.slope(at: x)
                    let steady = abs(s) >= 0.18 && abs(s) <= 0.30 && abs(s - h.slope(at: x + d)) <
                        0.003 // 직선 사면만 (cos 굴곡은 변곡점 ±0.15m 밖에서 탈락)
                    if steady, runStart == nil {
                        runStart = x
                    } else if !steady {
                        closeRun(at: x)
                    }
                    // 오르막 절벽(|경사| > 0.5, 발치→정상 8m+) 발치 20m 안 벙커 없음
                    if abs(h.slope(at: x)) > 0.5, h.ground(at: x + d * 12) - h.ground(at: x - d * 2) > 8 {
                        ascending += 1
                        var xb = x - d * 20
                        while d > 0 ? xb < x - 2 : xb > x + 2 {
                            XCTAssertNotEqual(h.surface(at: xb), .bunker, "오르막 절벽 발치 20m 안 벙커 seed \(seed) @\(xb)")
                            xb += d
                        }
                    }
                    x += d
                }
                closeRun(at: x)
            }
        }
        XCTAssertGreaterThan(descending, 50, "내리막 사면이 너무 적음 (\(descending))")
        XCTAssertGreaterThan(ascending, 50, "오르막 절벽 샘플이 너무 적음 (\(ascending))")
    }

    /// 핀 위치·그린 형태 변주 (M5-②): 40시드×9홀에서 앞핀·뒷핀·2단·포대·아일랜드가 충분히 나오고, 컵 주변은 여전히 평탄하다
    func testPinAndGreenVariety() {
        var front = 0, back = 0, tiered = 0, podium = 0, island = 0, holes = 0
        var tieredByKind: [String: Int] = [:], tierEligible: [String: Int] = [:]
        for seed: UInt32 in 1 ... 40 {
            for h in CourseGenerator.makeCourse(seed: seed) {
                holes += 1
                let d = h.holeX >= h.teeX ? 1.0 : -1.0
                let gFront = d > 0 ? h.greenStart : h.greenEnd, gBack = d > 0 ? h.greenEnd : h.greenStart
                let frac = abs(h.holeX - gFront) / abs(gBack - gFront)
                if frac < 0.3 {
                    front += 1
                }
                if frac > 0.7 {
                    back += 1
                }
                XCTAssertLessThan(abs(h.slope(at: h.holeX - 2)), 0.09, "컵 앞이 가파름 seed \(seed)")
                XCTAssertLessThan(abs(h.slope(at: h.holeX + 2)), 0.09, "컵 뒤가 가파름 seed \(seed)")
                var maxOnGreen = 0.0 // 턱(0.15~0.25) vs 브레이크(≤ 0.06)
                var gx = min(gFront, gBack) + 1
                while gx < max(gFront, gBack) - 1 {
                    maxOnGreen = max(maxOnGreen, abs(h.slope(at: gx)))
                    gx += 1
                }
                if maxOnGreen >= 0.12 {
                    tiered += 1
                    tieredByKind[h.signature?.rawValue ?? "plain", default: 0] += 1
                }
                if h.par >= 4, abs(gBack - gFront) >= 22 {
                    tierEligible[h.signature?.rawValue ?? "plain", default: 0] += 1
                }
                if let sig = h.signature, ![.summitGreen, .canyon, .valley].contains(sig),
                   h.ground(at: gFront) - h.ground(at: gFront - d * 22) >= 1.8 { // 포대 허용 종류만 (리뷰 m7 — 산정·협곡·계곡 제외)
                    podium += 1
                }
                if h.par == 3, h.surface(at: gFront - d * 12) == .water,
                   h.surface(at: gBack + d * 10) == .water {
                    island += 1
                }
            }
        }
        print("GREENS front \(front) back \(back) tiered \(tiered) podium \(podium) island \(island) / \(holes)")
        print(
            "GREENS tiered by kind \(tieredByKind.sorted { $0.key < $1.key }) eligible \(tierEligible.sorted { $0.key < $1.key })"
        )
        XCTAssertGreaterThan(Double(front) / Double(holes), 0.15, "앞핀이 적음 (\(front))")
        XCTAssertGreaterThan(Double(back) / Double(holes), 0.15, "뒷핀이 적음 (\(back))")
        // 적격(파4·5, 그린 ≥ 22m) ≈150홀 × 발생 ≈19% = 기대 28, σ ≈ 5 → 15는 −2.7σ (덱·난수 재편마다 흔들리는 값이라 20은 경계선 — 리뷰 m1)
        XCTAssertGreaterThan(tiered, 15, "2단 그린이 적음 (\(tiered))")
        XCTAssertGreaterThan(podium, 20, "포대 그린이 적음 (\(podium))")
        XCTAssertGreaterThan(island, 3, "아일랜드 그린이 적음 (\(island))")
    }

    /// 아일랜드 그린의 병합 waterRange(앞뒤 연못 한 구간)가 서프라이즈의 '물 밖으로'를 오작동시키지 않는다 (리뷰 M1 회귀)
    func testIslandGreenOutOfWaterUsesSegments() {
        var checked = 0
        for seed: UInt32 in 1 ... 60 {
            for h in CourseGenerator.makeCourse(seed: seed)
                where h.par == 3 && h.signature == .skyTee && h.waterRange != nil {
                let d = h.holeX >= h.teeX ? 1.0 : -1.0
                XCTAssertEqual(h.outOfWater(h.holeX), h.holeX, "그린 위 공이 옮겨짐 seed \(seed)")
                let gFront = d > 0 ? h.greenStart : h.greenEnd, gBack = d > 0 ? h.greenEnd : h.greenStart
                let inFront = gFront - d * 12
                XCTAssertEqual(h.surface(at: inFront), .water, "앞 연못 위치 seed \(seed)")
                let out = h.outOfWater(inFront)
                XCTAssertNotEqual(h.surface(at: out), .water, "물 밖으로 못 나감 seed \(seed)")
                XCTAssertLessThan(abs(out - inFront), 20, "연못 너머로 순간이동 seed \(seed) (\(out - inFront)m)")
                for wx in [inFront, gBack + d * 8] { // 앞·뒤 연못 어디에 빠져도 드롭 존은 물이 아니고 앞 둑 (waterRange 병합 구간)
                    XCTAssertNotEqual(h.surface(at: h.waterDropX(from: wx)), .water, "드롭 존이 물 seed \(seed)")
                    XCTAssertEqual(h.waterDropX(from: wx), h.waterDropX(from: inFront), "뒤 연못 드롭이 앞 둑이 아님 seed \(seed)")
                }
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 3)
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

    // ── 샷 종류 (Tab, M5-③) ──

    func testShotShapesChangeLaunch() {
        let c = club("7I")
        func launch(_ shape: ShotShape, club cl: Club = ClubTable.all.first { $0.id == "7I" }!) -> BallState {
            var b = BallState(x: 0, y: 0)
            Ballistics.launch(&b, club: cl, heightPct: 1, lie: .fairway, dir: 1, shape: shape)
            return b
        }
        let base = launch(.standard), punch = launch(.punch), lob = launch(.lob)
        func deg(_ b: BallState) -> Double {
            atan2(b.vy, b.vx) * 180 / .pi
        }
        func v(_ b: BallState) -> Double {
            hypot(b.vx, b.vy)
        }
        XCTAssertEqual(deg(base), c.loft, accuracy: 0.01)
        XCTAssertEqual(deg(punch), c.loft - 10, accuracy: 0.01, "펀치 로프트 -10°")
        XCTAssertEqual(deg(lob), c.loft + 18, accuracy: 0.01, "로브 로프트 +18°")
        XCTAssertEqual(v(punch) / v(base), ShotShape.punch.speedScale(for: .iron), accuracy: 0.001, "펀치 스피드 (아이언)")
        XCTAssertLessThan(
            ShotShape.punch.speedScale(for: .wedge), ShotShape.punch.speedScale(for: .iron), "웨지 펀치는 더 큰 스피드 손실"
        )
        XCTAssertGreaterThan(
            ShotShape.punch.spinScale(for: .wood), ShotShape.punch.spinScale(for: .iron), "우드 펀치는 스핀을 덜 깎는다 (캐리 유지)"
        )
        XCTAssertEqual(v(lob) / v(base), 0.92, accuracy: 0.001, "로브 스피드 -8%")
        XCTAssertEqual(punch.spin / base.spin, ShotShape.punch.spinScale(for: .iron), accuracy: 0.001, "펀치 스핀 (아이언)")
        XCTAssertEqual(lob.spin / base.spin, 0.9, accuracy: 0.001, "로브 스핀 -10%")
        // 클램프: 드라이버(10.5°) 낮은 샷은 바닥 8°, 샌드웨지(56°) 로브는 상한 62°
        XCTAssertEqual(
            deg(launch(.punch, club: club("DR"))),
            ShotShape.minLoftDeg,
            accuracy: 0.01,
            "드라이버 펀치 로프트 바닥 (10.5−4 → 8)"
        )
        XCTAssertEqual(deg(launch(.lob, club: club("SW"))), ShotShape.maxLoftDeg, accuracy: 0.01, "샌드웨지 로브 로프트 상한")
        // 자동 펀치(나무·벽)와 겹치면 둘 다 — 단 바닥 아래로는 안 내려간다
        var both = BallState(x: 0, y: 0)
        Ballistics.launch(&both, club: club("3I"), heightPct: 1, lie: .fairway, dir: 1, punch: 1, shape: .punch)
        XCTAssertEqual(deg(both), max(ShotShape.minLoftDeg, 21 - 8 - 10), accuracy: 0.01, "자동+수동 펀치 로프트 바닥")
        // 퍼터는 종류 무관 — 전 종류 (리뷰 F3: 낮은 샷의 로프트 바닥 8°가 퍼터에 새어 vx −1%였다)
        var pt = BallState(x: 0, y: 0)
        Ballistics.launch(&pt, club: club("PT"), heightPct: 0.5, lie: .green, dir: 1)
        for shape in ShotShape.allCases {
            var pt2 = BallState(x: 0, y: 0)
            Ballistics.launch(&pt2, club: club("PT"), heightPct: 0.5, lie: .green, dir: 1, shape: shape)
            XCTAssertEqual(pt.vx, pt2.vx, accuracy: 1e-9, "퍼터에 샷 종류 \(shape)가 적용됨")
            XCTAssertEqual(pt.vy, pt2.vy, accuracy: 1e-9)
        }
        // Tab 순환은 3종을 한 바퀴 돈다
        var sh = ShotShape.standard
        var seen: [ShotShape] = []
        for _ in 0 ..< 3 {
            seen.append(sh); sh = sh.next
        }
        XCTAssertEqual(Set(seen).count, 3)
        XCTAssertEqual(sh, .standard)
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

    // ── 공 바꿔치기 (BallKind) ──

    /// 평지 풀샷을 공 종류별로 시뮬레이션 → (총거리, 첫 착지 뒤 최고점, 바운스 횟수, 종결 여부)
    private func simulateKind(_ kind: BallKind, club id: String = "7I")
        -> (total: Double, reboundApex: Double, bounces: Int, rested: Bool) {
        let hole = Hole.flatTest()
        var b = BallState(x: 50, y: 0)
        Ballistics.launch(&b, club: club(id), heightPct: 1, lie: .fairway, dir: 1, kind: kind)
        var bounces = 0
        var reboundApex = 0.0
        var t = 0.0
        while b.phase != .rest, t < 60 {
            if case .bounce = Ballistics.step(&b, hole: hole, kind: kind) {
                bounces += 1
            }
            if bounces >= 1 {
                reboundApex = max(reboundApex, b.y)
            }
            t += Phys.dt
        }
        return (b.x - 50, reboundApex, bounces, b.phase == .rest)
    }

    func testStandardKindIsIdentity() {
        let a = simulate(club: club("7I"))
        let k = simulateKind(.standard)
        XCTAssertEqual(a.total, k.total, accuracy: 1e-9, "표준 공은 kind 기본값과 동일해야 한다")
    }

    func testRubberBallReboundsHigherAndMore() {
        let std = simulateKind(.standard)
        let rubber = simulateKind(.rubber)
        XCTAssertGreaterThan(rubber.reboundApex, std.reboundApex * 2, "고무공은 첫 착지 뒤 훨씬 높게 튀어야 한다")
        XCTAssertGreaterThan(rubber.bounces, std.bounces, "고무공은 더 여러 번 튄다")
        XCTAssertTrue(rubber.rested, "고무공도 60초 안에 멈춰야 한다")
    }

    func testBowlingBallFliesShortAndStops() {
        let std = simulateKind(.standard, club: "DR")
        let bowl = simulateKind(.bowling, club: "DR")
        XCTAssertLessThan(bowl.total, std.total * 0.6, "볼링공 드라이버는 표준의 60% 미만이어야 한다")
        XCTAssertLessThan(bowl.reboundApex, 0.6, "볼링공은 거의 안 튄다")
        XCTAssertTrue(bowl.rested, "볼링공도 60초 안에 멈춰야 한다")
    }

    // ── 핀 이동 ──

    func testMovingPinStaysOnGreenAndKeepsEverythingElse() {
        for seed: UInt32 in [1, 7, 42] {
            for h in CourseGenerator.makeCourse(seed: seed) {
                let far = h.movingPin(to: h.greenEnd + 50) // 그린 밖 요청은 클램프
                XCTAssertEqual(h.surface(at: far.holeX), .green)
                XCTAssertLessThanOrEqual(far.holeX, h.greenEnd - 1.5)
                let near = h.movingPin(to: h.greenStart - 50)
                XCTAssertGreaterThanOrEqual(near.holeX, h.greenStart + 1.5)
                XCTAssertEqual(far.par, h.par)
                XCTAssertEqual(far.dist, h.dist)
                XCTAssertEqual(far.worldW, h.worldW)
                XCTAssertEqual(far.teeX, h.teeX)
                XCTAssertEqual(far.wind, h.wind)
                XCTAssertEqual(far.segments.count, h.segments.count)
                XCTAssertEqual(far.elevation, h.elevation)
                XCTAssertEqual(far.waterRange, h.waterRange)
                XCTAssertEqual(far.obstacles.count, h.obstacles.count)
            }
        }
    }

    // ── 서프라이즈 3차: 바람 역전 사본 · 캐디 추천 클럽 ──

    func testWithWindChangesOnlyWind() {
        for h in CourseGenerator.makeCourse(seed: 19) {
            let r = h.withWind(-h.wind)
            XCTAssertEqual(r.wind, -h.wind)
            XCTAssertEqual(r.holeX, h.holeX)
            XCTAssertEqual(r.par, h.par)
            XCTAssertEqual(r.elevation, h.elevation)
            XCTAssertEqual(r.segments.count, h.segments.count)
            XCTAssertEqual(r.waterRange, h.waterRange)
            XCTAssertEqual(r.obstacles.count, h.obstacles.count)
        }
    }

    func testRecommendedClubCoversDistanceWithShortestClub() throws {
        // 평지·무풍: 추천 클럽의 풀샷 총거리는 거리 이상이고, 한 클럽 짧은 것은 모자란다
        for d in stride(from: 20.0, through: 220, by: 10) {
            let c = CourseStrategy.recommendedClub(distance: d, tailwind: 0, rise: 0, lie: .fairway)
            XCTAssertFalse(c.isPutter)
            XCTAssertNotEqual(c.id, "DR", "페어웨이에서 드라이버 추천")
            let i = try XCTUnwrap(ClubTable.all.firstIndex(of: c))
            let shorter = ClubTable.all[i + 1]
            if CourseStrategy.total(of: c.id) >= d, !shorter.isPutter {
                XCTAssertLessThan(CourseStrategy.total(of: shorter.id), d, "\(d)m에 \(c.id)보다 짧은 클럽으로 충분")
            }
        }
        XCTAssertEqual(CourseStrategy.recommendedClub(distance: 5, tailwind: 0, rise: 0, lie: .rough).id, "SW")
        XCTAssertEqual(CourseStrategy.recommendedClub(distance: 900, tailwind: 0, rise: 0, lie: .tee).id, "DR")
        XCTAssertEqual(CourseStrategy.recommendedClub(distance: 900, tailwind: 0, rise: 0, lie: .fairway).id, "3W")
        XCTAssertEqual(CourseStrategy.recommendedClub(distance: 60, tailwind: 0, rise: 0, lie: .bunker).id, "SW")
        XCTAssertTrue(CourseStrategy.recommendedClub(distance: 8, tailwind: 0, rise: 0, lie: .green).isPutter)
        // 맞바람·오르막은 같거나 긴 클럽 (인덱스가 작거나 같다)
        let base = CourseStrategy.recommendedClub(distance: 120, tailwind: 0, rise: 0, lie: .fairway)
        let head = CourseStrategy.recommendedClub(distance: 120, tailwind: -6, rise: 10, lie: .fairway)
        let headIdx = try XCTUnwrap(ClubTable.all.firstIndex(of: head))
        let baseIdx = try XCTUnwrap(ClubTable.all.firstIndex(of: base))
        XCTAssertLessThanOrEqual(headIdx, baseIdx)
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
