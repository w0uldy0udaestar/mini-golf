import Foundation

/// 물리 상수 — HTML 프로토타입에서 튜닝 완료한 값 (docs/research-tech-stack.md)
public enum Phys {
    public static let g = 9.81
    public static let q = 0.01869 // 0.5·ρ·A/m (ρ=1.2, A=0.00143㎡, m=0.0459kg)
    public static let cd = 0.25 // 항력 계수
    public static let ballRadius = 0.0213
    public static let clBase = 0.04, clSlope = 1.8, clMax = 0.35, spinRatioMax = 0.30 // 양력 계수 모델
    // 스핀 감쇠율(/s) = 이 값 × 속도, [0.01, 0.06] 클램프 — dω/dt ∝ −v·ω (Smits & Smith 풍동)
    public static let spinDecayPerSpeed = 0.00067
    public static let bounceFriction = 1.0 // 잔디 μ (Biber 2023 실측 0.997~0.998)
    public static let bounceToRoll = 1.0
    public static let stopSpeed = 0.15
    /// 저속 잔디 걸림 (2026-09-28 "비탈에서 그렇게까지 미끄러지지 않는다"): 이 속도 아래에선 굴림 저항이 선형으로 최대 2배 —
    /// 느린 공은 잔디에 파묻혀 비탈 중턱에서도 선다. 그린·에이프런은 제외(퍼팅 거리 프리셋·컵 캡처 속도 전제)
    public static let gripSpeed = 1.5
    /// 정지 마찰 = 굴림 저항 × 1.3 — 멈춘 공이 버티는 경사가 구르는 공의 감속 한계보다 크다(페어웨이 0.26 → 0.34, 러프 0.54 → 0.70)
    public static let staticHoldGain = 1.3
    public static let minPowerRatio = 0.25 // 백스윙 0%의 파워 바닥값
    public static let putterMinRatio = 0.08 // 퍼터 전용 (탭인 가능)
    public static let cupHalfWidth = 0.7
    public static let captureRoll = 3.6 // 홀인 최대 굴림 속도 (퍼팅 스윕 실측으로 확대)
    public static let lipOutSpeed = 6.0 // 이 속도까지 립아웃, 초과 시 통과
    public static let captureFly = 10.0
    public static let wallRestitution = 0.5
    public static let maxStrokes = 12
    /// 경사 라이 스탠스 기울기 = 로프트 전달 비율 — 물리·애니메이션이 이 하나를 공유해야 정합 (리뷰 S-6).
    /// 1.0 = 클럽이 지면을 따라가 경사각이 로프트에 그대로 더해진다(실제 라이). 구 0.7은 봇 실측 풀샷의 65%가 |경사| < 0.05인
    /// 지형과 겹쳐 발사각 변화 중앙값 1.1°로 체감 불가 판정(2026-09-28 "경사 위에서도 평지에서 치는 느낌")
    public static let stanceSlopeRatio = 1.0
    public static let dt = 1.0 / 240.0 // 고정 물리 스텝
}

public struct BallState: Sendable {
    public enum Phase: Sendable { case rest, fly, roll }

    public var x: Double
    public var y: Double // 절대 표고
    public var vx: Double
    public var vy: Double
    public var spin: Double
    public var spinSign: Double
    public var phase: Phase
    public var lipped: Bool
    public var lowSpeedTime = 0.0 // 저속 굴림 지속 시간 — V자 골짜기 미세 진동 정지 가드용

    public init(
        x: Double,
        y: Double,
        vx: Double = 0,
        vy: Double = 0,
        spin: Double = 0,
        spinSign: Double = 1,
        phase: Phase = .rest,
        lipped: Bool = false
    ) {
        self.x = x
        self.y = y
        self.vx = vx
        self.vy = vy
        self.spin = spin
        self.spinSign = spinSign
        self.phase = phase
        self.lipped = lipped
    }
}

