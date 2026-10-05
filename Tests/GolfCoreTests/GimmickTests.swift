@testable import GolfCore
import XCTest

/// 장치 그린 (M7, 2026-10-05): 지형 불변식 · "분지에 들어온 공은 반드시 들어간다" · 라운드 편성
final class GimmickTests: XCTestCase {
    /// 시드 1~12의 108홀에 두 장치를 얹어 본 표본 (얹을 수 있는 홀만)
    private static let dressed: [(base: Hole, hole: Hole, kind: GimmickKind, shape: GimmickShape)] = (1 ... 12)
        .flatMap { (seed: UInt32) in
            CourseGenerator.makeCourse(seed: seed).flatMap { base in
                GimmickKind.allCases.compactMap { kind in
                    base.withGimmick(kind).map {
                        (
                            base,
                            $0,
                            kind,
                            kind == .volcano ? GimmickShape.volcano(worldW: base.worldW) : .funnel(worldW: base.worldW)
                        )
                    }
                }
            }
        }

    /// 공을 한 자리에 가만히 놓고(굴림 상태, 속도 0) 끝까지 굴린다
    private func release(_ hole: Hole, at x: Double, maxT: Double = 20) -> (holed: Bool, x: Double, t: Double) {
        var b = BallState(x: x, y: hole.ground(at: x), phase: .roll)
        var t = 0.0
        while t < maxT {
            switch Ballistics.step(&b, hole: hole) {
            case .holed: return (true, hole.holeX, t)
            case .water: return (false, b.x, t)
            default:
                if b.phase == .rest {
                    return (false, b.x, t)
                }
            }
            t += Phys.dt
        }
        return (false, b.x, t)
    }

    func testMostHolesCanCarryAGimmick() {
        for kind in GimmickKind.allCases {
            let n = Self.dressed.filter { $0.kind == kind }.count
            XCTAssertGreaterThan(n, 85, "\(kind): 108홀 중 \(n)홀에만 얹힌다 (실측 96~100)")
        }
    }

