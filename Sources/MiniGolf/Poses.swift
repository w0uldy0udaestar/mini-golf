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

/// 스윙 스타일 — 프로 선수 face-on 영상 키포인트 실측 키프레임 (2026-09-15 사용자 제안: 선수별 스윙 선택).
/// 물리는 동일하고 연출(키프레임·템포)만 다르다. 스타일 간 차이는 판독되도록 실측 편차의 1.3배로 과장.
enum SwingStyle: String, CaseIterable {
    case rory, tiger, bryson

    var title: String {
        switch self {
        case .rory: "로리 매킬로이"
        case .tiger: "타이거 우즈"
        case .bryson: "브라이슨 디섐보"
        }
    }

    static let prefKey = "swingStyle"
    static var saved: SwingStyle {
        SwingStyle(rawValue: UserDefaults.standard.string(forKey: prefKey) ?? "") ?? .rory
    }
}

/// 스타일 × 클럽군의 풀스윙 키프레임 6개 + 템포 (퍼터는 공용 펜듈럼)
struct SwingKeyframes {
    let p1, p2, p4, p7, p8, p10: Pose
    let down, follow, finish: Double // 다운스윙·임팩트→최대 뻗음·→피니시 (초)
    let topHold: Double // 톱에서 멈칫 (초) — 타이거의 전환 간격, 브라이슨은 0

    /// ── 실측 6세트 (docs/research-swing-styles.md): face-on 영상 MediaPipe 키포인트 → 스틱맨 단위, 세 선수 평균 대비
    /// 편차 2.5배 과장(1.3배는 플레이에서 구분 불가 판정, 2026-09-15 — 템포·톱 홀드도 같은 배율). 어드레스·임팩트 손·클럽은 공 접촉 기하로 고정(tilt·hipDx 변화는 handA로
    /// 상쇄).
    /// 샤프트 각(톱·피니시)은 영상 검출이 불안정해 선수 특징 기반 수치: 로리 톱 평행 초과·타이거 평행·브라이슨 3/4,
    /// 피니시는 로리·타이거 감김(270) vs 브라이슨 홀드오프(300). 템포 일부 추정(브라이슨 빠름). 웨지는 아이언 세트 공용.
    static let roryDriver = SwingKeyframes(
        p1: Pose(hipDx: 0.0, tilt: -8.4, handA: 8.9, handD: 34, clubA: 12, heel: 0.0, headDx: 6.3),
        p2: Pose(hipDx: 0.2, tilt: -9.0, handA: -71.5, handD: 34, clubA: -110, heel: 0.0, headDx: 9.4),
        p4: Pose(hipDx: 1.6, tilt: -15.4, handA: -174.8, handD: 21.1, clubA: -275, heel: 0.0, headDx: 2.7),
        p7: Pose(hipDx: 12.7, tilt: -26.3, handA: 15.4, handD: 34, clubA: 6, heel: 2.4, headDx: 2.2),
        p8: Pose(hipDx: 15.4, tilt: -26.3, handA: 81.4, handD: 28.5, clubA: 125, heel: 3.7, headDx: 0.3),
        p10: Pose(hipDx: 18.5, tilt: -27.1, handA: 140, handD: 25.7, clubA: 270, heel: 11.3, headDx: 0.3),
        down: 0.26, follow: 0.13, finish: 0.31, topHold: 0.0
    )

    static let tigerDriver = SwingKeyframes(
        p1: Pose(hipDx: 0.0, tilt: -17.9, handA: 17.1, handD: 34, clubA: 12, heel: 0.0, headDx: 4.9),
        p2: Pose(hipDx: -0.1, tilt: -22.7, handA: -26.8, handD: 30, clubA: -110, heel: 0.0, headDx: -0.2),
        p4: Pose(hipDx: 2.7, tilt: -30.2, handA: -118.9, handD: 20.6, clubA: -268, heel: 0.0, headDx: 7.0),
        p7: Pose(hipDx: 6.6, tilt: -31.8, handA: 31.7, handD: 34, clubA: 6, heel: 1.0, headDx: -1.8),
        p8: Pose(hipDx: 6.8, tilt: -30.9, handA: 70, handD: 31.8, clubA: 125, heel: 0.0, headDx: 1.6),
        p10: Pose(hipDx: 4.0, tilt: -18.5, handA: 148.6, handD: 19, clubA: 270, heel: 0.0, headDx: 1.5),
        down: 0.26, follow: 0.13, finish: 0.36, topHold: 0.08
    )

