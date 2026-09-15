@testable import GolfCore
import XCTest

final class TwoBoneIKTests: XCTestCase {
    private func dist(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> Double {
        ((ax - bx) * (ax - bx) + (ay - by) * (ay - by)).squareRoot()
    }

    /// 뼈 길이 불변식: 목표가 어디든(사거리 안·밖·뿌리 위) 두 뼈 길이는 정확히 유지된다
    func testBoneLengthsAlwaysHold() {
        var rng = SeededRandom(seed: 7)
        let l1 = 17.5, l2 = 17.5
        for _ in 0 ..< 500 {
            let tx = rng.next() * 120 - 60
            let ty = rng.next() * 120 - 60
            let sol = TwoBoneIK.solve(
                rootX: 3, rootY: 68, targetX: 3 + tx, targetY: 68 + ty,
                l1: l1, l2: l2, poleX: -0.6, poleY: -0.8
            )
            XCTAssertEqual(dist(3, 68, sol.jointX, sol.jointY), l1, accuracy: 1e-9)
            XCTAssertEqual(dist(sol.jointX, sol.jointY, sol.endX, sol.endY), l2, accuracy: 1e-9)
        }
        let onRoot = TwoBoneIK.solve(rootX: 0, rootY: 0, targetX: 0, targetY: 0, l1: 10, l2: 10, poleX: 1, poleY: 0)
        XCTAssertEqual(dist(0, 0, onRoot.jointX, onRoot.jointY), 10, accuracy: 1e-9)
        XCTAssertEqual(dist(onRoot.jointX, onRoot.jointY, onRoot.endX, onRoot.endY), 10, accuracy: 1e-9)
    }

    /// 사거리 안의 목표는 정확히 도달한다 (shortfall 0) — 다리는 경성(softStart 1), 팔은 소프트닝 시작 전 구간
    func testReachableTargetIsHitExactly() {
        let leg = TwoBoneIK.solve(
            rootX: 0, rootY: 43.5, targetX: 9, targetY: 0, l1: 23.25, l2: 23.25, poleX: 1, poleY: 0, softStart: 1
        )
        XCTAssertEqual(leg.endX, 9, accuracy: 1e-9)
        XCTAssertEqual(leg.endY, 0, accuracy: 1e-9)
        XCTAssertEqual(leg.shortfall, 0, accuracy: 1e-12)
        XCTAssertLessThan(leg.extensionRatio, 1)
        let arm = TwoBoneIK.solve(
            rootX: 0.5, rootY: 68.5, targetX: 5, targetY: 48.5, l1: 17.5, l2: 17.5, poleX: -0.6, poleY: -0.8
        )
        XCTAssertEqual(arm.endX, 5, accuracy: 1e-9)
        XCTAssertEqual(arm.endY, 48.5, accuracy: 1e-9)
        XCTAssertEqual(arm.shortfall, 0, accuracy: 1e-12)
    }

    /// pole 방향이 관절의 굽힘 쪽을 결정한다: 무릎(+x)은 현의 앞, 팔꿈치(−x,−y)는 현의 뒤
    func testPoleSelectsBendSide() {
        let knee = TwoBoneIK.solve(
            rootX: 0,
            rootY: 43.5,
            targetX: 20,
            targetY: 0,
            l1: 23.25,
            l2: 23.25,
            poleX: 1,
            poleY: 0
        )
        let cross = 20 * (knee.jointY - 43.5) - (0 - 43.5) * (knee.jointX - 0)
        XCTAssertGreaterThan(cross, 0, "무릎은 힙→발 현의 앞쪽(+facing)에 있어야 한다")
        let elbow = TwoBoneIK.solve(
            rootX: 0,
            rootY: 68,
            targetX: 5,
            targetY: 48,
            l1: 17.5,
            l2: 17.5,
            poleX: -0.6,
            poleY: -0.8
        )
        XCTAssertLessThan(elbow.jointX, 2.5, "매달린 팔의 팔꿈치는 현보다 뒤(−x)에 있어야 한다")
        // 같은 목표에 pole만 뒤집으면 관절이 현의 반대편으로 간다
        let flipped = TwoBoneIK.solve(
            rootX: 0,
            rootY: 68,
            targetX: 5,
            targetY: 48,
            l1: 17.5,
            l2: 17.5,
            poleX: 0.6,
            poleY: 0.8
        )
        XCTAssertGreaterThan(flipped.jointX, elbow.jointX)
    }

    /// 사거리 밖 목표: 말단은 뿌리→목표 방향의 현 위에서 사거리 안으로 당겨지고, 당김은 거리에 단조·연속
    func testOutOfReachIsSoftenedMonotonically() {
        let l1 = 17.5, l2 = 17.5, lmax = l1 + l2
        var prevReach = 0.0
        var prevD = 0.0
        for k in 1 ... 200 { // d = 0은 방향이 정의되지 않는 퇴화 케이스 — 뼈 길이 테스트가 따로 다룬다
            let d = Double(k) * 0.4 // 0.4 ~ 80
            let sol = TwoBoneIK.solve(rootX: 0, rootY: 0, targetX: d, targetY: 0, l1: l1, l2: l2, poleX: 0, poleY: -1)
            let reach = dist(0, 0, sol.endX, sol.endY)
            XCTAssertLessThan(reach, lmax + 1e-9)
            XCTAssertGreaterThanOrEqual(reach, prevReach - 1e-9, "도달 거리가 단조 증가해야 한다")
            XCTAssertLessThanOrEqual(abs(reach - prevReach), (d - prevD) + 1e-9, "도달 거리 기울기 ≤ 1 (연속)")
            XCTAssertEqual(sol.endY, 0, accuracy: 1e-9, "말단은 현 위에 남는다")
            if d <= 0.9 * lmax {
                XCTAssertEqual(reach, d, accuracy: 1e-9, "소프트닝 시작 전엔 정확히 도달")
            }
            prevReach = reach
            prevD = d
        }
        let far = TwoBoneIK.solve(rootX: 0, rootY: 0, targetX: 80, targetY: 0, l1: l1, l2: l2, poleX: 0, poleY: -1)
        XCTAssertGreaterThan(far.shortfall, 40)
        XCTAssertGreaterThan(far.extensionRatio, 0.99)
    }

    /// 경성 클램프 모드(softStart 1): 사거리 밖은 정확히 lmax, 안은 정확히 목표
    func testHardClampMode() {
        let hard = TwoBoneIK.solve(
            rootX: 0,
            rootY: 0,
            targetX: 100,
            targetY: 0,
            l1: 20,
            l2: 15,
            poleX: 0,
            poleY: 1,
            softStart: 1
        )
        XCTAssertEqual(hard.endX, 35, accuracy: 1e-9)
        let inside = TwoBoneIK.solve(
            rootX: 0,
            rootY: 0,
            targetX: 34.9,
            targetY: 0,
            l1: 20,
            l2: 15,
            poleX: 0,
            poleY: 1,
            softStart: 1
        )
        XCTAssertEqual(inside.endX, 34.9, accuracy: 1e-9)
        // 최소 사거리(|l1−l2|) 안쪽 목표도 뼈 길이는 유지
        let tooClose = TwoBoneIK.solve(
            rootX: 0, rootY: 0, targetX: 1, targetY: 0, l1: 20, l2: 15, poleX: 0, poleY: 1, softStart: 1
        )
        XCTAssertEqual(dist(0, 0, tooClose.endX, tooClose.endY), 5, accuracy: 1e-9)
    }
}
