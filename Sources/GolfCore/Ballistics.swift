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
    public static let minPowerRatio = 0.25 // 백스윙 0%의 파워 바닥값
    public static let putterMinRatio = 0.08 // 퍼터 전용 (탭인 가능)
    public static let cupHalfWidth = 0.7
    public static let captureRoll = 3.6 // 홀인 최대 굴림 속도 (퍼팅 스윕 실측으로 확대)
    public static let lipOutSpeed = 6.0 // 이 속도까지 립아웃, 초과 시 통과
    public static let captureFly = 10.0
    public static let wallRestitution = 0.5
    public static let maxStrokes = 12
    /// 경사 라이 스탠스 기울기 = 로프트 전달 비율 — 물리·애니메이션이 이 하나를 공유해야 정합 (리뷰 S-6)
    public static let stanceSlopeRatio = 0.7
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

/// 스텝 결과 이벤트 — holed/water는 종결, 나머지는 연출(사운드·이펙트)용 신호
public enum StepEvent: Sendable, Equatable {
    case none
    case holed
    case water // 입수 — 호출측에서 1벌타 + 드롭 처리
    case bounce(speed: Double, surface: Surface) // 지면 충돌 (법선 속도 m/s)
    case lipOut // 컵 턱에 맞고 튐
    case wall(speed: Double) // 화면 가장자리 반사
    case bumper(speed: Double) // 범퍼(앱 창) 반사 — 창 범퍼 모드 (2026-08-21)
}

/// 범퍼 사각형 (미터) — 창 범퍼 모드: 열린 앱 창이 비행 중인 공을 튕긴다.
/// y = 바닥 표고, h는 위로. 굴림에는 관여하지 않는다 (비행 전용 — 직관 유지)
public struct Bumper: Sendable, Equatable {
    public let x, y, w, h: Double

    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }

    func contains(_ px: Double, _ py: Double) -> Bool {
        px > x && px < x + w && py > y && py < y + h
    }
}

public enum Ballistics {
    /// 샷 발사: 클럽·백스윙 높이·라이를 반영해 공 상태를 설정
    /// mishit: 미스샷 정도 [-1, 1] — 발사각 ±4°, 파워 -12%, 스핀 -30%까지 (풀파워 리스크는 호출측)
    /// punch: 펀치샷 정도 [0, 1] — 로프트 -8°·스핀 -40% (벽 등 백스윙 제한 상황의 낮은 탈출샷)
    /// slope: 유효 경사(dy/dx, 호출측에서 스탠스 기울기 비율 적용) — 오르막 라이는 발사각↑·스피드↓
    public static func launch(
        _ b: inout BallState,
        club: Club,
        heightPct: Double,
        lie: Surface,
        dir: Double,
        mishit: Double = 0,
        punch: Double = 0,
        slope: Double = 0
    ) {
        // 퍼터: 선형 파워 + 낮은 바닥값(탭인). 정밀함은 입력측 조절 속도에서 확보
        let minR = club.isPutter ? Phys.putterMinRatio : Phys.minPowerRatio
        var v0 = club.power * lie.powerFactor * (minR + (1 - minR) * heightPct) * (1 - abs(mishit) * 0.12)
        let slopeDeg = abs(atan(slope)) * 180 / .pi
        v0 *= 1 - min(0.12, 0.006 * slopeDeg) // 경사 라이 스피드 손실 (~0.6%/도, 실측 — 3eccc4f 복원)
        let loft = max(
            0.02,
            club.loft * .pi / 180 + atan(slope * dir) + mishit * 4 * .pi / 180 - punch * 8 * .pi / 180
        )
        b.vx = dir * v0 * cos(loft)
        b.vy = club.isPutter ? 0 : v0 * sin(loft)
        // 스핀 = 클럽 스피드 비례 × 압축 효율(저속에서 sublinear) — 부분 스윙의 상대 스핀 인플레 제거.
        // 구식 (0.6+0.4h)는 살살 칠수록 상대 스핀이 최대 2.4배로 부풀었다 (리서치 §3-3). 풀스윙은 불변
        let spinPower = (Phys.minPowerRatio + (1 - Phys.minPowerRatio) * heightPct) * (0.75 + 0.25 * heightPct)
        b.spin = club.spin * lie.spinFactor * spinPower * (1 - abs(mishit) * 0.3) * (1 - 0.4 * punch)
        b.spinSign = dir
        b.phase = club.isPutter ? .roll : .fly
        b.lipped = false
        b.lowSpeedTime = 0
    }

