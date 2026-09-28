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
        mark.zPosition = 1.5
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
