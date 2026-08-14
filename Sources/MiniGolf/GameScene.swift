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
    var demoMode = false // --demo: 조준에서 자동 스윙 반복 — 모션 관찰용 (디버그 전용)
    var demoWallForce = false // --demo-wall: 매 홀을 벽 옆에서 시작 — 벽 스탠스 관찰용
    var demoCardPreview = false // --demo-card: 스코어카드 레이아웃 즉시 표시 (디버그 전용)
    private var demoWait = 0.0

    /// 연출 상태
    private struct SwingAnim { var t = 0.0; var launched = false; let prof: SwingProfile; let fromPose: Pose }
    /// 발 하나의 게이트 상태 — 접지점은 월드(진행축) 좌표로 래치되어 절대 밀리지 않는다
    private struct FootGait {
        var plant = 0.0 // 접지점 (진행축 px, 래치)
        var swingFrom = 0.0
        var swingTo = 0.0 // 리프트오프 순간 고정되는 다음 착지점
        var inSwing = false
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
    private var renderWallT = 0.0 // 벽 스탠스 근접도 (스무딩) — 뒷발 벽 딛기 자세 블렌드
    private var finishAt: TimeInterval = 0 // 피니시 도달 시각 — 무빙 홀드 감쇠 진동 기준
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
    private let hintLabel = GlassLabel(font: HUDFont.regular, size: 11.5, alpha: 0.66)
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

        // HUD는 지면 아래 스트립(0~96px 빈 띠) — 시선이 플레이 지점을 떠나지 않는다 (2026-08-14 사용자 결정)
        scoreTitle.position = CGPoint(x: size.width - 24, y: 66)
        scoreSub.position = CGPoint(x: size.width - 24, y: 40)
        clubTitle.position = CGPoint(x: 24, y: 66)
        clubSub.position = CGPoint(x: 24, y: 40)
        hintLabel.position = CGPoint(x: size.width / 2, y: 60)
        hintLabel.setText("←→ 클럽 · ↑↓ 백스윙 · Space 스윙 · R 새 라운드 · Esc 종료")
        pauseLabel.position = CGPoint(x: size.width / 2, y: size.height - 46) // 일시정지 배너만 상단(⛳️ 버튼 곁)
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
        if demoCardPreview { // 스코어카드 레이아웃 검증용 고정 샘플 (이글·버디·파·보기·더블·기권 포함)
            let sample: [(par: Int, strokes: Int, gaveUp: Bool)] = [
                (4, 4, false), (3, 2, false), (4, 5, false), (5, 3, false), (4, 4, false),
                (3, 6, false), (4, 12, true), (5, 5, false), (4, 3, false),
            ]
            scorecard.show(results: sample, title: "라운드 종료", footer: "합계 +7 · 흐린 숫자 = 기권  —  R로 새 라운드")
        }
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
        ball = BallState(x: hole.teeX, y: hole.ground(at: hole.teeX)) // 미러 홀은 오른쪽 티에서 시작
        if demoWallForce { // 벽 스탠스 관찰: 몸 뒤 공간이 ~45px 남는 대표 케이스로 시작
            let m = 45 / Double(pxPerM)
            let x = hole.holeX > hole.teeX ? m : hole.worldW - m
            ball = BallState(x: x, y: hole.ground(at: x))
        }
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

    /// ── 벽 스탠스: 화면 끝 = 벽. 몸 뒤 공간이 좁으면 백스윙이 제한되고(펀치샷),
    /// 실제 골퍼처럼 뒷발을 벽에 딛는 자세로 선다 (2026-08-14 사용자 요청 + 리서치 Q5) ──
    private var wallBehindPx: Double {
        dir > 0 ? Double(px(stickX)) : Double(size.width - px(stickX))
    }

    /// 백스윙 상한 — 하한 0.55: 실측(Bulbulian 2001)상 제한 백스윙도 스피드 손실이 크지 않다
    private var wallSwingCap: Double {
        guard !club.isPutter else { return 1 }
        return min(1, max(0.55, (wallBehindPx - 28) / 45))
    }

    /// 벽이 스탠스 폭보다 가까우면 몸을 벽 안쪽으로 압축 — 공이 스탠스 뒤쪽(극단에선 뒷발 밑)에
    /// 놓인다 (실제 펀치샷 기술: 볼을 스탠스 뒤에. 몸이 화면 밖으로 나가는 것도 이것으로 방지)
    private var wallBallFwd: Double {
        club.isPutter ? renderBallFwd : min(renderBallFwd, max(2, wallBehindPx - 10))
    }

    /// 벽 스탠스 자세 보정 — 뒷발을 벽에 올리고(가까울수록 높이), 체중은 앞발로,
    /// 그립은 초크다운. t: 벽 근접도 0~1 (renderWallT로 스무딩되어 들어온다)
    private func applyWallStance(_ rig: inout Rig, t: Double) {
        guard t > 0.001 else { return }
        let wallX = -wallBehindPx // 로컬(공 원점, facing 기준) 벽 위치
        rig.foot1 = CGPoint(
            x: mix(rig.foot1.x, wallX + 1.5, t),
            y: mix(rig.foot1.y, 7 + 9 * t, t)
        )
        rig.knee1 = CGPoint(
            x: (rig.hip.x + rig.foot1.x) / 2 + 2,
            y: (rig.hip.y + rig.foot1.y) / 2 + 4
        )
        rig.hip.x += 4 * t // 체중 앞발 (펀치 자세 — 리서치: 체중 65% 앞발)
        rig.shoulder.x += 3 * t
        rig.clubLen *= 1 - 0.10 * t // 초크다운
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
        var anim = WalkAnim(fromX: from, toX: to, dur: min(12.0, max(1.2, dist / 10)))
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
        // 풀파워 리스크: 모든 샷에 베이스 분산(±1°) + 80% 초과분^1.6의 리스크, 정규분포 근사
        // (uniform 3개 평균 ≈ 가우시안 — 큰 미스는 드물고 작은 흔들림이 대부분, 리서치 E)
        let overdrive = max(0, (heightPct - 0.8) / 0.2)
        let risk = 0.25 + 0.75 * pow(overdrive, 1.6)
        let gauss = (Double.random(in: -1 ... 1) + Double.random(in: -1 ... 1) + Double.random(in: -1 ... 1)) / 3
        let mishit = club.isPutter ? 0 : risk * gauss
        // 벽 제한 = 펀치샷: 파워는 남기고 낮은 탄도·적은 스핀으로 (장르 관행)
        let punch = club.isPutter ? 0 : max(0, 1 - wallSwingCap)
        Ballistics.launch(&ball, club: club, heightPct: heightPct, lie: lie, dir: dir, mishit: mishit, punch: punch)
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
            let footer = results.contains(where: \.gaveUp)
                ? "합계 \(totalStr) · 흐린 숫자 = 기권  —  R로 새 라운드"
                : "합계 \(totalStr)  —  R로 새 라운드"
            scorecard.show(results: results, title: "라운드 종료", footer: footer)
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
        flag.fillColor = Palette.flagRed
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

        if demoMode { // 자동 플레이: 조준 1.2s 후 스윙, 라운드 끝나면 새 라운드
            if mode == .aim {
                demoWait += dt
                if demoWait > 1.2 {
                    demoWait = 0
                    heightPct = min(Double.random(in: 0.5 ... 0.85), wallSwingCap)
                    startSwing()
                }
            } else if mode == .end {
                demoWait += dt
                if demoWait > 3 {
                    demoWait = 0
                    newRound()
                }
            } else {
                demoWait = 0
            }
        }

        if mode == .aim {
            let rate = club.isPutter ? 0.4 : 0.85
            if heldKeys.contains(126) {
                heightPct = min(1, heightPct + rate * dt)
            }
            if heldKeys.contains(125) {
                heightPct = max(0, heightPct - rate * dt)
            }
            heightPct = min(heightPct, wallSwingCap) // 벽 뒤 공간만큼만 백스윙 (펀치샷)
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
                stickX = w.fromX + (w.toX - w.fromX) * smoothstep(u)
                let vInst = abs(w.toX - w.fromX) * 6 * u * (1 - u) / w.dur
                w.vPx = vInst * Double(pxPerM)
                // 게이트 갱신: 보폭·듀티는 속도 함수, 접지점은 리프트오프 순간 래치 (노슬립)
                w.stepL = 22 * min(1, max(0.5, (w.vPx / 30).squareRoot()))
                w.duty = 0.68 - 0.08 * min(1, w.vPx / 30)
                let dNow = abs(stickX - w.fromX) * Double(pxPerM)
                if !w.gaitReady {
                    w.gaitReady = true
                    w.feet[0].plant = dNow + 8 // 어드레스 발 위치 근처에서 시작
                    w.feet[1].plant = dNow - 10
                }
                w.gaitPhase += w.vPx * dt / (2 * w.stepL)
                for i in 0 ..< 2 {
                    let f = (w.gaitPhase + (i == 1 ? 0.5 : 0)).truncatingRemainder(dividingBy: 1)
                    if f < w.duty {
                        if w.feet[i].inSwing { // 착지 — 목표점에 래치
                            w.feet[i].inSwing = false
                            w.feet[i].plant = w.feet[i].swingTo
                        }
                    } else if !w.feet[i].inSwing { // 리프트오프 — 다음 착지점을 지금 고정
                        w.feet[i].inSwing = true
                        w.feet[i].swingFrom = w.feet[i].plant
                        w.feet[i].swingTo = dNow + 2 * w.stepL * (1 - w.duty) + w.duty * w.stepL
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
        // 벽 근접도 (0~1) — 조준·스윙 중에만 켜지고, 스무딩으로 자세가 툭 바뀌지 않는다
        let wallTarget = (mode == .aim || swingAnim != nil) && !club.isPutter
            ? smoothstep(min(1, max(0, (80 - wallBehindPx) / 36)))
            : 0
        renderWallT += (wallTarget - renderWallT) * (1 - exp(-6 * dt))
        var targetRig: Rig
        let rigRate: Double
        var rigClubRate: Double? = nil // 팔로스루 오버랩 — 클럽만 느린 추적
        if let anim = swingAnim {
            targetRig = RigBuilder.fromPose(
                swingPose(t: anim.t, fromPose: anim.fromPose, profile: anim.prof, heightPct: heightPct),
                ballFwd: wallBallFwd, clubLen: renderLen
            )
            // 다운스윙은 초고속 추적(220) — 스무딩 지연(≈31°)이 '클럽이 공에 닿는 프레임'을
            // 지우고 있었다 (리서치 P1). 임팩트 후는 45로 복귀 (그 시점 오차 ≈1°라 킥 없음)
            rigRate = anim.t < anim.prof.down ? 220 : 45
            if anim.t >= anim.prof.down { // 팔로스루: 클럽만 늦게 멈추는 오버랩 (리서치 P6)
                rigClubRate = 22
            }
            // 임팩트까지는 벽 스탠스 유지, 팔로스루에서 0.25s에 걸쳐 발을 내린다
            let wallSwingT = anim.t < anim.prof.down
                ? renderWallT
                : renderWallT * max(0, 1 - (anim.t - anim.prof.down) / 0.25)
            applyWallStance(&targetRig, t: wallSwingT)
        } else if mode == .walking, let w = walkAnim, w.t >= w.relax {
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
                let f = (w.gaitPhase + (i == 1 ? 0.5 : 0)).truncatingRemainder(dividingBy: 1)
                let g = w.feet[i]
                if !g.inSwing {
                    return (g.plant - dPx, 0)
                }
                let sw = max(0, (f - w.duty) / (1 - w.duty))
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
            rigRate = 14 // 상체는 부드럽게 — 발·무릎은 아래 footRate로 고속 추적
        } else if mode == .aim {
            targetRig = RigBuilder.fromPose(
                backswingPose(heightPct: heightPct, profile: profile, topScale: renderTop),
                ballFwd: wallBallFwd, clubLen: renderLen
            )
            applyWallStance(&targetRig, t: renderWallT)
            // 진입 직후엔 느리게 → 연속 램프로 기민해진다 (계단식 속도 전환 = 가속 킥 = 움찔의 원인)
            rigRate = 5 + 8 * smoothstep(min(1, aimTime / 1.1))
        } else if mode == .walking { // 피니시 여운 (relax) — 직립으로 느긋하게
            targetRig = RigBuilder.fromPose(Poses.upright, ballFwd: renderBallFwd, clubLen: renderLen)
            rigRate = 5
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
        let footRate: Double? = mode == .walking && (walkAnim.map { $0.t >= $0.relax } ?? false) ? 60 : nil
        renderRig.chase(targetRig, rate: rigRate, footRate: footRate, clubRate: rigClubRate, dt: dt)

        // 렌더 반영
        stickman.position = CGPoint(x: px(stickX), y: groundY(stickX))
        stickman.render(
            rig: renderRig, club: club, prevClub: prevHeadClub,
            headMorph: headMorph, visualLoft: renderLoft, dir: dir
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

        // 조준 중 캐릭터 위: 클럽 약어 + 파워 (좌상단까지 시선 왕복 제거 — 2026-08-14 사용자 요청)
        powerLabel.setText("\(club.id) · \(Int(heightPct * 100))")
        powerLabel.isHidden = mode != .aim
        powerLabel.position = CGPoint(
            x: min(size.width - 54, max(54, px(stickX) - CGFloat(dir) * 20)), // 벽 옆에서도 잘리지 않게
            y: groundY(stickX) + 112
        )
    }
}
