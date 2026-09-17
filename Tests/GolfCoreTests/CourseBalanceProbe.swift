@testable import GolfCore
import XCTest

/// 코스 밸런스 봇 (2026-09-17 코스 개편): 순진 봇(수평 남은 거리만) · 중수 봇(표고차 보정)이 9홀을 돌고
/// 아키타입별 평균 타수−파·12타 탈출 불가율·입수를 낸다. 관찰 출력용 — 개편 뒤 대역 단언을 붙인다.
final class CourseBalanceProbe: XCTestCase {
    static let maxStrokes = 12

    /// 낙차 있는 착지 지대에서 클럽 토탈이 얼마나 변하나 — 유효거리 계수 k 추정
    func testPrintElevationDistanceFactor() throws {
        var lines: [String] = []
        for id in ["DR", "7I"] {
            let club = try XCTUnwrap(ClubTable.all.first { $0.id == id })
            var base = 0.0
            for dz in [-40.0, -20, 0, 20, 40] {
                // 평지 → x ≥ 120m부터 dz만큼 단차 (완충 30m) — 착지 지대의 표고만 바꾼다
                var elev = [Double](repeating: 0, count: 10002)
                for i in 0 ..< elev.count {
                    let u = min(1, max(0, (Double(i) - 120) / 30))
                    elev[i] = dz * (0.5 - 0.5 * cos(u * .pi))
                }
                let hole = Hole(
                    par: 4, dist: 9974, holeX: 9999, worldW: 10000, greenStart: 9987, greenEnd: 10007, apronStart: 9982,
                    segments: [Segment(from: 0, to: 10000, type: .fairway)], elevation: elev, waterRange: nil,
                    greenSlope: 0
                )
                var b = BallState(x: 50, y: 0)
                Ballistics.launch(&b, club: club, heightPct: 1, lie: .fairway, dir: 1)
                var t = 0.0
                while b.phase != .rest, t < 60 {
                    _ = Ballistics.step(&b, hole: hole)
                    t += Phys.dt
                }
                let total = b.x - 50
                if dz == 0 {
                    base = total
                }
                lines.append(String(
                    format: "%@ dz %+.0f total %.0f (Δ %+.0f, k=%.2f)",
                    id,
                    dz,
                    total,
                    total - base,
                    dz == 0 ? 0 : (total - base) / -dz
                ))
            }
        }
        print("ELEVK\n" + lines.joined(separator: "\n"))
    }

    nonisolated(unsafe) static var steepRests = 0 // 급경사(|경사| > 0.35)에 정지한 횟수 — 0이어야 한다

    struct HoleResult {
        let kind: String; let par: Int; let strokes: Int; let water: Int; let netRise: Double; var trace: [String] = []
    }

    /// 봇 한 홀 플레이. elevK > 0이면 표고차를 거리로 환산해 클럽을 고른다(중수)
    static func play(_ hole: Hole, elevK: Double) -> HoleResult {
        var b = BallState(x: hole.teeX, y: hole.ground(at: hole.teeX))
        var strokes = 0, water = 0
        var trace: [String] = []
        var lastMoved = 999.0 // 직전 샷 이동 거리 — 벽에 막혀 제자리면 웨지로 탈출 (사람의 반응)
        let minR = Phys.minPowerRatio
        while strokes < maxStrokes {
            let dir = hole.holeX >= b.x ? 1.0 : -1.0
            let remain = abs(hole.holeX - b.x)
            let dz = hole.ground(at: hole.holeX) - hole.ground(at: b.x)
            let lie = strokes == 0 ? Surface.tee : hole.surface(at: b.x)
            var club: Club
            var h: Double
            if lie == .green ||
                (remain < 25 && (lie == .apron || lie == .fairway || lie == .tee)) { // 텍사스 웨지 — 칩 모델 오차 회피
                club = ClubTable.all.last! // PT
                let v = sqrt(2 * Surface.green.roll * remain * 1.08) + 0.3
                h = min(1, max(0.02, (v / club.power - Phys.putterMinRatio) / (1 - Phys.putterMinRatio)))
            } else if lie == .bunker {
                club = ClubTable.all.first { $0.id == "SW" }!
                h = 1
            } else if lastMoved < 3 { // 벽에 막혔다 — 피칭으로 넘긴다 (러프 SW는 45m밖에 못 간다)
                club = ClubTable.all.first { $0.id == "PW" }!
                h = 1
            } else {
                let target = max(20, remain + elevK * dz)
                let full = ClubTable.all.filter { !$0.isPutter }
                    .map { ($0, CourseStrategy.total(of: $0.id) * (lie == .rough ? 0.8 : 1)) }
                if let pick = full.filter({ $0.1 >= target }).min(by: { $0.1 < $1.1 }) {
                    club = pick.0
                    let ratio = sqrt(target / pick.1) // 토탈 ∝ v0² 근사
                    h = min(1, max(0.02, (ratio - minR) / (1 - minR))) // 칩샷도 친다 (하한 0.3이면 20m 안쪽을 못 세운다)
                } else {
                    club = full[0].0 // DR 풀샷
                    h = 1
                }
            }
            Ballistics.launch(&b, club: club, heightPct: h, lie: lie, dir: dir)
            strokes += 1
            let fromX = b.x
            var t = 0.0
            var ended = false
            while !ended, t < 60 {
                switch Ballistics.step(&b, hole: hole) {
                case .holed:
                    return HoleResult(
                        kind: hole.signature?.rawValue ?? "plain",
                        par: hole.par,
                        strokes: strokes,
                        water: water,
                        netRise: hole.ground(at: hole.holeX) - hole.ground(at: hole.teeX),
                        trace: trace + [String(format: "%@ h%.2f %@ %.0f→HOLED", club.id, h, "\(lie)", fromX)]
                    )
                case .water:
                    water += 1
                    strokes += 1
                    let wr = hole.waterRange ?? (b.x - 3) ... (b.x + 3)
                    let dropX = dir > 0 ? wr.lowerBound - 2.5 : wr.upperBound + 2.5
                    b = BallState(x: dropX, y: hole.ground(at: dropX))
                    ended = true
                default:
                    if b.phase == .rest {
                        ended = true
                    }
                }
                t += Phys.dt
            }
            if !ended {
                b.phase = .rest; b.vx = 0; b.vy = 0
            } // 60초 비종결 가드
            lastMoved = abs(b.x - fromX)
            if b.phase == .rest, hole.surface(at: b.x) != .water, abs(hole.slope(at: b.x)) > 0.35 {
                Self.steepRests += 1
                trace.append(String(format: "STEEP-REST @%.0f slope %.2f", b.x, hole.slope(at: b.x)))
            }
            trace.append(String(
                format: "%@ h%.2f %@ %.0f→%.0f(e%.0f) %@",
                club.id, h, "\(lie)", fromX, b.x, hole.ground(at: b.x), "\(hole.surface(at: b.x))"
            ))
        }
        return HoleResult(
            kind: hole.signature?.rawValue ?? "plain",
            par: hole.par,
            strokes: strokes,
            water: water,
            netRise: hole.ground(at: hole.holeX) - hole.ground(at: hole.teeX),
            trace: trace
        )
    }

