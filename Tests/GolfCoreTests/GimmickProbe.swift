@testable import GolfCore
import XCTest

/// 장치 그린 계측 (2026-10-05, M7): 화산·깔때기에 실제로 공을 쳐 보고 "들어가는 창이 얼마나 넓은가 · 빗나가면 어디에 서는가 ·
/// 끝나지 않는 굴림이 있는가"를 잰다. `swift test --filter GimmickProbe`의 `GIMMICK` 줄을 보고 치수(GimmickShape)를 정한다
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

    /// 한 자리에서 여러 클럽·샷 종류·세기를 훑어, 가장 잘 들어가는 조합의 "들어가는 세기 칸 수"와 빗나간 공의 평균 거리를 낸다
    static func scan(
        _ hole: Hole, from x: Double, clubs: [String], shapes: [ShotShape], powers: [Double]
    ) -> (window: Int, best: String, missDist: Double, maxHoledT: Double, timeouts: Int, onGreen: Int) {
        var best = (window: 0, name: "-", miss: 0.0, onGreen: 0)
        var maxT = 0.0, timeouts = 0
        var holedT: [Double] = []
        defer { Self.holedTimes += holedT }
        for id in clubs {
            for shape in shapes {
                var holed = 0, onGreen = 0
                var miss: [Double] = []
                for p in powers {
                    let o = shoot(hole, from: x, club: club(id), power: p, shape: shape)
                    timeouts += o.timedOut ? 1 : 0
                    if o.holed {
                        holed += 1
                        maxT = max(maxT, o.t)
                        holedT.append(o.t)
                    } else {
                        miss.append(abs(o.restX - hole.holeX))
                        onGreen += hole.surface(at: o.restX) == .green ? 1 : 0
                    }
                }
                if holed > best.window {
                    let near = miss.sorted().prefix(max(1, miss.count / 2)) // 가까운 절반의 평균 — 터무니없이 짧은 샷은 뺀다
                    best = (
                        holed,
                        "\(id)\(shape == .standard ? "" : "-\(shape.rawValue)")",
                        near.isEmpty ? 0 : near.reduce(0, +) / Double(near.count),
                        onGreen
                    )
                }
            }
        }
        return (best.window, best.name, best.miss, maxT, timeouts, best.onGreen)
    }

    func testGimmickGreens() {
        let powers = stride(from: 0.20, through: 1.0001, by: 0.04).map(\.self) // 21칸 — 한 칸 = 백스윙 4%
        let fine = stride(from: 0.50, through: 1.0001, by: 0.01).map(\.self) // 풀스윙 구간은 1% 간격 (티샷·먼 어프로치)
        var lines: [String] = []
        var totalTimeouts = 0
        var medians: [String: (median: Int, min: Int)] = [:]
        var slowest: [GimmickKind: Double] = [:]
        for kind in GimmickKind.allCases {
            Self.holedTimes = []
            var eligible = 0, total = 0
            var rows: [String: [(Int, Double, Double)]] = [:] // 자리 → (창, 빗나간 거리, 최장 홀인 시간)
            var samples: [String] = []
            for seed: UInt32 in 1 ... 6 {
                for base in CourseGenerator.makeCourse(seed: seed) {
                    total += 1
                    guard let hole = base.withGimmick(kind) else { continue }
                    eligible += 1
                    let dir = hole.holeX >= hole.teeX ? 1.0 : -1.0
                    var spots: [(String, Double, [String], [ShotShape])] = []
                    if hole.par == 3 {
                        spots.append(("tee1%", hole.teeX, ["4I", "5I", "6I", "7I", "8I", "9I"], [.standard]))
                    }
                    for d in [60.0, 110.0] where abs(hole.holeX - hole.teeX) > d + 30 {
                        let x = hole.holeX - dir * d
                        if hole.surface(at: x) != .water, abs(hole.slope(at: x)) < 0.2 {
                            if d < 100 {
                                spots.append(("\(Int(d))m", x, ["SW", "PW", "9I", "8I"], [.standard, .lob]))
                            } else {
                                spots.append(("\(Int(d))m1%", x, ["PW", "9I", "8I", "7I"], [.standard]))
                            }
                        }
                    }
                    if kind == .volcano { // 발치(평평한 띠 가운데)에서 다시 올리기
                        let k = Hole.gimmickKnots(cup: hole.holeX, shape: .volcano(worldW: hole.worldW))
                        let x = dir > 0 ? k.foot.lowerBound - 2.5 : k.foot.upperBound + 2.5
                        spots.append(("foot", x, ["SW", "PW", "9I"], [.standard, .lob]))
                    }
                    for (name, x, clubs, shapes) in spots {
                        let r = Self.scan(
                            hole,
                            from: x,
                            clubs: clubs,
                            shapes: shapes,
                            powers: name.hasSuffix("%") ? fine : powers
                        )
                        rows[name, default: []].append((r.window, r.missDist, r.maxHoledT))
                        totalTimeouts += r.timeouts
                        if samples.count < 6 {
                            samples.append(String(
                                format: "  seed %u par %d %@: 창 %d칸(%@) 빗나감 %.0fm 그린 위 %d 최장 %.1fs",
                                seed, hole.par, name, r.window, r.best, r.missDist, r.onGreen, r.maxHoledT
                            ))
                        }
                    }
                }
            }
            lines.append("\(kind.rawValue): 얹을 수 있는 홀 \(eligible)/\(total)")
            for name in ["tee1%", "60m", "110m1%", "foot"] {
                guard let v = rows[name], !v.isEmpty else { continue }
                let w = v.map(\.0).sorted()
                medians["\(kind.rawValue) \(name)"] = (w[w.count / 2], w[0])
                lines.append(String(
                    format: "  %@ (%d곳): 창 중앙 %d칸 · 최소 %d · 0칸인 곳 %d · 빗나감 평균 %.0fm · 최장 홀인 %.1fs",
                    name, v.count, w[w.count / 2], w[0], w.filter { $0 == 0 }.count,
                    v.map(\.1).reduce(0, +) / Double(v.count), v.map(\.2).max() ?? 0
                ))
            }
            let ts = Self.holedTimes.sorted()
            slowest[kind] = ts.isEmpty ? 0 : ts[ts.count * 9 / 10]
            if !ts.isEmpty {
                lines.append(String(
                    format: "  홀인까지: 중앙 %.1fs · 90%% %.1fs · 최장 %.1fs (%d샷, 비행 포함)",
                    ts[ts.count / 2], ts[ts.count * 9 / 10], ts[ts.count - 1], ts.count
                ))
            }
            lines += samples.prefix(3)
        }
        lines.append("끝나지 않은 굴림(45초): \(totalTimeouts)")
        for l in lines {
            print("GIMMICK " + l)
        }
        // 회귀 대역 (2026-10-05 실측 — 칸 = 백스윙 4%, '1%' 자리는 1%): 물리·치수를 바꾸면 여기서 드러난다
        XCTAssertEqual(totalTimeouts, 0, "끝나지 않는 굴림")
        // 화산 발치에서 다시 올리기: 실측 중앙 6칸·최소 4칸(SW 로브). 한 번의 압박 샷이 되면 안 된다 — 최소 3칸(12%)
        XCTAssertGreaterThanOrEqual(medians["volcano foot"]?.min ?? 0, 3)
        XCTAssertGreaterThanOrEqual(medians["volcano foot"]?.median ?? 0, 5)
        // 화산 파3 티샷 홀인원: 실측 중앙 5% — 노려 볼 만하되 흔하지 않게 (2~9%)
        XCTAssertGreaterThanOrEqual(medians["volcano tee1%"]?.median ?? 0, 2)
        XCTAssertLessThanOrEqual(medians["volcano tee1%"]?.median ?? 99, 9)
        // 깔때기 어프로치: 실측 60m 중앙 7칸(28%)·110m 16% — 넉넉한 홀이다
        XCTAssertGreaterThanOrEqual(medians["funnel 60m"]?.median ?? 0, 4)
        XCTAssertGreaterThanOrEqual(medians["funnel 110m1%"]?.median ?? 0, 8)
        // 홀인까지(비행 포함) 90%가 화산 9초·깔때기 12초 안 — 깔때기 첫 판은 시계추로 15초였다
        XCTAssertLessThan(slowest[.volcano] ?? 99, 10.5)
        XCTAssertLessThan(slowest[.funnel] ?? 99, 13.5)
    }
}
