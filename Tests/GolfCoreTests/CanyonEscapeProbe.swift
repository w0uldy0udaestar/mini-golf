@testable import GolfCore
import XCTest

/// 협곡 탈출 프로브 (2026-09-28 리뷰 #1): 근측 라이저 중턱에 놓인 공이 정착한 자리(발치)에서 홀 방향 풀 PW가 반대편 림을 넘는가.
/// 반영 강도 1.0·꼬리 정착(≤ 0.3)에서는 74홀 중 64홀 실패(내리막 라이 −16.7°) → 바닥 정착(≤ 0.12)·그립 라이저 제외·램프 깊이 예산 뒤 1~2홀.
/// 회귀 대역: 실패 ≤ 4홀
final class CanyonEscapeProbe: XCTestCase {
    func testNearFootFullPitchingWedgeClearsFarRim() throws {
        let pw = try XCTUnwrap(ClubTable.all.first { $0.id == "PW" })
        var fails = 0, total = 0, lines: [String] = []
        for seed: UInt32 in 1 ... 40 {
            for h in CourseGenerator.makeCourse(seed: seed) where h.signature == .canyon {
                let dir = h.holeX >= h.teeX ? 1.0 : -1.0
                func riser(from x0: Double) -> (start: Double, end: Double)? { // 홀 방향으로 첫 |경사| > 0.5 구간
                    var x = x0
                    var rs: Double? = nil
                    while dir > 0 ? x < h.holeX : x > h.holeX {
                        let steep = abs(h.slope(at: x)) > 0.5
                        if steep, rs == nil {
                            rs = x
                        }
                        if !steep, let s0 = rs, abs(x - s0) > 3 {
                            return (s0, x)
                        }
                        x += dir
                    }
                    return nil
                }
                guard let near = riser(from: h.teeX + dir * 10),
                      let far = riser(from: near.end + dir * 2) else { continue }
                let mid = (near.start + near.end) / 2
                var b = BallState(x: mid, y: h.ground(at: mid), vx: 0, vy: 0, phase: .roll)
                var t = 0.0
                while b.phase != .rest, t < 30 {
                    _ = Ballistics.step(&b, hole: h)
                    t += Phys.dt
                }
                let lie = h.surface(at: b.x)
                if lie == .water {
                    continue
                }
                let ls = h.slope(at: b.x)
                Ballistics.launch(&b, club: pw, heightPct: 1, lie: lie, dir: dir, slope: ls * Phys.stanceSlopeRatio)
                t = 0
                while b.phase != .rest, t < 60 {
                    if Ballistics.step(&b, hole: h) == .water {
                        break
                    }
                    t += Phys.dt
                }
                total += 1
                let cleared = dir > 0 ? b.x >= far.end - 1 : b.x <= far.end + 1
                if !cleared {
                    fails += 1
                    lines.append(String(
                        format: "  seed %d lie %@ slope %+.2f rest %.0f farRim %.0f",
                        seed,
                        "\(lie)",
                        ls,
                        b.x,
                        far.end
                    ))
                }
            }
        }
        print("CANYONESC near-foot full-PW escape fails \(fails)/\(total)\n" + lines.prefix(5).joined(separator: "\n"))
        XCTAssertLessThanOrEqual(fails, 4, "협곡 근측 발치에서 PW 한 방 탈출이 자주 실패함 (\(fails)/\(total))")
    }
}
