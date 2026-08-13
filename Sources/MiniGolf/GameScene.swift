import AppKit
import GolfCore
import SpriteKit

/// 게임 씬 — GolfCore 상태를 렌더하고 키보드 입력을 처리한다 (물리는 GolfCore)
final class GameScene: SKScene {
    // 게임 상태
    private var course: [Hole] = []
    private var holeIdx = 0
    private var ball = BallState(x: CourseGenerator.teeX, y: 0)
    private var strokes = 0
    private var clubIdx = 0
    private var heightPct = 0.6
    private var results: [(par: Int, strokes: Int, gaveUp: Bool)] = []
    private enum Mode { case aim, swinging, motion, walking, holed, end }
    private var mode = Mode.aim
    private var dir = 1.0
    private var heldKeys = Set<UInt16>()
    private var lastTime: TimeInterval = 0
    private var acc = 0.0
    private let timeScale = 2.5
    var isGamePaused = false // 포커스 상실·메뉴에서 제어

    // 연출 상태 (프로토타입 이식)
    private struct SwingAnim { var t = 0.0; var launched = false; let prof: SwingProfile; let fromPose: Pose }
    private struct WalkAnim { let fromX, toX,
                                  dur: Double; var t = 0.0; let relax = 0.4; var phase = -0.6; var vPx = 0.0
    }

    private var swingAnim: SwingAnim?
    private var walkAnim: WalkAnim?
    private var lastFinishPose: Pose?
    private var renderPose = Poses.p1
    private var renderBf = 24.0
    private var stickX = CourseGenerator.teeX
    private var trailPoints: [CGPoint] = []

    private var hole: Hole {
        course[holeIdx]
    }

    private var club: Club {
        ClubTable.all[clubIdx]
    }

    private var profile: SwingProfile {
        SwingProfile.profile(for: club.cat)
    }

    private var pxPerM: CGFloat {
        size.width / hole.worldW
    }

    private let groundBase: CGFloat = 96

    // 노드
    private let terrainNode = SKNode()
    private let stickman = StickmanNode()
    private let ballNode = SKShapeNode(circleOfRadius: 6)
    private let shadowNode = SKShapeNode(ellipseOf: CGSize(width: 16, height: 5))
    private let trailNode = SKShapeNode()
    private let flagNode = SKNode()
    private let scoreChip = ChipNode(align: .right)
    private let clubChip = ChipNode(align: .left, mainSize: 16, subSize: 11)
    private let hintChip = ChipNode(align: .right, mainSize: 11)
    private let toastChip = ChipNode(align: .center, mainSize: 26, subSize: 13)
    private let pauseChip = ChipNode(align: .center, mainSize: 15)
    private let powerLabel = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
    private let scorecard = ScorecardNode()

    private func px(_ m: Double) -> CGFloat {
        CGFloat(m) * pxPerM
    }

    private func py(_ elev: Double) -> CGFloat {
        groundBase + CGFloat(elev) * pxPerM
    }

    private func groundY(_ xm: Double) -> CGFloat {
        py(hole.ground(at: xm))
    }

    override func didMove(to _: SKView) {
        backgroundColor = .clear // ⚠️ skView.backgroundColor는 설정 금지

        ballNode.fillColor = .white
        ballNode.strokeColor = NSColor(white: 0, alpha: 0.25)
        shadowNode.fillColor = NSColor(white: 0, alpha: 0.3)
        shadowNode.strokeColor = .clear
        trailNode.strokeColor = NSColor(white: 1, alpha: 0.35)
        trailNode.lineWidth = 1.5
        powerLabel.fontSize = 12
        powerLabel.fontColor = NSColor(white: 0.93, alpha: 1)

        scoreChip.position = CGPoint(x: size.width - 16, y: size.height - 44)
        clubChip.position = CGPoint(x: 16, y: size.height - 44)
        hintChip.position = CGPoint(x: size.width - 16, y: size.height - 108)
        hintChip.setText("←→ 클럽 · ↑↓ 백스윙 · Space 스윙 · R 새 라운드 · Esc 종료")
        toastChip.position = CGPoint(x: size.width / 2, y: size.height * 0.62)
        toastChip.alpha = 0
        pauseChip.position = CGPoint(x: size.width / 2, y: size.height - 44)
        pauseChip.setText("일시정지 — 메뉴바 ⛳️에서 재개")
        pauseChip.isHidden = true
        scorecard.position = CGPoint(x: size.width / 2, y: size.height / 2)
        scorecard.hide()

        for n in [terrainNode, trailNode, stickman, shadowNode, ballNode, flagNode] as [SKNode] {
            addChild(n)
        }
        for n in [scoreChip, clubChip, hintChip, toastChip, pauseChip, powerLabel, scorecard] as [SKNode] {
            addChild(n)
        }

        newRound()
    }

