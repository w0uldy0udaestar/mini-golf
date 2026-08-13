import Foundation

/// 물리 상수 — HTML 프로토타입에서 튜닝 완료한 값 (docs/research-tech-stack.md)
public enum Phys {
    public static let g = 9.81
    public static let q = 0.01869 // 0.5·ρ·A/m (ρ=1.2, A=0.00143㎡, m=0.0459kg)
    public static let cd = 0.25 // 항력 계수
    public static let ballRadius = 0.0213
    public static let clBase = 0.04, clSlope = 1.8, clMax = 0.35, spinRatioMax = 0.30 // 양력 계수 모델
    public static let spinDecayFlight = 0.04 // 비행 중 스핀 감쇠 (비율/초)
    public static let bounceVxKeep = 0.72
    public static let bounceSpinKick = 9.0 // 백스핀 체크 최대 역방향 킥 (m/s @ 12000rpm)
    public static let bounceSpinKeep = 0.55
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

/// 스텝 결과 이벤트
public enum StepEvent: Sendable {
    case none
    case holed
    case water // 입수 — 호출측에서 1벌타 + 드롭 처리
}

public enum Ballistics {
    /// 샷 발사: 클럽·백스윙 높이·라이를 반영해 공 상태를 설정
    public static func launch(_ b: inout BallState, club: Club, heightPct: Double, lie: Surface, dir: Double) {
        // 퍼터: 선형 파워 + 낮은 바닥값(탭인). 정밀함은 입력측 조절 속도에서 확보
        let minR = club.isPutter ? Phys.putterMinRatio : Phys.minPowerRatio
        let v0 = club.power * lie.powerFactor * (minR + (1 - minR) * heightPct)
        let loft = club.loft * .pi / 180
        b.vx = dir * v0 * cos(loft)
        b.vy = v0 * sin(loft)
        b.spin = club.spin * lie.spinFactor * (0.6 + 0.4 * heightPct)
        b.spinSign = dir
        b.phase = club.isPutter ? .roll : .fly
        b.lipped = false
    }

    /// 결정론적 물리 스텝. 경사면 바운스는 법선 반사, 굴림에는 중력의 경사 성분이 더해진다
    public static func step(_ b: inout BallState, hole: Hole, dt: Double = Phys.dt) -> StepEvent {
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
            b.spin *= 1 - Phys.spinDecayFlight * dt

            let ground = hole.ground(at: b.x)
            if b.y <= ground {
                let surfType = hole.surface(at: b.x)
                if surfType == .water {
                    return .water
                }
                b.y = ground
                // 경사면 법선/접선 분해 반사
                let s = hole.slope(at: b.x)
                let len = hypot(1, s)
                let nx = -s / len, ny = 1 / len, tx = 1 / len, ty = s / len
                let vn = b.vx * nx + b.vy * ny
                if vn < 0 {
                    var vt = b.vx * tx + b.vy * ty
                    let kick = min(b.spin, 12000) / 12000 * Phys.bounceSpinKick * b.spinSign
                    vt = vt * Phys.bounceVxKeep - kick
                    let vnNew = -vn * surfType.restitution
                    b.spin *= Phys.bounceSpinKeep
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

        // 좌우 벽 반사
        if b.x < 0.5 {
            b.x = 0.5; b.vx = -b.vx * Phys.wallRestitution
        }
        if b.x > hole.worldW - 0.5 {
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
                }
            } else if b.phase == .fly, b.y < hole.ground(at: b.x) + 0.3, b.vy < 0, speed <= Phys.captureFly {
                return .holed
            }
        }
        return .none
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
