@testable import GolfCore
@testable import MiniGolf
import XCTest

/// 세로 과장(GameScene.verticalScale)의 불변식 — 긴 홀은 키우고, 짧은 파3는 그대로, 어떤 화면에서도 과장 때문에 공이 위로 넘치지 않는다 (리뷰 F1)
final class VerticalScaleTests: XCTestCase {
    func testPoints() {
        let h: CGFloat = 1080
        XCTAssertEqual(
            GameScene.verticalScale(pxPerM: 9.6, screenH: h, elevSpan: 20),
            1.0,
            accuracy: 0.001,
            "짧은 파3(세로 px/m 9.6)는 그대로"
        )
        XCTAssertEqual(
            GameScene.verticalScale(pxPerM: 3.2, screenH: h, elevSpan: 30),
            GameScene.vScaleMax,
            accuracy: 0.001,
            "파5는 최대"
        )
        XCTAssertEqual(GameScene.verticalScale(pxPerM: 6.0, screenH: h, elevSpan: 20), 1.4, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(
            GameScene.verticalScale(pxPerM: 6.0, screenH: 600, elevSpan: 40),
            1.0,
            "예산이 모자라도 1 아래로는 안 간다"
        )
        XCTAssertLessThan(GameScene.verticalScale(pxPerM: 6.0, screenH: 700, elevSpan: 40), 1.4, "낮은 화면은 예산이 깎는다")
    }

    /// 60시드 × 화면 5종: 과장을 적용한 필요 높이(바닥 + (최고 표고 + 로브 정점 66m)·세로px/m + 11)가 화면을 넘지 않거나,
    /// 넘는다면 과장 없이도 넘던 홀(2560+ 폭의 기존 문제)이어야 한다 — 과장이 새 넘침을 만들지 않는다
    func testNoNewOverflowAcrossScreens() {
        var worse = 0, checked = 0
        for seed: UInt32 in 1 ... 60 {
            for h in CourseGenerator.makeCourse(seed: seed) {
                let lo = h.elevation.min() ?? 0, hi = h.elevation.max() ?? 0
                for (w, sh) in [(1280.0, 800.0), (1440.0, 900.0), (1512.0, 982.0), (1920.0, 1080.0), (2560.0, 1440.0)] {
                    let pxPerM = CGFloat(w / h.worldW)
                    let v = GameScene.verticalScale(pxPerM: pxPerM, screenH: CGFloat(sh), elevSpan: hi - lo)
                    func need(_ scale: CGFloat) -> CGFloat {
                        let base = max(96, 84 - CGFloat(lo) * pxPerM * scale)
                        return base + CGFloat(hi + 66) * pxPerM * scale + 11
                    }
                    checked += 1
                    if need(v) > CGFloat(sh), need(1) <= CGFloat(sh) {
                        worse += 1
                    }
                }
            }
        }
        XCTAssertEqual(worse, 0, "과장이 새 화면 넘침을 만든 홀 \(worse)/\(checked)")
    }
}
