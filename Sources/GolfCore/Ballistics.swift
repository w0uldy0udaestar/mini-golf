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
    }

    /// 결정론적 물리 스텝. 경사면 바운스는 법선 반사, 굴림에는 중력의 경사 성분이 더해진다
    public static func step(_ b: inout BallState, hole: Hole, dt: Double = Phys.dt) -> StepEvent {
        var ev = StepEvent.none
        switch b.phase {
        case .rest:
            return .none

        case .fly:
            let v = max(hypot(b.vx, b.vy), 1e-9)
            let omega = b.spin * 2 * .pi / 60
            let spinRatio = min(Phys.ballRadius * omega / v, Phys.spinRatioMax)
            let cl = min(Phys.clMax, Phys.clBase + Phys.clSlope * spinRatio)
            // 항력(속도 반대) + 마그누스 양력(속도 수직, 백스핀=위) + 중력
            let ax = -Phys.q * Phys.cd * v * b.vx + Phys.q * cl * v * -b.vy * b.spinSign
            let ay = -Phys.g - Phys.q * Phys.cd * v * b.vy + Phys.q * cl * v * b.vx * b.spinSign
            b.vx += ax * dt
            b.vy += ay * dt
            b.x += b.vx * dt
            b.y += b.vy * dt
            b.spin *= 1 - min(0.06, max(0.01, Phys.spinDecayPerSpeed * v)) * dt // 느린 웨지가 스핀을 안고 착지

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
            let s = hole.slope(at: b.x)
            b.vx -= Phys.g * s * 0.85 * dt // 경사 중력: 그린 브레이크의 원천
            let dv = surfType.roll * dt
            if abs(b.vx) <= dv {
                b.vx = 0
            } else {
                b.vx -= (b.vx > 0 ? 1 : -1) * dv
            }
            b.y = hole.ground(at: b.x)
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
