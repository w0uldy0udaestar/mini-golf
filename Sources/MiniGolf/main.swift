import AppKit
import GolfCore
import SpriteKit

// ═══════════════════════════════════════════════════════════════
// MiniGolf M1 — GolfCore 기반 1홀 플레이 오버레이
// 조작: ←→ 클럽 · ↑↓ 백스윙 · Space 스윙 · R 새 라운드 · Esc 종료
// 스틱맨·연출은 M2에서 프로토타입 수준으로 이식한다
// ═══════════════════════════════════════════════════════════════

final class GameScene: SKScene {
    // 게임 상태
    private var course: [Hole] = []
    private var holeIdx = 0
    private var ball = BallState(x: CourseGenerator.teeX, y: 0)
    private var strokes = 0
    private var clubIdx = 0
    private var heightPct = 0.6
    private var results: [(par: Int, strokes: Int)] = []
    private enum Mode { case aim, motion, holed, end }
    private var mode = Mode.aim
    private var dir = 1.0
    private var heldKeys = Set<UInt16>()
    private var lastTime: TimeInterval = 0
    private var acc = 0.0
    private let timeScale = 2.5 // 프로토타입에서 확정한 재생 배속

    private var hole: Hole {
        course[holeIdx]
    }

    private var club: Club {
        ClubTable.all[clubIdx]
    }

    private var pxPerM: CGFloat {
        size.width / hole.worldW
    }

    private let groundBase: CGFloat = 96 // 표고 0의 화면 y (아래에서부터)

    // 노드
    private let terrainNode = SKNode()
    private let ballNode = SKShapeNode(circleOfRadius: 6)
    private let flagNode = SKNode()
    private let scoreLabel = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
    private let subLabel = SKLabelNode(fontNamed: "AppleSDGothicNeo-Medium")
    private let clubLabel = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
    private let powerLabel = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
    private let toastLabel = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")

    private func px(_ m: Double) -> CGFloat {
        CGFloat(m) * pxPerM
    }

    private func py(_ elev: Double) -> CGFloat {
        groundBase + CGFloat(elev) * pxPerM
    }

    override func didMove(to _: SKView) {
        backgroundColor = .clear // ⚠️ skView.backgroundColor는 설정 금지

        ballNode.fillColor = .white
        ballNode.strokeColor = NSColor(white: 0, alpha: 0.25)

        scoreLabel.fontSize = 15
        scoreLabel.horizontalAlignmentMode = .right
        scoreLabel.position = CGPoint(x: size.width - 20, y: size.height - 60)
        subLabel.fontSize = 12
        subLabel.fontColor = NSColor(white: 0.92, alpha: 0.75)
        subLabel.horizontalAlignmentMode = .right
        subLabel.position = CGPoint(x: size.width - 20, y: size.height - 80)
        clubLabel.fontSize = 16
        clubLabel.horizontalAlignmentMode = .left
        clubLabel.position = CGPoint(x: 20, y: size.height - 60)
        powerLabel.fontSize = 12
        toastLabel.fontSize = 30
        toastLabel.position = CGPoint(x: size.width / 2, y: size.height * 0.6)
        toastLabel.alpha = 0

        for node in [terrainNode, ballNode, flagNode] as [SKNode] {
            addChild(node)
        }
        for label in [scoreLabel, subLabel, clubLabel, powerLabel, toastLabel] {
            addChild(label)
        }

        newRound()
    }