/// 공 종류 (2026-09-16 서프라이즈 2차 '공 바꿔치기') — 다음 한 샷만 물리 계수가 바뀐다.
/// 고무공: 반발이 커서 착지 뒤에도 계속 튄다 · 볼링공: 무거워 공기력이 거의 안 먹고(안 뜸) 둔탁하게 떨어져 짧게 구른다.
/// 계수는 기존 물리에 배율로만 얹는다 — 표준 공은 전부 1이라 회귀 없음
public enum BallKind: String, Sendable, CaseIterable {
    case standard, rubber, bowling

    /// 바운스 반발 배율 (Surface.restitution에 곱한다, 결과는 0.85로 클램프)
    public var restitutionScale: Double {
        switch self {
        case .standard: 1
        case .rubber: 2.6
        case .bowling: 0.35
        }
    }

    /// 공기력 배율 (Phys.q = 0.5·ρ·A/m 에 곱한다 — 질량이 크면 항력·양력 모두 줄어든다).
    /// ⚠️ 클럽 파워가 항력 모델 전제로 튜닝돼 있어 공기력을 0에 가깝게 빼면 오히려 더 멀리 간다(실측 351m > 306m) —
    /// '안 뜸'은 발사 속도(launchScale)가 만들고, 여기서는 양력만 덜 먹게 한다
    public var aeroScale: Double {
        switch self {
        case .standard: 1
        case .rubber: 1.15
        case .bowling: 0.55
        }
    }

    /// 굴림 감속 배율 — 볼링공은 잔디에 박혀 금방 선다
    public var rollScale: Double {
        switch self {
        case .standard, .rubber: 1
        case .bowling: 1.6
        }
    }

    /// 발사 속도 배율 — 무거운 공은 클럽페이스에서 느리게 떠난다 (충돌 운동량 보존: 질량비가 크면 공 속도가 크게 준다)
    public var launchScale: Double {
        switch self {
        case .standard, .rubber: 1
        case .bowling: 0.5
        }
    }
}

/// 스텝 결과 이벤트 — holed/water는 종결, 나머지는 연출(사운드·이펙트)용 신호
public enum StepEvent: Sendable, Equatable {
    case none
    case holed
    case water // 입수 — 호출측에서 1벌타 + 드롭 처리
    case bounce(speed: Double, surface: Surface) // 지면 충돌 (법선 속도 m/s)
    case lipOut // 컵 턱에 맞고 튐
    case wall(speed: Double) // 화면 가장자리 반사
}

/// 샷 종류 — 플레이어가 Tab으로 고른다 (M5-③). 벽·나무 자동 펀치(`launch(punch:)`)와는 별개로 겹쳐 적용된다.
/// 2026-09-29 1차 판정: 3종(펀치·런닝·로브)에서 "런닝은 어프로치 말고는 들어본 적 없고 펀치와 차이를 모르겠다" → 런닝 삭제(2종).
/// "펀치가 약하다" → 드라이버 펀치가 평지 캐리 249→157m(로프트 바닥 8°에 걸리고 스핀 반감으로 양력 소실)이라 클럽군별로 나눴다:
/// 우드는 스핀을 덜 깎아 낮지만 캐리가 사는 스팅어, 아이언·웨지는 캐리 ≈ 기본·낮은 정점·긴 굴림. 밸런스 가드는 굴림 포함 총거리가 아니라
/// **캐리 ≤ 기본**(굴림은 러프·경사가 먹는다 — 실플레이 절벽 티 DR 펀치 224 vs 기본 290m). 수치는 평지 계측 ShotShapeProbe
public enum ShotShape: String, CaseIterable, Sendable {
    case standard, punch, lob

    /// 로프트 변화(도). 낮은 샷은 `minLoftDeg`가 바닥, 로브는 `maxLoftDeg`가 상한
    public func loftDelta(for cat: ClubCategory) -> Double {
        switch self {
        case .standard: 0
        case .punch: cat == .wood ? -4 : -10 // 우드는 로프트가 낮아 바닥에 걸린다 — 스팅어는 로프트보다 스핀·탄도로
        case .lob: 18
        }
    }

