import GolfCore
import SpriteKit

/// 클럽별 렌더 속성 — 클럽만 보고도 무엇을 들었는지 알 수 있게 (물리와 무관, 연출 전용)
extension Club {
    /// 렌더 길이(px): 드라이버가 가장 길고 퍼터가 가장 짧다
    var renderLength: Double {
        switch id {
        case "DR": 45
        case "3W": 43.5
        case "5W": 42
        case "PT": 31
        default: 41 - (loft - 21) * 6 / 35 // 아이언·웨지: 로프트가 클수록 짧게 (3I 41 → SW 35)
        }
    }
}

/// 걷기 중 랜덤 잉여 동작 — 스틱맨의 생명감 (twirl: 트월 진행 0→1 후 1 유지, shoulder: 어깨 캐리 블렌드)
struct WalkFlavor {
    var twirl: Double?
    var shoulder = 0.0
}

private func mix(_ a: CGPoint, _ b: CGPoint, _ u: Double) -> CGPoint {
    CGPoint(x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u)
}

private func mix(_ a: Double, _ b: Double, _ u: Double) -> Double {
    a + (b - a) * u
}

/// ═══════════════════════════════════════════════════════════════
/// 통합 리그 — 스윙·걷기·전환이 전부 이 하나의 파라미터 공간을 지나간다.
/// 모드는 '타깃 리그'만 바꾸고, 렌더는 지수 감쇠로 타깃을 쫓는다.
/// 어떤 모드 전환도 같은 공간 안의 보간이므로 순간이동이 구조적으로 불가능하다.
/// 좌표는 facing 기준(+x = 바라보는 쪽), 렌더에서 dir로 미러링한다.
/// ═══════════════════════════════════════════════════════════════
struct Rig {
    var hip = CGPoint(x: -5, y: 42)
    var shoulder = CGPoint(x: 1, y: 66)
    var headDx = 7.0
    var foot1 = CGPoint(x: -16, y: 0) // 포즈에선 뒷발, 걷기에선 위상 +발
    var foot2 = CGPoint(x: 11, y: 0)
    var knee1 = CGPoint(x: -13, y: 22)
    var knee2 = CGPoint(x: 6, y: 21)
    var grip = CGPoint(x: 8, y: 33) // 리드 손 = 클럽 그립
    var handTrail = CGPoint(x: 10, y: 30) // 트레일 손 (스윙: 그립에 겹침 · 걷기: 자유 팔)
    var clubPhi = 0.2 // 샤프트 절대각 (0 = 수직 아래, + = 타겟 쪽)
    var clubLen = 31.0

    /// 지수 감쇠 추적 — clubPhi는 최단 각도 경로로 (트월 한 바퀴 후 되감기 방지)
    mutating func chase(_ t: Rig, rate: Double, dt: Double) {
        let k = 1 - exp(-rate * dt)
        hip = mix(hip, t.hip, k)
        shoulder = mix(shoulder, t.shoulder, k)
        headDx = mix(headDx, t.headDx, k)
        foot1 = mix(foot1, t.foot1, k)
        foot2 = mix(foot2, t.foot2, k)
        knee1 = mix(knee1, t.knee1, k)
        knee2 = mix(knee2, t.knee2, k)
        grip = mix(grip, t.grip, k)
        handTrail = mix(handTrail, t.handTrail, k)
        clubLen = mix(clubLen, t.clubLen, k)
        let dPhi = (t.clubPhi - clubPhi).remainder(dividingBy: 2 * .pi)
        clubPhi += dPhi * k
    }
}

