import Foundation

/// 임계 감쇠 스프링 — 모션 전환의 단일 스무딩 프리미티브 (Daniel Holden, "Spring-It-On" 정해)
///
/// 1차 지수 감쇠(lerp 추적)와의 차이:
/// - 속도 상태를 보존한다 → 타깃이 점프해도 렌더는 위치·속도 모두 연속 (관성 보존, Inertialization과 동일 원리)
/// - 타깃 속도 피드포워드 → 등속 이동 타깃을 지연 0으로 추적 (1차 감쇠의 lag = v/rate 문제 해소)
/// - 임계 감쇠 → 정지 타깃엔 오버슈트 없이 수렴, 진입 속도가 있으면 한 번만 지나쳤다 되돌아온다 (팔로스루 오버랩)
///
/// 남는 잔차는 타깃 '가속도'에 비례(e ≈ a/y²) — 다운스윙처럼 가속이 극단인 구간은
/// halflife를 수 ms로 내려 근사-경성 추적해야 한다 (SpringTests가 수치로 검증).
public enum Spring {
    /// 한 스텝 적분 (닫힌 해 — dt 크기와 무관하게 정확). dt ≤ 0이면 무변화.
    /// - halflife: 감쇠 시상수(초). 작을수록 기민하다.
    /// - targetVel: 타깃의 현재 속도 (피드포워드). 모르면 0 — 1차 감쇠처럼 지연이 생긴다.
    public static func step(
        x: inout Double,
        v: inout Double,
        target: Double,
        targetVel: Double = 0,
        halflife: Double,
        dt: Double
    ) {
        guard dt > 0 else { return }
        let y = 2 * log(2.0) / max(halflife, 1e-5) // 감쇠 d/2 (d = 4ln2/halflife)
        let c = target + 2 * targetVel / y // 이동 타깃의 정상상태 중심 (피드포워드 보정)
        let j0 = x - c
        let j1 = v + j0 * y
        let e = exp(-y * dt)
        x = e * (j0 + j1 * dt) + c
        v = e * (v - j1 * y * dt)
    }
}
