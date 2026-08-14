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

    /// 연출 상태
    private struct SwingAnim { var t = 0.0; var launched = false; let prof: SwingProfile; let fromPose: Pose }
    /// 발 하나의 게이트 상태 — 접지점은 월드(진행축) 좌표로 래치되어 절대 밀리지 않는다
    private struct FootGait {
        var plant = 0.0 // 접지점 (진행축 px, 래치)
        var swingFrom = 0.0
        var swingTo = 0.0 // 리프트오프 순간 고정되는 다음 착지점
        var inSwing = false
        var sw = 0.0 // 스윙 진행 0→1 (모노토닉 — 위상 또는 시간 중 빠른 쪽)
    }

    private struct WalkAnim {
        let fromX, toX, dur: Double
        var t = 0.0
        let relax = 0.8 // 피니시 여운 — 서두르지 않는다
        var vPx = 0.0
        // 게이트 상태 (리서치 반영: stride warping + 접지점 래치)
        var gaitPhase = 0.0 // 보행 위상 (1 = 두 걸음)
        var stepL = 22.0 // 현재 보폭 — 속도에 비례해 줄어든다 (walk ratio)
        var duty = 0.66 // 접지 비율 — 느릴수록 커진다 (double support 증가)
        var feet = [FootGait(), FootGait()]
        var gaitReady = false
        // 랜덤 잉여 동작 (생명감): 어깨 캐리 구간 + 짧은 모션 이벤트들 (walk 시작 기준 초)
        var shoulderRange: ClosedRange<Double>?
        var flavorEvents: [WalkFlavorEvent] = []
    }

    private var swingAnim: SwingAnim?
    private var walkAnim: WalkAnim?
    private var lastFinishPose: Pose?
    private var renderRig = RigBuilder.fromPose(Poses.p1, ballFwd: 24, clubLen: 31)
    // 클럽 변경 시 즉시 점프하는 값들은 전부 스무딩을 탄다 (길이·스탠스·백스윙 폭)
    private var renderLen = 31.0
    private var renderBallFwd = 24.0
    private var renderTop = 1.0
    private var renderLoft = 10.5 // 헤드 기하(크기·틸트·굵기)도 이 값으로 구동 — 모양 점프 방지
    // 헤드 '종류'(우드/블레이드/퍼터) 전환은 캡슐 기하 morph — 이전 종류에서 새 종류로 0.3s 변형
    private var prevHeadClub = ClubTable.all[0]
    private var lastClub = ClubTable.all[0]
    private var headMorph = 1.0
    private var aimTime = 0.0 // 조준 진입 후 경과 — 진입 직후엔 천천히 가라앉는다
    private var finishAt: TimeInterval = 0 // 피니시 도달 시각 — 무빙 홀드 감쇠 진동 기준
    private var renderSlopeTilt = 0.0 // 경사 라이 스탠스 기울기 (스무딩)
    private var renderDir = 1.0 // 바라보는 방향 스무딩 — 반전 시 종이처럼 접히며 돌아선다
    // 모드 전환 타깃 크로스페이드 (Bollo Inertialization 계열 — 타깃 점프가 속도 계단을 만드는 것 방지)
    private var lastBranch = -1
    private var transFrom: Rig?
    private var transAt: TimeInterval = 0
    private var transDur = 0.25
    private var lastTargetSnapshot: Rig?
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
    /// 경사 라이: 스탠스 기울기 = 로프트 전달 비율 (같은 상수를 공유해야 물리·애니메이션이 정합)
    private let slopeTiltRatio = 0.7

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

    /// 화면 끝 = 벽. 몸 뒤 공간이 부족하면 백스윙이 제한된다 — 펀치샷 (낮은 탄도·적은 스핀)
    /// 하한 0.55: 실측(Bulbulian 2001 — 제한 백스윙도 스피드 -8%뿐)상 파워를 심하게 깎지 않는다
    private var wallSwingCap: Double {
        guard !club.isPutter else { return 1 }
        let behind = dir > 0 ? Double(px(stickX)) : Double(size.width - px(stickX))
        return min(1, max(0.55, (behind - 28) / 45))
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
        // 완전 여유로운 걸음 — 실제 골퍼처럼 서두르지 않는다
        // (smootherstep은 피크 속도가 1.875Δ/T라 dist/8로 보정 — 체감 속도는 이전과 동일)
        var anim = WalkAnim(fromX: from, toX: to, dur: min(12.0, max(1.2, dist / 8)))
        // 랜덤 잉여 동작: 긴 이동은 어깨 캐리 + 20종 모션을 겹치지 않게 흩뿌린다
        if anim.dur > 4.5, Double.random(in: 0 ..< 1) < 0.5 {
            anim.shoulderRange = (anim.relax + 0.8) ... (anim.relax + anim.dur * 0.72)
        }
        var t = anim.relax + 0.7
        while t < anim.relax + anim.dur - 1.2, anim.flavorEvents.count < 4 {
            guard Double.random(in: 0 ..< 1) < 0.5 else {
                t += 1.1
                continue
            }
            let kind = WalkFlavorKind.allCases.randomElement()!
            let dur = kind.duration
            // 어깨에 클럽을 걸친 동안엔 클럽 손짓 불가 (클럽이 손에 없다)
            if kind.needsClub, let r = anim.shoulderRange, r.overlaps(t ... (t + dur)) {
                t += 1.0
                continue
            }
            anim.flavorEvents.append(WalkFlavorEvent(kind: kind, t0: t, dur: dur))
            t += dur + Double.random(in: 0.8 ... 2.2)
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
        // 경사 라이(오르막=더 뜸) + 풀파워 리스크(80% 초과분의 제곱으로 미스샷 확률·크기 증가)
        // 경사는 스탠스 기울기와 같은 비율만 로프트로 전달 (물리·애니메이션 정합 — 리서치 C)
        let slope = club.isPutter ? 0 : hole.slope(at: ball.x) * slopeTiltRatio
        // 미스샷: 모든 샷에 베이스 분산(±1°) + 80% 초과분^1.6 리스크, 정규분포 근사 (리서치 E)
        let overdrive = max(0, (heightPct - 0.8) / 0.2)
        let risk = 0.25 + 0.75 * pow(overdrive, 1.6)
        let gauss = (Double.random(in: -1 ... 1) + Double.random(in: -1 ... 1) + Double.random(in: -1 ... 1)) / 3
        let mishit = club.isPutter ? 0 : risk * gauss
        // 벽 제한 = 펀치샷: 파워는 남기고 낮은 탄도·적은 스핀으로 (리서치 D — 장르 관행)
        let punch = club.isPutter ? 0 : max(0, 1 - wallSwingCap)
        Ballistics.launch(
            &ball, club: club, heightPct: heightPct, lie: lie, dir: dir,
            slope: slope, mishit: mishit, punch: punch
        )
        strokes += 1
        if !club.isPutter { // 임팩트 타격감: 공 신장 + 헤드 스미어 (퍼터는 조용히)
            // 히트스톱은 실플레이에서 '렉'으로 읽혀 제거 (2026-08-14 사용자 판정 —
            // 골프처럼 한 번의 연속 동작에선 정지가 타격감이 아니라 프레임 드랍으로 보인다)
            ballNode.zRotation = CGFloat(atan2(ball.vy, ball.vx))
            ballNode.xScale = 1.4
            ballNode.yScale = 0.72
            ballNode.run(.sequence([
                .group([.scaleX(to: 1, duration: 0.14), .scaleY(to: 1, duration: 0.14)]),
                .run { [weak self] in self?.ballNode.zRotation = 0 },
            ]))
            stickman.impactSmear()
        }
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
        case 123: clubIdx = max(0, clubIdx - 1); presetPutterHeight(); updateHUD() // ←
        case 124: clubIdx = min(ClubTable.all.count - 1, clubIdx + 1); presetPutterHeight(); updateHUD() // →
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
            heightPct = min(heightPct, wallSwingCap) // 화면 끝 = 벽: 뒷공간만큼만 백스윙 (펀치샷)
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
                finishAt = currentTime
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
                stickX = w.fromX + (w.toX - w.fromX) * smootherstep(u) // 최소 저크 (가속도도 0에서 시작)
                let vInst = abs(w.toX - w.fromX) * 6 * u * (1 - u) / w.dur
                w.vPx = vInst * Double(pxPerM)
                // 게이트 갱신: 보폭·듀티는 속도 함수, 접지점은 리프트오프 순간 래치 (노슬립)
                w.stepL = 22 * min(1, max(0.5, (w.vPx / 30).squareRoot()))
                w.duty = 0.68 - 0.08 * min(1, w.vPx / 30)
                let dNow = abs(stickX - w.fromX) * Double(pxPerM)
                if !w.gaitReady {
                    if w.vPx > 4 { // 몸이 실제로 움직이기 시작한 뒤에야 게이트 시동 (제자리 스텝 방지)
                        w.gaitReady = true
                        // 첫 접지점 = 지금 서 있는 발 위치 그대로 — 걷기 진입 순간 발이 점프하지 않는다
                        w.feet[0].plant = dNow + Double(renderRig.foot1.x)
                        w.feet[1].plant = dNow + Double(renderRig.foot2.x)
                        // 위상을 duty에서 시작 = 뒷발이 첫 프레임에 리프트오프 (보행 개시·pose matching)
                        // gaitPhase=0이면 뒷발이 위상 0.68까지 안 떨어져 다리가 늘어난다 (리서치 A2)
                        w.gaitPhase = w.duty
                    }
                }
                if w.gaitReady {
                    w.gaitPhase += w.vPx * dt / (2 * w.stepL)
                }
                for i in 0 ..< 2 where w.gaitReady {
                    let f = (w.gaitPhase + (i == 1 ? 0.5 : 0)).truncatingRemainder(dividingBy: 1)
                    if !w.feet[i].inSwing {
                        // 과신장 강제 리프트오프 (Holden unlock) — 다리가 늘어나기 전에 발을 뗀다
                        let cx = w.feet[i].plant - dNow
                        let overreach = (cx * cx + 43.5 * 43.5).squareRoot() > 48
                        if f >= w.duty || overreach {
                            w.feet[i].inSwing = true
                            w.feet[i].sw = 0
                            w.feet[i].swingFrom = w.feet[i].plant
                            w.feet[i].swingTo = dNow + 2 * w.stepL * (1 - w.duty) + w.duty * w.stepL
                        }
                    } else {
                        // 스윙 진행: 위상 기반과 시간 바닥(0.35s) 중 빠른 쪽, 모노토닉
                        let phaseSw = f >= w.duty ? (f - w.duty) / (1 - w.duty) : 0
                        w.feet[i].sw = max(phaseSw, w.feet[i].sw + dt / 0.35)
                        if w.feet[i].sw >= 1 { // 착지 — 목표점에 래치
                            w.feet[i].inSwing = false
                            w.feet[i].plant = w.feet[i].swingTo
                        }
                    }
                }
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
        /// 헤드 '종류'가 바뀌면 morph 시작 (캡슐 기하 변형 — 몸 동작 없이 헤드만 변한다)
        func headKind(_ c: Club) -> Int {
            c.cat == .wood ? 0 : c.cat == .putter ? 2 : 1
        }
        if headKind(club) != headKind(lastClub) {
            prevHeadClub = lastClub
            headMorph = 0
        }
        lastClub = club
        headMorph = min(1, headMorph + dt / 0.3)
        renderLoft += (club.loft - renderLoft) * clubK
        if mode == .aim {
            aimTime += dt
        }
        var targetRig: Rig
        let rigRate: Double
        var rigClubRate: Double? = nil // 팔로스루 오버랩 — 클럽만 느린 추적
        var branch = 4 // 타깃 브랜치 id: 0 스윙 · 1 걷기 · 2 조준 · 3 여운 · 4 홀드
        var gaitFeet: (CGPoint, CGPoint, CGPoint, CGPoint)? // 걷기 발·무릎 — 블렌드에서 보호
        if let anim = swingAnim {
            targetRig = RigBuilder.fromPose(
                swingPose(t: anim.t, fromPose: anim.fromPose, profile: anim.prof, heightPct: heightPct),
                ballFwd: renderBallFwd, clubLen: renderLen
            )
            // 다운스윙은 초고속 추적(220) — 스무딩 지연(≈31°)이 '클럽이 공에 닿는 프레임'을
            // 지우고 있었다 (리서치 P1). 임팩트 후는 45로 복귀 (그 시점 오차 ≈1°라 킥 없음)
            rigRate = anim.t < anim.prof.down ? 220 : 45
            branch = 0
            if anim.t >= anim.prof.down { // 팔로스루: 클럽만 늦게 멈추는 오버랩 (리서치 P6)
                rigClubRate = 22
            }
        } else if mode == .walking, let w = walkAnim, w.t >= w.relax, w.gaitReady {
            var flavor = WalkFlavor()
            if let r = w.shoulderRange { // 0.6초에 걸쳐 어깨에 올렸다 내린다
                let up = min(1, max(0, (w.t - r.lowerBound) / 0.6))
                let down = min(1, max(0, (r.upperBound - w.t) / 0.6))
                flavor.shoulder = smoothstep(min(up, down))
            }
            for e in w.flavorEvents {
                let u = (w.t - e.t0) / e.dur
                guard u > 0 else { continue }
                let ss = smoothstep(min(1, u))
                switch e.kind {
                // 트월 계열: 완료 후에도 누적각 유지 — 되감기 없음
                case .twirl: flavor.twirlAngle += 2 * .pi * ss
                case .twirlDouble: flavor.twirlAngle += 4 * .pi * ss
                case .twirlReverse: flavor.twirlAngle -= 2 * .pi * ss
                default:
                    guard u < 1 else { continue }
                    let bell = smoothstep(min(1, min(u, 1 - u) / 0.3)) // 부드러운 in-hold-out
                    let wob2 = sin(4 * .pi * u) * bell // 2회 진동
                    switch e.kind {
                    case .lookBack: flavor.lookBack = max(flavor.lookBack, bell)
                    case .lookSky: flavor.headDxOff += 2 * bell; flavor.headDyOff += 3 * bell
                    case .lookHole: flavor.headDxOff += 3.5 * bell
                    case .headBob: flavor.headDxOff += 1.5 * sin(6 * .pi * u) * bell
                    case .headTilt: flavor.headDyOff -= 2.5 * bell
                    case .hatTouch: flavor.hatTouch = max(flavor.hatTouch, bell)
                    case .armSwing: flavor.armAmpBoost += 1.2 * bell
                    case .shrug: flavor.shoulderYOff += 2.5 * bell
                    case .slump: flavor.shoulderYOff -= 2 * bell
                    case .stretch:
                        flavor.shoulderYOff += 1.5 * bell
                        flavor.headDyOff += 2 * bell
                        flavor.gripLift += 0.4 * bell
                    case .skip, .skipJoy: flavor.skip = max(flavor.skip, bell)
                    case .hipSway: flavor.hipXOff += 2 * wob2
                    case .shoulderRoll: flavor.shoulderYOff += 1.8 * wob2
                    case .wristRoll: flavor.phiWobble += 0.25 * wob2
                    case .clubRaise: flavor.gripLift += bell; flavor.phiWobble += 0.35 * bell
                    case .clubTapShoulder: flavor.gripLift += 0.8 * bell; flavor.phiWobble += 0.3 * wob2
                    case .twirl, .twirlDouble, .twirlReverse: break
                    }
                }
            }
            // 발 위치: 접지발 = 래치된 접지점 그대로, 스윙발 = 고정된 목표로 보간 (노슬립)
            let dPx = abs(stickX - w.fromX) * Double(pxPerM)
            let vAmp = min(1, w.vPx / 30)
            func footPose(_ i: Int) -> (x: Double, lift: Double) {
                let g = w.feet[i]
                if !g.inSwing {
                    return (g.plant - dPx, 0)
                }
                let sw = min(1, g.sw)
                // sin² 프로파일: 이륙·착지 모두 속도 0 (발 '찍기' 제거)
                let lift = sin(.pi * sw) * sin(.pi * sw) * (3 + 5 * vAmp + 6 * flavor.skip)
                return (mix(g.swingFrom, g.swingTo, smoothstep(sw)) - dPx, lift)
            }
            targetRig = RigBuilder.walking(
                f1: footPose(0), f2: footPose(1), gaitPhase: w.gaitPhase,
                vPx: w.vPx, clubLen: renderLen, flavor: flavor
            ) { dx in
                let xm = self.stickX + dx / Double(self.pxPerM)
                return Double(self.groundY(xm) - self.groundY(self.stickX))
            }
            gaitFeet = (targetRig.foot1, targetRig.foot2, targetRig.knee1, targetRig.knee2)
            // 도착 위상: 진입(relax)의 원점 블렌드와 대칭 — 마지막 0.6s 동안 걷기 원점(0)에서
            // 어드레스 스탠스(-ballFwd)로 흘려보내 24~51px 스케이팅 제거 (상체만 — 발은 접지 유지)
            let arriveU = smootherstep(min(1, max(0, (w.t - (w.relax + w.dur - 0.6)) / 0.6)))
            if arriveU > 0 {
                let standRig = RigBuilder.fromPose(
                    Poses.upright, ballFwd: renderBallFwd * arriveU, clubLen: renderLen
                )
                targetRig = Rig.lerp(targetRig, standRig, arriveU)
            }
            rigRate = 14 // 상체는 부드럽게 — 발·무릎은 아래 footRate로 고속 추적
            branch = 1
        } else if mode == .aim {
            targetRig = RigBuilder.fromPose(
                backswingPose(heightPct: heightPct, profile: profile, topScale: renderTop),
                ballFwd: renderBallFwd, clubLen: renderLen
            )
            // 진입 직후엔 느리게 → 연속 램프로 기민해진다 (계단식 속도 전환 = 가속 킥 = 움찔의 원인)
            rigRate = 5 + 8 * smoothstep(min(1, aimTime / 1.1))
            branch = 2
        } else if mode == .walking { // 피니시 여운 (relax) — 직립으로 느긋하게
            // 스탠스 원점(-ballFwd)을 걷기 원점(0)으로 흘려보내 걷기 시작 순간의 스텝 밀림 제거
            let ru = walkAnim.map { smoothstep(min(1, $0.t / $0.relax)) } ?? 1
            targetRig = RigBuilder.fromPose(Poses.upright, ballFwd: renderBallFwd * (1 - ru), clubLen: renderLen)
            rigRate = 5
            branch = 3
        } else {
            targetRig = RigBuilder.fromPose(lastFinishPose ?? Poses.p10, ballFwd: renderBallFwd, clubLen: renderLen)
            rigRate = 5
        }
        // 피니시 무빙 홀드: 완전 정지 대신 클럽이 관성으로 미세하게 흔들리다 잦아든다 (리서치 P6)
        if swingAnim == nil, mode == .motion || mode == .holed {
            let ft = currentTime - finishAt
            if ft > 0, ft < 3 {
                let osc: Double = sin(2 * Double.pi * 1.8 * ft)
                let decay: Double = exp(-ft * 2.2)
                targetRig.clubPhi += 0.18 * osc * decay
            }
        }
        // 걷기 중 발·무릎은 고속 추적 — 접지점이 스무딩에 밀려 미끄러져 보이는 것을 방지
        // 모드 전환 크로스페이드 — 타깃이 한 프레임에 점프해 속도 계단(0→213px/s)을 만드는 것 방지.
        // 스윙 진입(branch 0)만 즉응 유지 (Bollo GDC 2018, UE 블렌드 0.4s 상한)
        if branch != lastBranch {
            if lastBranch >= 0, branch != 0 {
                transFrom = lastTargetSnapshot
                transAt = currentTime
                transDur = branch == 3 ? 0.35 : 0.25 // 피니시→직립이 가장 먼 포즈
            }
            lastBranch = branch
        }
        if let from = transFrom {
            let tt = (currentTime - transAt) / transDur
            if tt < 1 {
                targetRig = Rig.lerp(from, targetRig, smootherstep(max(0, min(1, tt))))
            } else {
                transFrom = nil
            }
        }
        // 걷기 중 발·무릎은 어떤 블렌드에도 섞이지 않는다 — 접지점이 섞이면 그게 곧 미끄러짐
        if let gf = gaitFeet {
            targetRig.foot1 = gf.0
            targetRig.foot2 = gf.1
            targetRig.knee1 = gf.2
            targetRig.knee2 = gf.3
        }
        lastTargetSnapshot = targetRig

        let footRate: Double? = mode == .walking && (walkAnim.map { $0.t >= $0.relax && $0.gaitReady } ?? false) ? 60 :
            nil
        renderRig.chase(targetRig, rate: rigRate, footRate: footRate, clubRate: rigClubRate, dt: dt)

        // 렌더 반영 — 경사 라이: 걷기 외에는 스탠스가 지면 경사를 따라 기운다 (물리와 동일 비율)
        let tiltTarget = mode == .walking ? 0 : slopeTiltRatio * atan(hole.slope(at: stickX))
        renderSlopeTilt += (tiltTarget - renderSlopeTilt) * (1 - exp(-6 * dt))
        stickman.zRotation = CGFloat(renderSlopeTilt)
        // 방향 반전은 한 프레임 미러 대신 종이 인형처럼 접히며 돌아선다
        renderDir += (dir - renderDir) * (1 - exp(-8 * dt))
        stickman.position = CGPoint(x: px(stickX), y: groundY(stickX))
        stickman.render(
            rig: renderRig, club: club, prevClub: prevHeadClub,
            headMorph: headMorph, visualLoft: renderLoft, dir: renderDir
        )

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
