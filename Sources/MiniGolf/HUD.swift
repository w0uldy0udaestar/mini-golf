import SpriteKit

/// 어두운 반투명 칩 배경 + 텍스트 — 밝은 데스크탑 위에서도 읽히는 HUD (프로토타입 디자인)
final class ChipNode: SKNode {
    enum Align { case left, right, center }

    private let bg = SKShapeNode()
    private let mainLabel = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
    private let subLabel = SKLabelNode(fontNamed: "AppleSDGothicNeo-Medium")
    private let align: Align
    private let padX: CGFloat = 14
    private let padY: CGFloat = 9

    init(align: Align, mainSize: CGFloat = 15, subSize: CGFloat = 12) {
        self.align = align
        super.init()
        bg.fillColor = NSColor(white: 0.09, alpha: 0.82)
        bg.strokeColor = NSColor(white: 1, alpha: 0.12)
        bg.lineWidth = 1
        mainLabel.fontSize = mainSize
        mainLabel.fontColor = NSColor(white: 0.93, alpha: 1)
        subLabel.fontSize = subSize
        subLabel.fontColor = NSColor(white: 0.93, alpha: 0.68)
        for n in [bg, mainLabel, subLabel] as [SKNode] {
            addChild(n)
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError()
    }

    /// position 기준: left→왼쪽 위 모서리, right→오른쪽 위 모서리, center→가운데 위
    func setText(_ main: String, sub: String? = nil) {
        mainLabel.text = main
        subLabel.text = sub
        subLabel.isHidden = sub == nil
        let mainW = mainLabel.frame.width
        let subW = sub == nil ? 0 : subLabel.frame.width
        let w = max(mainW, subW) + padX * 2
        let lineH = mainLabel.fontSize + 6
        let subH = sub == nil ? 0 : subLabel.fontSize + 6
        let h = lineH + subH + padY * 2

        let anchorX: CGFloat = switch align {
        case .left: 0
        case .right: -w
        case .center: -w / 2
        }
        bg.path = CGPath(
            roundedRect: CGRect(x: anchorX, y: -h, width: w, height: h),
            cornerWidth: 12,
            cornerHeight: 12,
            transform: nil
        )

        let cx = anchorX + w / 2
        mainLabel.horizontalAlignmentMode = .center
        subLabel.horizontalAlignmentMode = .center
        mainLabel.position = CGPoint(x: cx, y: -padY - mainLabel.fontSize)
        subLabel.position = CGPoint(x: cx, y: -padY - lineH - subLabel.fontSize)
    }
}

/// 여러 줄 스코어카드 칩 (라운드 종료 화면)
final class ScorecardNode: SKNode {
    private let bg = SKShapeNode()
    private var lines: [SKLabelNode] = []

    override init() {
        super.init()
        bg.fillColor = NSColor(white: 0.08, alpha: 0.92)
        bg.strokeColor = NSColor(white: 1, alpha: 0.14)
        bg.lineWidth = 1
        addChild(bg)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError()
    }

    func show(rows: [String], title: String, footer: String) {
        for l in lines {
            l.removeFromParent()
        }
        lines = []
        let all = [title] + rows + [footer]
        let lineH: CGFloat = 24
        let h = CGFloat(all.count) * lineH + 30
        var w: CGFloat = 0
        for (i, text) in all.enumerated() {
            let label = SKLabelNode(fontNamed: i == 0 ? "AppleSDGothicNeo-Bold" : "AppleSDGothicNeo-Medium")
            label.text = text
            label.fontSize = i == 0 ? 19 : 14
            label.fontColor = NSColor(white: 0.93, alpha: i == 0 || i == all.count - 1 ? 1 : 0.78)
            label.horizontalAlignmentMode = .center
            label.position = CGPoint(x: 0, y: h / 2 - 24 - CGFloat(i) * lineH)
            addChild(label)
            lines.append(label)
            w = max(w, label.frame.width)
        }
        w += 68
        bg.path = CGPath(
            roundedRect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h),
            cornerWidth: 18,
            cornerHeight: 18,
            transform: nil
        )
        isHidden = false
    }

    func hide() {
        isHidden = true
    }
}
