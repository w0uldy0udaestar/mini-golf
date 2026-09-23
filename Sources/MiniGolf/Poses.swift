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
    /// 클럽을 옆에 들고 선 직립 — 걷기↔어드레스 전환 기준
    static let upright = Pose(hipDx: 0, tilt: 2, handA: -18, handD: 30, clubA: -35, heel: 0, headDx: 5)
}

/// 스윙 스타일 — 프로 선수 face-on 영상 키포인트 실측 키프레임 (2026-09-15 사용자 제안: 선수별 스윙 선택).
/// 물리는 동일하고 연출(키프레임·템포)만 다르다. 스타일 간 차이는 판독되도록 실측 편차의 2.5배로 과장(1.3배는 구분 불가 판정).
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

    // ── 트레이드마크 연출 (2026-09-15, docs/research-swing-styles.md §트레이드마크) ──
    // 정면 2D 키포인트로는 안 잡히는 특징이 진짜 구분점이라 키프레임 밖 연출로 넣는다. 물리는 전부 동일.

    /// 타이거: 굿샷 뒤 클럽 트월 (리코일된 팔로스루에서 오른손 엄지로 한 바퀴)
    var clubTwirl: Bool {
        self == .tiger
    }

    /// 타이거: 버디 이상 홀아웃에 어퍼컷 주먹 (이글·홀인원은 두 번)
    var uppercut: Bool {
        self == .tiger
    }

    /// 브라이슨: 팔을 곧게 편 채 스윙·어드레스 (호 대신 직선 — 원근 단축도 곧은 막대로)
    var straightArms: Bool {
        self == .bryson
    }

    // 브라이슨 암록 퍼팅은 PutterKeyframes.brysonPutt(길이 43·butt 10·샤프트=전완)로 표현 — 별도 플래그 없음

    /// 로리: 임팩트 점프 — 지면 반력으로 몸이 뜬다 (양발 이륙, 최대 px). 실측 ~5px는 리그 덤프에서 2~3px로 안 읽혀 8로 과장,
    /// 8도 "차이가 많이 나 보이지 않음"(2026-09-23 플레이 판정) → 12
    var impactJump: Double {
        self == .rory ? 12.0 : 0
    }

    /// 로리: 피니시 리코일 — 리드 다리 위로 탄력 있게 올라앉으며 잦아드는 반동
    var finishRecoil: Bool {
        self == .rory
    }
}

/// 퍼터 키프레임 — 선수별 face-on 실측 (2026-09-15 2단계, docs/research-swing-styles.md §2단계). 물리는 같고 자세·스트로크 모양·
/// 렌더 길이·그립 위치·스탠스(ballFwd)만 다르다. 실측 요지: 세 선수 모두 척추는 거의 수직(tilt −10~−14 = 어깨가 힙 위)이고 손은
/// 어깨 바로 아래 — 구 공용 세트(공이 힙 23px 앞, 손 10° 앞, 척추 앞기울기)는 드라이버 스탠스에 가까웠다. 공은 스탠스 중앙 약간
/// 앞(ballFwd 6, 암록은 전진 프레스를 위해 16). 백스트로크 폭(−32°)은 사용자 입력이 정하므로 공용, 팔로스루 길이만 선수별
/// (로리 길게 35° · 타이거 짧게 19° · 브라이슨 38°, 평균 대비 1.5배 과장).
struct PutterKeyframes {
    let a, top, imp, fin: Pose
    let len: Double // 렌더 길이(px) — 표준 34(실 34") · 암록 43(실 43")
    let butt: Double // 그립 위로 샤프트가 전완을 따라 더 올라가는 길이(px) — 암록의 17" 그립
    let ballFwd: Double // 스탠스에서 공 위치(px) — 실측 자세에서 헤드가 공 뒤 5px에 오도록 손 각을 수치 해로 맞췄다 (gen_table2.py)