    func newRound() {
        course = CourseGenerator
            .makeCourse(seed: UInt32(Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 2_000_000_000)))
        holeIdx = 0
        results = []
        scorecard.hide()
        startHole()
    }

    private func startHole() {
        strokes = 0
        ball = BallState(x: CourseGenerator.teeX, y: hole.ground(at: CourseGenerator.teeX))
        trailPoints = []
        swingAnim = nil
        walkAnim = nil
        rebuildTerrain()
        enterAim()
    }

    private func enterAim() {
        mode = .aim
        walkAnim = nil
        stickX = ball.x
        dir = hole.holeX >= ball.x ? 1 : -1
        updateHUD()
    }

    private func startWalk() {
        let from = stickX, to = ball.x
        let dist = abs(to - from)
        if dist < 1 {
            enterAim(); return
        }
        mode = .walking
        dir = to >= from ? 1 : -1
        walkAnim = WalkAnim(fromX: from, toX: to, dur: min(4.5, max(1.0, dist / 55)))
        updateHUD()
    }

    private func startSwing() {
        mode = .swinging
        swingAnim = SwingAnim(prof: profile, fromPose: renderPose)
    }

    private func launchBall() {
        let lie = strokes == 0 ? Surface.tee : hole.surface(at: ball.x)
        Ballistics.launch(&ball, club: club, heightPct: heightPct, lie: lie, dir: dir)
        strokes += 1
        trailPoints = []
        mode = .motion
        updateHUD()
    }

    /// ── 홀 이벤트 ──
    private func onHoled() {
        mode = .holed
        results.append((hole.par, strokes, false))
        toast(scoreName(strokes: strokes, par: hole.par), sub: "\(strokes)타 · 파 \(hole.par) · \(Int(hole.dist))m")
        run(.sequence([.wait(forDuration: 1.7), .run { [weak self] in self?.advanceHole() }]))
    }

    private func onWater() {
        strokes += 1
        let wr = hole.waterRange ?? (ball.x - 3) ... (ball.x + 3)
        let dropX = dir > 0 ? wr.lowerBound - 2.5 : wr.upperBound + 2.5
        ball = BallState(x: dropX, y: hole.ground(at: dropX))
        toast("워터 해저드 💧", sub: "+1 벌타 · 드롭")
        if strokes >= Phys.maxStrokes {
            giveUp()
        } else {
            startWalk()
        }
    }

    private func giveUp() {
        mode = .holed
        results.append((hole.par, Phys.maxStrokes, true))
        toast("기권", sub: "\(Phys.maxStrokes)타 초과")
        run(.sequence([.wait(forDuration: 1.4), .run { [weak self] in self?.advanceHole() }]))
    }

    private func advanceHole() {
        if holeIdx < 8 {
            holeIdx += 1
            startHole()
        } else {
            mode = .end
            let total = results.reduce(0) { $0 + ($1.strokes - $1.par) }
            let totalStr = total > 0 ? "+\(total)" : total == 0 ? "이븐 파" : "\(total)"
            let rows = results.enumerated().map { i, r in
                "\(i + 1)번 홀 · 파 \(r.par) · \(r.gaveUp ? "기권" : "\(r.strokes)타") · \(scoreName(strokes: r.strokes, par: r.par))"
            }
            scorecard.show(rows: rows, title: "⛳️ 라운드 종료", footer: "합계 \(totalStr) — R로 새 라운드")
        }
    }

    private func toast(_ main: String, sub: String? = nil) {
        toastChip.setText(main, sub: sub)
        toastChip.removeAllActions()
        toastChip.run(.sequence([.fadeIn(withDuration: 0.15), .wait(forDuration: 1.35), .fadeOut(withDuration: 0.3)]))
    }

    /// ── 일시정지 (포커스 상실·메뉴) ──
    func setGamePaused(_ paused: Bool) {
        isGamePaused = paused
        pauseChip.isHidden = !paused
        if paused {
            heldKeys.removeAll()
        }
    }

    /// ── 지형 렌더 ──
    private func rebuildTerrain() {
        terrainNode.removeAllChildren()
        let cupHalfM = max(Phys.cupHalfWidth, 5 / Double(pxPerM))
        let cupL = hole.holeX - cupHalfM
        let cupR = hole.holeX + cupHalfM

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
            path.move(to: CGPoint(x: px(from), y: groundY(from)))
            var x = from + 1
            while x < to {
                path.addLine(to: CGPoint(x: px(x), y: groundY(x)))
                x += 1
            }
            path.addLine(to: CGPoint(x: px(to), y: groundY(to)))
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
            if seg.type == .bunker { // 모래 점 질감
                var x = seg.from + 1
                while x < seg.to {
                    let dot = SKShapeNode(circleOfRadius: 1.1)
                    dot.fillColor = NSColor(red: 0.78, green: 0.75, blue: 0.69, alpha: 0.55)
                    dot.strokeColor = .clear
                    dot.position = CGPoint(x: px(x), y: groundY(x) - 4)
                    terrainNode.addChild(dot)
                    x += 1.7
                }
            }
            if seg.type == .water { // 물결 질감
                var x = seg.from + 2
                while x < seg.to - 2 {
                    let wave = SKShapeNode(path: {
                        let p = CGMutablePath()
                        p.move(to: .zero)
                        p.addQuadCurve(to: CGPoint(x: px(2.4), y: 0), control: CGPoint(x: px(1.2), y: 2))
                        return p
                    }())
                    wave.strokeColor = NSColor(red: 0.5, green: 0.59, blue: 0.66, alpha: 0.5)
                    wave.lineWidth = 1.5
                    wave.position = CGPoint(x: px(x), y: groundY(x) - 5)
                    terrainNode.addChild(wave)
                    x += 5
                }
            }
        }

        // 컵 (지면 아래 홈)
        let cupY = groundY(hole.holeX)
        let cup = SKShapeNode(rect: CGRect(x: px(hole.holeX) - 7, y: cupY - 12, width: 14, height: 12))
        cup.fillColor = NSColor(white: 0.07, alpha: 0.9)
        cup.strokeColor = NSColor(white: 0.93, alpha: 0.85)
        terrainNode.addChild(cup)

        // 깃발 (유일한 포인트 컬러)
        flagNode.removeAllChildren()
        let pole = SKShapeNode(rect: CGRect(x: -1, y: 0, width: 2, height: 58))
        pole.fillColor = NSColor(white: 0.92, alpha: 0.9)
        pole.strokeColor = .clear
        let flag = SKShapeNode(path: {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 0, y: 58))
            p.addQuadCurve(to: CGPoint(x: 26, y: 50), control: CGPoint(x: 20, y: 56))
            p.addQuadCurve(to: CGPoint(x: 0, y: 42), control: CGPoint(x: 20, y: 45))
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
        scoreChip.setText(
            "\(holeIdx + 1)번 홀 · 파 \(hole.par) · \(Int(hole.dist))m",
            sub: "타수 \(strokes) · 합계 \(totalStr) · \(lie.label) · 남은 거리 \(Int(remain))m"
        )
        clubChip.setText(
            "◀ \(club.name) ▶",
            sub: club.cat == .wood ? "우드" : club.cat == .iron ? "아이언" : club.cat == .wedge ? "웨지" : "퍼터"
        )
    }

    /// ── 입력 ──
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: NSApp.terminate(nil) // Esc
        case 15: newRound(); return // R
        default: break
        }
        guard mode == .aim, !isGamePaused else { return }
        switch event.keyCode {
        case 126, 125: heldKeys.insert(event.keyCode) // ↑↓
        case 123: clubIdx = max(0, clubIdx - 1); updateHUD() // ←
        case 124: clubIdx = min(ClubTable.all.count - 1, clubIdx + 1); updateHUD() // →
        case 49: startSwing() // Space
        default: break
        }
    }

    override func keyUp(with event: NSEvent) {
        heldKeys.remove(event.keyCode)
    }

    /// ── 메인 루프 ──
    override func update(_ currentTime: TimeInterval) {
        let dt = lastTime == 0 ? 0 : min(currentTime - lastTime, 0.1)
        lastTime = currentTime
        guard !isGamePaused else { return }

        // 백스윙 조절 (퍼터는 정밀)
        if mode == .aim {
            let rate = club.isPutter ? 0.4 : 0.85
            if heldKeys.contains(126) {
                heightPct = min(1, heightPct + rate * dt)
            }
            if heldKeys.contains(125) {
                heightPct = max(0, heightPct - rate * dt)
            }
        }

        // 스윙: 임팩트에 발사, 팔로스루는 이어짐
        if var anim = swingAnim {
            anim.t += dt
            if !anim.launched, anim.t >= anim.prof.down {
                anim.launched = true
                swingAnim = anim
                launchBall()
            }
            if anim.t >= SwingTiming.total {
                lastFinishPose = finishPose(profile: anim.prof)
                swingAnim = nil
            } else {
                swingAnim = anim
            }
        }

        // 걷기: 피니시 풀기(relax) 후 이동, 걸음 주기는 속도에 연동 (발 미끄럼 방지)
        if mode == .walking, var w = walkAnim {
            w.t += dt
            let tw = w.t - w.relax
            if tw >= 0 {
                let u = min(1, tw / w.dur)
                stickX = w.fromX + (w.toX - w.fromX) * smoothstep(u)
                let vInst = abs(w.toX - w.fromX) * 6 * u * (1 - u) / w.dur
                w.vPx = vInst * Double(pxPerM)
                w.phase += w.vPx / 16 * dt
                walkAnim = w
                if u >= 1 {
                    enterAim()
                }
            } else {
                walkAnim = w
            }
        }

        // 물리
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
            trailPoints.append(CGPoint(x: px(ball.x), y: py(ball.y) + 6))
            if trailPoints.count > 400 {
                trailPoints.removeFirst()
            }
            switch event {
            case .holed: onHoled()
            case .water: onWater()
            case .none:
                if ball.phase == .rest {
                    if strokes >= Phys.maxStrokes {
                        giveUp()
                    } else {
                        startWalk()
                    }
                }
            }
            updateHUD()
        }

        // 포즈 스무딩: 렌더 포즈가 목표 포즈를 지수 감쇠로 추적 — 모든 전환이 부드러워진다
        let target: Pose = if let anim = swingAnim {
            swingPose(t: anim.t, fromPose: anim.fromPose, profile: anim.prof, heightPct: heightPct)
        } else if mode == .aim {
            backswingPose(heightPct: heightPct, profile: profile)
        } else if mode == .walking {
            Poses.upright
        } else {
            lastFinishPose ?? Poses.p10
        }
        let rate: Double = swingAnim != nil ? 45 : mode == .aim ? 14 : 8
        renderPose.chase(target, rate: rate, dt: dt)
        renderBf += (profile.ballFwd - renderBf) * (1 - exp(-rate * dt))

        // 렌더 반영
        stickman.position = CGPoint(x: px(stickX), y: groundY(stickX))
        if mode == .walking, let w = walkAnim, w.t >= w.relax {
            stickman.updateWalking(phase: w.phase, vPx: w.vPx, dir: dir, clubCat: club.cat) { dxPx in
                let xm = self.stickX + Double(dxPx / self.pxPerM)
                return self.groundY(xm) - self.groundY(self.stickX)
            }
        } else {
            stickman.update(pose: renderPose, dir: dir, ballFwd: renderBf, clubCat: club.cat)
        }

        ballNode.position = CGPoint(x: px(ball.x), y: py(ball.y) + 6)
        let heightAbove = ball.y - hole.ground(at: ball.x)
        shadowNode.isHidden = heightAbove <= 0.2
        shadowNode.position = CGPoint(x: px(ball.x), y: groundY(ball.x) - 1)

        if trailPoints.count > 1 {
            let path = CGMutablePath()
            path.move(to: trailPoints[0])
            for p in trailPoints.dropFirst() {
                path.addLine(to: p)
            }
            trailNode.path = path
        } else {
            trailNode.path = nil
        }

        powerLabel.text = "\(Int(heightPct * 100))%"
        powerLabel.isHidden = mode != .aim
        powerLabel.position = CGPoint(x: px(stickX) - CGFloat(dir) * CGFloat(renderBf), y: groundY(stickX) + 100)
    }
}
