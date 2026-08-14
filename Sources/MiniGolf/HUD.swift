import SpriteKit

/// "조용한 계기판" 디자인 — 상자 없이 타이포그래피만으로 만드는 초심플 HUD.
/// 가는 서체 + 자간 + 1px 미세 그림자로 어떤 배경에서도 조용히 읽힌다.
enum HUDFont {
    static let light = "AppleSDGothicNeo-Light"
    static let regular = "AppleSDGothicNeo-Regular"
    static let medium = "AppleSDGothicNeo-Medium"
    static let semibold = "AppleSDGothicNeo-SemiBold"
}

/// 상자 없는 텍스트: 본문 + 사방 헤일로 그림자 — 밝은 배경에서도 상자 없이 읽힌다
final class GlassLabel: SKNode {
    /// 사방 확산 + 우하단 깊이 한 겹 (배경 무관 대비, FINDING-001)
    private static let haloOffsets: [(CGFloat, CGFloat, CGFloat)] = [
        (-1.2, 1.2, 0.28), (1.2, 1.2, 0.28), (-1.2, -1.2, 0.28), (1.2, -1.2, 0.28), (1.0, -1.4, 0.45),
    ]

    private var haloLabels: [SKLabelNode] = []
    private let mainLabel = SKLabelNode()
    private let font: String
    private let size: CGFloat
    private let textAlpha: CGFloat
    private let kern: CGFloat

    init(
        font: String,
        size: CGFloat,
        alpha: CGFloat = 1,
        align: SKLabelHorizontalAlignmentMode = .center,
        kern: CGFloat = 0.6
    ) {
        self.font = font
        self.size = size
        textAlpha = alpha
        self.kern = kern
        super.init()
        for (dx, dy, _) in Self.haloOffsets {
            let l = SKLabelNode()
            l.horizontalAlignmentMode = align
            l.verticalAlignmentMode = .top
            l.position = CGPoint(x: dx, y: dy)
            haloLabels.append(l)
            addChild(l)
        }
        mainLabel.horizontalAlignmentMode = align
        mainLabel.verticalAlignmentMode = .top
        addChild(mainLabel)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError()
    }

    func setText(_ text: String) {
        mainLabel.attributedText = attributed(text, color: NSColor(white: 0.98, alpha: textAlpha))
        for (l, offset) in zip(haloLabels, Self.haloOffsets) {
            l.attributedText = attributed(text, color: NSColor(white: 0, alpha: offset.2))
        }
    }

    private func attributed(_ text: String, color: NSColor) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont(name: font, size: size) ?? NSFont.systemFont(ofSize: size),
            .foregroundColor: color,
            .kern: kern,
        ])
    }
}

/// 라운드 종료 스코어카드 — 아주 옅은 스크림 위 텍스트 컬럼
final class ScorecardNode: SKNode {
    private let scrim = SKShapeNode()
    private var lines: [GlassLabel] = []

    override init() {
        super.init()
        scrim.fillColor = NSColor(white: 0, alpha: 0.32)
        scrim.strokeColor = .clear
        addChild(scrim)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError()
    }

    func show(rows: [String], title: String, footer: String) {
        for l in lines {
            l.removeFromParent()
        }
        lines = []
        let all = [(title, HUDFont.semibold, CGFloat(20))]
            + rows.map { ($0, HUDFont.regular, CGFloat(13.5)) }
            + [(footer, HUDFont.medium, CGFloat(14))]
        let lineH: CGFloat = 27
        let h = CGFloat(all.count) * lineH + 44
        var y = h / 2 - 34
        for (text, font, size) in all {
            let label = GlassLabel(font: font, size: size, alpha: font == HUDFont.regular ? 0.82 : 1)
            label.setText(text)
            label.position = CGPoint(x: 0, y: y)
            addChild(label)
            lines.append(label)
            y -= lineH
        }
        scrim.path = CGPath(
            roundedRect: CGRect(x: -190, y: -h / 2, width: 380, height: h),
            cornerWidth: 22, cornerHeight: 22, transform: nil
        )
        isHidden = false
    }

    func hide() {
        isHidden = true
    }
}
