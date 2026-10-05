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

    func testShapeAndSurfaces() {
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
            case .volcano: // 테두리는 바닥에서 height만큼 솟고, 발치 띠는 평평하다
                for (rim, foot, out) in [
                    (k.rim.lowerBound, k.foot.lowerBound, -1.0),
                    (k.rim.upperBound, k.foot.upperBound, 1.0),
                ] {
                    XCTAssertEqual(h.ground(at: rim), z0 + s.height, accuracy: 1e-9, tag)
                    XCTAssertEqual(h.ground(at: foot + out * 2), z0, accuracy: 1e-9, tag)
                    XCTAssertEqual(h.surface(at: foot + out * 2), .apron, tag)
                    XCTAssertEqual(h.surface(at: rim + out * 3), .rough, tag)
                    XCTAssertGreaterThan(abs(h.slope(at: (rim + foot) / 2)), 0.45, "\(tag): 비탈은 공이 설 수 없게 가파르다")
                }
            case .funnel: // 컵은 원래 그린보다 height만큼 깊다 (컵이 샘플 사이에 있어 바닥은 최대 반 칸만큼 얕다)
                XCTAssertEqual(h.ground(at: c), z0 - s.height, accuracy: s.bowlSlope * 0.5 + 0.05, tag)
                XCTAssertEqual(h.surface(at: k.rim.upperBound - 1), .fairway, tag)
                XCTAssertEqual(h.surface(at: k.rim.lowerBound - 2), .rough, tag)
            }
            // 물·월드 끝과 겹치지 않고, 나머지 홀 정보는 그대로다
            let lo = k.collar.lowerBound - Hole.gimmickBlend, hi = k.collar.upperBound + Hole.gimmickBlend
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

    /// 장치의 약속: 분화구·분지 안에 놓인 공은 서지 않고 컵까지 굴러 들어간다. 테두리 꼭짓점 1m 안쪽은 뺀다 — 봉우리 마루라
    /// 가만히 놓은 공은 걸쳐 설 수 있다(실제 샷은 속도를 갖고 들어온다)
    func testBallInTheBowlAlwaysDrops() {
        for d in Self.dressed {
            let k = Hole.gimmickKnots(cup: d.hole.holeX, shape: d.shape)
            // 컵 바로 위(±1m)도 뺀다 — 속도 0으로 컵 위에 놓인 공은 '굴러 들어온' 것이 아니라 판정이 없다
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
                XCTAssertGreaterThan((r.x - foot) * out, -1.5, "비탈 위에 섰다: 발치에서 \((r.x - foot) * out)m")
                XCTAssertLessThan((r.x - edge) * out, Hole.gimmickBlend + 4, "발치를 지나 멀리 달아났다")
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
        XCTAssertGreaterThanOrEqual(all.filter { $0.gimmick == .volcano }.count, 7, "관찰용 강제: 들어가는 홀 전부")
        let hole = try XCTUnwrap(all.first { $0.gimmick != nil })
        XCTAssertEqual(hole.movingPin(to: hole.holeX + 3).holeX, hole.holeX, "장치 그린의 컵은 분지 바닥에서 못 옮긴다")
        XCTAssertNil(hole.withGimmick(.funnel), "이미 장치가 있는 홀에는 또 얹지 않는다")
        XCTAssertEqual(hole.displayName, GimmickKind.volcano.displayName, "홀 이름은 장치가 앞선다")
        XCTAssertEqual(hole.withWind(3).gimmick, .volcano, "사본이 장치를 잃지 않는다")
    }
}