    static let brysonDriver = SwingKeyframes(
        p1: Pose(hipDx: 0.0, tilt: -15.9, handA: 15.4, handD: 34, clubA: 12, heel: 0.0, headDx: -0.7),
        p2: Pose(hipDx: 0.5, tilt: -14.8, handA: -65.8, handD: 34, clubA: -110, heel: 0.0, headDx: -1.5),
        p4: Pose(hipDx: -0.2, tilt: -9.1, handA: -119.4, handD: 17, clubA: -235, heel: 0.0, headDx: -5.8),
        p7: Pose(hipDx: 0.4, tilt: -16.8, handA: 29.1, handD: 34, clubA: 6, heel: 1.0, headDx: 0.6),
        p8: Pose(hipDx: 1.3, tilt: -21.2, handA: 86.0, handD: 34, clubA: 125, heel: 0.0, headDx: 2.3),
        p10: Pose(hipDx: 2.9, tilt: -19.6, handA: 153.3, handD: 28, clubA: 300, heel: 5.6, headDx: 13.5),
        down: 0.18, follow: 0.08, finish: 0.21, topHold: 0.0
    )

    static let roryIron = SwingKeyframes(
        p1: Pose(hipDx: 0.0, tilt: -12.7, handA: 12.6, handD: 34, clubA: 12, heel: 0.0, headDx: 6.1),
        p2: Pose(hipDx: 1.0, tilt: -12.4, handA: -57.3, handD: 33.6, clubA: -110, heel: 0.0, headDx: 7.0),
        p4: Pose(hipDx: 1.3, tilt: -18.8, handA: -153.4, handD: 25.0, clubA: -268, heel: 0.0, headDx: 10.3),
        p7: Pose(hipDx: 14.6, tilt: -16.6, handA: 3.7, handD: 34, clubA: 6, heel: 1.0, headDx: -0.7),
        p8: Pose(hipDx: 19.2, tilt: -22.3, handA: 85.6, handD: 28.8, clubA: 125, heel: 5.7, headDx: 1.7),
        p10: Pose(hipDx: 20.5, tilt: -15.2, handA: 140, handD: 28, clubA: 270, heel: 8.8, headDx: 1.0),
        down: 0.26, follow: 0.13, finish: 0.31, topHold: 0.0
    )

    static let tigerIron = SwingKeyframes(
        p1: Pose(hipDx: 0.0, tilt: -16.7, handA: 16.0, handD: 34, clubA: 12, heel: 0.0, headDx: 2.5),
        p2: Pose(hipDx: -0.7, tilt: -21.6, handA: -50.6, handD: 32.9, clubA: -110, heel: 0.0, headDx: 1.5),
        p4: Pose(hipDx: -0.3, tilt: -20.0, handA: -146.3, handD: 24.0, clubA: -262, heel: 0.0, headDx: -5.2),
        p7: Pose(hipDx: 7.5, tilt: -31.5, handA: 29.7, handD: 34, clubA: 6, heel: 1.0, headDx: 0.8),
        p8: Pose(hipDx: 11.3, tilt: -30.4, handA: 95, handD: 30.2, clubA: 125, heel: 1.3, headDx: 6.2),
        p10: Pose(hipDx: 9.7, tilt: -17.7, handA: 200, handD: 21.5, clubA: 270, heel: 11.3, headDx: 11.9),
        down: 0.26, follow: 0.13, finish: 0.36, topHold: 0.08
    )

    static let brysonIron = SwingKeyframes(
        p1: Pose(hipDx: 0.0, tilt: -7.8, handA: 8.4, handD: 34, clubA: 12, heel: 0.0, headDx: 3.5),
        p2: Pose(hipDx: 0.2, tilt: -4.9, handA: -93.5, handD: 34, clubA: -110, heel: 0.9, headDx: 2.3),
        p4: Pose(hipDx: 5.2, tilt: -2.4, handA: -102.0, handD: 27.3, clubA: -230, heel: 0.0, headDx: -0.3),
        p7: Pose(hipDx: 5.5, tilt: -15.5, handA: 18.6, handD: 34, clubA: 6, heel: 1.4, headDx: 4.2),
        p8: Pose(hipDx: 0.7, tilt: -5.9, handA: 83.1, handD: 30.1, clubA: 125, heel: 1.2, headDx: 8.2),
        p10: Pose(hipDx: -2.0, tilt: -8.7, handA: 200, handD: 20.2, clubA: 300, heel: 0.9, headDx: 13.3),
        down: 0.18, follow: 0.08, finish: 0.21, topHold: 0.0
    )

