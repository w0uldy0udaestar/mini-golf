@testable import GolfCore
import XCTest

/// M6 라운드 변주 (2026-10-05): 날씨 물리·미션 판정·라이벌 결정론
final class RoundVarietyTests: XCTestCase {
    private func club(_ id: String) throws -> Club {
        try XCTUnwrap(ClubTable.all.first { $0.id == id })
    }

    /// 평지 풀샷: (캐리, 총거리)
    private func flatShot(_ id: String, weather: Weather) throws -> (carry: Double, total: Double) {
        let hole = Hole.flatTest()
        var b = BallState(x: 50, y: 0)
        try Ballistics.launch(&b, club: club(id), heightPct: 1, lie: .fairway, dir: 1)
        var carry: Double?
        var t = 0.0
        while b.phase != .rest, t < 60 {
            if case .bounce = Ballistics.step(&b, hole: hole, weather: weather), carry == nil {
                carry = b.x - 50
            }
            t += Phys.dt
        }
        return (carry ?? b.x - 50, b.x - 50)
    }

    // ── 날씨 ──

    func testRainCutsRollButNotCarry() throws {
        for id in ["DR", "7I", "PW"] {
            let dry = try flatShot(id, weather: .clear), wet = try flatShot(id, weather: .rain)
            XCTAssertEqual(dry.carry, wet.carry, accuracy: 0.01, "\(id): 비는 탄도를 바꾸지 않는다 (협곡 탈출 규칙 전제)")
            let dryRoll = dry.total - dry.carry, wetRoll = wet.total - wet.carry
            if dryRoll > 3 { // 웨지는 원래 거의 안 구른다
                XCTAssertLessThan(wetRoll, dryRoll * 0.7, "\(id): 비에 굴림이 눈에 띄게 줄어야 한다 (\(dryRoll) → \(wetRoll))")
            }
            XCTAssertLessThanOrEqual(wet.total, dry.total + 0.01, "\(id): 비에 더 멀리 가면 안 된다")
        }
    }

    func testClearAndGaleLeavePhysicsAlone() throws {
        let base = try flatShot("DR", weather: .clear)
        let hole = Hole.flatTest()
        var b = BallState(x: 50, y: 0)
        try Ballistics.launch(&b, club: club("DR"), heightPct: 1, lie: .fairway, dir: 1)
        var t = 0.0
        while b.phase != .rest, t < 60 {
            _ = Ballistics.step(&b, hole: hole) // 인자 없는 구 호출
            t += Phys.dt
        }
        XCTAssertEqual(b.x - 50, base.total, accuracy: 1e-9, "맑음은 기본 인자와 같아야 한다 (회귀 없음)")
        XCTAssertEqual(
            try flatShot("DR", weather: .gale).total,
            base.total,
            accuracy: 1e-9,
            "강풍의 바람은 홀 데이터에 있다 — 배율은 1"
        )
    }

    func testRainSlowsPutts() throws {
        func putt(_ weather: Weather) throws -> Double {
            let hole = Hole.flatTest()
            var b = BallState(x: 50, y: 0)
            try Ballistics.launch(&b, club: club("PT"), heightPct: 0.4, lie: .fairway, dir: 1)
            var t = 0.0
            while b.phase != .rest, t < 60 {
                _ = Ballistics.step(&b, hole: hole, weather: weather)
                t += Phys.dt
            }
            return b.x - 50
        }
        XCTAssertLessThan(try putt(.rain), try putt(.clear) * 0.85)
    }

    func testGaleWindRange() {
        for base in stride(from: -7.0, through: 7.0, by: 0.5) {
            let w = Weather.gale.wind(base: base)
            XCTAssertGreaterThanOrEqual(abs(w), 4.5)
            XCTAssertLessThanOrEqual(abs(w), 8.0)
            if base != 0 {
                XCTAssertEqual(w > 0, base > 0, "방향은 원래 바람을 따른다")
            }
            XCTAssertEqual(Weather.rain.wind(base: base), base)
            XCTAssertEqual(Weather.clear.wind(base: base), base)
        }
    }