    func testShapeAndSurfaces() throws {
        for d in Self.dressed {
            let h = d.hole, c = h.holeX, s = d.shape
            let k = Hole.gimmickKnots(cup: c, shape: s)
            let tag = "\(d.kind) par \(h.par) worldW \(Int(h.worldW))"
            XCTAssertEqual(h.gimmick, d.kind)
            XCTAssertEqual(h.surface(at: c), .green, tag)
            // 컵은 분지의 가장 낮은 자리 — 양쪽 벽이 테두리 1m 안까지 같은 경사로 컵 쪽으로 기울어 있다
            // (테두리·발치를 정수 자리에 맞춰 양쪽 폭이 최대 0.5m 다르다 → 경사 ±12%)
            for x in stride(from: k.rim.lowerBound + 1, through: k.rim.upperBound - 1, by: 1.0)
                where abs(x - c) >= 1.5 {
                XCTAssertGreaterThan(h.ground(at: x), h.ground(at: c) + 0.1, tag)
                let toward = x < c ? -1.0 : 1.0
                XCTAssertGreaterThan(h.slope(at: x) * toward, s.bowlSlope * 0.86, "\(tag) x−c \(x - c)")
                XCTAssertLessThan(h.slope(at: x) * toward, s.bowlSlope * 1.14, "\(tag) x−c \(x - c)")
            }
            let z0 = d.base.ground(at: c)
            switch d.kind {
            case .volcano: // 테두리는 바닥에서 height만큼 솟고, 발치 띠는 평평한 러프다
                for (rim, foot, out) in [
                    (k.rim.lowerBound, k.foot.lowerBound, -1.0),
                    (k.rim.upperBound, k.foot.upperBound, 1.0),
                ] {
                    XCTAssertEqual(h.ground(at: rim), z0 + s.height, accuracy: 1e-9, tag)
                    XCTAssertEqual(h.ground(at: foot + out * 2), z0, accuracy: 1e-9, tag)
                    XCTAssertEqual(h.surface(at: foot + out * 2), .rough, tag)
                    XCTAssertEqual(h.surface(at: rim + out * 3), .rough, tag)
                    XCTAssertGreaterThan(abs(h.slope(at: (rim + foot) / 2)), 0.65, "\(tag): 비탈은 공이 설 수 없게 가파르다")
                }
                // 화면 끝 릴리프(46px)가 공을 비탈 위에 올려놓지 않는다 — 폭 1280pt 화면 기준, 컵 반대편 발치가 릴리프 거리 밖 (리뷰 M-2)
                let relief = 46 * h.worldW / 1280
                let farRoom = h.holeX >= h.teeX ? h.worldW - k.foot.upperBound : k.foot.lowerBound
                XCTAssertGreaterThan(farRoom, relief + 1, "\(tag): 반대편 발치가 월드 끝에서 \(farRoom)m, 릴리프 \(relief)m")
            case .funnel: // 컵은 원래 그린보다 height만큼 깊다 (컵이 샘플 사이에 있어 바닥은 최대 반 칸만큼 얕다)
                XCTAssertEqual(h.ground(at: c), z0 - s.height, accuracy: s.bowlSlope * 0.5 + 0.05, tag)
                XCTAssertEqual(h.surface(at: k.rim.upperBound - 1), .fairway, tag)
                XCTAssertEqual(h.surface(at: k.rim.lowerBound - 2), .rough, tag)
            }
            // 물·월드 끝과 겹치지 않고, 나머지 홀 정보는 그대로다
            let extent = try XCTUnwrap(d.base.gimmickLayout(d.kind, shape: s)?.extent)
            let lo = extent.lowerBound, hi = extent.upperBound
            // 그린은 장치의 그린 하나뿐이고 에이프런은 없다 — 원래 그린·에이프런 조각이 장치 밖에 남으면 그 위에서 퍼터가 잡히고
            // '온그린' 판정이 난다 (리뷰 M-1: 깔때기 홀의 64%)
            let greens = h.segments.filter { $0.type == .green }
            XCTAssertEqual(greens.count, 1, tag)
            XCTAssertEqual(greens.first?.from ?? 0, h.greenStart, accuracy: 1e-9, tag)
            XCTAssertEqual(greens.first?.to ?? 0, h.greenEnd, accuracy: 1e-9, tag)
            XCTAssertFalse(h.segments.contains { $0.type == .apron }, tag)
            XCTAssertFalse(
                h.segments.contains { $0.type == .bunker && $0.to > lo && $0.from < hi },
                "\(tag): 장치에 걸친 벙커 토막"
            )
            XCTAssertFalse(
                h.obstacles.contains { $0.x + $0.size >= lo && $0.x - $0.size <= hi },
                "\(tag): 장치 자리의 나무·바위"
            )
            XCTAssertEqual(
                h.obstacles.count,
                d.base.obstacles.filter { $0.x + $0.size < lo || $0.x - $0.size > hi }.count,
                tag
            )
            // 바깥 이음 띠가 턱을 만들지 않는다 — 원래 지형이 완만한(셀 경사 ≤ 0.3) 자리는 이은 뒤에도 0.5 이하 (리뷰 m-3: 고정 8m는 0.92까지)
            for zone in [lo ... k.collar.lowerBound, k.collar.upperBound ... hi] {
                for x in stride(from: zone.lowerBound + 0.5, through: zone.upperBound - 0.5, by: 1.0)
                    where abs(d.base.slope(at: x)) <= 0.3 {
                    XCTAssertLessThanOrEqual(abs(h.slope(at: x)), 0.5, "\(tag): 이음 띠 x \(x)")
                }
            }
            XCTAssertFalse(h.segments.contains { $0.type == .water && $0.to > lo && $0.from < hi }, tag)
            XCTAssertGreaterThanOrEqual(lo, 1, tag)
            XCTAssertLessThanOrEqual(hi, h.worldW - 1, tag)
            XCTAssertEqual(h.par, d.base.par)
            XCTAssertEqual(h.teeX, d.base.teeX)
            XCTAssertEqual(h.wind, d.base.wind)
            XCTAssertEqual(h.signature, d.base.signature)
            XCTAssertEqual(h.elevation.count, d.base.elevation.count)
            // 세그먼트는 빈틈·겹침 없이 월드를 덮는다
            for (a, b) in zip(h.segments, h.segments.dropFirst()) {
                XCTAssertEqual(a.to, b.from, accuracy: 1e-9, tag)
            }
            // 장치 바깥(티 쪽)은 한 점도 안 바뀐다
            let untouched = h.holeX >= h.teeX ? 0 ... Int(lo) - 1 : Int(hi) + 1 ... h.elevation.count - 1
            XCTAssertEqual(Array(h.elevation[untouched]), Array(d.base.elevation[untouched]), tag)
        }
    }

