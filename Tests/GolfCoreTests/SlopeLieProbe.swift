@testable import GolfCore
import XCTest

/// 경사 라이 프로브 (2026-09-28 판정 "경사 위에서도 평지에서 치는 느낌"): 순진 봇의 풀샷(티·그린·퍼터 제외)이 놓인 자리의 |경사| 분포와
/// 발사각 변화(stanceSlopeRatio × atan). 구 지형(평탄 트레드+절벽) 실측: 4° 이상 24%·중앙값 1.1°. 굴곡·비탈 라이 구간 뒤 47%·3.7°.
/// 회귀 대역: 4° 이상 ≥ 30% — 경사 라이가 사라지면 여기서 잡힌다
final class SlopeLieProbe: XCTestCase {
    func testPrintSlopeLieDistribution() {
        var spots: [(slope: Double, lie: Surface)] = []
        for seed: UInt32 in 1 ... 40 {
            for h in CourseGenerator.makeCourse(seed: seed) {
                for s in CourseBalanceProbe.play(h, elevK: 0).shotSpots
                    where s.club != "PT" && s.lie != .tee && s.lie != .green {
                    spots.append((h.slope(at: s.x), s.lie))
                }
            }
        }
        let bands: [(String, Double, Double)] = [
            ("<0.02", 0, 0.02), ("0.02–0.05", 0.02, 0.05), ("0.05–0.10", 0.05, 0.10), ("0.10–0.20", 0.10, 0.20), (
                "0.20–0.30",
                0.20,
                0.30
            ),
            (">0.30", 0.30, 99),
        ]
        func hist(_ xs: [Double]) -> String {
            bands.map { name, lo, hi in
                String(
                    format: "%@ %.1f%%",
                    name,
                    Double(xs.filter { $0 >= lo && $0 < hi }.count) / Double(max(1, xs.count)) * 100
                )
            }.joined(separator: " | ")
        }
        let deg = spots.map { abs(atan($0.slope * Phys.stanceSlopeRatio)) * 180 / .pi }.sorted()
        let share4 = Double(deg.filter { $0 >= 4 }.count) / Double(max(1, deg.count))
        var lines = [String(format: "full shots %d — |slope| ", spots.count) + hist(spots.map { abs($0.slope) })]
        lines.append(String(
            format: "launch Δ deg: median %.1f  p90 %.1f  max %.1f  share ≥4° %.0f%%  ≥8° %.0f%%",
            deg.isEmpty ? 0 : deg[deg.count / 2], deg.isEmpty ? 0 : deg[deg.count * 9 / 10], deg.last ?? 0,
            share4 * 100,
            Double(deg.filter { $0 >= 8 }.count) / Double(max(1, deg.count)) * 100
        ))
        for lie in [Surface.fairway, .rough, .bunker] {
            lines.append("  \(lie): " + hist(spots.filter { $0.lie == lie }.map { abs($0.slope) }))
        }
        print("SLOPEPROBE\n" + lines.joined(separator: "\n"))
        XCTAssertGreaterThan(share4, 0.30, "경사 라이가 드물어짐 (4° 이상 \(share4))")
    }
}