    func testWeatherPickIsDeterministicAndMixed() {
        var counts: [Weather: Int] = [:]
        for seed: UInt32 in 1 ... 2000 {
            let w = Weather.pick(seed: seed)
            XCTAssertEqual(w, Weather.pick(seed: seed))
            counts[w, default: 0] += 1
        }
        // 맑음 50%·비 25%·강풍 25% — 인접 시드에서도 고르게
        XCTAssertEqual(Double(counts[.clear] ?? 0) / 2000, 0.5, accuracy: 0.05)
        XCTAssertEqual(Double(counts[.rain] ?? 0) / 2000, 0.25, accuracy: 0.05)
        XCTAssertEqual(Double(counts[.gale] ?? 0) / 2000, 0.25, accuracy: 0.05)
        // 연속 시드(실플레이 시드는 초 단위 시각)가 같은 날씨로 뭉치지 않는다
        var runs = 0, longest = 0
        var prev: Weather?
        for seed: UInt32 in 1_790_000_000 ... 1_790_000_300 {
            let w = Weather.pick(seed: seed)
            runs = w == prev ? runs + 1 : 1
            longest = max(longest, runs)
            prev = w
        }
        XCTAssertLessThan(longest, 14, "인접 시드 날씨가 길게 뭉침")
    }

    // ── 미션 ──

    func testMissionPlanIsEligibleAndVaried() {
        for seed: UInt32 in 1 ... 60 {
            let course = CourseGenerator.makeCourse(seed: seed)
            let plan = MissionKind.plan(course: course, seed: seed)
            XCTAssertEqual(plan, MissionKind.plan(course: course, seed: seed), "결정론")
            XCTAssertEqual(plan.count, course.count)
            for (i, k) in plan.enumerated() {
                XCTAssertTrue(k.eligible(for: course[i]), "seed \(seed) hole \(i + 1): \(k)")
                if i > 0 {
                    XCTAssertNotEqual(k, plan[i - 1], "seed \(seed): 같은 미션이 연달아")
                }
            }
            XCTAssertGreaterThanOrEqual(Set(plan).count, 4, "seed \(seed): 한 라운드 미션 종류가 너무 적다")
        }
    }

    func testMissionKindsAllAppear() {
        var seen = Set<MissionKind>()
        for seed: UInt32 in 1 ... 60 {
            seen.formUnion(MissionKind.plan(course: CourseGenerator.makeCourse(seed: seed), seed: seed))
        }
        XCTAssertEqual(seen, Set(MissionKind.allCases))
    }

    func testNoDriver() throws {
        var m = MissionTracker(kind: .noDriver, par: 4)
        try m.shot(club: club("3W"), shape: .standard, lie: .tee, remain: 300, fromX: 25)
        m.rest(surface: .fairway, strokes: 1, x: 250, holeX: 325)
        XCTAssertEqual(m.state, .active)
        m.holed(strokes: 4)
        XCTAssertEqual(m.state, .cleared)

        var over = MissionTracker(kind: .noDriver, par: 4)
        try over.shot(club: club("3W"), shape: .standard, lie: .tee, remain: 300, fromX: 25)
        over.holed(strokes: 5)
        XCTAssertEqual(over.state, .failed, "보기는 실패")

        var dr = MissionTracker(kind: .noDriver, par: 4)
        try dr.shot(club: club("DR"), shape: .standard, lie: .tee, remain: 300, fromX: 25)
        XCTAssertEqual(dr.state, .failed, "드라이버를 잡는 순간 실패")
        dr.holed(strokes: 2)
        XCTAssertEqual(dr.state, .failed, "한 번 정해지면 안 바뀐다")
    }