    /// 볼스피드 배율 — 짧은 백스윙(펀치)·열린 페이스(로브)의 손실
    public func speedScale(for cat: ClubCategory) -> Double {
        switch self {
        case .standard: 1
        case .lob: 0.92
        case .punch:
            switch cat {
            case .wood: 0.95
            case .iron: 0.89
            case .wedge: 0.83
            case .putter: 1
            }
        }
    }

    /// 스핀 배율 — 펀치는 낮게 날아 착지 후 구른다. 우드는 스핀을 반으로 깎으면 양력이 사라져 공이 뚝 떨어진다(1차 판정 "약하다")
    public func spinScale(for cat: ClubCategory) -> Double {
        switch self {
        case .standard: 1
        case .lob: 0.9
        case .punch: cat == .wood ? 0.75 : 0.5
        }
    }

    /// 낮은 샷의 로프트 바닥 — 없으면 드라이버 펀치가 0°로 땅을 345m 구른다 (계측)
    public static let minLoftDeg = 8.0
    /// 로브 로프트 상한 — 없으면 샌드웨지 로브가 71°로 떠서 20m밖에 못 가고 9m 되감긴다 (계측)
    public static let maxLoftDeg = 62.0

    public var isLow: Bool {
        self == .punch
    }

    /// Tab 순환: 기본 → 펀치 → 로브 → 기본
    public var next: ShotShape {
        let all = ShotShape.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }

    /// HUD 단어 (클럽 이름 옆). 기본은 표시 없음
    public var label: String? {
        switch self {
        case .standard: nil
        case .punch: "펀치"
        case .lob: "로브"
        }
    }

    /// HUD 한 줄 설명 — 수치가 아니라 결과의 말 (어시스트 금지 원칙 안). 웨지 펀치가 곧 런닝 어프로치
    public func cue(for cat: ClubCategory) -> String? {
        switch self {
        case .standard: nil
        case .punch: cat == .wedge ? "낮게 굴려 붙인다" : "낮게 뚫고 조금 구른다"
        case .lob: "높이 띄워 바로 세운다"
        }
    }
}

