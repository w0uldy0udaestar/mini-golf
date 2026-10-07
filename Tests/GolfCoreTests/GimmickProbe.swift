@testable import GolfCore
import XCTest

/// 장치 계측 (2026-10-05 M7 화산·깔때기 → 10-07 메사·사구·항아리): 실제로 공을 쳐 보고 "성공하는 세기 창이 얼마나 넓은가 · 빗나가면 어디에 서는가 ·
/// 끝나지 않는 굴림이 있는가"를 잰다. 성공은 종류마다 다르다 — 분지는 홀인, 메사는 꼭대기에 서기, 사구는 넘기기, 항아리는 구덩이 밖으로.
/// `swift test --filter GimmickProbe`의 `GIMMICK` 줄을 보고 치수(GimmickShape)를 정한다
final class GimmickProbe: XCTestCase {
    struct Outcome {
        var holed = false, water = false, timedOut = false
        var t = 0.0, restX = 0.0
    }

    static func shoot(
        _ hole: Hole, from x: Double, club: Club, power: Double, shape: ShotShape = .standard, maxT: Double = 45
    ) -> Outcome {
        var b = BallState(x: x, y: hole.ground(at: x))
        let dir = hole.holeX >= x ? 1.0 : -1.0
        let lie = x == hole.teeX ? Surface.tee : hole.surface(at: x)
        Ballistics.launch(
            &b, club: club, heightPct: power, lie: lie, dir: dir,
            slope: club.isPutter ? 0 : hole.slope(at: x) * Phys.stanceSlopeRatio,
            shape: shape, roughLie: lie == .rough ? hole.roughLie(at: x) : .normal
        )
        var t = 0.0
        while t < maxT {
            switch Ballistics.step(&b, hole: hole) {
            case .holed: return Outcome(holed: true, t: t, restX: hole.holeX)
            case .water: return Outcome(water: true, t: t, restX: b.x)
            default:
                if b.phase == .rest {
                    return Outcome(t: t, restX: b.x)
                }
            }
            t += Phys.dt
        }
        return Outcome(timedOut: true, t: t, restX: b.x)
    }

    nonisolated(unsafe) static var holedTimes: [Double] = []

    static func club(_ id: String) -> Club {
        ClubTable.all.first { $0.id == id }!
    }

    /// 한 자리에서 여러 클럽·샷 종류·세기를 훑어, 가장 잘 되는 조합의 "성공하는 세기 칸 수"와 실패한 공의 평균 거리(목표에서)를 낸다
    static func scan(
        _ hole: Hole, from x: Double, clubs: [String], shapes: [ShotShape], powers: [Double],
        target: Double, success: (Outcome) -> Bool
    ) -> (window: Int, best: String, missDist: Double, maxHoledT: Double, timeouts: Int) {
        var best = (window: 0, name: "-", miss: 0.0)
        var maxT = 0.0, timeouts = 0
        var holedT: [Double] = []
        defer { Self.holedTimes += holedT }
        for id in clubs {
            for shape in shapes {
                var ok = 0
                var miss: [Double] = []
                for p in powers {
                    let o = shoot(hole, from: x, club: club(id), power: p, shape: shape)
                    timeouts += o.timedOut ? 1 : 0
                    if o.holed {
                        maxT = max(maxT, o.t)
                        holedT.append(o.t)
                    }
                    if success(o) {
                        ok += 1
                    } else {
                        miss.append(abs(o.restX - target))
                    }
                }
                if ok > best.window {
                    let near = miss.sorted().prefix(max(1, miss.count / 2)) // 가까운 절반의 평균 — 터무니없이 짧은 샷은 뺀다
                    best = (
                        ok,
                        "\(id)\(shape == .standard ? "" : "-\(shape.rawValue)")",
                        near.isEmpty ? 0 : near.reduce(0, +) / Double(near.count)
                    )
                }
            }
        }
        return (best.window, best.name, best.miss, maxT, timeouts)
    }

    /// 비탈 위 한 자리에 놓은 공이 굴러 내려와 선 자리
    static func settle(_ hole: Hole, from: Double) -> Double {
        var b = BallState(x: from, y: hole.ground(at: from), phase: .roll)
        var t = 0.0
        while b.phase != .rest, t < 30 {
            _ = Ballistics.step(&b, hole: hole)
            t += Phys.dt
        }
        return b.x
    }

