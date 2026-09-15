@testable import GolfCore
import XCTest

final class WalkProfileTests: XCTestCase {
    /// 양 끝: 출발 0·정지 0, 도착 위치 = 거리 (걷기 도착 지점이 어드레스 원점이라 오차 0이어야 한다)
    func testEndpoints() {
        for (dist, dur) in [(120.0, 12.0), (30.0, 3.0), (5.0, 1.2), (200.0, 14.0)] {
            let p = WalkProfile(dist: dist, dur: dur)
            XCTAssertEqual(p.position(at: 0), 0, accuracy: 1e-9)
            XCTAssertEqual(p.position(at: dur), dist, accuracy: 1e-9, "dist \(dist) dur \(dur)")
            XCTAssertEqual(p.velocity(at: 0), 0, accuracy: 1e-9)
            XCTAssertEqual(p.velocity(at: dur), 0, accuracy: 1e-9)
            XCTAssertEqual(p.position(at: dur + 5), dist, accuracy: 1e-9, "밖은 클램프")
            XCTAssertEqual(p.velocity(at: -1), 0)
        }
    }

    /// 속도는 위치의 도함수 — 유한차분과 전 구간 일치 (게이트가 속도를 적분해 발을 놓으므로 필수)
    func testVelocityMatchesFiniteDifference() {
        let p = WalkProfile(dist: 150, dur: 10)
        let h = 1e-5
        var t = h
        while t < p.dur - h {
            let fd = (p.position(at: t + h) - p.position(at: t - h)) / (2 * h)
            XCTAssertEqual(p.velocity(at: t), fd, accuracy: 1e-5, "t=\(t)")
            t += 0.013
        }
    }

    /// 사다리꼴: 가속은 앞으로 몰리고(램프 절반에 등속의 75%), 중간은 정확히 등속, 정점은 평균의 1.15배 미만
    func testTrapezoidShape() {
        let p = WalkProfile(dist: 150, dur: 10)
        XCTAssertEqual(p.velocity(at: p.rampIn / 2), 0.75 * p.cruise, accuracy: 1e-9)
        XCTAssertEqual(p.velocity(at: p.rampIn), p.cruise, accuracy: 1e-9)
        XCTAssertEqual(p.velocity(at: 5), p.cruise, accuracy: 1e-9)
        XCTAssertEqual(p.velocity(at: p.dur - p.rampOut), p.cruise, accuracy: 1e-9)
        let avg = p.dist / p.dur
        XCTAssertLessThan(p.cruise, avg * 1.15, "구 포물선은 1.5배였다")
        XCTAssertGreaterThan(p.cruise, avg)
        // 감속은 가속보다 완만하게 시작(예고) — 램프 10% 지점의 속도 감소량이 가속 램프 10% 지점의 증가량보다 작다
        let accel10 = p.velocity(at: 0.1 * p.rampIn) / p.cruise
        let decel10 = 1 - p.velocity(at: p.dur - p.rampOut + 0.1 * p.rampOut) / p.cruise
        XCTAssertGreaterThan(accel10, decel10)
    }

    /// 위치는 단조 증가, 속도는 음수가 되지 않는다
    func testMonotonic() {
        let p = WalkProfile(dist: 40, dur: 2.5)
        var prev = 0.0
        var t = 0.0
        while t <= p.dur {
            let x = p.position(at: t)
            XCTAssertGreaterThanOrEqual(x, prev - 1e-12)
            XCTAssertGreaterThanOrEqual(p.velocity(at: t), -1e-12)
            prev = x
            t += 0.01
        }
    }

    /// 짧은 걷기: 램프가 dur/3로 줄어도 정합 유지
    func testShortWalkCapsRamps() {
        let p = WalkProfile(dist: 6, dur: 1.2)
        XCTAssertEqual(p.rampIn, 0.4, accuracy: 1e-12)
        XCTAssertEqual(p.rampOut, 0.4, accuracy: 1e-12)
        XCTAssertEqual(p.position(at: 1.2), 6, accuracy: 1e-9)
    }
}