    static let roryPutt = PutterKeyframes(
        a: Pose(hipDx: 0.0, tilt: -10.1, handA: 5.9, handD: 30, clubA: 3.9, heel: 0, headDx: 3.7),
        top: Pose(hipDx: 0.1, tilt: -10.7, handA: -25.8, handD: 30, clubA: -33.8, heel: 0, headDx: 3.0),
        imp: Pose(hipDx: 0.3, tilt: -11.7, handA: 8.6, handD: 30, clubA: 6.6, heel: 0, headDx: 2.7),
        fin: Pose(hipDx: 3, tilt: -7.6, handA: 34.7, handD: 30, clubA: 46.7, heel: 0, headDx: 4.7),
        len: 34, butt: 0, ballFwd: 6
    )

    static let tigerPutt = PutterKeyframes(
        a: Pose(hipDx: 0.0, tilt: -10.8, handA: 6.2, handD: 30, clubA: 4.2, heel: 0, headDx: 6.3),
        top: Pose(hipDx: 2.4, tilt: -14, handA: -24.3, handD: 30, clubA: -32.3, heel: 0, headDx: 5.9),
        imp: Pose(hipDx: 0.4, tilt: -11.6, handA: 8.6, handD: 30, clubA: 6.6, heel: 0, headDx: 5.3),
        fin: Pose(hipDx: -0.6, tilt: -9.4, handA: 19.4, handD: 30, clubA: 31.4, heel: 0, headDx: 5.7),
        len: 34, butt: 0, ballFwd: 6
    )

    /// 암록: 샤프트가 리드 전완과 한 직선(clubA == handA)이고 손목이 꺾이지 않아 어깨 회전만으로 흔든다. handD 34는 RigBuilder의
    /// 긴 클럽 보정(−12) 후 22 — 곧은 팔의 원근 단축. 전진 프레스 15°를 지키려면 공이 앞쪽(ballFwd 16)이어야 한다
    static let brysonPutt = PutterKeyframes(
        a: Pose(hipDx: 0.0, tilt: -14, handA: 15.2, handD: 34, clubA: 15.2, heel: 0, headDx: 0.0),
        top: Pose(hipDx: -1.1, tilt: -14, handA: -16.8, handD: 34, clubA: -16.8, heel: 0, headDx: 0.0),
        imp: Pose(hipDx: 0.2, tilt: -14, handA: 17.2, handD: 34, clubA: 17.2, heel: 0, headDx: 0.0),
        fin: Pose(hipDx: -2.6, tilt: -14, handA: 37.9, handD: 34, clubA: 37.9, heel: 0, headDx: 0.0),
        len: 43, butt: 14, ballFwd: 16 // butt 10 → 14: 그립 위 연장부가 전완에 붙은 게 읽히도록 (2026-09-23 플레이 판정)
    )

    static func table(_ style: SwingStyle) -> PutterKeyframes {
        switch style {
        case .rory: roryPutt
        case .tiger: tigerPutt
        case .bryson: brysonPutt
        }
    }
}

/// 스타일 × 클럽군의 풀스윙 키프레임 6개 + 템포 (드라이버·아이언·웨지; 퍼터는 PutterKeyframes)
struct SwingKeyframes {
    let p1, p2, p4, p7, p8, p10: Pose
    let down, follow, finish: Double // 다운스윙·임팩트→최대 뻗음·→피니시 (초)
    let topHold: Double // 톱에서 멈칫 (초) — 타이거의 전환 간격, 브라이슨은 0

