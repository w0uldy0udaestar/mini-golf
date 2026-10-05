import GolfCore
import SpriteKit

/// 미세 연출 — "조용한 계기판" 결: 점과 헤어라인만 쓰는 절제된 파티클
enum FX {
    /// 착지·타격 먼지 — 라이별 색의 작은 점 몇 개가 튀었다 가라앉는다
    static func dust(on parent: SKNode, at p: CGPoint, surface: Surface, intensity: Double) {
        let color = switch surface {
        case .bunker: Palette.bunkerSand.withAlphaComponent(0.7)
        case .rough: Palette.roughGray.withAlphaComponent(0.5)
        default: Palette.hairline.withAlphaComponent(0.55) // 지형에서 튀는 먼지 = 지형선 색
        }
        let count = 2 + Int(intensity * 3)
        for _ in 0 ..< count {
            let dot = SKShapeNode(circleOfRadius: CGFloat.random(in: 0.9 ... 1.5))
            dot.fillColor = color
            dot.strokeColor = .clear
            dot.position = p
            parent.addChild(dot)
            let dx = CGFloat.random(in: -14 ... 14)
            let dy = CGFloat.random(in: 10 ... 30) * CGFloat(0.5 + intensity * 0.7)
            let up = SKAction.moveBy(x: dx * 0.6, y: dy, duration: 0.16)
            up.timingMode = .easeOut
            let down = SKAction.moveBy(x: dx * 0.4, y: -dy * 0.6, duration: 0.26)
            down.timingMode = .easeIn
            dot.run(.sequence([
                .group([.sequence([up, down]), .fadeOut(withDuration: 0.42)]),
                .removeFromParent(),
            ]))
        }
    }

    /// 디봇 (2026-09-28 사용자 요청): 아이언·웨지 풀샷이 잔디를 파낸다 — 덩어리 몇 개가 샷 방향으로 낮게 날아가 굴러 떨어진다(0.7s).
    /// 페어웨이는 지형선 색, 러프는 러프 색 — 팔레트 밖의 색은 쓰지 않는다
    static func divot(on parent: SKNode, at p: CGPoint, dir: Double, surface: Surface, intensity: Double) {
        let color = surface == .rough ? Palette.roughGray.withAlphaComponent(0.85) : Palette.hairline
            .withAlphaComponent(0.8)
        let count = 3 + Int(intensity * 3)
        for i in 0 ..< count {
            let w = CGFloat.random(in: 4 ... 8), h = CGFloat.random(in: 2.2 ... 3.5)
            let clod = SKShapeNode(rectOf: CGSize(width: w, height: h), cornerRadius: h / 2)
            clod.fillColor = color
            clod.strokeColor = .clear
            clod.position = CGPoint(x: p.x + CGFloat(dir) * 2, y: p.y + 1)
            clod.zPosition = 5
            parent.addChild(clod)
            let dx = CGFloat(dir) * CGFloat.random(in: 16 ... 40) * CGFloat(0.6 + intensity * 0.5)
            let dy = CGFloat.random(in: 9 ... 20)
            let up = SKAction.moveBy(x: dx * 0.55, y: dy, duration: 0.2)
            up.timingMode = .easeOut
            let down = SKAction.moveBy(x: dx * 0.45, y: -dy - 1, duration: 0.3)
            down.timingMode = .easeIn
            let spin = SKAction.rotate(byAngle: CGFloat(dir) * CGFloat.random(in: -2.5 ... -0.8), duration: 0.5)
            clod.run(.sequence([
                .group([.sequence([up, down]), spin]),
                .wait(forDuration: 0.25 + Double(i) * 0.05),
                .fadeOut(withDuration: 0.35),
                .removeFromParent(),
            ]))
        }
    }

    /// 디봇 자국 — 공 자리에서 샷 방향으로 파인 짧은 타원. 호출측이 terrainNode에 얹어 홀 전환 때 함께 지워진다.
    /// 지형선(0.94)보다 어둡고 두꺼운 중회색 — 어두운 배경에서도 밝은 배경에서도 '파인 자국'으로 읽힌다
    static func divotMark(at p: CGPoint, dir: Double, intensity: Double) -> SKNode {
        let mark = SKShapeNode(ellipseOf: CGSize(width: 7 + 6 * intensity, height: 3.5))
        mark.fillColor = NSColor(white: 0.62, alpha: 0.9)
        mark.strokeColor = .clear
        mark.position = CGPoint(x: p.x + CGFloat(dir) * (3 + 2 * intensity), y: p.y - 0.3)
        mark.zPosition = 0 // terrainNode의 마지막 자식 — 지형 위, 씬의 공·스틱맨 아래 (전역 z가 형제 순서보다 우선, 리뷰 #8)
        return mark
    }

