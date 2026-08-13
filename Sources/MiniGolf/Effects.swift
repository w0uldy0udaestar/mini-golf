import GolfCore
import SpriteKit

/// 미세 연출 — "조용한 계기판" 결: 점과 헤어라인만 쓰는 절제된 파티클
enum FX {
    /// 착지·타격 먼지 — 라이별 색의 작은 점 몇 개가 튀었다 가라앉는다
    static func dust(on parent: SKNode, at p: CGPoint, surface: Surface, intensity: Double) {
        let color = switch surface {
        case .bunker: NSColor(red: 0.82, green: 0.78, blue: 0.7, alpha: 0.7)
        case .rough: NSColor(white: 0.85, alpha: 0.5)
        default: NSColor(white: 0.95, alpha: 0.55)
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

    /// 입수 파문 — 수면에서 퍼지는 동심 타원 두 개
    static func ripple(on parent: SKNode, at p: CGPoint) {
        for i in 0 ..< 2 {
            let ring = SKShapeNode(ellipseOf: CGSize(width: 18, height: 5))
            ring.strokeColor = NSColor(red: 0.62, green: 0.71, blue: 0.78, alpha: 0.7)
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
