@testable import GolfCore
import XCTest

/// 임계 감쇠 스프링의 성질 검증 — 리그 전환 구조가 기대는 4가지 보증:
/// 수렴·무오버슈트·등속 무지연·임팩트 프레임 정밀도
final class SpringTests: XCTestCase {
    /// 정지 타깃: 5×halflife 안에 잔차 1% 미만으로 수렴한다
    func testConvergesToStaticTarget() {
        var x = 0.0, v = 0.0
        let h = 0.06
        Spring.step(x: &x, v: &v, target: 1, halflife: h, dt: 5 * h)
        XCTAssertGreaterThan(x, 0.99)
        XCTAssertLessThan(x, 1.001)
    }

    /// 정지 상태에서 출발하면 오버슈트가 없다 (임계 감쇠)
    func testNoOvershootFromRest() {
        var x = 0.0, v = 0.0
        var prev = 0.0
        for _ in 0 ..< 240 {
            Spring.step(x: &x, v: &v, target: 1, halflife: 0.05, dt: 1 / 60.0)
            XCTAssertLessThanOrEqual(x, 1.0 + 1e-9, "타깃을 넘어섰다")
            XCTAssertGreaterThanOrEqual(x, prev - 1e-9, "단조 증가가 깨졌다")
            prev = x
        }
        XCTAssertEqual(x, 1.0, accuracy: 1e-6)
    }

    /// 등속 이동 타깃 + 피드포워드: 추적 지연이 반 프레임 샘플링 편차(±v·dt/2) 이내
    /// (1차 지수 감쇠라면 lag = v/rate·상수 — rate 220 같은 모드별 상수가 필요했던 이유.
    /// 걷기 스케일 30px/s에선 편차 0.25px — 무시 가능)
    func testConstantVelocityLagWithinHalfFrame() {
        var x = 0.0, v = 0.0
        let speed = 300.0 // px/s — 걷기·전환 스케일보다 훨씬 빠른 축
        var g = 0.0
        let dt = 1 / 60.0
        for _ in 0 ..< 120 { // 2초 — 과도응답이 끝나고도 남는다
            g += speed * dt
            Spring.step(x: &x, v: &v, target: g, targetVel: speed, halflife: 0.06, dt: dt)
        }
        XCTAssertEqual(x, g, accuracy: speed * dt) // 이산화 편차 한계
        XCTAssertEqual(v, speed, accuracy: speed * 0.05)
    }

    /// 타깃이 점프해도 렌더 경로는 연속 — 한 프레임 이동량이 물리적 한계 안
    /// (크로스페이드 없이 모드 전환을 스프링에 맡길 수 있는 근거)
    func testContinuityAcrossTargetJump() {
        var x = 0.0, v = 0.0
        let dt = 1 / 60.0
        for _ in 0 ..< 30 {
            Spring.step(x: &x, v: &v, target: 10, halflife: 0.06, dt: dt)
        }
        let before = x
        // 타깃 급점프 (모드 전환 상황)
        Spring.step(x: &x, v: &v, target: -40, halflife: 0.06, dt: dt)
        // 한 프레임 이동량은 |이전 속도|·dt + 스프링 가속 기여 이내 — 순간이동 없음
        XCTAssertLessThan(abs(x - before), 5.0)
        // 이후 새 타깃으로 수렴
        for _ in 0 ..< 120 {
            Spring.step(x: &x, v: &v, target: -40, halflife: 0.06, dt: dt)
        }
        XCTAssertEqual(x, -40, accuracy: 0.01)
    }

    /// 다운스윙 u³ 프로파일(클럽 최후 폭발)은 스프링으로 추적할 수 없다는 수치 근거:
    /// 클럽 채널 halflife 0.11s는 가속 잔차(e ≈ a/y²)로 수십° 지연, 초소 halflife 3ms도
    /// 피드포워드의 이산 편차(≈2q/y 선행)로 임팩트에서 ~7° 어긋난다.
    /// → 다운스윙은 스프링이 아니라 '리그=타깃 잠금 + 속도=유한차분 이어받기'로 처리한다
    /// (임팩트 프레임 보존, 리서치 P1 — 잠금이어도 속도 상태가 이어져 팔로스루 전환은 연속)
    func testDownswingNeedsHardLock() {
        let sweep = 3.16 // rad — 톱(-175°)→임팩트(6°)
        let T = 0.17 // 다운스윙 시간
        let dt = 1 / 60.0

        func simulate(halflife: Double) -> Double {
            var x = 0.0, v = 0.0
            var prevG = 0.0
            var t = 0.0
            while t < T {
                let step = min(dt, T - t)
                t += step
                let g = sweep * pow(t / T, 3)
                Spring.step(
                    x: &x, v: &v, target: g,
                    targetVel: (g - prevG) / step, halflife: halflife, dt: step
                )
                prevG = g
            }
            return abs(x - sweep)
        }

        XCTAssertGreaterThan(simulate(halflife: 0.003), 0.05, "3ms도 임팩트 프레임을 못 지킨다 (잠금 필요 근거)")
        XCTAssertGreaterThan(simulate(halflife: 0.11), 0.5, "클럽 채널 상수로 다운스윙이 되면 예외가 불필요해진다")
    }
}