    static func table(_ style: SwingStyle, _ cat: ClubCategory) -> SwingKeyframes {
        switch (style, cat) {
        case (.rory, .wood): roryDriver
        case (.rory, _): roryIron
        case (.tiger, .wood): tigerDriver
        case (.tiger, _): tigerIron
        case (.bryson, .wood): brysonDriver
        case (.bryson, _): brysonIron
        }
    }

    /// 스윙 애니메이션 총 길이 상한 — 모든 스타일·퍼터(0.29+0.25)를 덮는다
    static var maxTotal: Double {
        var m = 0.54
        for st in SwingStyle.allCases {
            for cat in [ClubCategory.wood, .iron, .wedge] {
                let k = table(st, cat)
                m = max(m, k.topHold + k.down + k.follow + k.finish)
            }
        }
        return m
    }
}

/// 클럽별 스윙 프로파일 — 우드 풀스윙 / 아이언 컴팩트 / 웨지 3/4 / 퍼터 펜듈럼
struct SwingProfile {
    let topScale: Double // 백스윙 최대 폭
    let ballFwd: Double // 스탠스에서 공 위치(px)
    let finishScale: Double // 피니시 감김 정도
    let down: Double // 다운스윙 시간(초) — 풀스윙은 keys.down
    let isPutter: Bool
    let keys: SwingKeyframes // 스타일 × 클럽군 키프레임·템포

    static func profile(for cat: ClubCategory, style: SwingStyle = .rory) -> SwingProfile {
        let k = SwingKeyframes.table(style, cat)
        return switch cat {
        // ballFwd −4: 어드레스 tilt −5→−12(어깨 −3.8px)의 보정 (2026-09-15 프로 실측 반영)
        // down = 톱 홀드 + 다운스윙 (Space → 임팩트 총 시간; 발사·rigRate·벽 스탠스 해제가 이 값을 본다)
        case .wood: SwingProfile(
                topScale: 1.0,
                ballFwd: 20,
                finishScale: 1.0,
                down: k.topHold + k.down,
                isPutter: false,
                keys: k
            )
        case .iron: SwingProfile(
                topScale: 0.88,
                ballFwd: 16,
                finishScale: 0.9,
                down: k.topHold + k.down,
                isPutter: false,
                keys: k
            )
        case .wedge: SwingProfile(
                topScale: 0.72,
                ballFwd: 13,
                finishScale: 0.72,
                down: k.topHold + k.down,
                isPutter: false,
                keys: k
            )
        case .putter: SwingProfile(
                topScale: 1.0, ballFwd: 18, finishScale: 1.0, down: 0.29, isPutter: true, keys: k
            ) // PGA 실측 317±35ms
        }
    }
}

enum SwingTiming {
    static let total = SwingKeyframes.maxTotal // 퍼터·모든 스타일의 풀스윙을 덮는 상한
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
    let k = profile.keys
    let s = 0.22 + 0.78 * heightPct * (topScale ?? profile.topScale)
    return s < 0.35
        ? Pose.lerp(k.p1, k.p2, s / 0.35)
        : Pose.lerp(k.p2, k.p4, (s - 0.35) / 0.65)
}

func finishPose(profile: SwingProfile) -> Pose {
    profile.isPutter ? Poses.ptFin : Pose.lerp(profile.keys.p8, profile.keys.p10, profile.finishScale)
}

/// 스윙 애니메이션 타임라인에서 포즈 샘플 (t: 스윙 시작 후 경과 초)
func swingPose(t: Double, fromPose: Pose, profile: SwingProfile, heightPct _: Double) -> Pose {
    if t < profile.down { // 다운스윙: 급가속 (퍼터는 펜듈럼 — 최하점=임팩트에서 속도 최대)
        if profile.isPutter {
            let v = t / profile.down
            return Pose.lerp(fromPose, Poses.ptImp, v * v)
        }
        if t < profile.keys.topHold { // 톱 홀드: 전환 전 멈칫 (스타일 템포)
            return fromPose
        }
        let u = (t - profile.keys.topHold) / profile.keys.down
        // 운동 사슬(kinematic sequence): 골반→몸통→팔→클럽 순차 도달.
        // 클럽은 u³로 최후에 터진다 — 손목 래그 유지 후 late release (리서치 P2)
        let impact = profile.keys.p7
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
    let k = profile.keys
    if t2 < k.follow {
        return Pose.lerp(k.p7, k.p8, t2 / k.follow)
    }
    let v = min(1, (t2 - k.follow) / k.finish)
    return Pose.lerp(k.p8, finishPose(profile: profile), 1 - (1 - v) * (1 - v)) // 감속하며 피니시
}