public enum Ballistics {
    /// 샷 발사: 클럽·백스윙 높이·라이를 반영해 공 상태를 설정
    /// mishit: 미스샷 정도 [-1, 1] — 발사각 ±4°, 파워 -12%, 스핀 -30%까지 (풀파워 리스크는 호출측)
    /// punch: 펀치샷 정도 [0, 1] — 로프트 -8°·스핀 -40% (벽 등 백스윙 제한 상황의 낮은 탈출샷)
    /// slope: 유효 경사(dy/dx, 호출측에서 스탠스 기울기 비율 적용) — 오르막 라이는 발사각↑·스피드↓
    /// shape: 플레이어가 고른 샷 종류 — 로프트·스피드·스핀 배율 (ShotShape). 자동 펀치와 겹치면 둘 다 적용, 로프트는 바닥·상한으로 클램프
    /// roughLie: 러프 라이 이원화 (RoughLie) — 러프에서만 의미, 파워·스핀 배율과 로프트 +2°/+5°
    public static func launch(
        _ b: inout BallState,
        club: Club,
        heightPct: Double,
        lie: Surface,
        dir: Double,
        mishit: Double = 0,
        punch: Double = 0,
        slope: Double = 0,
        kind: BallKind = .standard,
        shape: ShotShape = .standard,
        roughLie: RoughLie = .normal
    ) {
        // 퍼터: 선형 파워 + 낮은 바닥값(탭인). 정밀함은 입력측 조절 속도에서 확보
        let minR = club.isPutter ? Phys.putterMinRatio : Phys.minPowerRatio
        let rl = lie == .rough ? roughLie : .normal // 러프 라이 이원화 (2026-09-29)
        let teeWood = (lie == .tee && club.cat == .wood) ? 0.85 :
            1.0 // 티 위 우드는 스핀 −15% (스핀 리서치 미적용분, 2026-09-29) — 드라이브가 조금 더 구른다
        var v0 = club.power * lie.powerFactor * rl.powerMul * (minR + (1 - minR) * heightPct) * (1 - abs(mishit) * 0.12)
        v0 *= club.isPutter ? 1 : kind.launchScale // 공 바꿔치기: 볼링공은 느리게 떠난다 — 퍼터는 면제 (0.16x '죽은 샷' 방지, 리뷰 m4)
        let slopeDeg = abs(atan(slope)) * 180 / .pi
        v0 *= 1 - min(0.12, 0.006 * slopeDeg) // 경사 라이 스피드 손실 (~0.6%/도, 실측 — 3eccc4f 복원)
        let shape = club.isPutter ? ShotShape.standard : shape // 퍼터는 종류 무관 — 호출측 가드와 무관하게 여기서 정규화 (리뷰 F3)
        v0 *= shape.speedScale(for: club.cat)
        // 클럽 로프트 + 자동 펀치 + 샷 종류 → 종류별 바닥·상한 클램프 → 경사·미스힛은 그 뒤 (내리막 라이는 물리대로 더 낮아진다)
        var loftDeg = club.loft - punch * 8 + shape.loftDelta(for: club.cat) + (club.isPutter ? 0 : rl.loftDelta)
        if shape.isLow {
            loftDeg = max(ShotShape.minLoftDeg, loftDeg)
        }
        if shape == .lob {
            loftDeg = min(ShotShape.maxLoftDeg, loftDeg)
        }
        let loft = max(0.02, loftDeg * .pi / 180 + atan(slope * dir) + mishit * 4 * .pi / 180)
        b.vx = dir * v0 * cos(loft)
        b.vy = club.isPutter ? 0 : v0 * sin(loft)
        // 스핀 = 클럽 스피드 비례 × 압축 효율(저속에서 sublinear) — 부분 스윙의 상대 스핀 인플레 제거.
        // 구식 (0.6+0.4h)는 살살 칠수록 상대 스핀이 최대 2.4배로 부풀었다 (리서치 §3-3). 풀스윙은 불변
        let spinPower = (Phys.minPowerRatio + (1 - Phys.minPowerRatio) * heightPct) * (0.75 + 0.25 * heightPct)
        b.spin = club.spin * lie.spinFactor * rl
            .spinMul * teeWood * spinPower * (1 - abs(mishit) * 0.3) * (1 - 0.4 * punch) * shape
            .spinScale(for: club.cat)
        b.spinSign = dir
        b.phase = club.isPutter ? .roll : .fly
        b.lipped = false
        b.lowSpeedTime = 0
    }