enum RigBuilder {
    /// P-System 포즈 → 리그 (스탠스는 공 원점 기준)
    static func fromPose(_ p: Pose, ballFwd: Double, clubLen: Double) -> Rig {
        let px = -ballFwd
        var r = Rig()
        r.hip = CGPoint(x: px + p.hipDx - 5, y: 42)
        r.shoulder = CGPoint(x: r.hip.x + 6 + 0.5 * p.tilt, y: 66)
        r.headDx = p.headDx
        let aH = p.handA * .pi / 180
        let aC = p.clubA * .pi / 180
        // 긴 클럽일수록 그립을 몸쪽으로 — 어드레스·임팩트에서 헤드가 지면에 닿는 기하 유지
        let handD = max(16, p.handD - (clubLen - 31))
        r.grip = CGPoint(x: r.shoulder.x + sin(aH) * handD, y: r.shoulder.y - cos(aH) * handD)
        r.handTrail = CGPoint(x: r.grip.x + sin(aC) * 4, y: r.grip.y - cos(aC) * 4) // 그립 아래쪽에 겹쳐 잡는다
        r.clubPhi = aC
        r.clubLen = clubLen
        // 뒷발꿈치 들림 = 발끝으로 서기 (발이 뜨지 않는다)
        r.foot1 = CGPoint(x: px - (16 - p.heel * 0.45), y: min(p.heel * 0.25, 3.5))
        r.foot2 = CGPoint(x: px + 11, y: 0)
        r.knee1 = CGPoint(x: px - 13 + p.hipDx * 0.5, y: 22)
        r.knee2 = CGPoint(x: px + 6 + p.hipDx * 0.5, y: 21)
        return r
    }

    /// 걷기 — 같은 Rig 공간. groundDelta: 로컬 x(px) → 그 지점 지면의 로컬 y(px)
    static func walking(
        phase: Double,
        vPx: Double,
        clubLen: Double,
        flavor: WalkFlavor,
        groundDelta: (Double) -> Double
    ) -> Rig {
        let s1 = sin(phase)
        let c1 = cos(phase)
        let vAmp = min(1, vPx / 30)
        let bob = 1.6 * vAmp * abs(c1)
        let stride = 16.0 * (0.2 + 0.8 * vAmp) // 보폭 ∝ 속도 — 출발·도착 때 발이 모인다

        var r = Rig()
        r.hip = CGPoint(x: 0, y: 43.5 + bob)
        r.shoulder = CGPoint(x: 2 + 2.5 * vAmp, y: 67 + bob)
        r.headDx = 4
        let f1x = stride * s1
        let f2x = -stride * s1
        r.foot1 = CGPoint(x: f1x, y: groundDelta(f1x) + 7 * vAmp * max(0, c1))
        r.foot2 = CGPoint(x: f2x, y: groundDelta(f2x) + 7 * vAmp * max(0, -c1))
        r.knee1 = CGPoint(
            x: (r.hip.x + f1x) / 2 + 3,
            y: (r.hip.y + r.foot1.y) / 2 + 3 + 6 * vAmp * max(0, c1)
        )
        r.knee2 = CGPoint(
            x: (r.hip.x + f2x) / 2 + 3,
            y: (r.hip.y + r.foot2.y) / 2 + 3 + 6 * vAmp * max(0, -c1)
        )

        // 클럽 캐리: 기본은 옆에, 어깨 캐리 블렌드 시 어깨 위로
        let s = clubLen / 38
        var grip = CGPoint(x: -12, y: 47 + bob)
        var tip = CGPoint(x: grip.x - 16 * s, y: grip.y - 38 * s)
        if flavor.shoulder > 0 {
            let sGrip = CGPoint(x: r.shoulder.x + 9, y: r.shoulder.y - 3)
            let sTip = CGPoint(x: r.shoulder.x - 26 * s, y: r.shoulder.y + 15 * s)
            grip = mix(grip, sGrip, flavor.shoulder)
            tip = mix(tip, sTip, flavor.shoulder)
        }
        var phi = atan2(tip.x - grip.x, grip.y - tip.y)
        if let tw = flavor.twirl { // 손목 트월 — 완료 후에도 +2π를 유지해 되감기 없음
            phi += tw * 2 * .pi
        }
        r.grip = grip
        r.clubPhi = phi
        r.clubLen = clubLen
        r.handTrail = CGPoint(x: 5 - 8 * s1 * vAmp, y: 47 + bob) // 자유 팔 (다리 반대 위상)
        return r
    }
}