    /// ── 실측 6세트 (docs/research-swing-styles.md): face-on 영상 MediaPipe 키포인트 → 스틱맨 단위, 세 선수 평균 대비
    /// 편차 2.5배 과장(1.3배는 플레이에서 구분 불가 판정, 2026-09-15 — 템포·톱 홀드도 같은 배율). 어드레스·임팩트 손·클럽은 공 접촉 기하로 고정(tilt·hipDx 변화는 handA로
    /// 상쇄).
    /// 샤프트 각(톱·피니시)은 영상 검출이 불안정해 선수 특징 기반 수치: 로리 톱 평행 초과·타이거 평행·브라이슨 3/4,
    /// 피니시는 로리·타이거 감김(270) vs 브라이슨 홀드오프(300). 템포 일부 추정(브라이슨 빠름). 웨지는 아이언 세트 공용.
    /// 백스윙(p2·p4) headDx는 ≥ +1로 클램프 — 실측은 타이거 아이언 톱 −5.2·브라이슨 드라이버 톱 −5.8였으나 어깨가 뒤로 기운 위에
    /// 머리까지 뒤면 '부자연스럽게 뒤로 쏠린 어드레스'로 읽혔다 (2026-09-15 사용자 판정, 조준 프리뷰 heightPct 0.6에서).
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
        p2: Pose(hipDx: -0.1, tilt: -22.7, handA: -26.8, handD: 30, clubA: -110, heel: 0.0, headDx: 1.0),
        p4: Pose(hipDx: 2.7, tilt: -30.2, handA: -118.9, handD: 20.6, clubA: -268, heel: 0.0, headDx: 7.0),
        p7: Pose(hipDx: 6.6, tilt: -31.8, handA: 31.7, handD: 34, clubA: 6, heel: 1.0, headDx: -1.8),
        p8: Pose(hipDx: 6.8, tilt: -30.9, handA: 70, handD: 31.8, clubA: 125, heel: 0.0, headDx: 1.6),
        p10: Pose(hipDx: 4.0, tilt: -18.5, handA: 148.6, handD: 19, clubA: 270, heel: 0.0, headDx: 1.5),
        down: 0.26, follow: 0.13, finish: 0.36, topHold: 0.08
    )

    static let brysonDriver = SwingKeyframes(
        p1: Pose(hipDx: 0.0, tilt: -15.9, handA: 15.4, handD: 34, clubA: 12, heel: 0.0, headDx: -0.7),
        p2: Pose(
            hipDx: 0.5,
            tilt: -14.8,
            handA: -65.8,
            handD: 34,
            clubA: -85,
            heel: 0.0,
            headDx: 1.0
        ), // 손목 힌지 19° — 싱글 플레인 스윕(트레이드마크)
        p4: Pose(hipDx: -0.2, tilt: -9.1, handA: -119.4, handD: 17, clubA: -235, heel: 0.0, headDx: 1.0),
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

    /// 타이거 아이언·웨지의 tilt(척추 후방 기울기)만 과장 2.5 → 1.0(기본 포즈 대비 편차 ×0.4 — 실측 그대로): 임팩트 −31.5는
    /// 드라이버(−31.8, 수용됨)와 같은 값이지만 짧은 클럽에서 "세컨샷부터 몸 자체가 과도하게 기울어 부자연" (2026-09-23 플레이 판정).
    /// **테이크어웨이(p2) handA는 3인 평균**(아이언 −67·웨지 −70, 구 2.5배 −50.6/−35): 과장값은 손이 엉덩이 높이에 남은 채
    /// 클럽만 코킹돼(SW 43% 프리뷰 손 −61°·클럽 −142° → 손목 −81°, 로리 −48°) "어정쩡한" 자세 — 스크린샷 판정 2차(2026-09-23).
    /// 나머지 채널(hipDx·p4 이후 handA·템포·톱 홀드)은 2.5배 유지. 구 tilt: −16.7/−21.6/−20.0/−31.5/−30.4/−17.7
    static let tigerIron = SwingKeyframes(
        p1: Pose(hipDx: 0.0, tilt: -13.9, handA: 16.0, handD: 34, clubA: 12, heel: 0.0, headDx: 2.5),
        p2: Pose(hipDx: -0.7, tilt: -15.8, handA: -67, handD: 32.9, clubA: -110, heel: 0.0, headDx: 3.0),
        p4: Pose(hipDx: -0.3, tilt: -17.6, handA: -146.3, handD: 24.0, clubA: -262, heel: 0.0, headDx: 2.0),
        p7: Pose(hipDx: 7.5, tilt: -24.0, handA: 29.7, handD: 34, clubA: 6, heel: 1.0, headDx: 0.8),
        p8: Pose(hipDx: 11.3, tilt: -24.2, handA: 95, handD: 30.2, clubA: 125, heel: 1.3, headDx: 6.2),
        p10: Pose(hipDx: 9.7, tilt: -15.5, handA: 200, handD: 21.5, clubA: 270, heel: 11.3, headDx: 11.9),
        down: 0.26, follow: 0.13, finish: 0.36, topHold: 0.08
    )

    static let brysonIron = SwingKeyframes(
        p1: Pose(hipDx: 0.0, tilt: -7.8, handA: 8.4, handD: 34, clubA: 12, heel: 0.0, headDx: 3.5),
        p2: Pose(hipDx: 0.2, tilt: -4.9, handA: -93.5, handD: 34, clubA: -110, heel: 0.9, headDx: 2.3),
        p4: Pose(hipDx: 5.2, tilt: -2.4, handA: -102.0, handD: 27.3, clubA: -230, heel: 0.0, headDx: 1.0),
        p7: Pose(hipDx: 5.5, tilt: -15.5, handA: 18.6, handD: 34, clubA: 6, heel: 1.4, headDx: 4.2),
        p8: Pose(hipDx: 0.7, tilt: -5.9, handA: 83.1, handD: 30.1, clubA: 125, heel: 1.2, headDx: 8.2),
        p10: Pose(hipDx: -2.0, tilt: -8.7, handA: 200, handD: 20.2, clubA: 300, heel: 0.9, headDx: 13.3),
        down: 0.18, follow: 0.08, finish: 0.21, topHold: 0.0
    )

    /// ── 웨지 3세트 (2026-09-15 2단계): 로리·타이거는 face-on 실측(3/4 스윙이 그대로 담겨 wedge 프로파일 topScale 1.0),
    /// 브라이슨은 정면 풀웨지 영상을 6편 뒤져도 없어(TV 줌·후방 뷰·칩샷) 아이언 세트에서 유도 — 톱·피니시만 짧게.
    /// 두 선수 평균 대비 2.5배 과장. 타이거 피니시는 클립이 팔로스루에서 끝나 손·팔만 아이언 피니시로 대체
    static let roryWedge = SwingKeyframes(
        p1: Pose(hipDx: 0.0, tilt: -13.6, handA: 13.4, handD: 34, clubA: 12, heel: 0.0, headDx: 5.0),
        p2: Pose(hipDx: 1.0, tilt: -14.5, handA: -80.7, handD: 34, clubA: -100, heel: 0.0, headDx: 3.9),
        p4: Pose(hipDx: -0.5, tilt: -7.1, handA: -124.8, handD: 26.1, clubA: -235, heel: 0.0, headDx: 1.1),
        p7: Pose(hipDx: 7.3, tilt: -17.5, handA: 17.1, handD: 34, clubA: 6, heel: 1.0, headDx: 4.0),
        p8: Pose(hipDx: 9.1, tilt: -16.0, handA: 72.6, handD: 32.6, clubA: 120, heel: 3.0, headDx: 5.0),
        p10: Pose(hipDx: 9.8, tilt: -19.7, handA: 200, handD: 19, clubA: 250, heel: 6.0, headDx: 9.8),
        down: 0.24, follow: 0.12, finish: 0.28, topHold: 0.0
    )

    /// tilt만 편차 ×0.4 (tigerIron 주석 참조). 구 tilt: −17.0/−14.1/−23.4/−26.8/−22.5/−20.1
    static let tigerWedge = SwingKeyframes(
        p1: Pose(hipDx: 0.0, tilt: -14.0, handA: 16.3, handD: 34, clubA: 12, heel: 0.0, headDx: 3.7),
        p2: Pose(hipDx: -1.1, tilt: -12.8, handA: -70, handD: 30, clubA: -100, heel: 0.0, headDx: 2.2),
        p4: Pose(hipDx: 3.7, tilt: -19.0, handA: -115.4, handD: 31.8, clubA: -230, heel: 0.0, headDx: 1.0),
        p7: Pose(hipDx: 7.7, tilt: -22.1, handA: 24.9, handD: 34, clubA: 6, heel: 1.0, headDx: -0.1),
        p8: Pose(hipDx: 7.7, tilt: -21.0, handA: 73.4, handD: 26.7, clubA: 120, heel: 3.0, headDx: 3.9),
        p10: Pose(hipDx: 7.2, tilt: -16.4, handA: 200, handD: 21.5, clubA: 250, heel: 6.0, headDx: 4.0),
        down: 0.24, follow: 0.12, finish: 0.3, topHold: 0.08
    )

    static let brysonWedge = SwingKeyframes(
        p1: brysonIron.p1,
        p2: brysonIron.p2,
        p4: Pose(hipDx: 5.2, tilt: -2.4, handA: -95.0, handD: 27.3, clubA: -205, heel: 0.0, headDx: 1.0),
        p7: brysonIron.p7,
        p8: brysonIron.p8,
        p10: Pose(hipDx: -2.0, tilt: -8.7, handA: 185, handD: 20.2, clubA: 285, heel: 0.9, headDx: 13.3),
        down: 0.17, follow: 0.08, finish: 0.20, topHold: 0.0
    )

    static func table(_ style: SwingStyle, _ cat: ClubCategory) -> SwingKeyframes {
        switch (style, cat) {
        case (.rory, .wood): roryDriver
        case (.rory, .wedge): roryWedge
        case (.rory, _): roryIron
        case (.tiger, .wood): tigerDriver
        case (.tiger, .wedge): tigerWedge
        case (.tiger, _): tigerIron
        case (.bryson, .wood): brysonDriver
        case (.bryson, .wedge): brysonWedge
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
    let putt: PutterKeyframes // 스타일별 퍼터 (표준 펜듈럼 / 암록)

    static func profile(for cat: ClubCategory, style: SwingStyle = .rory) -> SwingProfile {
        let k = SwingKeyframes.table(style, cat)
        let pt = PutterKeyframes.table(style)
        return switch cat {
        // ballFwd −4: 어드레스 tilt −5→−12(어깨 −3.8px)의 보정 (2026-09-15 프로 실측 반영)
        // down = 톱 홀드 + 다운스윙 (Space → 임팩트 총 시간; 발사·rigRate·벽 스탠스 해제가 이 값을 본다)
        case .wood: SwingProfile(
                topScale: 1.0,
                ballFwd: 20,
                finishScale: 1.0,
                down: k.topHold + k.down,
                isPutter: false,
                keys: k,
                putt: pt
            )
        case .iron: SwingProfile(
                topScale: 0.88,
                ballFwd: 16,
                finishScale: 0.9,
                down: k.topHold + k.down,
                isPutter: false,
                keys: k,
                putt: pt
            )
        case .wedge: SwingProfile( // 실측 웨지 세트가 3/4 스윙을 담고 있어 스케일 없음 (구 0.72는 아이언 세트 축소용)
                topScale: 1.0,
                ballFwd: 13,
                finishScale: 1.0,
                down: k.topHold + k.down,
                isPutter: false,
                keys: k,
                putt: pt
            )
        case .putter: SwingProfile(
                topScale: 1.0, ballFwd: pt.ballFwd, finishScale: 1.0, down: 0.29, isPutter: true, keys: k, putt: pt
            ) // PGA 실측 317±35ms · 스탠스는 스타일 퍼터 세트(표준 6 · 암록 16)
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
        return Pose.lerp(profile.putt.a, profile.putt.top, heightPct)
    }
    let k = profile.keys
    let s = 0.22 + 0.78 * heightPct * (topScale ?? profile.topScale)
    return s < 0.35
        ? Pose.lerp(k.p1, k.p2, s / 0.35)
        : Pose.lerp(k.p2, k.p4, (s - 0.35) / 0.65)
}

func finishPose(profile: SwingProfile) -> Pose {
    profile.isPutter ? profile.putt.fin : Pose.lerp(profile.keys.p8, profile.keys.p10, profile.finishScale)
}

/// 스윙 애니메이션 타임라인에서 포즈 샘플 (t: 스윙 시작 후 경과 초)
func swingPose(t: Double, fromPose: Pose, profile: SwingProfile, heightPct _: Double) -> Pose {
    if t < profile.down { // 다운스윙: 급가속 (퍼터는 펜듈럼 — 최하점=임팩트에서 속도 최대)
        if profile.isPutter {
            let v = t / profile.down
            return Pose.lerp(fromPose, profile.putt.imp, v * v)
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
        return Pose.lerp(profile.putt.imp, profile.putt.fin, 1 - (1 - v) * (1 - v))
    }
    let k = profile.keys
    if t2 < k.follow {
        return Pose.lerp(k.p7, k.p8, t2 / k.follow)
    }
    let v = min(1, (t2 - k.follow) / k.finish)
    return Pose.lerp(k.p8, finishPose(profile: profile), 1 - (1 - v) * (1 - v)) // 감속하며 피니시
}