    func testGimmickGreens() {
        let powers = stride(from: 0.20, through: 1.0001, by: 0.04).map(\.self) // 21칸 — 한 칸 = 백스윙 4%
        let fine = stride(from: 0.50, through: 1.0001, by: 0.01).map(\.self) // 풀스윙 구간은 1% 간격 (티샷·먼 어프로치)
        var lines: [String] = []
        var totalTimeouts = 0
        var medians: [String: (median: Int, min: Int)] = [:]
        var slowest: [GimmickKind: Double] = [:]
        var collarRate: [GimmickKind: Double] = [:]
        var pitStats: [String: (n: Int, hit: Int)] = [:] // 항아리: 티샷이 구덩이에 빠지는 비율
        for kind in GimmickKind.allCases {
            Self.holedTimes = []
            var eligible = 0, total = 0, rests = 0, inCollar = 0
            var rows: [String: [(Int, Double, Double)]] = [:] // 자리 → (창, 빗나간 거리, 최장 홀인 시간)
            var samples: [String] = []
            for seed: UInt32 in 1 ... 6 {
                for base in CourseGenerator.makeCourse(seed: seed) {
                    total += 1
                    guard let hole = base.withGimmick(kind), let k = hole.gimmickKnots else { continue }
                    eligible += 1
                    let dir = hole.holeX >= hole.teeX ? 1.0 : -1.0
                    let c = hole.gimmickCenter
                    let (nearRim, nearFoot, farRim, farFoot) = dir > 0
                        ? (k.rim.lowerBound, k.foot.lowerBound, k.rim.upperBound, k.foot.upperBound)
                        : (k.rim.upperBound, k.foot.upperBound, k.rim.lowerBound, k.foot.lowerBound)
                    // 종류별 성공: 분지 홀인 · 메사 꼭대기에 서기(홀인 포함) · 사구 넘기기(모래 아닌 반대쪽) · 항아리 구덩이 밖
                    let success: (Outcome) -> Bool = { o in
                        switch kind {
                        case .volcano, .funnel: o.holed
                        case .mesa: o.holed || (!o.water && !o.timedOut && hole.surface(at: o.restX) == .green)
                        case .dune: o
                            .holed ||
                            (!o.water && !o.timedOut && (o.restX - farFoot) * dir >= 0 && hole
                                .surface(at: o.restX) != .bunker)
                        case .potBunker: o.holed || (!o.water && !o.timedOut && hole.surface(at: o.restX) != .bunker)
                        }
                    }
                    let target = kind.replacesGreen ? hole.holeX : c
                    var spots: [(String, Double, [String], [ShotShape])] = []
                    if hole.par == 3 {
                        spots.append(("tee1%", hole.teeX, ["4I", "5I", "6I", "7I", "8I", "9I"], [.standard]))
                    }
                    if kind != .potBunker || hole.par == 3 { // 어프로치: 장치 앞 60m·110m에서 (항아리는 파3만 — 파4·5는 티샷의 문제)
                        for d in [60.0, 110.0] where abs(c - hole.teeX) > d + 30 {
                            let x = c - dir * d
                            if hole.surface(at: x) != .water, abs(hole.slope(at: x)) < 0.2 {
                                if d < 100 {
                                    spots.append(("\(Int(d))m", x, ["SW", "PW", "9I", "8I"], [.standard, .lob]))
                                } else {
                                    spots.append(("\(Int(d))m1%", x, ["PW", "9I", "8I", "7I"], [.standard]))
                                }
                            }
                        }
                    }
                    if kind.isRaised { // 다시 올리기: 티 쪽 비탈 중턱에 놓은 공이 굴러 내려와 실제로 선 자리에서
                        let from = nearRim + (nearFoot - nearRim) * 0.5
                        let x = Self.settle(hole, from: from)
                        inCollar += k.collar.contains(x) && !k.foot.contains(x) ? 1 : 0
                        rests += 1
                        spots.append(("foot", x, ["SW", "PW", "9I"], [.standard, .lob]))
                        spots.append(("foot SW로브만", x, ["SW"], [.lob])) // 발치에서 자동으로 잡히는 조합
                        if kind == .mesa { // 뒤로 떨어진 공: 반대쪽 절벽 중턱 → 반대쪽 발치에서 되돌아 올리기
                            let fx = Self.settle(hole, from: farRim + (farFoot - farRim) * 0.5)
                            inCollar += k.collar.contains(fx) && !k.foot.contains(fx) ? 1 : 0
                            rests += 1
                            spots.append(("farFoot SW로브만", fx, ["SW"], [.lob]))
                        }
                    }
                    if kind == .potBunker { // 바닥에서 탈출 (모래 파워 45%)
                        let floor = Self.settle(hole, from: nearRim + (c - nearRim) * 0.5)
                        inCollar += abs(floor - c) < 1.5 ? 1 : 0
                        rests += 1
                        spots.append(("floor", floor, ["SW", "PW"], [.standard, .lob]))
                        spots.append(("floor SW만", floor, ["SW"], [.standard, .lob]))
                        if hole.par >= 4 { // 티샷: 풀 드라이버는 넘기고 덜 친 드라이브는 빠지는가, 3번 우드 레이업은 안전한가
                            for (name, id, ps) in [("DR", "DR", fine), ("3W", "3W", [1.0])] {
                                var hit = 0
                                for p in ps {
                                    let o = Self.shoot(hole, from: hole.teeX, club: Self.club(id), power: p)
                                    hit += hole.surface(at: o.restX) == .bunker && k.rim.contains(o.restX) ? 1 : 0
                                }
                                pitStats[name, default: (0, 0)].n += ps.count
                                pitStats[name, default: (0, 0)].hit += hit
                            }
                            let full = Self.shoot(hole, from: hole.teeX, club: Self.club("DR"), power: 1.0)
                            pitStats["DR 1.0 넘김", default: (0, 0)].n += 1
                            pitStats["DR 1.0 넘김", default: (0, 0)].hit += (full.restX - farRim) * dir > 0 && hole
                                .surface(at: full.restX) != .bunker ? 1 : 0
                            let one = Self.shoot(hole, from: hole.teeX, club: Self.club("DR"), power: 0.96)
                            pitStats["DR 0.96 빠짐", default: (0, 0)].n += 1
                            pitStats["DR 0.96 빠짐", default: (0, 0)].hit += hole
                                .surface(at: one.restX) == .bunker ? 1 : 0
                        }
                    }
                    for (name, x, clubs, shapes) in spots {
                        let r = Self.scan(
                            hole, from: x, clubs: clubs, shapes: shapes, powers: name.hasSuffix("%") ? fine : powers,
                            target: target, success: success
                        )
                        rows[name, default: []].append((r.window, r.missDist, r.maxHoledT))
                        totalTimeouts += r.timeouts
                        if samples.count < 6 {
                            samples.append(String(
                                format: "  seed %u par %d %@: 창 %d칸(%@) 빗나감 %.0fm 최장 %.1fs", seed, hole.par, name,
                                r.window, r.best, r.missDist, r.maxHoledT
                            ))
                        }
                    }
                }
            }
            lines.append("\(kind.rawValue): 얹을 수 있는 홀 \(eligible)/\(total)")
            if rests > 0 {
                lines.append("  비탈·벽에서 내려온 공이 제자리(발치 띠·바닥)에 선 곳: \(inCollar)/\(rests)")
                collarRate[kind] = Double(inCollar) / Double(rests)
            }
            for name in ["tee1%", "60m", "110m1%", "foot", "foot SW로브만", "farFoot SW로브만", "floor", "floor SW만"] {
                guard let v = rows[name], !v.isEmpty else { continue }
                let w = v.map(\.0).sorted()
                medians["\(kind.rawValue) \(name)"] = (w[w.count / 2], w[0])
                lines.append(String(
                    format: "  %@ (%d곳): 창 중앙 %d칸 · 최소 %d · 0칸인 곳 %d · 빗나감 평균 %.0fm · 최장 홀인 %.1fs",
                    name, v.count, w[w.count / 2], w[0], w.filter { $0 == 0 }.count,
                    v.map(\.1).reduce(0, +) / Double(v.count), v.map(\.2).max() ?? 0
                ))
            }
            if kind == .potBunker {
                for name in ["DR", "3W", "DR 1.0 넘김", "DR 0.96 빠짐"] {
                    if let s = pitStats[name], s.n > 0 {
                        lines.append(String(
                            format: "  티샷 %@: %d/%d (%.0f%%)",
                            name,
                            s.hit,
                            s.n,
                            100 * Double(s.hit) / Double(s.n)
                        ))
                    }
                }
            }
            let ts = Self.holedTimes.sorted()
            slowest[kind] = ts.isEmpty ? 0 : ts[ts.count * 9 / 10]
            if !ts.isEmpty {
                lines.append(String(
                    format: "  홀인까지: 중앙 %.1fs · 90%% %.1fs · 최장 %.1fs (%d샷, 비행 포함)", ts[ts.count / 2],
                    ts[ts.count * 9 / 10], ts[ts.count - 1], ts.count
                ))
            }
            lines += samples.prefix(3)
        }
        lines.append("끝나지 않은 굴림(45초): \(totalTimeouts)")
        for l in lines {
            print("GIMMICK " + l)
        }
        fflush(stdout)
        // 단언이 실패하면 `swift test`가 이 프로세스의 stdout·stderr를 통째로 버린다 (2026-10-07 확인) — 표는 파일에도 남긴다
        let out = NSTemporaryDirectory() + "gimmick-probe.txt"
        try? (lines.map { "GIMMICK " + $0 }.joined(separator: "\n") + "\n").write(
            toFile: out,
            atomically: true,
            encoding: .utf8
        )
        // 회귀 대역 (2026-10-05 실측 — 칸 = 백스윙 4%, '1%' 자리는 1%): 물리·치수를 바꾸면 여기서 드러난다
        XCTAssertEqual(totalTimeouts, 0, "끝나지 않는 굴림")
        // 화산에서 빗나간 공은 발치의 평평한 띠 안에 선다 (실측 46/46) — 띠 밖으로 달아나면 자동 로브가 안 잡히고 닿지도 않는다
        XCTAssertGreaterThanOrEqual(collarRate[.volcano] ?? 0, 0.95)
        // 그 자리에서 다시 올리기: 실측 중앙 7칸·최소 5칸, 자동으로 잡히는 SW 로브만으로도 같다. 한 번의 압박 샷이 되면 안 된다 — 최소 3칸(12%)
        XCTAssertGreaterThanOrEqual(medians["volcano foot"]?.min ?? 0, 3)
        XCTAssertGreaterThanOrEqual(medians["volcano foot"]?.median ?? 0, 5)
        XCTAssertGreaterThanOrEqual(medians["volcano foot SW로브만"]?.min ?? 0, 3, "발치에서 자동으로 잡히는 조합이 통해야 한다")
        // 화산 파3 티샷 홀인원: 실측 중앙 4% — 노려 볼 만하되 흔하지 않게 (2~9%)
        XCTAssertGreaterThanOrEqual(medians["volcano tee1%"]?.median ?? 0, 2)
        XCTAssertLessThanOrEqual(medians["volcano tee1%"]?.median ?? 99, 9)
        // 깔때기 어프로치: 실측 60m 중앙 7칸(28%)·110m 17% — 넉넉한 홀이다
        XCTAssertGreaterThanOrEqual(medians["funnel 60m"]?.median ?? 0, 4)
        XCTAssertGreaterThanOrEqual(medians["funnel 110m1%"]?.median ?? 0, 8)
        // 홀인까지(비행 포함) 90%가 화산 9초·깔때기 12초 안 — 깔때기 첫 판은 시계추로 15초였다
        XCTAssertLessThan(slowest[.volcano] ?? 99, 10.5)
        XCTAssertLessThan(slowest[.funnel] ?? 99, 13.5)
        // 2차 (2026-10-07): 메사·사구에서 내려온 공도 발치 띠에, 항아리 벽의 공은 바닥에 선다. 발치·바닥에서 자동으로 잡히는 조합의 창은 최소 3칸(12%)
        for kind in [GimmickKind.mesa, .dune, .potBunker] {
            XCTAssertGreaterThanOrEqual(collarRate[kind] ?? 0, 0.95, "\(kind)")
        }
        XCTAssertGreaterThanOrEqual(medians["mesa foot SW로브만"]?.min ?? 0, 3, "메사 발치에서 꼭대기에 올려 세우기")
        XCTAssertGreaterThanOrEqual(medians["mesa farFoot SW로브만"]?.min ?? 0, 3, "메사 뒤 발치에서 되돌아 올리기")
        XCTAssertGreaterThanOrEqual(medians["dune foot SW로브만"]?.min ?? 0, 3, "사구 발치에서 넘기기")
        XCTAssertGreaterThanOrEqual(medians["potBunker floor SW만"]?.min ?? 0, 3, "항아리 바닥에서 나오기")
    }
}