    /// 급경사면(|경사| > steepRest)에서 멈추려는 공을 내리막으로 굴려 완경사까지 내려놓는다 — 실제 공은 43° 잔디에 서지 않는다.
    /// 구 V자 가드가 라이저 발치의 진동을 경사면 위에서 얼렸고, 그 자리의 경사 스탠스(stanceSlopeRatio×경사)가 샷 로프트를 30° 넘게 세워
    /// 매 샷이 수직으로 떠 제자리에 떨어졌다 (2026-09-17 협곡 "도저히 못 나온다"의 원인 — 봇 추적 240→240 반복).
    /// 내려놓은 자리가 물이면 true (호출측이 입수로 처리).
    /// 2026-09-28 리뷰 실측: 발치 꼬리(경사 ≤ 0.3)에 세우면 협곡 근측 발치가 홀 쪽 **내리막** 라이(−16.7°)가 되어 PW 발사각이 29°로 낮아져
    /// 반대편 림을 86% 못 넘겼다(0.7 시절도 55%). 라이저에서 굴러 내려온 공은 settleTail(0.12) 이하의 바닥까지, 처음 방향으로만
    /// 내려놓는다 — 부호가 뒤집히면 바닥을 지난 것이니 멈춘다. 벙커 벽·굴곡 정점(≤ 0.3)은 라이저가 아니라 여기 안 걸린다(급경사 라이 유지)
    public static let steepRest = 0.3
    public static let settleTail = 0.12
    static func settleOffSteepSlope(_ b: inout BallState, hole: Hole) -> Bool {
        guard abs(hole.slope(at: b.x)) > steepRest else { return false } // 발동은 라이저 몸통(> 0.3)에 서려 할 때만
        var x = b.x
        var steps = 0
        let down: Double = hole.slope(at: b.x) > 0 ? -0.5 : 0.5 // 내리막 방향 (고정)
        while steps < 200 {
            let s = hole.slope(at: x)
            if abs(s) <= settleTail || s * down > 0 { // 완경사에 닿았거나 바닥을 지나 오르막(부호 반전)
                break
            }
            // 직선 언덕 사면(경사가 4m 앞까지 일정, ≤ 0.3)에 들어섰으면 거기서 선다 — 러프·페어웨이 정지 마찰이 붙잡는 곳을 바닥까지 미끄러뜨리지
            // 않는다(구 SETTLE max 32m → 22m). cos 꼬리(협곡 벽)는 경사가 계속 줄어 여기 안 걸리고 바닥(0.12)까지 간다. 벙커 벽도 직선 V라 제외(리뷰)
            if abs(s) <= steepRest, hole.surface(at: x) != .bunker, abs(s - hole.slope(at: x + down * 4)) < 0.01 {
                break
            }
            x += down
            steps += 1
        }
        x = min(max(x, 0.5), hole.worldW - 0.5)
        // 200스텝 소진(좁은 V 양벽 진동)·경계 클램프로 여전히 급경사면 이동을 포기한다 — 현 생성기는 V 바닥이 항상 완경사라
        // 도달 불가(프로브 steepRests == 0 단언이 가드), 지형 파라미터가 바뀌면 여기서 드러난다
        guard x != b.x, abs(hole.slope(at: x)) <= steepRest else { return false }
        b.x = x
        b.y = hole.ground(at: x)
        return hole.surface(at: x) == .water
    }

    /// 장애물 충돌 — 캐노피는 비행을 삼키고(잎 스침 = rough 바운스 이벤트 재활용),
    /// 바위는 단단한 원호 반사(wall 이벤트). 트렁크는 화면 뒤편(2D 사이드뷰 관례)이라
    /// 충돌하지 않는다 — 그래야 '캐노피 밑 펀치샷'이라는 극복 플레이가 성립한다.
    /// 결정론적 — RNG 없음, 기하가 곧 예측 불가성
    static func obstacleCollision(_ b: inout BallState, hole: Hole) -> StepEvent {
        for ob in hole.obstacles {
            let g = hole.ground(at: ob.x)
            switch ob.kind {
            case .tree:
                // 캐노피: 원 안에 들어오면 잎이 비행을 삼킨다 — 뚝 떨어짐
                let cy = ob.canopyCenterY(above: g)
                let dx = b.x - ob.x, dy = b.y - cy
                if b.phase == .fly, dx * dx + dy * dy < ob.size * ob.size {
                    let speed = hypot(b.vx, b.vy)
                    b.vx *= 0.12
                    b.vy = min(b.vy, 0) * 0.2 - 1.5
                    b.spin *= 0.3
                    return .bounce(speed: speed, surface: .rough)
                }
            case .rock:
                // 바위: 원호 표면 법선 반사 — 어디에 맞느냐가 방향을 정한다
                let cy = ob.rockCenterY(above: g)
                let dx = b.x - ob.x, dy = b.y + 0.02 - cy
                let d2 = dx * dx + dy * dy
                if d2 < ob.size * ob.size, d2 > 1e-9 {
                    let d = d2.squareRoot()
                    let nx = dx / d, ny = dy / d
                    let vn = b.vx * nx + b.vy * ny
                    if vn < 0 {
                        b.vx -= 1.55 * vn * nx // 반발 0.55
                        b.vy -= 1.55 * vn * ny
                        b.x = ob.x + nx * (ob.size + 0.05)
                        b.y = max(hole.ground(at: b.x), cy + ny * (ob.size + 0.05))
                        b.spin *= 0.5
                        if b.phase == .roll {
                            if b.vy > 0.8 {
                                b.phase = .fly // 바위를 타고 튀어오른다
                                b.lowSpeedTime = 0
                            } else {
                                b.vy = 0 // roll 불변식: 수직 속도 없음 (리뷰 S-3)
                            }
                        }
                        return .wall(speed: -vn)
                    }
                }
            }
        }
        return .none
    }