/// 스틱맨 렌더 — Rig 하나를 그린다. 로컬 (0,0) = 공이 놓인 지면 지점, y는 위쪽
/// 굵고 둥근 획의 회색 스틱맨. 두 팔: 리드 암(진하게) + 트레일 암(옅게 — 원근)
final class StickmanNode: SKNode {
    private let stickColor = NSColor(white: 0.88, alpha: 0.95)
    private let shaftColor = NSColor(white: 0.76, alpha: 0.9)
    private let clubHeadColor = NSColor(white: 0.85, alpha: 0.95)
    private let rimColor = NSColor(white: 0, alpha: 0.32) // 고대비 모드용 다크 림
    private let headShape = SKShapeNode(circleOfRadius: 10)
    private let bodyShape = SKShapeNode() // 척추+다리+리드 암 통합 경로
    private let trailArmShape = SKShapeNode() // 트레일 암 — 옅게 그려 원근을 만든다
    private let shaftShape = SKShapeNode()
    private let clubHeadShape = SKShapeNode()
    private let headRim = SKShapeNode(circleOfRadius: 11.2)
    private let bodyRim = SKShapeNode()
    private let trailArmRim = SKShapeNode()
    private let shaftRim = SKShapeNode()
    private let clubHeadRim = SKShapeNode()

    override init() {
        super.init()
        headShape.fillColor = stickColor
        headShape.strokeColor = .clear
        headRim.fillColor = rimColor
        headRim.strokeColor = .clear
        bodyShape.strokeColor = stickColor
        bodyShape.lineWidth = 6
        bodyShape.lineCap = .round
        bodyShape.lineJoin = .round
        bodyRim.strokeColor = rimColor
        bodyRim.lineWidth = 8.4
        bodyRim.lineCap = .round
        bodyRim.lineJoin = .round
        trailArmShape.strokeColor = stickColor.withAlphaComponent(0.55)
        trailArmShape.lineWidth = 5.5
        trailArmShape.lineCap = .round
        trailArmRim.strokeColor = rimColor
        trailArmRim.lineWidth = 7.7
        trailArmRim.lineCap = .round
        shaftShape.strokeColor = shaftColor
        shaftShape.lineWidth = 3
        shaftShape.lineCap = .round
        shaftRim.strokeColor = rimColor
        shaftRim.lineWidth = 5.2
        shaftRim.lineCap = .round
        clubHeadShape.strokeColor = clubHeadColor
        clubHeadShape.fillColor = clubHeadColor
        clubHeadShape.lineCap = .round
        clubHeadRim.strokeColor = rimColor
        clubHeadRim.fillColor = rimColor
        clubHeadRim.lineCap = .round
        for n in [trailArmRim, bodyRim, shaftRim, clubHeadRim, headRim, trailArmShape, bodyShape,
                  shaftShape, clubHeadShape, headShape] as [SKNode] {
            addChild(n)
        }
        applyContrast()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError()
    }

    /// 고대비 모드에서만 다크 림을 켠다 (기본은 원래의 가벼운 획)
    func applyContrast() {
        for r in [headRim, bodyRim, trailArmRim, shaftRim, clubHeadRim] as [SKNode] {
            r.isHidden = !Theme.highContrast
        }
    }

    func render(rig r: Rig, club: Club, visualLoft: Double, dir: Double) {
        func m(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x * dir, y: p.y)
        } // facing → 화면 미러
        let hip = m(r.hip)
        let shoulder = m(r.shoulder)
        let head = CGPoint(x: shoulder.x + dir * r.headDx, y: shoulder.y + 12)
        headShape.position = head
        headRim.position = head

        let f1 = m(r.foot1), f2 = m(r.foot2)
        let k1 = m(r.knee1), k2 = m(r.knee2)
        let grip = m(r.grip)

        let body = CGMutablePath()
        // 척추 (살짝 굽음)
        body.move(to: shoulder)
        body.addQuadCurve(
            to: hip,
            control: CGPoint(x: (shoulder.x + hip.x) / 2 - dir * 2.5, y: (shoulder.y + hip.y) / 2)
        )
        // 다리 둘 (무릎 제어점 포함)
        body.move(to: hip)
        body.addQuadCurve(to: f1, control: k1)
        body.move(to: hip)
        body.addQuadCurve(to: f2, control: k2)
        // 리드 암
        body.move(to: shoulder)
        body.addQuadCurve(
            to: grip,
            control: CGPoint(x: (shoulder.x + grip.x) / 2 + dir * 2, y: (shoulder.y + grip.y) / 2 + 2)
        )
        bodyShape.path = body
        bodyRim.path = body