    /// 장치의 약속: 분화구·분지 안에 놓인 공은 서지 않고 컵까지 굴러 들어간다. 컵 바로 위(±1m)는 뺀다 — 속도 0으로 컵 위에 놓인 공은
    /// '굴러 들어온' 것이 아니라 판정이 없다
    func testBallInTheBowlAlwaysDrops() {
        for d in Self.dressed {
            let k = Hole.gimmickKnots(cup: d.hole.holeX, shape: d.shape)
            for x in stride(from: k.rim.lowerBound + 1, through: k.rim.upperBound - 1, by: 1.0)
                where abs(x - d.hole.holeX) >= 1 {
                let r = release(d.hole, at: x)
                XCTAssertTrue(
                    r.holed,
                    "\(d.kind) par \(d.hole.par): 컵에서 \(x - d.hole.holeX)m에 놓은 공이 \(r.x - d.hole.holeX)m에 섰다"
                )
                XCTAssertLessThan(r.t, 12, "\(d.kind): 굴러 들어가는 데 \(r.t)초")
            }
        }
    }

    /// 분화구 테두리 마루에도 공이 걸쳐 서지 않는다 — 테두리 안쪽 0.12~0.45m는 경사가 0.17 아래로 누운 평형 띠라 공이 섰고, 그 공을 치려면
    /// 스틱맨이 바깥 비탈 3m 아래에 서야 했다. 테두리 근처에 놓은 공은 안으로 들어가거나(홀인) 바깥 비탈로 굴러 내려간다(발치) — 봉우리 위에는 안 남는다
    func testNoBallHangsOnTheCraterRim() {
        for d in Self.dressed where d.kind == .volcano {
            let k = Hole.gimmickKnots(cup: d.hole.holeX, shape: d.shape)
            for (rim, inward) in [(k.rim.lowerBound, 1.0), (k.rim.upperBound, -1.0)] {
                for delta in stride(from: -0.5, through: 0.95, by: 0.05) { // 음수 = 테두리 바깥(비탈 쪽)
                    let r = release(d.hole, at: rim + inward * delta)
                    XCTAssertTrue(
                        r.holed || !k.foot.contains(r.x),
                        "par \(d.hole.par): 테두리 안쪽 \(delta)m에 놓은 공이 컵에서 \(r.x - d.hole.holeX)m(봉우리 위)에 섰다"
                    )
                    if delta >= 0.3 {
                        XCTAssertTrue(r.holed, "par \(d.hole.par): 테두리 안쪽 \(delta)m에 놓은 공은 들어가야 한다")
                    }
                    if delta < 0 {
                        XCTAssertFalse(r.holed, "par \(d.hole.par): 테두리 바깥 \(-delta)m에 놓은 공은 내려가야 한다")
                    }
                }
            }
        }
    }