    func testTeeShotMissions() throws {
        var fw = MissionTracker(kind: .fairwayTee, par: 4)
        try fw.shot(club: club("DR"), shape: .standard, lie: .tee, remain: 300, fromX: 25)
        fw.rest(surface: .fairway, strokes: 1, x: 270, holeX: 325)
        XCTAssertEqual(fw.state, .cleared)

        var rough = MissionTracker(kind: .fairwayTee, par: 4)
        try rough.shot(club: club("DR"), shape: .standard, lie: .tee, remain: 300, fromX: 25)
        rough.rest(surface: .rough, strokes: 1, x: 270, holeX: 325)
        XCTAssertEqual(rough.state, .failed)

        var wet = MissionTracker(kind: .fairwayTee, par: 4)
        try wet.shot(club: club("DR"), shape: .standard, lie: .tee, remain: 300, fromX: 25)
        wet.water(strokes: 2)
        XCTAssertEqual(wet.state, .failed)

        var long = MissionTracker(kind: .longDrive, par: 5)
        try long.shot(club: club("DR"), shape: .standard, lie: .tee, remain: 480, fromX: 40)
        long.rest(surface: .rough, strokes: 1, x: 291, holeX: 520)
        XCTAssertEqual(long.state, .cleared, "251m — 러프여도 거리만 본다")

        var short = MissionTracker(kind: .longDrive, par: 5)
        try short.shot(club: club("DR"), shape: .standard, lie: .tee, remain: 480, fromX: 40)
        short.rest(surface: .fairway, strokes: 1, x: 280, holeX: 520)
        XCTAssertEqual(short.state, .failed, "240m")

        // 미러 홀(오른쪽 → 왼쪽)도 거리로
        var mirrored = MissionTracker(kind: .longDrive, par: 4)
        try mirrored.shot(club: club("DR"), shape: .standard, lie: .tee, remain: 340, fromX: 380)
        mirrored.rest(surface: .fairway, strokes: 1, x: 120, holeX: 40)
        XCTAssertEqual(mirrored.state, .cleared)
    }

    func testGreenInRegulation() throws {
        var ok = MissionTracker(kind: .greenInReg, par: 4)
        try ok.shot(club: club("DR"), shape: .standard, lie: .tee, remain: 300, fromX: 25)
        ok.rest(surface: .rough, strokes: 1, x: 250, holeX: 325)
        XCTAssertEqual(ok.state, .active)
        try ok.shot(club: club("PW"), shape: .standard, lie: .rough, remain: 75, fromX: 250)
        ok.rest(surface: .green, strokes: 2, x: 320, holeX: 325)
        XCTAssertEqual(ok.state, .cleared)

        var late = MissionTracker(kind: .greenInReg, par: 4)
        try late.shot(club: club("DR"), shape: .standard, lie: .tee, remain: 300, fromX: 25)
        late.rest(surface: .rough, strokes: 1, x: 250, holeX: 325)
        try late.shot(club: club("PW"), shape: .standard, lie: .rough, remain: 75, fromX: 250)
        late.rest(surface: .apron, strokes: 2, x: 310, holeX: 325)
        XCTAssertEqual(late.state, .failed, "2타째가 그린 밖이면 끝")

        var penalty = MissionTracker(kind: .greenInReg, par: 4)
        try penalty.shot(club: club("DR"), shape: .standard, lie: .tee, remain: 300, fromX: 25)
        penalty.water(strokes: 2)
        XCTAssertEqual(penalty.state, .failed, "벌타로 2타를 다 썼다")

        var par3 = MissionTracker(kind: .greenInReg, par: 3)
        try par3.shot(club: club("7I"), shape: .standard, lie: .tee, remain: 150, fromX: 25)
        par3.holed(strokes: 1)
        XCTAssertEqual(par3.state, .cleared, "홀인원")
    }

    func testClubAndShapeMissions() throws {
        var iron = MissionTracker(kind: .midIronGreen, par: 4)
        try iron.shot(club: club("DR"), shape: .standard, lie: .tee, remain: 300, fromX: 25)
        iron.rest(surface: .green, strokes: 1, x: 320, holeX: 325)
        XCTAssertEqual(iron.state, .active, "드라이버 원온은 아이언 미션이 아니다")
        try iron.shot(club: club("7I"), shape: .standard, lie: .green, remain: 5, fromX: 320)
        iron.rest(surface: .green, strokes: 2, x: 324, holeX: 325)
        XCTAssertEqual(iron.state, .active, "그린 위에서 아이언으로 굴린 건 안 친다")
        iron.holed(strokes: 3)
        XCTAssertEqual(iron.state, .failed)

        var good = MissionTracker(kind: .midIronGreen, par: 3)
        try good.shot(club: club("6I"), shape: .standard, lie: .tee, remain: 160, fromX: 25)
        good.rest(surface: .green, strokes: 1, x: 180, holeX: 185)
        XCTAssertEqual(good.state, .cleared)

        var lob = MissionTracker(kind: .shapeShot, par: 4)
        try lob.shot(club: club("SW"), shape: .standard, lie: .fairway, remain: 60, fromX: 265)
        lob.rest(surface: .green, strokes: 2, x: 322, holeX: 325)
        XCTAssertEqual(lob.state, .active, "기본 샷은 아니다")
        var lob2 = MissionTracker(kind: .shapeShot, par: 4)
        try lob2.shot(club: club("SW"), shape: .lob, lie: .fairway, remain: 60, fromX: 265)
        lob2.rest(surface: .green, strokes: 2, x: 322, holeX: 325)
        XCTAssertEqual(lob2.state, .cleared)
        var putterShape = MissionTracker(kind: .shapeShot, par: 4)
        try putterShape.shot(club: club("PT"), shape: .punch, lie: .fairway, remain: 20, fromX: 305)
        putterShape.rest(surface: .green, strokes: 2, x: 322, holeX: 325)
        XCTAssertEqual(putterShape.state, .active, "퍼터는 샷 종류가 없다")
    }

