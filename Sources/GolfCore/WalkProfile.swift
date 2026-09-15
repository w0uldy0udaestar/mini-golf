import Foundation

/// 걷기 속도 프로파일 — 램프(가속) · 등속 · 램프(감속)의 사다리꼴.
///
/// 구 방식은 전 구간 하나의 smoothstep 위치 곡선이라 속도가 포물선(평균의 1.5배 정점, 시작 21%는
/// 평균 이하)이었고, 거리가 멀수록 "느릿하다가 가속"이 길어졌다 (사용자 피드백 2번, 2026-09-14).
/// 사람의 보행은 개시 1~2걸음에 정상 속도에 들고, 종료는 1스트라이드(자연 속도 2~3걸음)이며
/// 개시 속도는 첫 걸음에 몰린다(Brenière & Do 1986; Crenna et al. 2001 — docs/research-stickman-rig.md).
/// - 가속 램프: 앞으로 몰린 2차 이즈아웃 `v = vc·(1 − (1 − t/tIn)²)` (초기 기울기 최대)
/// - 감속 램프: smoothstep 역상 `v = vc·(1 − s²(3 − 2s))` (예고처럼 천천히 시작해 부드럽게 정지)
/// 램프 시간은 거리와 무관한 상수(짧은 걷기는 dur/3 상한). 위치는 램프 적분의 닫힌식이고
/// 속도는 그 도함수 — 둘은 반드시 한 쌍이다 (게이트 위상이 속도를 적분하므로 어긋나면 발이 밀린다).
public struct WalkProfile: Equatable {
    public let dist: Double
    public let dur: Double
    public let rampIn: Double
    public let rampOut: Double
    /// 등속 구간 속도
    public let cruise: Double

    public init(dist: Double, dur: Double, rampIn: Double = 0.9, rampOut: Double = 1.1) {
        self.dist = dist
        self.dur = max(dur, 1e-6)
        let cap = self.dur / 3
        self.rampIn = max(1e-6, min(rampIn, cap))
        self.rampOut = max(1e-6, min(rampOut, cap))
        // 램프 거리: 가속 (2/3)·vc·tIn, 감속 (1/2)·vc·tOut
        let effective = self.dur - self.rampIn / 3 - self.rampOut / 2
        cruise = dist / max(effective, 1e-6)
    }

    /// 0 ≤ t ≤ dur → 0 ≤ x ≤ dist (밖은 클램프)
    public func position(at t: Double) -> Double {
        let t = min(max(t, 0), dur)
        if t < rampIn {
            let r = 1 - t / rampIn
            return cruise * (t - rampIn / 3 * (1 - r * r * r))
        }
        let xIn = cruise * (rampIn - rampIn / 3)
        let tOutStart = dur - rampOut
        if t < tOutStart {
            return xIn + cruise * (t - rampIn)
        }
        let xCruise = xIn + cruise * (tOutStart - rampIn)
        let s = (t - tOutStart) / rampOut
        return xCruise + cruise * rampOut * (s - s * s * s + s * s * s * s / 2)
    }

    /// position의 해석 도함수 (밖은 0)
    public func velocity(at t: Double) -> Double {
        guard t >= 0, t <= dur else { return 0 }
        if t < rampIn {
            let r = 1 - t / rampIn
            return cruise * (1 - r * r)
        }
        let tOutStart = dur - rampOut
        if t < tOutStart {
            return cruise
        }
        let s = (t - tOutStart) / rampOut
        return cruise * (1 - s * s * (3 - 2 * s))
    }
}
