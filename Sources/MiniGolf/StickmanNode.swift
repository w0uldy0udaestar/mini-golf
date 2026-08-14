import GolfCore
import SpriteKit

/// 스틱맨 렌더 리그 — 로컬 좌표 (0,0) = 공이 놓인 지면 지점, y는 위쪽
/// 굵고 둥근 획의 회색 스틱맨 (포인트 컬러는 깃발 하나뿐이라는 디자인 원칙)
final class StickmanNode: SKNode {
    private let stickColor = NSColor(white: 0.88, alpha: 0.95)
    private let shaftColor = NSColor(white: 0.76, alpha: 0.9)
    private let clubHeadColor = NSColor(white: 0.85, alpha: 0.95)
    private let rimColor = NSColor(white: 0, alpha: 0.32) // 밝은 배경 대비용 다크 림
    private let headShape = SKShapeNode(circleOfRadius: 10)
    private let bodyShape = SKShapeNode() // 척추+다리+팔 통합 경로
    private let shaftShape = SKShapeNode()
    private let clubHeadShape = SKShapeNode()
    // 언더스트로크 트윈 — 같은 경로를 어둡고 굵게 한 겹 아래 (FINDING-001)
    private let headRim = SKShapeNode(circleOfRadius: 11.2)
    private let bodyRim = SKShapeNode()
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
        for n in [bodyRim, shaftRim, clubHeadRim, headRim, bodyShape, shaftShape, clubHeadShape,
                  headShape] as [SKNode] {
            addChild(n)
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError()
    }

    /// 포즈 리그 (조준·스윙·피니시)
    func update(pose p: Pose, dir: Double, ballFwd: Double, clubCat: ClubCategory) {
        let px = -dir * ballFwd // 스탠스 중심 (공 = 원점)
        let hip = CGPoint(x: px + dir * (p.hipDx - 5), y: 42)
        let shoulder = CGPoint(x: hip.x + dir * (6 + 0.5 * p.tilt), y: 66)
        let head = CGPoint(x: shoulder.x + dir * p.headDx, y: shoulder.y + 12)
        let aH = p.handA * .pi / 180
        let aC = p.clubA * .pi / 180
        let hands = CGPoint(x: shoulder.x + sin(aH) * p.handD * dir, y: shoulder.y - cos(aH) * p.handD)
        let clubLen = 31.0
        let tip = CGPoint(x: hands.x + sin(aC) * clubLen * dir, y: hands.y - cos(aC) * clubLen)

        headShape.position = head
        headRim.position = head

        let body = CGMutablePath()
        // 척추 (살짝 굽음)
        body.move(to: shoulder)
        body.addQuadCurve(to: hip, control: CGPoint(x: (shoulder.x + hip.x) / 2 - dir * 3, y: (shoulder.y + hip.y) / 2))
        // 다리: 발 위치 고정, 힙 이동으로 체중 표현, 뒷발꿈치 들림
        body.move(to: hip)
        body.addQuadCurve(
            to: CGPoint(x: px - dir * 16, y: p.heel),
            control: CGPoint(x: px - dir * 13 + dir * p.hipDx * 0.5, y: 22)
        )
        body.move(to: hip)
        body.addQuadCurve(
            to: CGPoint(x: px + dir * 11, y: 0),
            control: CGPoint(x: px + dir * 6 + dir * p.hipDx * 0.5, y: 21)
        )
        // 팔 두 개 (handD가 줄면 접힌 느낌)
        body.move(to: shoulder)
        body.addQuadCurve(
            to: hands,
            control: CGPoint(x: (shoulder.x + hands.x) / 2 + dir * 2, y: (shoulder.y + hands.y) / 2 + 2)
        )
        body.move(to: CGPoint(x: shoulder.x, y: shoulder.y + 2.5))
        body.addQuadCurve(
            to: hands,
            control: CGPoint(x: (shoulder.x + hands.x) / 2 + dir * 4, y: (shoulder.y + hands.y) / 2)
        )
        bodyShape.path = body
        bodyRim.path = body

        let shaft = CGMutablePath()
        shaft.move(to: hands)
        shaft.addLine(to: tip)
        shaftShape.path = shaft
        shaftRim.path = shaft

        clubHeadShape.path = clubHeadPath(cat: clubCat, tip: tip, phi: aC, dir: dir)
        clubHeadShape.lineWidth = clubCat == .putter ? 6 : (clubCat == .wedge ? 5 : 4)
        clubHeadRim.path = clubHeadShape.path
        clubHeadRim.lineWidth = clubHeadShape.lineWidth + 2.2
    }