    /// 범퍼(앱 창) 충돌 — AABB 면 반사. 진입면은 스텝 이전 위치로 판정
    /// (240Hz 스텝 이동량 ≤ 0.32m — 창 크기 대비 한 면만 통과 가능, 터널링 없음).
    /// 공이 범퍼 '안에서' 출발한 샷은 통과시킨다 (창 밑 티샷이 갇히면 버그로 보인다)
    static func bumperCollision(
        _ b: inout BallState, prevX: Double, prevY: Double, bumpers: [Bumper]
    ) -> StepEvent {
        let e = 0.55 // 창 프레임 반발 — 벽(0.5)보다 살짝 탱탱하게
        for r in bumpers where r.contains(b.x, b.y) {
            if r.contains(prevX, prevY) {
                continue
            } // 내부 출발 — 탈출 허용
            if prevY >= r.y + r.h { // 상판 낙하 바운스
                let s = -b.vy
                b.y = r.y + r.h
                b.vy = -b.vy * e
                b.spin *= 0.7
                return .bumper(speed: max(0, s))
            }
            if prevY <= r.y { // 밑면
                let s = b.vy
                b.y = r.y
                b.vy = -b.vy * e
                b.spin *= 0.7
                return .bumper(speed: max(0, s))
            }
            let fromLeft = prevX <= r.x
            let s = abs(b.vx)
            b.x = fromLeft ? r.x : r.x + r.w
            b.vx = -b.vx * e
            b.spin *= 0.7
            return .bumper(speed: s)
        }
        return .none
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
    /// bumpers: 창 범퍼 모드의 앱 창 사각형들 (비행 중에만 반사 — 240Hz 스텝이라 터널링 없음)
    public static func step(
        _ b: inout BallState, hole: Hole, bumpers: [Bumper] = [], dt: Double = Phys.dt
    ) -> StepEvent {
        var ev = StepEvent.none
        switch b.phase {
        case .rest:
            return .none

        case .fly:
            // 바람: 공기력은 대기 상대속도 기준 — 뒷바람은 항력을 줄이고 맞바람은 키운다
            let rvx = b.vx - hole.wind
            let v = max(hypot(rvx, b.vy), 1e-9)
            let omega = b.spin * 2 * .pi / 60
            let spinRatio = min(Phys.ballRadius * omega / v, Phys.spinRatioMax)
            let cl = min(Phys.clMax, Phys.clBase + Phys.clSlope * spinRatio)
            // 항력(상대속도 반대) + 마그누스 양력(상대속도 수직, 백스핀=위) + 중력
            let ax = -Phys.q * Phys.cd * v * rvx + Phys.q * cl * v * -b.vy * b.spinSign
            let ay = -Phys.g - Phys.q * Phys.cd * v * b.vy + Phys.q * cl * v * rvx * b.spinSign
            let prevX = b.x, prevY = b.y
            b.vx += ax * dt
            b.vy += ay * dt
            b.x += b.vx * dt
            b.y += b.vy * dt
            b.spin *= 1 - min(0.06, max(0.01, Phys.spinDecayPerSpeed * v)) * dt // 느린 웨지가 스핀을 안고 착지
            let bmEv = bumperCollision(&b, prevX: prevX, prevY: prevY, bumpers: bumpers)
            if bmEv != .none {
                ev = bmEv
            }
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
                    let e = surfType.restitution * (1 - min(0.55, -vn / 60))
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
            let dv = surfType.roll * dt
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
                    if abs(b.x - hole.holeX) < Phys.cupHalfWidth + 0.05 {
                        b.x = hole.holeX + (b.x >= hole.holeX ? 1 : -1) * (Phys.cupHalfWidth + 0.05)
                        b.y = hole.ground(at: b.x)
                    }
                    b.lipped = false
                }
            } else {
                b.lowSpeedTime = 0
            }
            // 정지: 마찰이 경사 중력을 이길 때만
            if abs(b.vx) < Phys.stopSpeed, surfType.roll >= Phys.g * abs(s) * 0.85 {
                b.vx = 0
                b.phase = .rest
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
