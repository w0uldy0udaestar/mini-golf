import Foundation
import GolfCore

/// 스틱맨 포즈 파라미터 — HTML 프로토타입의 P-System 키프레임을 그대로 이식
/// hipDx: 힙 수평 이동(체중, +=타겟 쪽) · tilt: 척추 측면 기울기(+=타겟 쪽)
/// handA: 어깨→손 방향각(0=수직 아래, +=타겟 쪽) · handD: 어깨→손 거리(팔 접힘)
/// clubA: 샤프트 절대각 · heel: 뒷발꿈치 들림(px) · headDx: 머리 오프셋
struct Pose {
    var hipDx = 0.0
    var tilt = 0.0
    var handA = 0.0
    var handD = 0.0
    var clubA = 0.0
    var heel = 0.0
    var headDx = 0.0

    static func lerp(_ a: Pose, _ b: Pose, _ u: Double) -> Pose {
        Pose(
            hipDx: a.hipDx + (b.hipDx - a.hipDx) * u,
            tilt: a.tilt + (b.tilt - a.tilt) * u,
            handA: a.handA + (b.handA - a.handA) * u,
            handD: a.handD + (b.handD - a.handD) * u,
            clubA: a.clubA + (b.clubA - a.clubA) * u,
            heel: a.heel + (b.heel - a.heel) * u,
            headDx: a.headDx + (b.headDx - a.headDx) * u
        )
    }

    /// 지수 감쇠 추적 — 포즈 스무딩 레이어 (모든 상태 전환이 자동으로 부드러워짐)
    mutating func chase(_ target: Pose, rate: Double, dt: Double) {
        let k = 1 - exp(-rate * dt)
        self = Pose.lerp(self, target, k)
    }
}

/// P-System 키프레임 (docs/research-swing-pose.md) — 2026-09-15 PGA 프로 face-on 영상 키포인트 실측으로 몸 파라미터 갱신
/// (docs/research-swing-keypoints.md: 로리 매킬로이 아이언 스윙, MediaPipe Pose, 슬로모션 1095프레임).
/// 실측 요지: 톱에서 힙은 타깃 쪽 +2·상체는 거의 중립(구 −6·−18 = "뒤로 흔들림"), 임팩트에 머리는 공 뒤(−3),
/// 팔로스루에도 척추는 타깃 반대로 기움(구 +18은 타깃 쪽 과다), 피니시 손은 머리 뒤로 감김(196°)·샤프트 수평 뒤(270°).
/// 어드레스·임팩트의 손·클럽 기하는 공 접촉이 걸려 있어 tilt 변화분(−3.8px)을 ballFwd −4로, 임팩트 힙 +5는 handA −2°로 상쇄.
enum Poses {
    static let p1 = Pose(hipDx: 0, tilt: -12, handA: 12, handD: 34, clubA: 12, heel: 0, headDx: 6) // 어드레스
    static let p2 = Pose(
        hipDx: 0,
        tilt: -12,
        handA: -55,
        handD: 34,
        clubA: -110,
        heel: 0,
        headDx: 6
    ) // 테이크어웨이 (샤프트 지면 평행 뒤)
    static let p4 = Pose(
        hipDx: 2,
        tilt: -16,
        handA: -142,
        handD: 27,
        clubA: -268,
        heel: 0,
        headDx: 5
    ) // 톱 (샤프트 지면 평행, 타깃 향함)
    static let p7 = Pose(hipDx: 11, tilt: -19, handA: 12, handD: 34, clubA: 6, heel: 2, headDx: -2) // 임팩트 (머리는 공 뒤)
    static let p8 = Pose(
        hipDx: 14,
        tilt: -20,
        handA: 87,
        handD: 31,
        clubA: 125,
        heel: 5,
        headDx: 0
    ) // 팔로스루 (척추는 여전히 뒤로)
    static let p10 = Pose(
        hipDx: 14,
        tilt: -14,
        handA: 196,
        handD: 25,
        clubA: 270,
        heel: 10,
        headDx: 2
    ) // 피니시 (손 머리 뒤, 샤프트 수평 뒤)
    // 퍼터 전용: 펜듈럼 스트로크
    static let ptA = Pose(hipDx: 0, tilt: -3, handA: 10, handD: 30, clubA: 8, heel: 0, headDx: 7)
    static let ptTop = Pose(hipDx: 0, tilt: -4, handA: -22, handD: 30, clubA: -30, heel: 0, headDx: 7)
    static let ptImp = Pose(hipDx: 1, tilt: -3, handA: 12, handD: 30, clubA: 10, heel: 0, headDx: 7)
    static let ptFin = Pose(hipDx: 2, tilt: -2, handA: 34, handD: 30, clubA: 46, heel: 0, headDx: 8) // 팔로 ≥ 백 (대칭 이상)
    // 클럽을 옆에 들고 선 직립 — 걷기↔어드레스 전환 기준
    static let upright = Pose(hipDx: 0, tilt: 2, handA: -18, handD: 30, clubA: -35, heel: 0, headDx: 5)
}

