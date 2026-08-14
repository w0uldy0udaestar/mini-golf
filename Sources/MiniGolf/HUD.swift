import SpriteKit

/// "조용한 계기판" 디자인 — 상자 없이 타이포그래피만으로 만드는 초심플 HUD.
/// 가는 서체 + 자간 + 1px 미세 그림자로 어떤 배경에서도 조용히 읽힌다.
enum HUDFont {
    static let light = "AppleSDGothicNeo-Light"
    static let regular = "AppleSDGothicNeo-Regular"
    static let medium = "AppleSDGothicNeo-Medium"
    static let semibold = "AppleSDGothicNeo-SemiBold"
}

/// 상자 없는 텍스트: 본문 + 오프셋 그림자 (기본). 고대비 모드에서만 사방 헤일로가 추가로 켜진다
final class GlassLabel: SKNode {
    private static let haloOffsets: [(CGFloat, CGFloat)] = [(-1.2, 1.2), (1.2, 1.2), (-1.2, -1.2), (1.2, -1.2)]

    private var haloLabels: [SKLabelNode] = []
    private let shadowLabel = SKLabelNode()
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
        for (dx, dy) in Self.haloOffsets {
            let l = SKLabelNode()
            l.horizontalAlignmentMode = align
            l.verticalAlignmentMode = .top
            l.position = CGPoint(x: dx, y: dy)
            haloLabels.append(l)
            addChild(l)
        }
        shadowLabel.horizontalAlignmentMode = align
        shadowLabel.verticalAlignmentMode = .top
        shadowLabel.position = CGPoint(x: 1, y: -1.2)
        addChild(shadowLabel)
        addChild(mainLabel)
        mainLabel.horizontalAlignmentMode = align
        mainLabel.verticalAlignmentMode = .top
        applyContrast()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError()
    }

    func setText(_ text: String) {
        mainLabel.attributedText = attributed(text, color: NSColor(white: 0.98, alpha: textAlpha))
        shadowLabel.attributedText = attributed(text, color: NSColor(white: 0, alpha: 0.5))
        for l in haloLabels {
            l.attributedText = attributed(text, color: NSColor(white: 0, alpha: 0.28))
        }
    }

    /// 고대비 설정 변경 반영
    func applyContrast() {
        for l in haloLabels {
            l.isHidden = !Theme.highContrast
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

/// 라운드 종료 스코어카드 — 실제 골프 스코어카드 관례로 그린다:
/// 홀·파·타수 행렬 + 언더파 원(이글 이중 원)·오버파 사각(더블+ 이중 사각) 기호. 기권은 딤 처리
final class ScorecardNode: SKNode {
    private let scrim = SKShapeNode()
    private var content: [SKNode] = []

    override init() {
        super.init()
        scrim.fillColor = NSColor(white: 0, alpha: 0.32)
        scrim.strokeColor = .clear
        addChild(scrim)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError()
    }

    func applyContrast() {
        for c in content {
            (c as? GlassLabel)?.applyContrast()
        }
    }

    func show(results: [(par: Int, strokes: Int, gaveUp: Bool)], title: String, footer: String) {
        for c in content {
            c.removeFromParent()
        }
        content = []

        let colW: CGFloat = 42
        let labelX: CGFloat = -240 // 행 이름 (좌측 정렬)
        let firstColX: CGFloat = -170 // 1번 홀 컬럼 중심
        let totalX: CGFloat = 214 // 합계 컬럼 (실카드의 OUT 자리)
        let headerY: CGFloat = 30, parY: CGFloat = 2, scoreY: CGFloat = -28

        func put(
            _ text: String, x: CGFloat, y: CGFloat, font: String = HUDFont.regular,
            size: CGFloat, alpha: CGFloat = 1, align: SKLabelHorizontalAlignmentMode = .center
        ) {
            let l = GlassLabel(font: font, size: size, alpha: alpha, align: align)
            l.setText(text)
            l.position = CGPoint(x: x, y: y)
            addChild(l)
            content.append(l)
        }

        put(title, x: 0, y: 76, font: HUDFont.semibold, size: 18)
        put("홀", x: labelX, y: headerY, size: 11, alpha: 0.6, align: .left)
        put("파", x: labelX, y: parY, size: 12, alpha: 0.75, align: .left)
        put("타수", x: labelX, y: scoreY, size: 12, alpha: 0.75, align: .left)
        for (i, r) in results.enumerated() {
            let x = firstColX + CGFloat(i) * colW
            put("\(i + 1)", x: x, y: headerY, size: 11, alpha: 0.6)
            put("\(r.par)", x: x, y: parY, size: 12, alpha: 0.75)
            put("\(r.strokes)", x: x, y: scoreY, font: HUDFont.medium, size: 15, alpha: r.gaveUp ? 0.45 : 1)
            if !r.gaveUp {
                addMark(diff: r.strokes - r.par, at: CGPoint(x: x, y: scoreY - 9))
            }
        }
        put("계", x: totalX, y: headerY, size: 11, alpha: 0.6)
        put("\(results.reduce(0) { $0 + $1.par })", x: totalX, y: parY, size: 12, alpha: 0.75)
        put("\(results.reduce(0) { $0 + $1.strokes })", x: totalX, y: scoreY, font: HUDFont.medium, size: 15)
        put(footer, x: 0, y: -60, font: HUDFont.medium, size: 13)

        // 행 구분 헤어라인 + 합계 컬럼 구분선 (상자 없는 디자인 안에서 최소한의 격자)
        let grid = CGMutablePath()
        grid.move(to: CGPoint(x: -248, y: headerY - 18))
        grid.addLine(to: CGPoint(x: 248, y: headerY - 18))
        grid.move(to: CGPoint(x: -248, y: parY - 19))
        grid.addLine(to: CGPoint(x: 248, y: parY - 19))
        grid.move(to: CGPoint(x: totalX - 25, y: headerY + 1))
        grid.addLine(to: CGPoint(x: totalX - 25, y: scoreY - 21))
        let gridNode = SKShapeNode(path: grid)
        gridNode.strokeColor = NSColor(white: 1, alpha: 0.22)
        gridNode.lineWidth = 1
        addChild(gridNode)
        content.append(gridNode)

        scrim.path = CGPath(
            roundedRect: CGRect(x: -266, y: -92, width: 532, height: 192),
            cornerWidth: 22, cornerHeight: 22, transform: nil
        )
        isHidden = false
    }

    /// 스코어 기호 — 골프 스코어카드 관례: 버디 원 · 이글+ 이중 원 · 보기 사각 · 더블+ 이중 사각
    private func addMark(diff: Int, at center: CGPoint) {
        guard diff != 0 else { return }
        func ring(_ r: CGFloat) -> SKShapeNode {
            SKShapeNode(circleOfRadius: r)
        }
        func box(_ s: CGFloat) -> SKShapeNode {
            SKShapeNode(rect: CGRect(x: -s / 2, y: -s / 2, width: s, height: s), cornerRadius: 2.5)
        }
        let shapes: [SKShapeNode] = switch diff {
        case ...(-2): [ring(11), ring(7.5)]
        case -1: [ring(11)]
        case 1: [box(20)]
        default: [box(20), box(14)]
        }
        for s in shapes {
            s.position = center
            s.fillColor = .clear
            s.strokeColor = diff < 0 ? Palette.flagRed.withAlphaComponent(0.9) : NSColor(white: 1, alpha: 0.55)
            s.lineWidth = 1.2
            addChild(s)
            content.append(s)
        }
    }

    func hide() {
        isHidden = true
    }
}