    /// 입수 파문 — 수면에서 퍼지는 동심 타원 두 개
    static func ripple(on parent: SKNode, at p: CGPoint) {
        for i in 0 ..< 2 {
            let ring = SKShapeNode(ellipseOf: CGSize(width: 18, height: 5))
            ring.strokeColor = Palette.waterBlue.withAlphaComponent(0.7)
            ring.lineWidth = 1.2
            ring.fillColor = .clear
            ring.position = p
            ring.setScale(0.3)
            parent.addChild(ring)
            ring.run(.sequence([
                .wait(forDuration: Double(i) * 0.16),
                .group([.scale(to: 1.6, duration: 0.7), .fadeOut(withDuration: 0.7)]),
                .removeFromParent(),
            ]))
        }
    }

    /// 홀인 — 컵 위로 점 몇 개가 톡 튀고, 깃발이 살짝 흔들린다
    /// 퍼팅 접촉 링 — 페이스가 공에 닿는 순간 공 뒤에서 작은 고리가 퍼졌다 사라진다 (0.18s). 임팩트 스쿼시와 함께 '맞았다'를 읽히게
    static func contactTick(on parent: SKNode, at p: CGPoint) {
        let ring = SKShapeNode(circleOfRadius: 3)
        ring.strokeColor = NSColor(white: 1, alpha: 0.7)
        ring.lineWidth = 1
        ring.fillColor = .clear
        ring.position = p
        ring.zPosition = 6
        parent.addChild(ring)
        ring.run(.sequence([
            .group([.scale(to: 3.2, duration: 0.18), .fadeOut(withDuration: 0.18)]),
            .removeFromParent(),
        ]))
    }

    /// 음표 — 휘파람·콧노래의 '소리'를 그림으로 (2026-10-05 M6: 사용자가 사운드를 끄고 플레이해 소리 기반 잔동작이 전달되지 않았다).
    /// 머리 옆에서 떠올라 흔들리며 사라진다(1.3s). index 홀수는 8분음표 하나, 짝수는 이어진 두 개 — 굵고 둥근 선 규칙, 색은 스틱맨과 같은 밝은 회백
    static func note(on parent: SKNode, at p: CGPoint, index: Int, dir: Double) {
        let node = SKNode()
        let color = NSColor(white: 0.96, alpha: 0.95)
        func head(_ x: CGFloat, _ y: CGFloat) -> SKShapeNode {
            let h = SKShapeNode(ellipseOf: CGSize(width: 6.4, height: 4.6))
            h.fillColor = color
            h.strokeColor = .clear
            h.zRotation = 0.35
            h.position = CGPoint(x: x, y: y)
            return h
        }
        let lines = CGMutablePath()
        if index % 2 == 1 { // ♪
            node.addChild(head(0, 0))
            lines.move(to: CGPoint(x: 2.7, y: 0.8))
            lines.addLine(to: CGPoint(x: 2.7, y: 14))
            lines.addQuadCurve(to: CGPoint(x: 8, y: 8), control: CGPoint(x: 8.5, y: 12.5))
        } else { // ♫
            node.addChild(head(0, 0))
            node.addChild(head(10, 2))
            lines.move(to: CGPoint(x: 2.7, y: 0.8))
            lines.addLine(to: CGPoint(x: 2.7, y: 13))
            lines.addLine(to: CGPoint(x: 12.7, y: 15))
            lines.addLine(to: CGPoint(x: 12.7, y: 2.8))
        }
        let stroke = SKShapeNode(path: lines)
        stroke.strokeColor = color
        stroke.lineWidth = 1.6
        stroke.lineCap = .round
        stroke.lineJoin = .round
        stroke.fillColor = .clear
        node.addChild(stroke)
        if Theme.highContrast { // 밝은 배경: 어두운 받침 획 — 줄기와 머리 모두
            let under = SKShapeNode(path: lines)
            under.strokeColor = NSColor(white: 0, alpha: 0.4)
            under.lineWidth = 3.4
            under.lineCap = .round
            under.zPosition = -1
            node.addChild(under)
            for h in node.children.compactMap({ $0 as? SKShapeNode }) where h.fillColor == color {
                h.strokeColor = NSColor(white: 0, alpha: 0.4)
                h.lineWidth = 1.2
            }
        }
        let d = CGFloat(dir)
        node.position = CGPoint(x: p.x + d * (12 + CGFloat(index % 3) * 5), y: p.y + 10)
        node.alpha = 0
        node.setScale(0.75)
        node.zPosition = 8
        parent.addChild(node)
        let sway = SKAction.sequence([
            .moveBy(x: d * 7, y: 11, duration: 0.42),
            .moveBy(x: -d * 3, y: 11, duration: 0.42),
            .moveBy(x: d * 6, y: 10, duration: 0.46),
        ])
        node.run(.sequence([
            .group([
                sway,
                .scale(to: 1.15, duration: 1.3),
                .sequence([.fadeIn(withDuration: 0.12), .wait(forDuration: 0.75), .fadeOut(withDuration: 0.43)]),
            ]),
            .removeFromParent(),
        ]))
    }