    private func newRound() {
        course = CourseGenerator
            .makeCourse(seed: UInt32(Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 2_000_000_000)))
        holeIdx = 0
        results = []
        startHole()
    }

    private func startHole() {
        strokes = 0
        ball = BallState(x: CourseGenerator.teeX, y: hole.ground(at: CourseGenerator.teeX))
        mode = .aim
        dir = 1
        rebuildTerrain()
        updateHUD()
    }

    /// 지형·컵·깃발을 SKShapeNode 경로로 재구성 (홀마다 스케일이 달라짐)
    private func rebuildTerrain() {
        terrainNode.removeAllChildren()
        let cupHalfM = max(Phys.cupHalfWidth, 5 / Double(pxPerM))
        let cupL = hole.holeX - cupHalfM, cupR = hole.holeX + cupHalfM

        func styleFor(_ s: Surface) -> (NSColor, CGFloat) {
            switch s {
            case .tee, .fairway: (NSColor(white: 0.84, alpha: 0.75), 4)
            case .rough: (NSColor(white: 0.48, alpha: 0.8), 9)
            case .apron: (NSColor(white: 0.93, alpha: 0.85), 4)
            case .green: (NSColor(white: 1.0, alpha: 0.95), 3)
            case .bunker: (NSColor(red: 0.78, green: 0.75, blue: 0.69, alpha: 0.9), 6)
            case .water: (NSColor(red: 0.5, green: 0.59, blue: 0.66, alpha: 0.9), 5)
            }
        }
        func addGroundPath(from: Double, to: Double, surface: Surface) {
            guard to - from > 0.1 else { return }
            let path = CGMutablePath()
            path.move(to: CGPoint(x: px(from), y: py(hole.ground(at: from))))
            var x = from + 1
            while x < to {
                path.addLine(to: CGPoint(x: px(x), y: py(hole.ground(at: x))))
                x += 1
            }
            path.addLine(to: CGPoint(x: px(to), y: py(hole.ground(at: to))))
            let node = SKShapeNode(path: path)
            let (color, width) = styleFor(surface)
            node.strokeColor = color
            node.lineWidth = width
            node.lineCap = .round
            terrainNode.addChild(node)
        }
        for seg in hole.segments {
            if seg.to <= cupL || seg.from >= cupR {
                addGroundPath(from: seg.from, to: seg.to, surface: seg.type)
            } else {
                addGroundPath(from: seg.from, to: max(seg.from, cupL), surface: seg.type)
                addGroundPath(from: min(seg.to, cupR), to: seg.to, surface: seg.type)
            }
        }

        // 깃발 (포인트 컬러는 이것 하나)
        flagNode.removeAllChildren()
        let cupY = py(hole.ground(at: hole.holeX))
        let pole = SKShapeNode(rect: CGRect(x: -1, y: 0, width: 2, height: 58))
        pole.fillColor = NSColor(white: 0.92, alpha: 0.9)
        pole.strokeColor = .clear
        let flag = SKShapeNode(path: {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 0, y: 58))
            p.addLine(to: CGPoint(x: 26, y: 50))
            p.addLine(to: CGPoint(x: 0, y: 42))
            p.closeSubpath()
            return p
        }())
        flag.fillColor = NSColor(red: 0.84, green: 0.27, blue: 0.20, alpha: 1)
        flag.strokeColor = .clear
        flagNode.addChild(pole)
        flagNode.addChild(flag)
        flagNode.position = CGPoint(x: px(hole.holeX), y: cupY)
    }

    private func updateHUD() {
        let total = results.reduce(0) { $0 + ($1.strokes - $1.par) }
        let totalStr = total > 0 ? "+\(total)" : total == 0 ? "E" : "\(total)"
        let remain = abs(hole.holeX - ball.x)
        let lie = strokes == 0 ? Surface.tee : hole.surface(at: ball.x)
        scoreLabel.text = "\(holeIdx + 1)번 홀 · 파 \(hole.par) · \(Int(hole.dist))m"
        subLabel.text = "타수 \(strokes) · 합계 \(totalStr) · \(lie.label) · 남은 거리 \(Int(remain))m"
        clubLabel.text = "◀ \(club.name) ▶"
        powerLabel.text = "\(Int(heightPct * 100))%"
    }

    private func showToast(_ text: String) {
        toastLabel.text = text
        toastLabel.removeAllActions()
        toastLabel.run(.sequence([.fadeIn(withDuration: 0.15), .wait(forDuration: 1.3), .fadeOut(withDuration: 0.3)]))
    }

    /// ── 입력 ──
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: NSApp.terminate(nil) // Esc
        case 15: newRound() // R
        default: break
        }
        guard mode == .aim else { return }
        switch event.keyCode {
        case 126, 125: heldKeys.insert(event.keyCode) // ↑↓
        case 123: clubIdx = max(0, clubIdx - 1); updateHUD() // ←
        case 124: clubIdx = min(ClubTable.all.count - 1, clubIdx + 1); updateHUD() // →
        case 49: swing() // Space
        default: break
        }
    }

    override func keyUp(with event: NSEvent) {
        heldKeys.remove(event.keyCode)
    }

    private func swing() {
        dir = hole.holeX >= ball.x ? 1 : -1
        let lie = strokes == 0 ? Surface.tee : hole.surface(at: ball.x)
        Ballistics.launch(&ball, club: club, heightPct: heightPct, lie: lie, dir: dir)
        strokes += 1
        mode = .motion
        updateHUD()
    }

    private func onHoled() {
        mode = .holed
        results.append((hole.par, strokes))
        showToast(scoreName(strokes: strokes, par: hole.par))
        run(.sequence([.wait(forDuration: 1.7), .run { [weak self] in self?.advanceHole() }]))
    }

    private func advanceHole() {
        if holeIdx < 8 {
            holeIdx += 1
            startHole()
        } else {
            mode = .end
            let total = results.reduce(0) { $0 + ($1.strokes - $1.par) }
            showToast("라운드 종료 · 합계 \(total > 0 ? "+\(total)" : total == 0 ? "이븐 파" : "\(total)") — R로 새 라운드")
        }
    }

    private func onWater() {
        strokes += 1 // 벌타
        let wr = hole.waterRange ?? (ball.x - 3) ... (ball.x + 3)
        let dropX = dir > 0 ? wr.lowerBound - 2.5 : wr.upperBound + 2.5
        ball = BallState(x: dropX, y: hole.ground(at: dropX))
        showToast("워터 해저드 💧 +1벌타")
        mode = strokes >= Phys.maxStrokes ? .holed : .aim
        if strokes >= Phys.maxStrokes {
            giveUp()
        }
        updateHUD()
    }

    private func giveUp() {
        results.append((hole.par, Phys.maxStrokes))
        showToast("기권")
        run(.sequence([.wait(forDuration: 1.4), .run { [weak self] in self?.advanceHole() }]))
    }

    /// ── 메인 루프 ──
    override func update(_ currentTime: TimeInterval) {
        let dt = lastTime == 0 ? 0 : min(currentTime - lastTime, 0.1)
        lastTime = currentTime

        if mode == .aim {
            let rate = club.isPutter ? 0.4 : 0.85 // 퍼터는 정밀 조절
            if heldKeys.contains(126) {
                heightPct = min(1, heightPct + rate * dt)
            }
            if heldKeys.contains(125) {
                heightPct = max(0, heightPct - rate * dt)
            }
            updateHUD()
        }

        if mode == .motion {
            acc += dt * timeScale
            var event = StepEvent.none
            while acc >= Phys.dt {
                acc -= Phys.dt
                event = Ballistics.step(&ball, hole: hole)
                if event != .none {
                    break
                }
            }
            switch event {
            case .holed: onHoled()
            case .water: onWater()
            case .none:
                if ball.phase == .rest {
                    if strokes >= Phys.maxStrokes {
                        giveUp()
                    } else {
                        mode = .aim
                    }
                }
            }
            updateHUD()
        }

        // 렌더 반영
        ballNode.position = CGPoint(x: px(ball.x), y: py(ball.y) + 6)
        powerLabel.position = CGPoint(x: px(ball.x), y: py(hole.ground(at: ball.x)) + 40)
        powerLabel.isHidden = mode != .aim
    }
}

/// ── 오버레이 앱 골격 (M0 스파이크에서 검증된 구성) ──
final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: OverlayPanel!

    func applicationDidFinishLaunching(_: Notification) {
        guard let screen = NSScreen.main else { NSApp.terminate(nil); return }
        panel = OverlayPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let skView = SKView(frame: screen.frame)
        skView.allowsTransparency = true
        let scene = GameScene(size: screen.frame.size)
        scene.scaleMode = .resizeFill
        panel.contentView = skView
        skView.presentScene(scene)

        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(scene)
        NSApp.activate(ignoringOtherApps: true)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