    /// 걷기 리그 — 발이 지면을 딛는 보행. groundDelta: 로컬 x(px) → 그 지점 지면의 로컬 y(px)
    func updateWalking(
        phase: Double,
        vPx: Double,
        dir: Double,
        clubCat: ClubCategory,
        groundDelta: (CGFloat) -> CGFloat
    ) {
        let s1 = sin(phase)
        let c1 = cos(phase)
        let vAmp = min(1, vPx / 30)
        let bob = 1.6 * vAmp * abs(c1)
        let stride = 16.0

        let hip = CGPoint(x: 0, y: 45 + bob)
        let shoulder = CGPoint(x: dir * (2 + 2.5 * vAmp), y: 68 + bob)
        let head = CGPoint(x: shoulder.x + dir * 4, y: shoulder.y + 12)
        headShape.position = head
        headRim.position = head

        let f1x = dir * stride * s1
        let f2x = -dir * stride * s1
        let f1 = CGPoint(x: f1x, y: groundDelta(f1x) + 7 * vAmp * max(0, c1))
        let f2 = CGPoint(x: f2x, y: groundDelta(f2x) + 7 * vAmp * max(0, -c1))

        let body = CGMutablePath()
        body.move(to: shoulder)
        body.addQuadCurve(
            to: hip,
            control: CGPoint(x: (shoulder.x + hip.x) / 2 - dir * 1.5, y: (shoulder.y + hip.y) / 2)
        )
        body.move(to: hip)
        body.addQuadCurve(
            to: f1,
            control: CGPoint(x: (hip.x + f1.x) / 2 + dir * 3, y: (hip.y + f1.y) / 2 + 3 + 6 * vAmp * max(0, c1))
        )
        body.move(to: hip)
        body.addQuadCurve(
            to: f2,
            control: CGPoint(x: (hip.x + f2.x) / 2 + dir * 3, y: (hip.y + f2.y) / 2 + 3 + 6 * vAmp * max(0, -c1))
        )
        // 클럽 든 팔 + 자유 팔 (다리 반대 위상)
        let grip = CGPoint(x: -dir * 12, y: 51 + bob)
        body.move(to: shoulder)
        body.addQuadCurve(
            to: grip,
            control: CGPoint(x: (shoulder.x + grip.x) / 2 - dir * 3, y: (shoulder.y + grip.y) / 2 - 2)
        )
        let freeHand = CGPoint(x: dir * (5 - 8 * s1 * vAmp), y: 51 + bob)
        body.move(to: shoulder)
        body.addQuadCurve(
            to: freeHand,
            control: CGPoint(x: (shoulder.x + freeHand.x) / 2 + dir * 2, y: (shoulder.y + freeHand.y) / 2 - 3)
        )
        bodyShape.path = body
        bodyRim.path = body

        // 클럽: 뒤로 비스듬히 든 채 이동
        let tip = CGPoint(x: grip.x - dir * 16, y: 13 + bob)
        let shaft = CGMutablePath()
        shaft.move(to: grip)
        shaft.addLine(to: tip)
        shaftShape.path = shaft
        shaftRim.path = shaft
        let carryPhi = atan2((tip.x - grip.x) * dir, grip.y - tip.y)
        clubHeadShape.path = clubHeadPath(cat: clubCat, tip: tip, phi: carryPhi, dir: dir)
        clubHeadRim.path = clubHeadShape.path
        clubHeadRim.lineWidth = clubHeadShape.lineWidth + 2.2
    }

    /// 클럽 헤드 디자인 — 숫자 대신 생김새로 클럽을 구분한다
    private func clubHeadPath(cat: ClubCategory, tip: CGPoint, phi: Double, dir: Double) -> CGPath {
        // 샤프트 방향(along)·타격 방향(perp), SpriteKit y-up 기준
        let along = CGVector(dx: sin(phi) * dir, dy: -cos(phi))
        let perp = CGVector(dx: cos(phi) * dir, dy: sin(phi))
        let p = CGMutablePath()
        switch cat {
        case .wood: // 크고 둥근 덩어리 헤드
            let c = CGPoint(x: tip.x + perp.dx * 4, y: tip.y + perp.dy * 4)
            var transform = CGAffineTransform(translationX: c.x, y: c.y)
                .rotated(by: atan2(perp.dy, perp.dx))
            if let ellipse = CGPath(
                ellipseIn: CGRect(x: -7.5, y: -5, width: 15, height: 10),
                transform: &transform
            ) as CGPath? {
                p.addPath(ellipse)
            }
        case .iron: // 얇은 블레이드
            p.move(to: tip)
            p.addLine(to: CGPoint(x: tip.x + perp.dx * 9 + along.dx * 3, y: tip.y + perp.dy * 9 + along.dy * 3))
        case .wedge: // 넓고 젖혀진 블레이드
            p.move(to: tip)
            p.addLine(to: CGPoint(x: tip.x + perp.dx * 10 - along.dx * 5, y: tip.y + perp.dy * 10 - along.dy * 5))
        case .putter: // 납작한 블록
            p.move(to: CGPoint(x: tip.x - perp.dx * 3, y: tip.y - perp.dy * 3))
            p.addLine(to: CGPoint(x: tip.x + perp.dx * 7, y: tip.y + perp.dy * 7))
        }
        return p
    }
}
