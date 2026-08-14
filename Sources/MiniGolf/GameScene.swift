import AppKit
import GolfCore
import SpriteKit

/// 게임 씬 — GolfCore 상태를 렌더하고 키보드 입력을 처리한다 (물리는 GolfCore)
/// 디자인: "조용한 계기판" — 상자 없는 타이포 HUD, 균일한 헤어라인 지형, 포인트 컬러는 깃발 하나
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
    var isGamePaused = false

    // 연출 상태
    private struct SwingAnim { var t = 0.0; var launched = false; let prof: SwingProfile; let fromPose: Pose }
    private struct WalkAnim {
        let fromX, toX, dur: Double
        var t = 0.0
        let relax = 0.8 // 피니시 여운 — 서두르지 않는다
        var phase = -0.6
        var vPx = 0.0
        // 랜덤 잉여 동작 (생명감): 트월 시작 시각 / 어깨 캐리 구간 (walk 시작 기준 초)
        var twirlAt: Double?
        var shoulderRange: ClosedRange<Double>?
    }

    private var swingAnim: SwingAnim?
    private var walkAnim: WalkAnim?
    private var lastFinishPose: Pose?
    private var renderRig = RigBuilder.fromPose(Poses.p1, ballFwd: 24, clubLen: 31)
    // 클럽 변경 시 즉시 점프하는 값들은 전부 스무딩을 탄다 (길이·스탠스·백스윙 폭)
    private var renderLen = 31.0
    private var renderBallFwd = 24.0
    private var renderTop = 1.0
    private var clubSettle = 1.0 // 클럽 변경 후 경과 — 직후엔 추적을 늦춰 잔여 점프를 누른다
    private var aimTime = 0.0 // 조준 진입 후 경과 — 진입 직후엔 천천히 가라앉는다
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
    private let ballNode = SKShapeNode(circleOfRadius: 5.5)
    private let shadowNode = SKShapeNode(ellipseOf: CGSize(width: 15, height: 4.5))
    private let trailNode = SKShapeNode()
    private let trailUnderNode = SKShapeNode() // 궤적 언더스트로크 (밝은 배경 대비)
    private let flagNode = SKNode()
    private let scoreTitle = GlassLabel(font: HUDFont.medium, size: 17, align: .right, kern: 1.0)
    private let scoreSub = GlassLabel(font: HUDFont.regular, size: 12, alpha: 0.8, align: .right)
    private let clubTitle = GlassLabel(font: HUDFont.medium, size: 17, align: .left, kern: 1.0)
    private let clubSub = GlassLabel(font: HUDFont.regular, size: 11.5, alpha: 0.7, align: .left, kern: 1.4)
    private let hintLabel = GlassLabel(font: HUDFont.regular, size: 11.5, alpha: 0.66, align: .right)
    private let pauseLabel = GlassLabel(font: HUDFont.medium, size: 14)
    private let toastTitle = GlassLabel(font: HUDFont.light, size: 34, kern: 2.0)
    private let toastSub = GlassLabel(font: HUDFont.regular, size: 13, alpha: 0.8)
    private let powerLabel = GlassLabel(font: HUDFont.medium, size: 11, alpha: 0.85)
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
        ballNode.lineWidth = 1.2
        shadowNode.fillColor = NSColor(white: 0, alpha: 0.28)
        shadowNode.strokeColor = .clear
        trailNode.strokeColor = NSColor(white: 1, alpha: 0.28)
        trailNode.lineWidth = 1
        trailUnderNode.strokeColor = NSColor(white: 0, alpha: 0.3)
        trailUnderNode.lineWidth = 2.8
        trailUnderNode.lineCap = .round

        scoreTitle.position = CGPoint(x: size.width - 24, y: size.height - 46)
        scoreSub.position = CGPoint(x: size.width - 24, y: size.height - 72)
        clubTitle.position = CGPoint(x: 24, y: size.height - 46)
        clubSub.position = CGPoint(x: 24, y: size.height - 72)
        hintLabel.position = CGPoint(x: size.width - 24, y: size.height - 98)
        hintLabel.setText("←→ 클럽 · ↑↓ 백스윙 · Space 스윙 · R 새 라운드 · Esc 종료")
        pauseLabel.position = CGPoint(x: size.width / 2, y: size.height - 46)
        pauseLabel.setText("일시정지 — 메뉴바 ⛳️ 클릭으로 재개")
        pauseLabel.isHidden = true
        toastTitle.position = CGPoint(x: size.width / 2, y: size.height * 0.64)
        toastSub.position = CGPoint(x: size.width / 2, y: size.height * 0.64 - 42)
        toastTitle.alpha = 0
        toastSub.alpha = 0
        scorecard.position = CGPoint(x: size.width / 2, y: size.height / 2)
        scorecard.hide()

        for n in [terrainNode, trailUnderNode, trailNode, stickman, shadowNode, ballNode, flagNode] as [SKNode] {
            addChild(n)
        }
        for n in [
            scoreTitle,
            scoreSub,
            clubTitle,
            clubSub,
            hintLabel,
            pauseLabel,
            toastTitle,
            toastSub,
            powerLabel,
            scorecard,
        ] as [SKNode] {
            addChild(n)
        }

        // 힌트는 잠시 후 조용히 사라진다 (화면을 어지르지 않기)
        hintLabel.run(.sequence([.wait(forDuration: 8), .fadeOut(withDuration: 1.2)]))

        applyContrastMode()
        newRound()
    }

    /// ── 고대비 모드 (밝은 배경 opt-in) ──
    func setHighContrast(_ on: Bool) {
        Theme.highContrast = on
        applyContrastMode()
        rebuildTerrain() // 지형 언더스트로크·깃대 테두리는 재생성으로 반영
    }

    private func applyContrastMode() {
        ballNode.strokeColor = Theme.highContrast ? NSColor(white: 0, alpha: 0.4) : .clear
        trailUnderNode.isHidden = !Theme.highContrast
        stickman.applyContrast()
        scorecard.applyContrast()
        for l in [
            scoreTitle, scoreSub, clubTitle, clubSub, hintLabel,
            pauseLabel, toastTitle, toastSub, powerLabel,
        ] {
            l.applyContrast()
        }
    }

    func newRound() {
        course = CourseGenerator.makeCourse(
            seed: UInt32(Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 2_000_000_000))
        )
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
        ballNode.removeAllActions() // 홀인 드롭 연출 복구
        ballNode.alpha = 1
        ballNode.setScale(1)
        rebuildTerrain()
        enterAim()
    }

    private func enterAim() {
        mode = .aim
        aimTime = 0
        walkAnim = nil
        stickX = ball.x
        dir = hole.holeX >= ball.x ? 1 : -1
        presetPutterHeight()
        updateHUD()
    }

    /// 퍼터를 잡으면 남은 거리에 맞는 백스윙에서 시작한다 — 평지 기준 계산이라
    /// 그린 경사 읽기는 여전히 플레이어의 몫 (어시스트가 아니라 합리적 시작점)
    private func presetPutterHeight() {
        guard club.isPutter, mode == .aim else { return }
        let d = abs(hole.holeX - ball.x)
        let v0 = min(13.0, (2 * 1.1 * d + 4).squareRoot()) // 도착 속도 ~2m/s 목표
        heightPct = min(0.92, max(0.03, (v0 / 13.0 - Phys.putterMinRatio) / (1 - Phys.putterMinRatio)))
    }

    private func startWalk() {
        endShotTrail()
        let from = stickX, to = ball.x
        let dist = abs(to - from)
        mode = .walking
        if dist > 0.5 { // 아주 짧은 이동은 방향 유지 (제자리 반걸음)
            dir = to >= from ? 1 : -1
        }
        // 여유로운 걸음 — 실제 골퍼처럼 서두르지 않는다
        var anim = WalkAnim(fromX: from, toX: to, dur: min(9.0, max(0.9, dist / 16)))
        // 랜덤 잉여 동작: 긴 이동은 어깨 캐리, 아니면 가끔 클럽 트월 (동시엔 안 한다)
        if anim.dur > 4.5, Double.random(in: 0 ..< 1) < 0.5 {
            anim.shoulderRange = (anim.relax + 0.8) ... (anim.relax + anim.dur * 0.72)
        } else if anim.dur > 2.5, Double.random(in: 0 ..< 1) < 0.55 {
            anim.twirlAt = anim.relax + Double.random(in: 0.6 ... max(0.7, anim.dur * 0.55))
        }
        walkAnim = anim
        updateHUD()
    }

    private func startSwing() {
        mode = .swinging
        swingAnim = SwingAnim(prof: profile, fromPose: backswingPose(heightPct: heightPct, profile: profile))
        if !club.isPutter {
            SoundKit.shared.whoosh(power: heightPct, dur: profile.down + 0.05)
        }
    }

    private func launchBall() {
        let lie = strokes == 0 ? Surface.tee : hole.surface(at: ball.x)
        Ballistics.launch(&ball, club: club, heightPct: heightPct, lie: lie, dir: dir)
        strokes += 1
        trailPoints = []
        for t in [trailNode, trailUnderNode] {
            t.removeAllActions()
            t.alpha = 1
        }
        mode = .motion
        SoundKit.shared.impact(cat: club.cat, lie: lie, power: heightPct)
        if lie == .rough || lie == .bunker { // 러프 풀잎·벙커 모래가 튄다
            FX.dust(
                on: self,
                at: CGPoint(x: px(ball.x), y: groundY(ball.x)),
                surface: lie,
                intensity: 0.4 + 0.6 * heightPct
            )
        }
        updateHUD()
    }

    /// 샷이 끝나면 궤적은 잠시 여운을 남기고 사라진다
    private func endShotTrail() {
        guard !trailPoints.isEmpty else { return }
        trailUnderNode.removeAllActions()
        trailUnderNode.run(.fadeAlpha(to: 0, duration: 1.1))
        trailNode.removeAllActions()
        trailNode.run(.sequence([
            .fadeAlpha(to: 0, duration: 1.1),
            .run { [weak self] in
                guard let self else { return }
                trailPoints.removeAll()
                trailNode.alpha = 1
                trailUnderNode.alpha = 1
            },
        ]))
    }

    /// ── 홀 이벤트 ──
    private func onHoled() {
        mode = .holed
        results.append((hole.par, strokes, false))
        endShotTrail()
        SoundKit.shared.holeIn()
        dropBallIntoCup()
        toast(scoreName(strokes: strokes, par: hole.par), sub: "\(strokes)타 · 파 \(hole.par) · \(Int(hole.dist))m")
        run(.sequence([.wait(forDuration: 1.7), .run { [weak self] in self?.advanceHole() }]))
    }

    /// 공이 컵 속으로 굴러떨어지는 연출 — 렌더 루프는 .holed 동안 공 위치를 덮지 않는다
    private func dropBallIntoCup() {
        let cup = CGPoint(x: px(hole.holeX), y: groundY(hole.holeX))
        shadowNode.isHidden = true
        ballNode.removeAllActions()
        let slide = SKAction.move(to: CGPoint(x: cup.x, y: cup.y + 4), duration: 0.1)
        let sink = SKAction.move(to: CGPoint(x: cup.x, y: cup.y - 6), duration: 0.14)
        sink.timingMode = .easeIn
        ballNode.run(.sequence([
            slide,
            .group([sink, .scale(to: 0.72, duration: 0.14)]),
            .fadeOut(withDuration: 0.1), // 컵 안 어둠 속으로
        ]))
        // 공이 바닥에 닿은 뒤에야 점이 튀고 깃발이 흔들린다
        run(.sequence([.wait(forDuration: 0.24), .run { [weak self] in
            guard let self else { return }
            FX.holePop(on: self, at: cup)
            FX.flagWave(flagNode)
        }]))
    }

    private func onWater() {
        strokes += 1
        endShotTrail()
        SoundKit.shared.splash()
        FX.ripple(on: self, at: CGPoint(x: px(ball.x), y: groundY(ball.x)))
        let wr = hole.waterRange ?? (ball.x - 3) ... (ball.x + 3)
        let dropX = dir > 0 ? wr.lowerBound - 2.5 : wr.upperBound + 2.5
        ball = BallState(x: dropX, y: hole.ground(at: dropX))
        toast("워터 해저드", sub: "+1 벌타 · 드롭")
        if strokes >= Phys.maxStrokes {
            giveUp()
        } else {
            startWalk()
        }
    }

    private func giveUp() {
        mode = .holed
        results.append((hole.par, Phys.maxStrokes, true))
        endShotTrail()
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
                "\(i + 1)  ·  파 \(r.par)  ·  \(r.gaveUp ? "기권" : "\(r.strokes)타")  ·  \(scoreName(strokes: r.strokes, par: r.par))"
            }
            scorecard.show(rows: rows, title: "라운드 종료", footer: "합계 \(totalStr)  —  R로 새 라운드")
            SoundKit.shared.chime()
        }
    }

    private func toast(_ main: String, sub: String? = nil) {
        toastTitle.setText(main)
        toastSub.setText(sub ?? "")
        for node in [toastTitle, toastSub] as [SKNode] {
            node.removeAllActions()
            node.run(.sequence([.fadeIn(withDuration: 0.18), .wait(forDuration: 1.4), .fadeOut(withDuration: 0.45)]))
        }
    }

    /// ── 일시정지 ──
    func setGamePaused(_ paused: Bool) {
        isGamePaused = paused
        pauseLabel.isHidden = !paused
        if paused {
            heldKeys.removeAll()
        }
    }

    /// ── 지형: 균일한 헤어라인 + 라이별 미세 질감 ──
    private func rebuildTerrain() {
        terrainNode.removeAllChildren()
        let cupHalfM = max(Phys.cupHalfWidth, 4.5 / Double(pxPerM))
        let cupL = hole.holeX - cupHalfM
        let cupR = hole.holeX + cupHalfM

        func linePath(from: Double, to: Double) -> CGMutablePath {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: px(from), y: groundY(from)))
            var x = from + 1
            while x < to {
                path.addLine(to: CGPoint(x: px(x), y: groundY(x)))
                x += 1
            }
            path.addLine(to: CGPoint(x: px(to), y: groundY(to)))
            return path
        }

        func addGround(from: Double, to: Double, surface: Surface) {
            guard to - from > 0.1 else { return }
            let node = SKShapeNode()
            let base = linePath(from: from, to: to)
            switch surface {
            case .water: // 잔잔한 대시 라인
                node.path = base.copy(dashingWithPhase: 0, lengths: [5, 4])
                node.strokeColor = Palette.waterBlue.withAlphaComponent(0.75)
                node.lineWidth = 1.6
            case .green: // 살짝 도드라진 순백
                node.path = base
                node.strokeColor = NSColor(white: 1, alpha: 0.95)
                node.lineWidth = 2.6
            case .rough: // 어둡게 가라앉힘 + 잔디 틱
                node.path = base
                node.strokeColor = Palette.roughGray.withAlphaComponent(0.42)
                node.lineWidth = 1.8
                let grass = CGMutablePath()
                var gx = from + 1.2
                while gx < to - 0.5 {
                    let gy = groundY(gx)
                    grass.move(to: CGPoint(x: px(gx), y: gy))
                    grass.addLine(to: CGPoint(x: px(gx) + 0.6, y: gy + 3.6))
                    gx += 2.4
                }
                let grassNode = SKShapeNode(path: grass)
                grassNode.strokeColor = Palette.roughGray.withAlphaComponent(0.3)
                grassNode.lineWidth = 1
                terrainNode.addChild(grassNode)
            case .bunker: // 모래 스티플
                node.path = base
                node.strokeColor = Palette.bunkerSand.withAlphaComponent(0.8)
                node.lineWidth = 1.8
                let dots = CGMutablePath()
                var bx = from + 0.8
                while bx < to - 0.5 {
                    let cy = groundY(bx) - 3.2
                    dots.addEllipse(in: CGRect(x: px(bx) - 0.7, y: cy - 0.7, width: 1.4, height: 1.4))
                    bx += 1.5
                }
                let dotNode = SKShapeNode(path: dots)
                dotNode.fillColor = Palette.bunkerSand.withAlphaComponent(0.45)
                dotNode.strokeColor = .clear
                terrainNode.addChild(dotNode)
            default: // 티·페어웨이·에이프런: 조용한 헤어라인
                node.path = base
                node.strokeColor = Palette.hairline.withAlphaComponent(0.75)
                node.lineWidth = 1.8
            }
            node.lineCap = .round
            if Theme.highContrast { // 언더스트로크: 밝은 배경에서 헤어라인이 사라지지 않게 (opt-in)
                let under = SKShapeNode(path: node.path ?? base)
                under.strokeColor = NSColor(white: 0, alpha: 0.32)
                under.lineWidth = node.lineWidth + 2.2
                under.lineCap = .round
                terrainNode.addChild(under)
            }
            terrainNode.addChild(node)
        }

        for seg in hole.segments {
            if seg.to <= cupL || seg.from >= cupR {
                addGround(from: seg.from, to: seg.to, surface: seg.type)
            } else {
                addGround(from: seg.from, to: max(seg.from, cupL), surface: seg.type)
                addGround(from: min(seg.to, cupR), to: seg.to, surface: seg.type)
            }
        }

        // 컵: 지면 아래 조용한 홈
        let cupY = groundY(hole.holeX)
        let cup = SKShapeNode(rect: CGRect(x: px(hole.holeX) - 5, y: cupY - 9, width: 10, height: 9))
        cup.fillColor = NSColor(white: 0.05, alpha: 0.85)
        cup.strokeColor = .clear
        terrainNode.addChild(cup)

        // 깃발: 유일한 포인트 컬러
        flagNode.removeAllChildren()
        flagNode.zRotation = 0 // flagWave가 중간에 끊겨도 잔여 회전이 남지 않게
        let pole = SKShapeNode(rect: CGRect(x: -0.6, y: 0, width: 1.2, height: 62))
        pole.fillColor = NSColor(white: 0.95, alpha: 0.85)
        pole.strokeColor = Theme.highContrast ? NSColor(white: 0, alpha: 0.35) : .clear
        pole.lineWidth = 1
        let flag = SKShapeNode(path: {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 0, y: 62))
            p.addLine(to: CGPoint(x: 21, y: 55.5))
            p.addLine(to: CGPoint(x: 0, y: 49))
            p.closeSubpath()
            return p
        }())
        flag.fillColor = NSColor(red: 0.85, green: 0.3, blue: 0.24, alpha: 1)
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
        scoreTitle.setText("\(holeIdx + 1)번 홀 · 파 \(hole.par)")
        scoreSub.setText("타수 \(strokes) · 합계 \(totalStr) · \(lie.label) · \(Int(remain))m")
        clubTitle.setText(club.name)
        clubSub.setText(club.cat == .wood ? "우드" : club.cat == .iron ? "아이언" : club.cat == .wedge ? "웨지" : "퍼터")
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
        case 123: clubIdx = max(0, clubIdx - 1); clubSettle = 0; presetPutterHeight(); updateHUD() // ←
        case 124: clubIdx = min(
                ClubTable.all.count - 1,
                clubIdx + 1
            ); clubSettle = 0; presetPutterHeight(); updateHUD() // →
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

        if mode == .aim {
            let rate = club.isPutter ? 0.4 : 0.85
            if heldKeys.contains(126) {
                heightPct = min(1, heightPct + rate * dt)
            }
            if heldKeys.contains(125) {
                heightPct = max(0, heightPct - rate * dt)
            }
        }

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

        if mode == .motion {
            acc += dt * timeScale
            var terminal = StepEvent.none
            var landing: (speed: Double, surface: Surface, x: Double)?
            var wallHit: (speed: Double, x: Double)?
            var lipped = false
            while acc >= Phys.dt {
                acc -= Phys.dt
                let event = Ballistics.step(&ball, hole: hole)
                switch event {
                case .holed, .water:
                    terminal = event
                case let .bounce(speed, surface): // 프레임당 가장 강한 착지 하나만 연출
                    if speed > (landing?.speed ?? 0) {
                        landing = (speed, surface, ball.x)
                    }
                case let .wall(speed):
                    if speed > (wallHit?.speed ?? 0) {
                        wallHit = (speed, ball.x)
                    }
                case .lipOut:
                    lipped = true
                case .none:
                    break
                }
                if terminal != .none {
                    break
                }
            }
            if let l = landing, l.speed > 1.4 {
                SoundKit.shared.bounce(speed: l.speed, surface: l.surface)
                FX.dust(
                    on: self,
                    at: CGPoint(x: px(l.x), y: groundY(l.x)),
                    surface: l.surface,
                    intensity: min(1, l.speed / 12)
                )
            }
            if let w = wallHit, w.speed > 0.8 {
                SoundKit.shared.wall(speed: w.speed)
            }
            if lipped {
                SoundKit.shared.lipOut()
            }
            trailPoints.append(CGPoint(x: px(ball.x), y: py(ball.y) + 5.5))
            if trailPoints.count > 400 {
                trailPoints.removeFirst()
            }
            switch terminal {
            case .holed: onHoled()
            case .water: onWater()
            default:
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

        // ── 통합 리그: 모든 상태가 같은 파라미터 공간의 '타깃'만 바꾼다 → 전환이 자동으로 이어진다 ──
        // 클럽 변경으로 점프하는 값 전부 스무딩 (길이·스탠스·백스윙 폭 — 카테고리 경계 움찔 방지)
        let clubK = 1 - exp(-8 * dt)
        renderLen += (club.renderLength - renderLen) * clubK
        renderBallFwd += (profile.ballFwd - renderBallFwd) * clubK
        renderTop += (profile.topScale - renderTop) * clubK
        clubSettle += dt
        if mode == .aim {
            aimTime += dt
        }
        let targetRig: Rig
        let rigRate: Double
        if let anim = swingAnim {
            targetRig = RigBuilder.fromPose(
                swingPose(t: anim.t, fromPose: anim.fromPose, profile: anim.prof, heightPct: heightPct),
                ballFwd: renderBallFwd, clubLen: renderLen
            )
            rigRate = 45 // 스윙은 기민하게
        } else if mode == .walking, let w = walkAnim, w.t >= w.relax {
            var flavor = WalkFlavor()
            if let r = w.shoulderRange { // 0.6초에 걸쳐 어깨에 올렸다 내린다
                let up = min(1, max(0, (w.t - r.lowerBound) / 0.6))
                let down = min(1, max(0, (r.upperBound - w.t) / 0.6))
                flavor.shoulder = smoothstep(min(up, down))
            }
            if let ta = w.twirlAt, w.t >= ta { // 완료 후에도 1 유지 (+2π 고정 — 되감기 없음)
                flavor.twirl = smoothstep(min(1, (w.t - ta) / 1.0))
            }
            targetRig = RigBuilder.walking(phase: w.phase, vPx: w.vPx, clubLen: renderLen, flavor: flavor) { dx in
                let xm = self.stickX + dx / Double(self.pxPerM)
                return Double(self.groundY(xm) - self.groundY(self.stickX))
            }
            rigRate = 14 // 걸음은 또렷하게 — 진입·이탈은 보폭 램프가 받쳐준다
        } else if mode == .aim {
            targetRig = RigBuilder.fromPose(
                backswingPose(heightPct: heightPct, profile: profile, topScale: renderTop),
                ballFwd: renderBallFwd, clubLen: renderLen
            )
            // 진입 직후·클럽 변경 직후엔 천천히 가라앉고, 이후 입력에 기민하게
            rigRate = aimTime < 0.9 ? 6 : (clubSettle < 0.45 ? 7 : 14)
        } else if mode == .walking { // 피니시 여운 (relax) — 직립으로 느긋하게
            targetRig = RigBuilder.fromPose(Poses.upright, ballFwd: renderBallFwd, clubLen: renderLen)
            rigRate = 5
        } else {
            targetRig = RigBuilder.fromPose(lastFinishPose ?? Poses.p10, ballFwd: renderBallFwd, clubLen: renderLen)
            rigRate = 5
        }
        renderRig.chase(targetRig, rate: rigRate, dt: dt)

        // 렌더 반영
        stickman.position = CGPoint(x: px(stickX), y: groundY(stickX))
        stickman.render(rig: renderRig, club: club, dir: dir)

        if mode != .holed { // 홀인 드롭 연출 중에는 SKAction이 공 위치를 갖는다
            ballNode.position = CGPoint(x: px(ball.x), y: py(ball.y) + 5.5)
            let heightAbove = ball.y - hole.ground(at: ball.x)
            shadowNode.isHidden = heightAbove <= 0.2
            shadowNode.position = CGPoint(x: px(ball.x), y: groundY(ball.x) - 1)
        }

        if trailPoints.count > 1 {
            let path = CGMutablePath()
            path.move(to: trailPoints[0])
            for p in trailPoints.dropFirst() {
                path.addLine(to: p)
            }
            trailNode.path = path
            trailUnderNode.path = path
        } else {
            trailNode.path = nil
            trailUnderNode.path = nil
        }

        powerLabel.setText("\(Int(heightPct * 100))")
        powerLabel.isHidden = mode != .aim
        powerLabel.position = CGPoint(x: px(stickX) - CGFloat(dir) * 20, y: groundY(stickX) + 112)
    }
}
