@testable import GolfCore
import XCTest

/// 장치 그린·지형 장애물 (M7, 2026-10-05 화산·깔때기 → 10-07 메사·사구·항아리): 지형 불변식 · 장치의 약속(분지에 들어온 공은 들어간다 ·
/// 비탈의 공은 발치로 · 메사 꼭대기의 공은 선다 · 구덩이의 공은 바닥으로) · 라운드 편성
final class GimmickTests: XCTestCase {
    /// 시드 1~12의 108홀에 다섯 장치를 얹어 본 표본 (얹을 수 있는 홀만)
    private static let dressed: [(base: Hole, hole: Hole, kind: GimmickKind, shape: GimmickShape)] = (1 ... 12)
        .flatMap { (seed: UInt32) in
            CourseGenerator.makeCourse(seed: seed).flatMap { base in
                GimmickKind.allCases.compactMap { kind in
                    base.withGimmick(kind).map { (base, $0, kind, GimmickShape.shape(for: kind, worldW: base.worldW)) }
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
            let floor = kind.replacesGreen ? 85 : 40 // 장애물은 그린 앞·착지 지대가 평평해야 해서 덜 들어간다 (실측은 프로브 표)
            XCTAssertGreaterThan(n, floor, "\(kind): 108홀 중 \(n)홀에만 얹힌다")
        }
    }

    func testShapeAndSurfaces() throws {
        for d in Self.dressed {
            let h = d.hole, s = d.shape, c = h.gimmickCenter
            let dir: Double = h.holeX >= h.teeX ? 1 : -1
            let k = try XCTUnwrap(h.gimmickKnots)
            let tag = "\(d.kind) par \(h.par) worldW \(Int(h.worldW)) seed-hole cup \(Int(h.holeX))"
            let z0 = d.base.ground(at: c)
            XCTAssertEqual(h.gimmick, d.kind)
            XCTAssertEqual(h.surface(at: h.holeX), .green, tag)
            let extent = try XCTUnwrap(d.base.gimmickLayout(d.kind, shape: s)?.extent)
            let lo = extent.lowerBound, hi = extent.upperBound
            if d.kind.isBowl || d.kind == .potBunker {
                // 바닥(컵·구덩이 꼭짓점)이 가장 낮은 자리 — 양쪽 벽이 가장자리 1m 안까지 같은 경사로 바닥 쪽으로 기울어 있다
                // (가장자리·발치를 정수 자리에 맞춰 양쪽 폭이 최대 0.5m 다르다 → 경사 ±12%)
                for x in stride(from: k.rim.lowerBound + 1, through: k.rim.upperBound - 1, by: 1.0)
                    where abs(x - c) >= 1.5 {
                    XCTAssertGreaterThan(h.ground(at: x), h.ground(at: c) + 0.1, tag)
                    let toward = x < c ? -1.0 : 1.0
                    XCTAssertGreaterThan(h.slope(at: x) * toward, s.bowlSlope * 0.86, "\(tag) x−c \(x - c)")
                    XCTAssertLessThan(h.slope(at: x) * toward, s.bowlSlope * 1.14, "\(tag) x−c \(x - c)")
                }
            }
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
            case .funnel: // 컵은 원래 그린보다 height만큼 깊다 (컵이 샘플 사이에 있어 바닥은 최대 반 칸만큼 얕다)
                XCTAssertEqual(h.ground(at: c), z0 - s.height, accuracy: s.bowlSlope * 0.5 + 0.05, tag)
                XCTAssertEqual(h.surface(at: k.rim.upperBound - 1), .fairway, tag)
                XCTAssertEqual(h.surface(at: k.rim.lowerBound - 2), .rough, tag)
            case .mesa: // 꼭대기는 height 높이의 평평한 그린, 절벽은 경사 1.2 이상, 발치 띠는 평평한 러프
                for x in stride(from: k.rim.lowerBound, through: k.rim.upperBound, by: 1.0) {
                    XCTAssertEqual(h.ground(at: x), z0 + s.height, accuracy: 1e-9, "\(tag) x \(x)")
                }
                XCTAssertEqual(h.greenStart, k.rim.lowerBound, tag)
                XCTAssertEqual(h.greenEnd, k.rim.upperBound, tag)
                for (rim, foot, out) in [
                    (k.rim.lowerBound, k.foot.lowerBound, -1.0),
                    (k.rim.upperBound, k.foot.upperBound, 1.0),
                ] {
                    XCTAssertGreaterThan(abs(h.slope(at: (rim + foot) / 2)), 1.2, "\(tag): 절벽")
                    XCTAssertEqual(h.ground(at: foot + out * 2), z0, accuracy: 1e-9, tag)
                    XCTAssertEqual(h.surface(at: foot + out * 2), .rough, tag)
                    XCTAssertEqual(h.surface(at: rim + out * 1), .rough, tag)
                }
            case .dune: // 마루는 한 점(height), 양면은 모래(경사 ≈ 1.0), 티 쪽 발치는 러프 띠, 그린 쪽 발치는 페어웨이 띠 — 그린 복합체는 그대로
                XCTAssertEqual(h.ground(at: c), z0 + s.height, accuracy: 1e-9, tag)
                XCTAssertEqual(k.rim.lowerBound, k.rim.upperBound, tag)
                for (foot, out) in [(k.foot.lowerBound, -1.0), (k.foot.upperBound, 1.0)] {
                    let mid = (c + foot) / 2
                    XCTAssertEqual(h.surface(at: mid), .bunker, tag)
                    XCTAssertEqual(abs(h.slope(at: mid)), s.coneSlope, accuracy: s.coneSlope * 0.15, "\(tag): 모래면 경사")
                    XCTAssertEqual(h.ground(at: foot + out * 1.5), z0, accuracy: 1e-9, tag)
                }
                let nearFoot = dir > 0 ? k.foot.lowerBound : k.foot.upperBound
                let farFoot = dir > 0 ? k.foot.upperBound : k.foot.lowerBound
                XCTAssertEqual(h.surface(at: nearFoot - dir * 2), .rough, "\(tag): 티 쪽 발치 띠")
                XCTAssertEqual(h.surface(at: farFoot + dir * 1.5), .fairway, "\(tag): 그린 쪽 띠")
            case .potBunker: // 바닥은 height만큼 깊고, 벽은 모래, 양쪽 띠는 페어웨이. 파4·5는 반대쪽 테두리가 풀 드라이버 캐리의 여유 앞
                XCTAssertEqual(h.ground(at: c), z0 - s.height, accuracy: s.bowlSlope * 0.5 + 0.05, tag)
                XCTAssertEqual(h.surface(at: c), .bunker, tag)
                XCTAssertEqual(h.surface(at: k.rim.lowerBound + 1), .bunker, tag)
                XCTAssertEqual(h.surface(at: k.rim.upperBound - 1), .bunker, tag)
                XCTAssertEqual(h.surface(at: k.rim.lowerBound - 1), .fairway, tag)
                XCTAssertEqual(h.surface(at: k.rim.upperBound + 1), .fairway, tag)
                if h.par >= 4 { // 반대쪽 테두리는 풀 드라이버 캐리의 여유 앞 — 자리가 안 나오면 5m씩 최대 20m 티 쪽으로 밀린다
                    let carry = try XCTUnwrap(d.base.fullDriveCarry())
                    let farRim = abs((dir > 0 ? k.rim.upperBound : k.rim.lowerBound) - h.teeX)
                    let want = carry - Hole.driveClearMargin(carry: carry)
                    XCTAssertLessThanOrEqual(farRim, want + 1.01, "\(tag): 반대쪽 테두리 \(farRim)m, 풀 드라이버 캐리 \(carry)m")
                    XCTAssertGreaterThanOrEqual(farRim, want - 21.01, "\(tag): 반대쪽 테두리 \(farRim)m, 풀 드라이버 캐리 \(carry)m")
                }
            }
            if d.kind.isRaised { // 화면 끝 릴리프(46px)가 공을 비탈 위에 올려놓지 않는다 — 폭 1280pt 화면 기준, 반대편 발치가 릴리프 거리 밖 (리뷰 M-2)
                let relief = 46 * h.worldW / 1280
                let farRoom = dir > 0 ? h.worldW - k.foot.upperBound : k.foot.lowerBound
                XCTAssertGreaterThan(farRoom, relief + 1, "\(tag): 반대편 발치가 월드 끝에서 \(farRoom)m, 릴리프 \(relief)m")
            }
            // 그린은 하나뿐이다. 그린을 바꾸는 장치는 에이프런이 없고(원래 그린·에이프런 조각이 밖에 남으면 그 위에서 퍼터가 잡히고 '온그린' 판정 — 리뷰 M-1),
            // 장애물은 그린 복합체를 한 점도 건드리지 않는다
            let greens = h.segments.filter { $0.type == .green }
            XCTAssertEqual(greens.count, 1, tag)
            XCTAssertEqual(greens.first?.from ?? 0, h.greenStart, accuracy: 1e-9, tag)
            XCTAssertEqual(greens.first?.to ?? 0, h.greenEnd, accuracy: 1e-9, tag)
            if d.kind.replacesGreen {
                XCTAssertFalse(h.segments.contains { $0.type == .apron }, tag)
                XCTAssertEqual(h.greenSlope, 0, tag)
                XCTAssertNil(h.gimmickX, tag)
            } else {
                XCTAssertEqual(h.greenStart, d.base.greenStart, tag)
                XCTAssertEqual(h.greenEnd, d.base.greenEnd, tag)
                XCTAssertEqual(h.apronStart, d.base.apronStart, tag)
                XCTAssertEqual(h.greenSlope, d.base.greenSlope, tag)
                XCTAssertEqual(h.gimmickX, c, tag)
                let far = dir > 0 ? hi : lo
                XCTAssertGreaterThanOrEqual(
                    (h.apronStart - far) * dir,
                    0,
                    "\(tag): 장애물 끝 \(far)이 에이프런 \(h.apronStart)을 넘었다"
                )
                XCTAssertEqual(
                    h.segments.filter { $0.type == .apron }.map { [$0.from, $0.to] },
                    d.base.segments.filter { $0.type == .apron }.map { [$0.from, $0.to] }, tag
                )
            }
            // 장치 자리의 원래 벙커 조각은 없다 — 모래는 장치 자신의 것(사구 양면·항아리 구덩이)뿐
            let sand = h.segments.filter { $0.type == .bunker && $0.to > lo && $0.from < hi }.map { [$0.from, $0.to] }
            switch d.kind {
            case .dune: XCTAssertEqual(sand, [[k.foot.lowerBound, k.foot.upperBound]], tag)
            case .potBunker: XCTAssertEqual(sand, [[k.rim.lowerBound, k.rim.upperBound]], tag)
            default: XCTAssertEqual(sand, [], "\(tag): 장치에 걸친 벙커 토막")
            }
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
            XCTAssertGreaterThanOrEqual((min(lo, hi, by: dir) - h.teeX) * dir, 40, "\(tag): 티샷이 설 자리")
            XCTAssertEqual(h.par, d.base.par)
            XCTAssertEqual(h.teeX, d.base.teeX)
            XCTAssertEqual(h.wind, d.base.wind)
            XCTAssertEqual(h.signature, d.base.signature)
            XCTAssertEqual(h.elevation.count, d.base.elevation.count)
            XCTAssertEqual(h.holeX, d.base.holeX)
            // 세그먼트는 빈틈·겹침 없이 월드를 덮는다
            for (a, b) in zip(h.segments, h.segments.dropFirst()) {
                XCTAssertEqual(a.to, b.from, accuracy: 1e-9, tag)
            }
            // 장치 바깥은 양쪽 다 한 점도 안 바뀐다
            XCTAssertEqual(Array(h.elevation[0 ..< Int(lo)]), Array(d.base.elevation[0 ..< Int(lo)]), tag)
            XCTAssertEqual(Array(h.elevation[(Int(hi) + 1)...]), Array(d.base.elevation[(Int(hi) + 1)...]), tag)
        }
    }