    /// 화산 비탈에 떨어진 공은 비탈에 서지 않고 그쪽 발치(평평한 띠 근처)로 내려온다 — 다음 샷을 칠 자리가 있다
    func testBallOnTheConeComesDownToTheFoot() {
        for d in Self.dressed where d.kind == .volcano {
            let k = Hole.gimmickKnots(cup: d.hole.holeX, shape: d.shape)
            for (rim, foot, edge, out) in [
                (k.rim.lowerBound, k.foot.lowerBound, k.collar.lowerBound, -1.0),
                (k.rim.upperBound, k.foot.upperBound, k.collar.upperBound, 1.0),
            ] {
                let r = release(d.hole, at: rim + (foot - rim) * 0.4)
                XCTAssertFalse(r.holed)
                XCTAssertGreaterThan((r.x - foot) * out, -0.5, "비탈 위에 섰다: 발치에서 \((r.x - foot) * out)m")
                XCTAssertLessThan((r.x - edge) * out, 0.5, "발치 띠를 지나 달아났다: 띠 끝에서 \((r.x - edge) * out)m")
                XCTAssertLessThanOrEqual(abs(d.hole.slope(at: r.x)), Ballistics.steepRest)
            }
        }
    }

    func testDressPlacesThreeAndShowsOneEarly() {
        var early = 0, rounds = 0, counts: [GimmickKind: Int] = [:]
        for seed: UInt32 in 1 ... 60 {
            let course = CourseGenerator.makeCourse(seed: seed)
            let out = GimmickKind.dress(course: course, seed: seed)
            XCTAssertEqual(
                out.map(\.gimmick),
                GimmickKind.dress(course: course, seed: seed).map(\.gimmick),
                "같은 시드면 같은 편성"
            )
            let kinds = out.map(\.gimmick)
            rounds += 1
            early += kinds.prefix(2).contains { $0 != nil } ? 1 : 0
            XCTAssertLessThanOrEqual(kinds.compactMap(\.self).count, 3, "seed \(seed)")
            XCTAssertGreaterThanOrEqual(kinds.compactMap(\.self).count, 2, "seed \(seed): 장치가 너무 적다")
            // 세 토막에 하나씩 — 한 토막에 둘이 몰리지 않는다
            for group in [0 ..< 2, 3 ..< 6, 6 ..< 9] {
                XCTAssertLessThanOrEqual(kinds[group].compactMap(\.self).count, 1, "seed \(seed) \(group)")
            }
            XCTAssertNil(kinds[2], "3번 홀은 비워 둔다 (첫 토막은 1·2번)")
            for (i, h) in out.enumerated() {
                if let k = h.gimmick {
                    counts[k, default: 0] += 1
                    XCTAssertFalse(k == .funnel && h.par == 3, "seed \(seed) hole \(i + 1): 깔때기는 파3에 걸지 않는다")
                } else {
                    XCTAssertEqual(h.elevation, course[i].elevation, "장치 없는 홀은 그대로")
                }
            }
        }
        XCTAssertGreaterThan(Double(early) / Double(rounds), 0.9, "첫 장치가 1·2번 홀 안에 나오는 라운드 \(early)/\(rounds)")
        for k in GimmickKind.allCases {
            XCTAssertGreaterThan(counts[k] ?? 0, 40, "\(k)가 너무 드물다: \(counts[k] ?? 0)/\(rounds)라운드")
        }
    }

    func testForcedDressAndPinStaysPut() throws {
        let course = CourseGenerator.makeCourse(seed: 3)
        let all = GimmickKind.dress(course: course, seed: 3, forced: .volcano)
        XCTAssertGreaterThanOrEqual(all.filter { $0.gimmick == .volcano }.count, 6, "관찰용 강제: 들어가는 홀 전부")
        let funnels = GimmickKind.dress(course: course, seed: 3, forced: .funnel)
        XCTAssertFalse(funnels.contains { $0.gimmick == .funnel && $0.par == 3 }, "강제해도 깔때기는 파3에 걸지 않는다")
        let hole = try XCTUnwrap(all.first { $0.gimmick != nil })
        XCTAssertEqual(hole.movingPin(to: hole.holeX + 3).holeX, hole.holeX, "장치 그린의 컵은 분지 바닥에서 못 옮긴다")
        XCTAssertNil(hole.withGimmick(.funnel), "이미 장치가 있는 홀에는 또 얹지 않는다")
        XCTAssertEqual(hole.displayName, GimmickKind.volcano.displayName, "홀 이름은 장치가 앞선다")
        XCTAssertEqual(hole.withWind(3).gimmick, .volcano, "사본이 장치를 잃지 않는다")
    }
}
