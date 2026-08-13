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

/// P-System 키프레임 (docs/research-swing-pose.md)
enum Poses {
    static let p1 = Pose(hipDx: 0, tilt: -5, handA: 12, handD: 34, clubA: 12, heel: 0, headDx: 7) // 어드레스
    static let p2 = Pose(hipDx: -2, tilt: -9, handA: -40, handD: 34, clubA: -85, heel: 0, headDx: 7) // 테이크어웨이
    static let p4 = Pose(hipDx: -6, tilt: -18, handA: -145, handD: 28, clubA: -175, heel: 0, headDx: 6) // 톱
    static let p7 = Pose(hipDx: 6, tilt: -12, handA: 14, handD: 34, clubA: 6, heel: 5, headDx: 7) // 임팩트
    static let p8 = Pose(hipDx: 9, tilt: 18, handA: 85, handD: 34, clubA: 100, heel: 9, headDx: 9) // 팔로스루
    static let p10 = Pose(hipDx: 16, tilt: 6, handA: 148, handD: 22, clubA: 300, heel: 14, headDx: 4) // 피니시
    // 퍼터 전용: 펜듈럼 스트로크
    static let ptA = Pose(hipDx: 0, tilt: -3, handA: 10, handD: 30, clubA: 8, heel: 0, headDx: 7)
    static let ptTop = Pose(hipDx: 0, tilt: -4, handA: -22, handD: 30, clubA: -30, heel: 0, headDx: 7)
    static let ptImp = Pose(hipDx: 1, tilt: -3, handA: 12, handD: 30, clubA: 10, heel: 0, headDx: 7)
    static let ptFin = Pose(hipDx: 2, tilt: -2, handA: 30, handD: 30, clubA: 38, heel: 0, headDx: 8)
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
        case .wood: SwingProfile(topScale: 1.0, ballFwd: 24, finishScale: 1.0, down: 0.13, isPutter: false)
        case .iron: SwingProfile(topScale: 0.88, ballFwd: 20, finishScale: 0.9, down: 0.13, isPutter: false)
        case .wedge: SwingProfile(topScale: 0.72, ballFwd: 17, finishScale: 0.72, down: 0.13, isPutter: false)
        case .putter: SwingProfile(topScale: 1.0, ballFwd: 18, finishScale: 1.0, down: 0.2, isPutter: true)
        }
    }
}

enum SwingTiming {
    static let follow = 0.14
    static let finish = 0.22
    static let total = 0.5
}

func smoothstep(_ u: Double) -> Double {
    u * u * (3 - 2 * u)
}

/// 백스윙 궤적: ↑↓ 입력이 어드레스→테이크어웨이→톱 경로 위의 몸 전체 포즈를 움직인다
func backswingPose(heightPct: Double, profile: SwingProfile) -> Pose {
    if profile.isPutter {
        return Pose.lerp(Poses.ptA, Poses.ptTop, heightPct)
    }
    let s = 0.22 + 0.78 * heightPct * profile.topScale
    return s < 0.35
        ? Pose.lerp(Poses.p1, Poses.p2, s / 0.35)
        : Pose.lerp(Poses.p2, Poses.p4, (s - 0.35) / 0.65)
}

func finishPose(profile: SwingProfile) -> Pose {
    profile.isPutter ? Poses.ptFin : Pose.lerp(Poses.p8, Poses.p10, profile.finishScale)
}

/// 스윙 애니메이션 타임라인에서 포즈 샘플 (t: 스윙 시작 후 경과 초)
func swingPose(t: Double, fromPose: Pose, profile: SwingProfile, heightPct _: Double) -> Pose {
    if t < profile.down { // 다운스윙: 급가속
        let u = t / profile.down
        let impact = profile.isPutter ? Poses.ptImp : Poses.p7
        return Pose.lerp(fromPose, impact, profile.isPutter ? smoothstep(u) : u * u)
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