    /// 릴리스 착지 — 앞으로 낮게 쓸리는 먼지 줄기 3개 (스핀이 남지 않고 굴러간다)
    static func skid(on parent: SKNode, at p: CGPoint, dir: Double, surface: Surface, intensity: Double) {
        let color = surface == .rough ? Palette.roughGray.withAlphaComponent(0.55) : Palette.hairline
            .withAlphaComponent(0.6)
        for k in 0 ..< 3 {
            let dot = SKShapeNode(circleOfRadius: 1.1)
            dot.fillColor = color
            dot.strokeColor = .clear
            dot.position = CGPoint(x: p.x + CGFloat(dir) * CGFloat(k) * 3, y: p.y + 1.5)
            parent.addChild(dot)
            let dx = CGFloat(dir) * CGFloat(16 + 12 * intensity) * CGFloat(1 + Double(k) * 0.35)
            let move = SKAction.moveBy(x: dx, y: CGFloat(3 + k * 2), duration: 0.28)
            move.timingMode = .easeOut
            dot.run(.sequence([.group([move, .fadeOut(withDuration: 0.3)]), .removeFromParent()]))
        }
    }

    /// 백업 착지 — 역회전이 물고 뒤로 감기는 순간: 작은 점 3개가 진행 반대쪽·위로 튀고, 접지 링이 한 번
    static func backspin(on parent: SKNode, at p: CGPoint, dir: Double) {
        contactTick(on: parent, at: CGPoint(x: p.x, y: p.y + 4))
        for k in 0 ..< 3 {
            let dot = SKShapeNode(circleOfRadius: 1.2)
            dot.fillColor = NSColor(white: 1, alpha: 0.75)
            dot.strokeColor = .clear
            dot.position = CGPoint(x: p.x, y: p.y + 2)
            parent.addChild(dot)
            let dx = -CGFloat(dir) * CGFloat(8 + k * 5)
            let up = SKAction.moveBy(x: dx * 0.6, y: CGFloat(9 + k * 3), duration: 0.14)
            up.timingMode = .easeOut
            let down = SKAction.moveBy(x: dx * 0.4, y: -CGFloat(6 + k * 2), duration: 0.22)
            down.timingMode = .easeIn
            dot.run(.sequence([.group([.sequence([up, down]), .fadeOut(withDuration: 0.36)]), .removeFromParent()]))
        }
    }

    static func holePop(on parent: SKNode, at p: CGPoint) {
        for _ in 0 ..< 3 {
            let dot = SKShapeNode(circleOfRadius: 1.2)
            dot.fillColor = NSColor(white: 0.98, alpha: 0.8)
            dot.strokeColor = .clear
            dot.position = p
            parent.addChild(dot)
            let dx = CGFloat.random(in: -8 ... 8)
            let up = SKAction.moveBy(x: dx, y: CGFloat.random(in: 12 ... 22), duration: 0.14)
            up.timingMode = .easeOut
            let down = SKAction.moveBy(x: dx * 0.5, y: -8, duration: 0.2)
            down.timingMode = .easeIn
            dot.run(.sequence([
                .group([.sequence([up, down]), .fadeOut(withDuration: 0.38)]),
                .removeFromParent(),
            ]))
        }
    }

    static func flagWave(_ flag: SKNode) {
        flag.removeAllActions()
        flag.run(.sequence([
            .rotate(byAngle: 0.045, duration: 0.09),
            .rotate(byAngle: -0.08, duration: 0.14),
            .rotate(byAngle: 0.05, duration: 0.14),
            .rotate(byAngle: -0.015, duration: 0.12),
        ]))
    }
}