    /// 티 쪽 끝 (dir에 따라 lo 또는 hi)
    private func min(_ lo: Double, _ hi: Double, by dir: Double) -> Double {
        dir > 0 ? lo : hi
    }

    /// 분지 장치의 약속: 분화구·분지 안에 놓인 공은 서지 않고 컵까지 굴러 들어간다. 컵 바로 위(±1m)는 뺀다 — 속도 0으로 컵 위에 놓인 공은
    /// '굴러 들어온' 것이 아니라 판정이 없다
    func testBallInTheBowlAlwaysDrops() throws {
        for d in Self.dressed where d.kind.isBowl {
            let k = try XCTUnwrap(d.hole.gimmickKnots)
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
    func testNoBallHangsOnTheCraterRim() throws {
        for d in Self.dressed where d.kind == .volcano {
            let k = try XCTUnwrap(d.hole.gimmickKnots)
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

    /// 솟은 장치의 비탈(화산 봉우리·메사 절벽·사구 모래면)에 떨어진 공은 비탈에 서지 않고 그쪽 발치(평평한 띠 근처)로 내려온다 — 다음 샷을 칠 자리가 있다
    func testBallOnTheSlopeComesDownToTheFoot() throws {
        for d in Self.dressed where d.kind.isRaised {
            let k = try XCTUnwrap(d.hole.gimmickKnots)
            for (rim, foot, edge, out) in [
                (k.rim.lowerBound, k.foot.lowerBound, k.collar.lowerBound, -1.0),
                (k.rim.upperBound, k.foot.upperBound, k.collar.upperBound, 1.0),
            ] {
                let dir: Double = d.hole.holeX >= d.hole.teeX ? 1 : -1
                let farSideOfDune = d.kind == .dune && out == dir // 사구 뒷면: 넘긴 공은 짧은 페어웨이 띠(3m)를 지나 그린 쪽으로 가도 된다
                for frac in [0.4, 0.8] {
                    let r = release(d.hole, at: rim + (foot - rim) * frac)
                    XCTAssertFalse(r.holed, "\(d.kind)")
                    XCTAssertGreaterThan(
                        (r.x - foot) * out,
                        -0.5,
                        "\(d.kind) par \(d.hole.par): 비탈 위에 섰다: 발치에서 \((r.x - foot) * out)m"
                    )
                    if farSideOfDune {
                        XCTAssertNotEqual(
                            d.hole.surface(at: r.x),
                            .bunker,
                            "\(d.kind) par \(d.hole.par): 뒷면을 내려온 공이 모래에 섰다"
                        )
                        XCTAssertGreaterThanOrEqual(
                            (d.hole.greenEnd - r.x) * dir,
                            -0.5,
                            "\(d.kind) par \(d.hole.par): 그린을 지나쳤다"
                        )
                    } else {
                        XCTAssertLessThan(
                            (r.x - edge) * out,
                            0.5,
                            "\(d.kind) par \(d.hole.par): 발치 띠를 지나 달아났다: 띠 끝에서 \((r.x - edge) * out)m"
                        )
                    }
                    XCTAssertLessThanOrEqual(abs(d.hole.slope(at: r.x)), Ballistics.steepRest, "\(d.kind)")
                    XCTAssertLessThan(r.t, 10, "\(d.kind) par \(d.hole.par): 내려오는 데 \(r.t)초")
                }
            }
        }
    }

    /// 메사의 약속: 꼭대기(평평한 그린)에 놓인 공은 그대로 선다 — 분지 장치처럼 컵으로 밀리지 않는다
    func testBallOnTheMesaTopStays() throws {
        for d in Self.dressed where d.kind == .mesa {
            let k = try XCTUnwrap(d.hole.gimmickKnots)
            for x in stride(from: k.rim.lowerBound + 1, through: k.rim.upperBound - 1, by: 1.0)
                where abs(x - d.hole.holeX) >= 1 {
                let r = release(d.hole, at: x)
                XCTAssertFalse(r.holed, "par \(d.hole.par): 꼭대기 \(x - d.hole.holeX)m에 놓은 공이 들어갔다")
                XCTAssertEqual(
                    r.x,
                    x,
                    accuracy: 0.6,
                    "par \(d.hole.par): 꼭대기 \(x - d.hole.holeX)m에 놓은 공이 \(r.x - x)m 움직였다"
                )
                XCTAssertEqual(d.hole.surface(at: r.x), .green)
            }
        }
    }

    /// 항아리의 약속: 벽 어디에 떨어져도 모래 바닥(V 꼭짓점)으로 내려온다 — 거기서 샌드웨지로 나온다
    func testBallInThePitSettlesAtTheBottom() throws {
        for d in Self.dressed where d.kind == .potBunker {
            let k = try XCTUnwrap(d.hole.gimmickKnots), c = d.hole.gimmickCenter
            for (rim, inward) in [(k.rim.lowerBound, 1.0), (k.rim.upperBound, -1.0)] {
                for frac in [0.3, 0.7] {
                    let r = release(d.hole, at: rim + inward * (c - k.rim.lowerBound) * frac)
                    XCTAssertFalse(r.holed)
                    XCTAssertEqual(r.x, c, accuracy: 1.5, "par \(d.hole.par): 벽에 놓은 공이 바닥에서 \(r.x - c)m에 섰다")
                    XCTAssertEqual(d.hole.surface(at: r.x), .bunker)
                    XCTAssertLessThan(r.t, 10, "par \(d.hole.par): 바닥까지 \(r.t)초")
                }
            }
        }
    }

    func testDressPlacesThreeDifferentGimmicksAndShowsOneEarly() {
        var early = 0, rounds = 0, placed = 0, repeats = 0
        var seen: [GimmickKind: Int] = [:]
        XCTAssertEqual(
            GimmickKind.inRotation,
            [.volcano, .mesa, .dune, .potBunker],
            "깔때기는 편성에서 뺐다 (2026-10-06 판정 '너무 쉬워질 것 같다')"
        )
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
            let used = kinds.compactMap(\.self)
            placed += used.count
            for k in used {
                seen[k, default: 0] += 1
            }
            XCTAssertLessThanOrEqual(used.count, 3, "seed \(seed)")
            XCTAssertGreaterThanOrEqual(used.count, 2, "seed \(seed): 장치가 \(used.count)홀뿐")
            repeats += Set(used).count < used.count ? 1 : 0 // 남은 종류가 그 토막의 어느 홀에도 안 맞으면 쓴 종류를 한 번 더 — 드물어야 한다
            XCTAssertFalse(kinds.contains(.funnel), "seed \(seed): 깔때기가 편성에 들어왔다")
            // 앞 토막(1·2번)·가운데(4~6번)·뒤(7~9번)에 하나씩, 3번은 비운다
            XCTAssertLessThanOrEqual(kinds[0 ..< 2].compactMap(\.self).count, 1, "seed \(seed)")
            XCTAssertNil(kinds[2], "seed \(seed): 3번 홀은 비워 둔다")
            XCTAssertLessThanOrEqual(kinds[3 ..< 6].compactMap(\.self).count, 1, "seed \(seed)")
            XCTAssertLessThanOrEqual(kinds[6 ..< 9].compactMap(\.self).count, 1, "seed \(seed)")
            for (i, h) in out.enumerated() where h.gimmick == nil {
                XCTAssertEqual(h.elevation, course[i].elevation, "장치 없는 홀은 그대로")
            }
        }
        XCTAssertGreaterThan(Double(early) / Double(rounds), 0.9, "첫 장치가 1·2번 홀 안에 나오는 라운드 \(early)/\(rounds)")
        XCTAssertGreaterThan(Double(placed) / Double(rounds), 2.7, "라운드당 장치 \(Double(placed) / Double(rounds))홀")
        XCTAssertLessThanOrEqual(repeats, 4, "같은 장치가 두 번 나온 라운드 \(repeats)/\(rounds)")
        for kind in GimmickKind.inRotation {
            XCTAssertGreaterThan(seen[kind] ?? 0, 20, "\(kind): 60라운드에 \(seen[kind] ?? 0)번 — 네 종류가 고르게 나와야 한다 \(seen)")
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
        XCTAssertNil(hole.withGimmick(.potBunker), "이미 장치가 있는 홀에는 장애물도 안 얹는다")
        XCTAssertEqual(hole.displayName, GimmickKind.volcano.displayName, "홀 이름은 장치가 앞선다")
        XCTAssertEqual(hole.withWind(3).gimmick, .volcano, "사본이 장치를 잃지 않는다")
        let pit = try XCTUnwrap(GimmickKind.dress(course: course, seed: 3, forced: .potBunker)
            .first { $0.gimmick == .potBunker })
        XCTAssertEqual(pit.withWind(3).gimmickX, pit.gimmickX, "장애물 사본이 자리를 잃지 않는다")
        XCTAssertEqual(pit.movingPin(to: pit.holeX + 3).holeX, pit.holeX, "장애물 홀도 핀을 안 옮긴다 (서프라이즈가 거른다)")
    }
}