/// 클럽별 스윙 프로파일 — 우드 풀스윙 / 아이언 컴팩트 / 웨지 3/4 / 퍼터 펜듈럼
struct SwingProfile {
    let topScale: Double // 백스윙 최대 폭
    let ballFwd: Double // 스탠스에서 공 위치(px)
    let finishScale: Double // 피니시 감김 정도
    let down: Double // 다운스윙 시간(초)
    let isPutter: Bool

    static func profile(for cat: ClubCategory) -> SwingProfile {
        switch cat {
        // ballFwd −4: 어드레스 tilt −5→−12(어깨 −3.8px)의 보정 · down 0.24: 프로 실측 다운스윙 0.27s(30fps ±0.03)
        case .wood: SwingProfile(topScale: 1.0, ballFwd: 20, finishScale: 1.0, down: 0.24, isPutter: false)
        case .iron: SwingProfile(topScale: 0.88, ballFwd: 16, finishScale: 0.9, down: 0.24, isPutter: false)
        case .wedge: SwingProfile(topScale: 0.72, ballFwd: 13, finishScale: 0.72, down: 0.24, isPutter: false)
        case .putter: SwingProfile(
                topScale: 1.0,
                ballFwd: 18,
                finishScale: 1.0,
                down: 0.29,
                isPutter: true
            ) // PGA 실측 317±35ms
        }
    }
}

enum SwingTiming {
    static let follow = 0.12 // 프로 실측: 임팩트→손 타깃 쪽 최대 뻗음 0.10s
    static let finish = 0.30 // 프로 실측: 뻗음→피니시 0.27s
    static let total = 0.68 // 퍼터(0.29+0.25)·풀스윙(0.24+0.12+0.30) 모두 커버
}

func smoothstep(_ u: Double) -> Double {
    u * u * (3 - 2 * u)
}

/// 백스윙 궤적: ↑↓ 입력이 어드레스→테이크어웨이→톱 경로 위의 몸 전체 포즈를 움직인다
/// topScale: 카테고리 경계에서 움찔하지 않게 스무딩된 값을 넘길 수 있다 (기본은 프로파일 값)
func backswingPose(heightPct: Double, profile: SwingProfile, topScale: Double? = nil) -> Pose {
    if profile.isPutter {
        return Pose.lerp(Poses.ptA, Poses.ptTop, heightPct)
    }
    let s = 0.22 + 0.78 * heightPct * (topScale ?? profile.topScale)
    return s < 0.35
        ? Pose.lerp(Poses.p1, Poses.p2, s / 0.35)
        : Pose.lerp(Poses.p2, Poses.p4, (s - 0.35) / 0.65)
}

func finishPose(profile: SwingProfile) -> Pose {
    profile.isPutter ? Poses.ptFin : Pose.lerp(Poses.p8, Poses.p10, profile.finishScale)
}

/// 스윙 애니메이션 타임라인에서 포즈 샘플 (t: 스윙 시작 후 경과 초)
func swingPose(t: Double, fromPose: Pose, profile: SwingProfile, heightPct _: Double) -> Pose {
    if t < profile.down { // 다운스윙: 급가속 (퍼터는 펜듈럼 — 최하점=임팩트에서 속도 최대)
        let u = t / profile.down
        if profile.isPutter {
            return Pose.lerp(fromPose, Poses.ptImp, u * u)
        }
        // 운동 사슬(kinematic sequence): 골반→몸통→팔→클럽 순차 도달.
        // 클럽은 u³로 최후에 터진다 — 손목 래그 유지 후 late release (리서치 P2)
        let impact = Poses.p7
        let hipW = 1 - pow(1 - u, 2.2)
        let heelW = 1 - pow(1 - u, 1.8)
        let tiltW = 1 - pow(1 - u, 1.5)
        let armW = pow(u, 1.6)
        let extW = pow(u, 2.2)
        let clubW = pow(u, 3.0)
        return Pose(
            hipDx: mix(fromPose.hipDx, impact.hipDx, hipW),
            tilt: mix(fromPose.tilt, impact.tilt, tiltW),
            handA: mix(fromPose.handA, impact.handA, armW),
            handD: mix(fromPose.handD, impact.handD, extW),
            clubA: mix(fromPose.clubA, impact.clubA, clubW),
            heel: mix(fromPose.heel, impact.heel, heelW),
            headDx: mix(fromPose.headDx, impact.headDx, tiltW)
        )
    }
    let t2 = t - profile.down
    if profile.isPutter { // 퍼터: 임팩트 → 짧은 팔로만
        let v = min(1, t2 / 0.25)
        return Pose.lerp(Poses.ptImp, Poses.ptFin, 1 - (1 - v) * (1 - v))
    }
    if t2 < SwingTiming.follow {
        return Pose.lerp(Poses.p7, Poses.p8, t2 / SwingTiming.follow)
    }
    let v = min(1, (t2 - SwingTiming.follow) / SwingTiming.finish)
    return Pose.lerp(Poses.p8, finishPose(profile: profile), 1 - (1 - v) * (1 - v)) // 감속하며 피니시
}