        // 트레일 암 — 살짝 뒤 어깨에서, 팔꿈치는 몸쪽으로 굽는다
        let hTrail = m(r.handTrail)
        let tShoulder = CGPoint(x: shoulder.x - dir * 3, y: shoulder.y + 2)
        let trail = CGMutablePath()
        trail.move(to: tShoulder)
        trail.addQuadCurve(
            to: hTrail,
            control: CGPoint(x: (tShoulder.x + hTrail.x) / 2 + dir * 1.5, y: (tShoulder.y + hTrail.y) / 2 - 1.5)
        )
        trailArmShape.path = trail
        trailArmRim.path = trail

        // 클럽
        let tip = CGPoint(x: grip.x + sin(r.clubPhi) * r.clubLen * dir, y: grip.y - cos(r.clubPhi) * r.clubLen)
        let shaft = CGMutablePath()
        shaft.move(to: grip)
        shaft.addLine(to: tip)
        shaftShape.path = shaft
        shaftRim.path = shaft

        clubHeadShape.path = clubHeadPath(club: club, visualLoft: visualLoft, tip: tip, phi: r.clubPhi, dir: dir)
        // 블레이드 굵기도 로프트 연속 함수 (아이언 4 → SW 5)
        clubHeadShape.lineWidth = club.cat == .putter
            ? 5
            : club.cat == .wood ? 4 : 4 + max(0, visualLoft - 42) * 0.0714
        clubHeadRim.path = clubHeadShape.path
        clubHeadRim.lineWidth = clubHeadShape.lineWidth + 2.2
    }

    /// 클럽 헤드 디자인 — 숫자 대신 생김새로 클럽을 구분한다 (심플·둥근 획)
    /// 기하는 전부 스무딩된 visualLoft로 구동 — 클럽 변경 시 모양이 미끄러지듯 변한다
    private func clubHeadPath(club: Club, visualLoft: Double, tip: CGPoint, phi: Double, dir: Double) -> CGPath {
        // 샤프트 방향(along)·타격 방향(perp), SpriteKit y-up 기준
        let along = CGVector(dx: sin(phi) * dir, dy: -cos(phi))
        let perp = CGVector(dx: cos(phi) * dir, dy: sin(phi))
        let p = CGMutablePath()
        switch club.cat {
        case .wood: // 둥근 덩어리 헤드 — 드라이버가 가장 크다
            let w = 16 - (visualLoft - 10.5) * 0.45 // DR 16 · 3W 14 · 5W 12.6
            let h = w * 0.68
            let c = CGPoint(x: tip.x + perp.dx * 4, y: tip.y + perp.dy * 4)
            var transform = CGAffineTransform(translationX: c.x, y: c.y)
                .rotated(by: atan2(perp.dy, perp.dx))
            if let ellipse = CGPath(
                ellipseIn: CGRect(x: -w / 2, y: -h / 2, width: w, height: h),
                transform: &transform
            ) as CGPath? {
                p.addPath(ellipse)
            }
        case .iron, .wedge: // 블레이드 — 로프트만큼 페이스가 젖혀지고(9I>7I), 웨지로 갈수록 길어진다
            let len = 9 + max(0, visualLoft - 42) * 0.107 // 아이언 9 → SW 10.5
            let lo = visualLoft * 0.9 * .pi / 180
            let bx = (perp.dx * cos(lo) - along.dx * sin(lo)) * len
            let by = (perp.dy * cos(lo) - along.dy * sin(lo)) * len
            p.move(to: tip)
            p.addLine(to: CGPoint(x: tip.x + bx, y: tip.y + by))
        case .putter: // 납작한 블록 + 얼라인먼트 점 하나
            p.move(to: CGPoint(x: tip.x - perp.dx * 3, y: tip.y - perp.dy * 3))
            p.addLine(to: CGPoint(x: tip.x + perp.dx * 7, y: tip.y + perp.dy * 7))
            let mark = CGPoint(x: tip.x + perp.dx * 2 - along.dx * 5, y: tip.y + perp.dy * 2 - along.dy * 5)
            p.addEllipse(in: CGRect(x: mark.x - 0.9, y: mark.y - 0.9, width: 1.8, height: 1.8))
        }
        return p
    }
}