    func testCloseApproachAndBunker() throws {
        var close = MissionTracker(kind: .closeApproach, par: 4)
        try close.shot(club: club("9I"), shape: .standard, lie: .fairway, remain: 120, fromX: 205)
        close.rest(surface: .green, strokes: 2, x: 321, holeX: 325)
        XCTAssertEqual(close.state, .cleared)

        var far = MissionTracker(kind: .closeApproach, par: 4)
        try far.shot(club: club("9I"), shape: .standard, lie: .fairway, remain: 120, fromX: 205)
        far.rest(surface: .green, strokes: 2, x: 316, holeX: 325)
        XCTAssertEqual(far.state, .active, "9m — 아직 기회는 남는다")
        try far.shot(club: club("SW"), shape: .standard, lie: .green, remain: 9, fromX: 316)
        far.rest(surface: .green, strokes: 3, x: 324, holeX: 325)
        XCTAssertEqual(far.state, .active, "40m 안쪽에서 붙인 건 안 친다")
        far.holed(strokes: 4)
        XCTAssertEqual(far.state, .failed)

        var sand = MissionTracker(kind: .noBunker, par: 4)
        try sand.shot(club: club("DR"), shape: .standard, lie: .tee, remain: 300, fromX: 25)
        sand.rest(surface: .bunker, strokes: 1, x: 250, holeX: 325)
        XCTAssertEqual(sand.state, .failed)

        var clean = MissionTracker(kind: .noBunker, par: 4)
        try clean.shot(club: club("DR"), shape: .standard, lie: .tee, remain: 300, fromX: 25)
        clean.rest(surface: .fairway, strokes: 1, x: 250, holeX: 325)
        clean.holed(strokes: 6)
        XCTAssertEqual(clean.state, .cleared, "스코어와 무관")

        var quit = MissionTracker(kind: .birdie, par: 4)
        quit.gaveUp()
        XCTAssertEqual(quit.state, .failed)
    }

    // ── 라이벌 ──

    func testRivalIsDeterministicAndBounded() {
        let course = CourseGenerator.makeCourse(seed: 7)
        let a = Rival.playRound(course, seed: 7, weather: .rain, skill: 1.5)
        XCTAssertEqual(a, Rival.playRound(course, seed: 7, weather: .rain, skill: 1.5))
        XCTAssertEqual(a.count, 9)
        for s in a {
            XCTAssertGreaterThanOrEqual(s, 1)
            XCTAssertLessThanOrEqual(s, Phys.maxStrokes)
        }
        XCTAssertNotEqual(a, Rival.playRound(course, seed: 8, weather: .rain, skill: 1.5), "시드가 다르면 다른 라운드")
    }

    func testRivalSkillLookup() {
        XCTAssertEqual(Rival.skill(forOverPar: -5), Rival.calibration[0].skill, "표 아래는 가장 잘 치는 쪽으로 클램프")
        XCTAssertEqual(Rival.skill(forOverPar: 9), Rival.calibration[Rival.calibration.count - 1].skill)
        var prev = -Double.infinity
        for t in stride(from: -0.3, through: 2.0, by: 0.1) {
            let s = Rival.skill(forOverPar: t)
            XCTAssertGreaterThanOrEqual(s, prev, "목표가 높을수록(못 칠수록) 오차 배율이 커야 한다")
            prev = s
        }
        for row in Rival.calibration {
            XCTAssertEqual(Rival.skill(forOverPar: row.overPar), row.skill, accuracy: 1e-6)
        }
    }
}