    /// 결정론적 물리 스텝. 경사면 바운스는 법선 반사, 굴림에는 중력의 경사 성분이 더해진다.
    /// wind: 바람 덮어쓰기(m/s) — 돌풍 서프라이즈가 비행 중 잠시 넘긴다 (nil이면 홀 바람)
    /// kind: 공 종류 — 공 바꿔치기 서프라이즈의 고무공·볼링공 (표준은 배율 전부 1)
    public static func step(
        _ b: inout BallState, hole: Hole, dt: Double = Phys.dt, wind: Double? = nil,
        kind: BallKind = .standard
    ) -> StepEvent {
        var ev = StepEvent.none
        switch b.phase {
        case .rest:
            return .none

        case .fly:
            // 바람: 공기력은 대기 상대속도 기준 — 뒷바람은 항력을 줄이고 맞바람은 키운다
            let rvx = b.vx - (wind ?? hole.wind)
            let v = max(hypot(rvx, b.vy), 1e-9)
            let omega = b.spin * 2 * .pi / 60
            let spinRatio = min(Phys.ballRadius * omega / v, Phys.spinRatioMax)
            let cl = min(Phys.clMax, Phys.clBase + Phys.clSlope * spinRatio)
            // 항력(상대속도 반대) + 마그누스 양력(상대속도 수직, 백스핀=위) + 중력
            let q = Phys.q * kind.aeroScale // 볼링공은 무거워 공기력이 거의 안 먹는다
            let ax = -q * Phys.cd * v * rvx + q * cl * v * -b.vy * b.spinSign
            let ay = -Phys.g - q * Phys.cd * v * b.vy + q * cl * v * rvx * b.spinSign
            b.vx += ax * dt
            b.vy += ay * dt
            b.x += b.vx * dt
            b.y += b.vy * dt
            b.spin *= 1 - min(0.06, max(0.01, Phys.spinDecayPerSpeed * v)) * dt // 느린 웨지가 스핀을 안고 착지
            let obEv = obstacleCollision(&b, hole: hole)
            if obEv != .none {
                ev = obEv
            }

            let ground = hole.ground(at: b.x)
            if b.y <= ground {
                let surfType = hole.surface(at: b.x)
                if surfType == .water {
                    return .water
                }
                b.y = ground
                // 접촉 프레임: 지형 경사 + Penner 유효 경사(β) — 잔디 변형을 '진행 방향을 마주보는
                // 가상 오르막'으로 등가 처리 (Penner 2002, Biber 2023 — 실측 1000+회 검증 모델)
                let s = hole.slope(at: b.x)
                let baseAng = atan(s)
                // β는 낙하 강도에 비례해서만 (Penner 원논문의 β도 속도·각 비례 — 관입 깊이의 등가 경사).
                // 얕은 재바운스에 풀 β를 주면 구름 스핀(접선 무손실)과 결합해 수평→수직 펌핑이
                // 반복되는 '탱탱볼 스킵'이 된다 (2026-08-14 실플레이 판정) — 법선 낙하 12 m/s에서 포화
                let vnTerrain = -b.vx * sin(baseAng) + b.vy * cos(baseAng)
                let beta = surfType.bounceBeta * min(1, max(0, -vnTerrain) / 12)
                let ang = baseAng + beta * (b.vx >= 0 ? 1 : -1)
                let nx = -sin(ang), ny = cos(ang), tx = cos(ang), ty = sin(ang)
                let vn = b.vx * nx + b.vy * ny
                if vn < 0 {
                    ev = .bounce(speed: -vn, surface: surfType)
                    var vt = b.vx * tx + b.vy * ty
                    // 속도 의존 반발 — 강한 낙하일수록 잔디에 파묻힌다
                    let e = min(0.85, surfType.restitution * kind.restitutionScale * (1 - min(0.55, -vn / 60)))
                    // 접지점 상대속도로 구름/미끄러짐 판정. 구름이면 (5/7, 2/7) 각운동량 보존 해 —
                    // 릴리스·체크·백업 세 상태가 추가 튜닝 없이 이 식에서 저절로 나온다 (Biber 2023)
                    var w = Phys.ballRadius * b.spin * .pi / 30 * b.spinSign // 스핀 표면속도 (백스핀 +)
                    if abs(vt + w) < 3.5 * Phys.bounceFriction * (1 + e) * -vn {
                        let vtNew = (5.0 / 7.0) * vt - (2.0 / 7.0) * w
                        vt = vtNew
                        w = -vtNew
                    } else { // 미끄러짐 (얕고 빠른 저스핀 낙하) — 마찰 충격량, 위 판정이 과보정을 막는다
                        let dv = Phys.bounceFriction * (1 + e) * vn * (vt + w >= 0 ? 1 : -1)
                        vt += dv
                        w += 2.5 * dv
                    }
                    b.spin = abs(w) * 30 / (.pi * Phys.ballRadius)
                    b.spinSign = w >= 0 ? 1 : -1
                    let vnNew = -vn * e
                    if vnNew > Phys.bounceToRoll {
                        b.vx = vt * tx + vnNew * nx
                        b.vy = vt * ty + vnNew * ny
                    } else {
                        b.phase = .roll
                        b.vx = vt * tx
                        b.vy = 0
                    }
                }
            }

        case .roll:
            b.x += b.vx * dt
            let surfType = hole.surface(at: b.x)
            if surfType == .water {
                return .water
            }
            let obEv = obstacleCollision(&b, hole: hole)
            if obEv != .none {
                ev = obEv
                if b.phase == .fly {
                    return ev // 바위를 타고 이륙 — 다음 스텝부터 비행 처리
                }
            }
            let s = hole.slope(at: b.x)
            b.vx -= Phys.g * s * 0.85 * dt // 경사 중력: 그린 브레이크의 원천
            // 잔디 걸림은 라이저(> steepRest)에선 없다 — 43° 잔디에서 느린 공이 멈춰 서면(러프 9 > 중력 7.9) 정착 규칙이 꼬리에 세운다 (협곡 프로브 13/72)
            let grip = surfType == .green || surfType == .apron || abs(s) > steepRest
                ? 1.0 : 1 + max(0, 1 - abs(b.vx) / Phys.gripSpeed)
            let dv = surfType.roll * kind.rollScale * grip * dt
            if abs(b.vx) <= dv {
                b.vx = 0
            } else {
                b.vx -= (b.vx > 0 ? 1 : -1) * dv
            }
            b.y = hole.ground(at: b.x)
            // V자 골짜기 미세 진동 가드: 저속(<1.2)이 2.5s 지속되면 그 자리에 멈춘다 —
            // 실제 공은 정지 마찰·잔디 눌림으로 경사에서도 멈춘다. 다이나믹 지형(급경사 골)에서
            // 아래 정지 조건이 영원히 성립하지 않는 비종결 굴림 6/3206을 QA 소크로 재현·수정.
            // 컵 반경 안에서 발동하면 가장자리로 밀어낸다 (립아웃 잔존 처리와 동일 규칙 —
            // 리뷰 S-2: 컵 주변에 가드 사각 고리를 남기지 않는다)
            if abs(b.vx) < 1.2 {
                b.lowSpeedTime += dt
                if b.lowSpeedTime > 2.5 {
                    b.vx = 0
                    b.phase = .rest
                    if settleOffSteepSlope(&b, hole: hole) { // 라이저 발치의 V자에서 얼어붙던 공 — 트레드로 (2026-09-17)
                        return .water
                    }
                    if abs(b.x - hole.holeX) < Phys.cupHalfWidth + 0.05 {
                        b.x = hole.holeX + (b.x >= hole.holeX ? 1 : -1) * (Phys.cupHalfWidth + 0.05)
                        b.y = hole.ground(at: b.x)
                    }
                    b.lipped = false
                }
            } else {
                b.lowSpeedTime = 0
            }
            // 정지: 정지 마찰(굴림 저항 × staticHoldGain)이 경사 중력을 이길 때만 — 페어웨이 0.34·러프 0.70까지. 라이저(> 0.3)는 정착 규칙이 바닥으로
            let hold = abs(s) > steepRest ? 1.0 : Phys
                .staticHoldGain // 라이저(> 0.3)는 main과 같은 정지 조건 — 정착 텔레포트 거리 불변 (리뷰 #2)
            if abs(b.vx) < Phys.stopSpeed, surfType.roll * hold >= Phys.g * abs(s) * 0.85 {
                b.vx = 0
                b.phase = .rest
                if settleOffSteepSlope(&b, hole: hole) {
                    return .water
                }
                // 립아웃 직후 컵 위에서 멈추면 컵 가장자리에 걸친 것으로 처리
                if b.lipped, abs(b.x - hole.holeX) < Phys.cupHalfWidth {
                    b.x = hole.holeX + (b.x >= hole.holeX ? 1 : -1) * (Phys.cupHalfWidth + 0.05)
                    b.y = hole.ground(at: b.x)
                }
            }
        }

        // 좌우 벽 반사 — speed는 반발 전 충돌 속도. 같은 스텝의 지면 bounce가 연출 우선
        if b.x < 0.5 {
            if ev == .none {
                ev = .wall(speed: abs(b.vx))
            }
            b.x = 0.5; b.vx = -b.vx * Phys.wallRestitution
        }
        if b.x > hole.worldW - 0.5 {
            if ev == .none {
                ev = .wall(speed: abs(b.vx))
            }
            b.x = hole.worldW - 0.5; b.vx = -b.vx * Phys.wallRestitution
        }

        // 컵 캡처 / 립아웃 — 임계값 절벽을 연속 구간으로:
        // 롤 ≤3.0 m/s 홀인 · 3.0~5.5 립아웃(턱에 맞고 튀어 근처 정지) · >5.5 통과
        if b.lipped {
            if abs(b.x - hole.holeX) > Phys.cupHalfWidth + 0.2 {
                b.lipped = false
            }
        } else if abs(b.x - hole.holeX) < Phys.cupHalfWidth {
            let speed = hypot(b.vx, b.vy)
            if b.phase == .roll {
                if abs(b.vx) <= Phys.captureRoll {
                    return .holed
                }
                if abs(b.vx) <= Phys.lipOutSpeed {
                    b.lipped = true
                    let over = (abs(b.vx) - Phys.captureRoll) / (Phys.lipOutSpeed - Phys.captureRoll)
                    b.phase = .fly
                    b.lowSpeedTime = 0
                    b.vy = 0.8 + over * 0.7 // 톡 튀어오르는 연출
                    b.vx = (b.vx > 0 ? 1 : -1) * (0.5 + over * 1.2)
                    b.spin = 0
                    ev = .lipOut
                }
            } else if b.phase == .fly, b.y < hole.ground(at: b.x) + 0.3, b.vy < 0, speed <= Phys.captureFly {
                return .holed
            }
        }
        return ev
    }
}

/// 스코어 이름 (홀인원·이글·버디…)
public func scoreName(strokes: Int, par: Int) -> String {
    if strokes == 1 {
        return "홀인원!"
    }
    switch strokes - par {
    case ...(-3): return "알바트로스"
    case -2: return "이글"
    case -1: return "버디"
    case 0: return "파"
    case 1: return "보기"
    case 2: return "더블 보기"
    default: return "+\(strokes - par)"
    }
}