    static func summarize(_ results: [HoleResult], label: String) -> [String] {
        var lines = ["\(label): \(results.count) holes"]
        let kinds = Array(Set(results.map(\.kind))).sorted()
        for k in kinds {
            let rs = results.filter { $0.kind == k }
            let over = rs.map { Double($0.strokes - $0.par) }
            let mean = over.reduce(0, +) / Double(over.count)
            let stuck = Double(rs.filter { $0.strokes >= maxStrokes }.count) / Double(rs.count)
            let water = Double(rs.map(\.water).reduce(0, +)) / Double(rs.count)
            let rise = rs.map(\.netRise).reduce(0, +) / Double(rs.count)
            let under = Double(rs.filter { $0.strokes < $0.par }.count) / Double(rs.count)
            lines.append(String(
                format: "  %-12@ n=%3d  over par %+5.2f  stuck %4.0f%%  under-par %3.0f%%  water/hole %.2f  netRise %+6.1fm",
                k as NSString,
                rs.count,
                mean,
                stuck * 100,
                under * 100,
                water,
                rise
            ))
        }
        let all = results.map { Double($0.strokes - $0.par) }
        lines.append(String(
            format: "  ALL          n=%3d  over par %+5.2f  stuck %4.0f%%",
            results.count,
            all.reduce(0, +) / Double(all.count),
            Double(results.filter { $0.strokes >= maxStrokes }.count) / Double(results.count) * 100
        ))
        return lines
    }

    func testPrintBotBalance() {
        var naive: [HoleResult] = []
        var aware: [HoleResult] = []
        for seed: UInt32 in 1 ... 40 {
            for h in CourseGenerator.makeCourse(seed: seed) {
                naive.append(Self.play(h, elevK: 0))
                aware.append(Self.play(h, elevK: 1.0))
            }
        }
        var lines = Self.summarize(naive, label: "NAIVE (수평 거리만)") + Self.summarize(aware, label: "AWARE (표고차 k=1.0)")
        for par in [3, 4, 5] {
            let rs = naive.filter { $0.par == par }
            let mean = rs.map { Double($0.strokes - $0.par) }.reduce(0, +) / Double(max(1, rs.count))
            lines.append(String(format: "  NAIVE par%d n=%3d over par %+5.2f", par, rs.count, mean))
        }
        for r in naive.filter({ $0.strokes >= Self.maxStrokes }).prefix(3) {
            lines.append("  STUCK \(r.kind) par\(r.par): " + r.trace.joined(separator: " | "))
        }
        print("BOTBAL\n" + lines.joined(separator: "\n"))
        // ── 회귀 대역 (2026-09-17 재예산 실측: 아키타입 −0.3~−0.5, 고착 ≤1%, 급경사 정지 0) ──
        XCTAssertEqual(Self.steepRests, 0, "공이 급경사면에 정지함 (\(Self.steepRests)회)")
        for k in Set(naive.map(\.kind)) {
            let rs = naive.filter { $0.kind == k }
            let mean = rs.map { Double($0.strokes - $0.par) }.reduce(0, +) / Double(rs.count)
            let stuck = Double(rs.filter { $0.strokes >= Self.maxStrokes }.count) / Double(rs.count)
            XCTAssertGreaterThan(mean, -1.0, "\(k): 순진 봇에게 너무 쉬움 (\(mean))")
            XCTAssertLessThan(mean, 0.6, "\(k): 순진 봇에게 너무 어려움 (\(mean))")
            XCTAssertLessThanOrEqual(stuck, 0.02, "\(k): 12타 고착 (\(stuck * 100)%)")
        }
    }
}
