import AppKit
import GolfCore
import SpriteKit

// 서프라이즈 2차 (2026-09-16, 사용자 선택 "계열별 1종") — 1차 프레임워크(Surprises.swift) 위에 다섯 종류를 더한다.
// 데스크탑 `windowTunnel` · 규칙 `pinMove` · 물리 `ballSwap` · 스틱맨 `gallery` · 생물 `geese`.
// 셋(핀·택배·거위)은 씬을 점유하고, 둘(터널·갤러리)은 비행·다음 샷 위에 얹힌다.
// 3박자는 각 함수 주석에: 예고 → 사건 → 반응.

/// 창 터널 통과 상태 — 진입 순간의 속도를 들고 출구에서 다시 난다 (통과 중엔 비행 물리 정지)
struct TunnelTransit {
    let until: TimeInterval
    let exit: (x: Double, y: Double)
    let vx: Double
    let vy: Double
    var portalShown = false
}

/// 갤러리 상태 — 도착 → 관전 → (샷 종료) 반응 → 퇴장
struct GalleryState {
    enum Phase { case arriving, watching, reacting, leaving }
    enum Verdict { case cheer, clap, groan }
    let node: SKNode
    let targets: [CGFloat] // 관중별 관전 자리 x — 도착 전에 샷이 끝나면 여기로 스냅한다 (리뷰 m6)
    var phase: Phase
    var verdict: Verdict?
    var sceneTaken = false // 공이 멈춘 샷이면 스틱맨 반응을 위해 잠깐 씬을 점유한다 (한 번만)
}

extension BallKind {
    /// 공 노드 렌더 배율 — applyBallStyle과 임팩트 스쿼시 복원이 같은 값을 써야 한다 (리뷰 m2)
    var renderScale: CGFloat {
        switch self {
        case .standard: 1
        case .rubber: 1.15
        case .bowling: 1.75
        }
    }
}

extension GameScene {
    static let tunnelGhostName = "tunnelGhost"
    static let demoBumperName = "demoBumper"

    // ── 공통 ──

    /// 샷이 끝나는 순간(홀인·입수·정지) 한 번 — 공 바꿔치기 복귀, 터널 잔상 정리, 갤러리 판정
    func onShotEnded(terminal: StepEvent) {
        if ballKind != .standard {
            revertBallKind()
        }
        if tunnelArmed { // 창을 한 번도 안 지나 무산된 터널 — epic 카운트(라운드 1회)를 돌려준다 (리뷰 n2)
            surpriseCounts[.windowTunnel] = max(0, surpriseCounts[.windowTunnel, default: 1] - 1)
        }
        tunnelArmed = false
        enumerateChildNodes(withName: Self.tunnelGhostName) { node, _ in
            node.run(.sequence([.fadeOut(withDuration: 1.1), .removeFromParent()]))
        }
        if let g = galleryState, g.phase == .arriving || g.phase == .watching {
            galleryJudge(terminal: terminal)
        }
    }

    /// 매 프레임 (updateSurprises에서) — 창 터널 출구
    func updateSurprises2(currentTime: TimeInterval) {
        updateTunnel(currentTime: currentTime)
    }

    /// 홀 시작·새 라운드 정리 (cancelSurprises에서)
    func cancelSurprises2() {
        tunnelArmed = false
        tunnelTransit = nil
        ballNode.isHidden = false
        enumerateChildNodes(withName: Self.tunnelGhostName) { node, _ in node.removeFromParent() }
        galleryState?.node.removeFromParent()
        galleryState = nil
        flagNode.removeAllActions() // 걷던 깃발 — startHole의 rebuildTerrain이 제자리에 다시 그린다
        if ballKind != .standard {
            revertBallKind()
        }
    }

    /// 지연 실행을 서프라이즈 노드에 매단다 — 새 홀에서 cancelSurprises()가 노드를 지우면 예약도 함께 사라진다
    /// (씬 자체에 run하면 R 새 라운드 뒤에도 클로저가 살아남는다 — 1차 리뷰 M2와 같은 함정)
    func afterSurprise(_ delay: Double, _ block: @escaping () -> Void) {
        let timer = SKNode()
        timer.name = Self.surpriseNodeName
        addChild(timer)
        timer.run(.sequence([.wait(forDuration: delay), .run { [weak timer] in
            // 같은 프레임에 정리된 타이머는 건너뛴다 — 씬 액션(데모 재시작)이 노드를 지운 프레임에도 SpriteKit은 그 액션 패스의
            // 나머지 노드 액션을 평가한다 (3차 --demo-restart-in 2.0에서 뻐꾸기 울음이 새 라운드에 한 번 더 찍힘, 2026-09-23)
            guard timer?.parent != nil else { return }
            block()
        }, .removeFromParent()]))
    }

    /// 지면을 따라 x를 옮기는 걷기 액션 (관중·거위 공용) — y는 표고를 따라가고 잔걸음만큼 통통 튄다
    func groundWalk(
        from x0: CGFloat,
        to x1: CGFloat,
        dur: Double,
        bob: CGFloat = 1.5,
        stepsPerSec: Double = 6
    ) -> SKAction {
        SKAction.customAction(withDuration: dur) { [weak self] node, t in
            guard let self else { return }
            let u = min(1, Double(t) / dur)
            let x = x0 + (x1 - x0) * CGFloat(u)
            let hop = CGFloat(abs(sin(Double(t) * .pi * stepsPerSec))) * bob
            node.position = CGPoint(x: x, y: groundY(Double(x) / Double(pxPerM)) + hop)
        }
    }

    /// 포물선 점프 (공 교체·거위 공용): 중간에 위로 솟았다 내려온다
    func arcHop(from a: CGPoint, to b: CGPoint, lift: CGFloat, dur: Double) -> SKAction {
        let up = SKAction.move(to: CGPoint(x: (a.x + b.x) / 2, y: max(a.y, b.y) + lift), duration: dur * 0.5)
        up.timingMode = .easeOut
        let down = SKAction.move(to: b, duration: dur * 0.5)
        down.timingMode = .easeIn
        return .sequence([up, down])
    }

    // ── 데스크탑: 창 터널 (비행 훅, epic) ──

    /// 예고 = 발사 직후 창들의 윤곽이 세 번 술렁이고 낮은 웅웅 · 사건 = 첫 창 진입 순간 공이 창 속으로 사라졌다가
    /// 홀 쪽으로 더 나아간 다른 창(없으면 같은 창)의 반대편에서 같은 속도로 튀어나온다 · 반응 = 화들짝 → 낄낄
    func playWindowTunnel() {
        guard !shotBumpers.isEmpty else { return } // 지날 창이 없으면 조용히 (강제 관찰 모드에서만 올 수 있는 경로)
        tunnelArmed = true
        SoundKit.shared.hum()
        for r in shotBumpers {
            let outline = SKShapeNode(rect: bumperRect(r))
            outline.name = Self.surpriseNodeName
            outline.strokeColor = NSColor(white: 1, alpha: 0.75)
            outline.fillColor = .clear
            outline.lineWidth = 1.2
            outline.alpha = 0
            outline.zPosition = 3
            addChild(outline)
            outline.run(.sequence([
                .repeat(
                    .sequence([.fadeAlpha(to: 0.9, duration: 0.22), .fadeAlpha(to: 0.15, duration: 0.22)]),
                    count: 3
                ),
                .fadeOut(withDuration: 0.3),
                .removeFromParent(),
            ]))
        }
        toast("창이 술렁인다…", sub: nil)
        if demoMode {
            print("TUNNEL armed bumpers \(shotBumpers.count)")
            fflush(stdout)
        }
    }

    /// 범퍼(미터·표고) → 씬 사각형(pt)
    func bumperRect(_ r: Bumper) -> CGRect {
        CGRect(x: px(r.x), y: py(r.y), width: px(r.w), height: CGFloat(r.h) * pxPerM)
    }

    /// 비행 스텝마다 — 무장 상태에서 공이 창 안으로 들어가면 반사 대신 삼킨다 (GameScene 비행 루프에서 호출).
    /// 출구는 진행 방향으로 가장 멀리 있는 다른 창, 없으면 같은 창의 반대편 면. 속도는 진입 그대로
    func enterTunnelIfInside(prevX: Double, prevY: Double) -> Bool {
        guard ball.phase == .fly,
              let entry = shotBumpers.first(where: { $0.contains(ball.x, ball.y) && !$0.contains(prevX, prevY) })
        else { return false }
        tunnelArmed = false
        let forward = ball.vx >= 0 ? 1.0 : -1.0
        func center(_ b: Bumper) -> Double {
            b.x + b.w / 2
        }
        let ahead = shotBumpers.filter { $0 != entry && forward * (center($0) - center(entry)) > 0 }
        let exitB = ahead.max { forward * center($0) < forward * center($1) } ?? entry
        let exitX = min(max(forward > 0 ? exitB.x + exitB.w + 0.1 : exitB.x - 0.1, 1), hole.worldW - 1)
        let insideY = min(max(ball.y, exitB.y + 0.3), exitB.y + exitB.h - 0.3)
        let exitY = max(hole.ground(at: exitX) + 0.3, insideY)
        let entryPt = CGPoint(x: px(ball.x), y: py(ball.y) + 5.5)
        let exitPt = CGPoint(x: px(exitX), y: py(exitY) + 5.5)
        let dist = Double(hypot(exitPt.x - entryPt.x, exitPt.y - entryPt.y))
        let dur = min(1.3, 0.3 + dist / 1000)
        tunnelTransit = TunnelTransit(until: lastTime + dur, exit: (exitX, exitY), vx: ball.vx, vy: ball.vy)
        freezeTrailAsGhost() // 궤적은 진입점에서 끊긴다 — 출구에서 새로 시작
        ballNode.isHidden = true
        shadowNode.isHidden = true
        portalRing(at: entryPt)
        SoundKit.shared.warp(up: true)
        react(.startled)
        toast("창 터널!", sub: "…어디로 나오지?")
        if demoMode {
            print(String(
                format: "TUNNEL in (%.1f, %.1f) → out (%.1f, %.1f) v(%.1f, %.1f) %.2fs",
                ball.x, ball.y, exitX, exitY, ball.vx, ball.vy, dur
            ))
            fflush(stdout)
        }
        return true
    }

    private func updateTunnel(currentTime: TimeInterval) {
        guard var t = tunnelTransit else { return }
        let exitPt = CGPoint(x: px(t.exit.x), y: py(t.exit.y) + 5.5)
        if !t.portalShown, currentTime >= t.until - 0.35 { // 출구 예고 — 나올 자리에 고리가 먼저 퍼진다
            t.portalShown = true
            tunnelTransit = t
            portalRing(at: exitPt)
        }
        guard currentTime >= t.until else { return }
        tunnelTransit = nil
        ball = BallState(
            x: t.exit.x, y: t.exit.y, vx: t.vx, vy: t.vy,
            spin: ball.spin, spinSign: ball.spinSign, phase: .fly
        )
        ballNode.isHidden = false
        ballNode.position = exitPt
        trailPoints = [exitPt]
        SoundKit.shared.warp(up: false)
        react(.laugh)
        toast("저기서 나왔다!", sub: nil)
        if demoMode {
            print(String(format: "TUNNEL out (%.1f, %.1f)", ball.x, ball.y))
            fflush(stdout)
        }
    }

    /// 고리 두 개가 퍼진다 — 입구·출구 표식 (물결은 파란 물색이라 따로)
    private func portalRing(at p: CGPoint) {
        for i in 0 ..< 2 {
            let ring = SKShapeNode(circleOfRadius: 9)
            ring.strokeColor = NSColor(white: 1, alpha: 0.85)
            ring.lineWidth = 1.4
            ring.fillColor = .clear
            ring.position = p
            ring.setScale(0.3)
            ring.zPosition = 7
            addChild(ring)
            ring.run(.sequence([
                .wait(forDuration: Double(i) * 0.12),
                .group([.scale(to: 1.9, duration: 0.5), .fadeOut(withDuration: 0.5)]),
                .removeFromParent(),
            ]))
        }
    }

    /// 지금까지의 궤적을 잔상 노드로 굳히고 새 궤적을 비운다 — 창 속 구간은 선이 없다
    private func freezeTrailAsGhost() {
        guard let path = trailNode.path else {
            trailPoints = []
            return
        }
        for src in [trailUnderNode, trailNode] where !src.isHidden { // 언더스트로크는 고대비 모드에서만 보인다 (리뷰 m5)
            let ghost = SKShapeNode(path: path)
            ghost.name = Self.tunnelGhostName
            ghost.strokeColor = src.strokeColor
            ghost.lineWidth = src.lineWidth
            ghost.lineCap = src.lineCap
            ghost.zPosition = -0.5 // 라이브 궤적처럼 스틱맨·깃발 아래
            addChild(ghost)
        }
        trailPoints = []
    }

    /// --demo-bumpers "fx,fy,fw,fh;…" — 창이 없는 관찰 환경에서 화면 비율로 합성 범퍼를 만든다 (실플레이 경로 아님)
    func syntheticBumpers() -> [Bumper] {
        let gb = Double(py(0))
        let m = Double(pxPerM)
        return demoBumperFracs.compactMap { f in
            guard f.count == 4 else { return nil }
            let x = f[0] * Double(size.width), y = f[1] * Double(size.height)
            let w = f[2] * Double(size.width), h = f[3] * Double(size.height)
            return Bumper(x: x / m, y: (y - gb) / m, w: w / m, h: h / m)
        }
    }

    func drawSyntheticBumpers() {
        enumerateChildNodes(withName: Self.demoBumperName) { node, _ in node.removeFromParent() }
        for r in shotBumpers {
            let box = SKShapeNode(rect: bumperRect(r))
            box.name = Self.demoBumperName
            box.strokeColor = NSColor(white: 0.6, alpha: 0.6)
            box.fillColor = NSColor(white: 0.5, alpha: 0.12)
            box.lineWidth = 1
            box.zPosition = 2
            addChild(box)
        }
    }

    // ── 규칙: 핀 이동 (공 정지, rare) ──

    /// 예고 = 깃발이 두 번 부르르 떨린다 · 사건 = 깃대가 쑥 뽑혀 다리를 내고 그린 위를 걸어가 새 자리에 꽂힌다(컵이 옮겨진다) ·
    /// 반응 = 멀어지면 처짐, 가까워지면 주먹. 홀 데이터는 Hole.movingPin 사본으로 교체 (GameScene.replaceHole)
    func playPinMove() {
        let oldX = hole.holeX
        let lo = hole.greenStart + 2, hi = hole.greenEnd - 2
        // 그린이 허용하는 만큼 멀리 — 긴 홀은 4px/m라 5m는 20px밖에 안 돼 걷는 게 안 읽혔다 (캡처 1차).
        // 양 끝 중 먼 쪽을 기본으로, 가끔(30%) 가까운 쪽 — 늘 같은 방향이면 예측된다
        let toLo = oldX - lo, toHi = hi - oldX
        let farEnd = toLo > toHi ? lo : hi, nearEnd = toLo > toHi ? hi : lo
        var newX = Double.random(in: 0 ..< 1) < 0.3 && abs(nearEnd - oldX) >= 5 ? nearEnd : farEnd
        newX += Double.random(in: -1.5 ... 1.5) // 끝에 딱 붙지 않게
        newX = min(max(newX, lo), hi)
        if abs(newX - oldX) < 5 { // 그린이 좁으면 (eligible 12m 이상) 여유가 큰 쪽으로 5m
            newX = min(max(oldX + (toLo > toHi ? -5 : 5), lo), hi)
        }
        let farther = abs(newX - ball.x) > abs(oldX - ball.x)
        let delta = Int((abs(newX - ball.x) - abs(oldX - ball.x)).rounded())
        let oldCup = CGPoint(x: px(oldX), y: groundY(oldX))

        let legs = SKNode()
        legs.alpha = 0
        legs.position = CGPoint(x: 0, y: 1)
        for (i, s) in [-1.0, 1.0].enumerated() {
            let leg = SKShapeNode()
            let lp = CGMutablePath()
            lp.move(to: .zero)
            lp.addLine(to: CGPoint(x: s * 3, y: -9))
            leg.path = lp
            leg.strokeColor = NSColor(white: 0.95, alpha: 0.9)
            leg.lineWidth = 1.6
            leg.lineCap = .round
            legs.addChild(leg)
            leg.run(.repeatForever(.sequence([ // 종종걸음
                .wait(forDuration: Double(i) * 0.1),
                .rotate(toAngle: 0.5, duration: 0.1), .rotate(toAngle: -0.5, duration: 0.1),
            ])))
        }
        let cloth = flagNode.children.last // 깃발 천 — legs를 붙이기 전에 잡아야 한다 (붙인 뒤엔 children.last가 legs, 리뷰 m1)
        flagNode.addChild(legs)

        let travelPx = Double(px(newX) - px(oldX))
        let dur = min(3.2, max(1.0, abs(travelPx) / 90))
        let walk = SKAction.moveTo(x: px(newX), duration: dur)
        walk.timingMode = .easeInEaseOut
        let bob = SKAction.repeatForever(.sequence([
            .moveBy(x: 0, y: 3, duration: 0.11), .moveBy(x: 0, y: -3, duration: 0.11),
        ]))
        let pullOut = SKAction.moveBy(x: 0, y: 10, duration: 0.3)
        pullOut.timingMode = .easeOut
        let plant = SKAction.moveBy(x: 0, y: -10, duration: 0.22)
        plant.timingMode = .easeIn

        flagNode.run(.sequence([
            .run { // 예고: 부르르 ×2 (flagNode 자체를 흔들면 removeAllActions가 이 시퀀스를 지운다)
                if let cloth {
                    FX.flagWave(cloth)
                }
                SoundKit.shared.pluck()
            },
            .wait(forDuration: 0.55),
            .run { [weak self] in
                if let cloth {
                    FX.flagWave(cloth)
                }
                SoundKit.shared.pluck()
                self?.toast("핀이…?", sub: nil)
            },
            .wait(forDuration: 0.6),
            .run { [weak self] in
                self?.react(.startled)
                legs.run(.fadeIn(withDuration: 0.15))
            },
            pullOut,
            .run { [weak self] in self?.flagNode.run(bob, withKey: "bob") },
            walk,
            .run { [weak self] in
                self?.flagNode.removeAction(forKey: "bob")
                legs.removeFromParent()
            },
            plant,
            .run { [weak self] in // 마지막 스텝: 여기서 홀을 교체하면 rebuildTerrain이 깃발·컵을 제자리에 다시 그린다
                guard let self else { return }
                FX.dust(on: self, at: oldCup, surface: .green, intensity: 0.5) // 옛 컵은 덮인다
                replaceHole(hole.movingPin(to: newX))
                preShot.remain = abs(hole.holeX - ball.x) // 멀리건 '나쁜 샷' 판정이 옮겨진 핀에 속지 않게
                SoundKit.shared.thump()
                afterSurprise(0.05) { [weak self] in // flagWave는 removeAllActions를 부른다 — 이 시퀀스 밖에서
                    guard let self else { return }
                    FX.flagWave(flagNode)
                }
                toast("핀 이동!", sub: farther ? "\(delta)m 멀어졌다" : "\(-delta)m 가까워졌다")
                react(farther ? .slump : .fistPump)
                updateHUD()
                if demoMode {
                    print(String(format: "PIN %.1f → %.1f (%@)", oldX, hole.holeX, farther ? "farther" : "closer"))
                    fflush(stdout)
                }
                afterSurprise(1.3) { [weak self] in self?.finishSurprise() }
            },
        ]))
    }

    // ── 물리: 공 바꿔치기 (공 정지, rare) ──

    /// 예고 = 낙하산 달린 택배 상자가 팔랑 내려온다 · 사건 = 상자가 열리고 공이 바뀐다 — 다음 한 샷만 고무공(계속 튄다)·
    /// 볼링공(느리게 떠나 안 뜨고 둔탁하게 떨어진다), 샷이 끝나면 표준으로 · 반응 = 고무공 낄낄, 볼링공 화들짝
    func playBallSwap() {
        let kind: BallKind = Bool.random() ? .rubber : .bowling
        let parcel = makeParcel()
        parcel.name = Self.surpriseNodeName
        let landPt = CGPoint(x: px(ball.x) + CGFloat(dir) * 28, y: groundY(ball.x) + 8)
        let ballPt = CGPoint(x: px(ball.x), y: groundY(ball.x) + 5.5)
        parcel.position = CGPoint(x: landPt.x - CGFloat(dir) * 40, y: size.height * 0.95)
        parcel.alpha = 0
        addChild(parcel)
        SoundKit.shared.flutter()
        var fall: [SKAction] = [] // 팔랑: 좌우로 흔들리며 내려온다 (멀리건 카드 문법)
        let steps = 5
        for i in 0 ..< steps {
            let u = Double(i + 1) / Double(steps)
            let y = mix(Double(size.height * 0.95), Double(landPt.y), u)
            let x = Double(landPt.x) + (i % 2 == 0 ? 22.0 : -22.0) * (1 - u)
            let m = SKAction.move(to: CGPoint(x: x, y: y), duration: 0.4)
            m.timingMode = .easeInEaseOut
            fall.append(.group([m, .rotate(toAngle: i % 2 == 0 ? 0.2 : -0.2, duration: 0.4)]))
        }
        parcel.run(.sequence([
            .fadeIn(withDuration: 0.3),
            .sequence(fall),
            .rotate(toAngle: 0, duration: 0.15),
            .run { [weak self, weak parcel] in
                parcel?.childNode(withName: "chute")?.run(.sequence([
                    .fadeOut(withDuration: 0.25),
                    .removeFromParent(),
                ]))
                self?.toast("택배?", sub: nil)
            },
            .wait(forDuration: 0.5),
            .run { [weak self, weak parcel] in // 상자가 열리고 공이 바뀐다 — 헌 공은 상자로, 새 공은 상자에서
                guard let self, let parcel else { return }
                SoundKit.shared.pop()
                parcel.childNode(withName: "lid")?.run(.rotate(toAngle: -1.3, duration: 0.18))
                let old = SKShapeNode(circleOfRadius: 5.5)
                old.fillColor = ballNode.fillColor
                old.strokeColor = .clear
                old.position = ballPt
                old.name = Self.surpriseNodeName
                addChild(old)
                old.run(.sequence([
                    arcHop(from: ballPt, to: landPt, lift: 26, dur: 0.38),
                    .fadeOut(withDuration: 0.1),
                    .removeFromParent(),
                ]))
                ballNode.position = landPt
                ballKind = kind
                applyBallStyle()
                ballNode.run(.sequence([
                    .wait(forDuration: 0.2),
                    arcHop(from: landPt, to: ballPt, lift: 30, dur: 0.42),
                ]))
                react(kind == .rubber ? .laugh : .startled)
                toast(kind == .rubber ? "고무공!" : "볼링공!", sub: kind == .rubber ? "다음 한 샷 — 튄다" : "다음 한 샷 — 안 뜬다")
                if demoMode {
                    print("BALLKIND \(kind.rawValue)")
                    fflush(stdout)
                }
            },
            .wait(forDuration: 1.1),
            .group([.fadeOut(withDuration: 0.3), .moveBy(x: 0, y: -6, duration: 0.3)]),
            .removeFromParent(),
            .run { [weak self] in self?.finishSurprise() },
        ]))
    }

    /// 공 종류에 맞는 생김새 — 고무공은 띠 두른 밝은 공, 볼링공은 손가락 구멍 셋의 크고 어두운 공
    func applyBallStyle() {
        for mark in ballNode.children where mark.name == "kindMark" {
            mark.removeFromParent()
        }
        switch ballKind {
        case .standard:
            ballNode.setScale(1)
            ballNode.fillColor = .white
            ballNode.lineWidth = 1.2
            ballNode.strokeColor = Theme.highContrast ? NSColor(white: 0, alpha: 0.4) : .clear
        case .rubber:
            ballNode.setScale(BallKind.rubber.renderScale)
            ballNode.fillColor = NSColor(white: 0.97, alpha: 1)
            ballNode.lineWidth = 1.2
            ballNode.strokeColor = NSColor(white: 0.45, alpha: 0.9)
            let band = SKShapeNode(rect: CGRect(x: -5, y: -1.1, width: 10, height: 2.2))
            band.fillColor = NSColor(white: 0.55, alpha: 0.9)
            band.strokeColor = .clear
            band.name = "kindMark"
            ballNode.addChild(band)
        case .bowling:
            ballNode.setScale(BallKind.bowling.renderScale)
            ballNode.fillColor = NSColor(white: 0.3, alpha: 1)
            ballNode.lineWidth = 0.8
            ballNode.strokeColor = NSColor(white: 0.12, alpha: 0.8)
            for (x, y) in [(-1.6, 1.4), (1.6, 1.4), (0.0, -1.0)] {
                let hole = SKShapeNode(circleOfRadius: 0.8)
                hole.position = CGPoint(x: x, y: y)
                hole.fillColor = NSColor(white: 0.1, alpha: 1)
                hole.strokeColor = .clear
                hole.name = "kindMark"
                ballNode.addChild(hole)
            }
        }
    }

    func revertBallKind() {
        ballKind = .standard
        applyBallStyle()
        if demoMode {
            print("BALLKIND standard")
            fflush(stdout)
        }
    }

    // ── 스틱맨: 갤러리 (공 정지, common — 다음 샷 위에 얹힌다) ──

    /// 예고 = 웅성거림과 함께 관중 넷이 스탠스 뒤로 걸어 들어온다 · 사건 = 다음 샷을 지켜보고 결과에 환호·박수·야유 ·
    /// 반응 = 환호엔 손 흔들기, 박수엔 끄덕, 야유엔 처짐 (공이 멈춘 샷이면 씬을 잠깐 점유해 보여준다)
    func playGallery() {
        let node = SKNode()
        node.name = Self.surpriseNodeName
        node.zPosition = -1 // 스틱맨 뒤
        let ballPx = px(ball.x)
        let count = 4
        var side = -dir // 스탠스 뒤쪽
        let spread = CGFloat(70 + 30 * (count - 1))
        if ballPx + CGFloat(side) * spread < 30 || ballPx + CGFloat(side) * spread > size.width - 30 {
            side = dir // 뒤에 자리가 없으면 앞쪽 멀찍이
        }
        let base: CGFloat = side == -dir ? 70 : 110
        let edgeX: CGFloat = side < 0 ? -30 : size.width + 30
        var targets: [CGFloat] = []
        for i in 0 ..< count {
            let s = makeSpectator(variant: i)
            let targetX = ballPx + CGFloat(side) * (base + CGFloat(i) * 30)
            targets.append(targetX)
            let startX = side < 0 ? max(edgeX, targetX - 420) : min(edgeX, targetX + 420)
            s.position = CGPoint(x: startX, y: groundY(Double(startX) / Double(pxPerM)))
            s.xScale = (side < 0 ? 1 : -1) * abs(s.xScale) // 스틱맨 쪽을 본다 — setScale의 키 다양성은 유지 (리뷰 n1)
            node.addChild(s)
            let dur = Double(abs(targetX - startX)) / 140 + Double(i) * 0.15
            s.run(.sequence([
                groundWalk(from: startX, to: targetX, dur: dur),
                .repeatForever(.sequence([ // 관전: 느린 좌우 흔들림
                    .wait(forDuration: Double(i) * 0.2),
                    .rotate(toAngle: 0.04, duration: 1.1), .rotate(toAngle: -0.04, duration: 1.1),
                ])),
            ]))
        }
        addChild(node)
        galleryState = GalleryState(node: node, targets: targets, phase: .arriving, verdict: nil)
        SoundKit.shared.murmur()
        toast("갤러리가 모였다", sub: "다음 샷을 지켜본다")
        afterSurprise(2.8) { [weak self] in
            guard let self, var g = galleryState, g.phase == .arriving else { return }
            g.phase = .watching
            galleryState = g
        }
        if demoMode {
            print("GALLERY arrive side \(Int(side))")
            fflush(stdout)
        }
    }

    /// 샷 종료 판정 — 홀인·그린·남은 거리 절반 이상 줄면 환호, 물·벙커·15% 미만이면 야유, 나머지 박수
    private func galleryJudge(terminal: StepEvent) {
        guard var g = galleryState else { return }
        let before = max(1, preShot.remain)
        let gain = before - abs(hole.holeX - ball.x)
        let surface = hole.surface(at: ball.x)
        let verdict: GalleryState.Verdict = switch terminal {
        case .holed: .cheer
        case .water: .groan
        default: surface == .green ? .cheer // 그린에 올리면 짧아도 환호 (리뷰 n4)
            : surface == .bunker || gain < 0.15 * before ? .groan
            : gain >= 0.5 * before ? .cheer : .clap
        }
        let arriving = g.phase == .arriving
        g.phase = .reacting
        g.verdict = verdict
        galleryState = g
        for (i, s) in g.node.children.enumerated() {
            s.removeAllActions()
            s.zRotation = 0
            if arriving, i < g.targets.count { // 도착 전에 샷이 끝났으면 관전 자리로 스냅 — 걷던 자리·홉 오프셋에 얼어붙지 않게 (리뷰 m6)
                let tx = g.targets[i]
                s.position = CGPoint(x: tx, y: groundY(Double(tx) / Double(pxPerM)))
            }
            let armL = s.childNode(withName: "armL"), armR = s.childNode(withName: "armR")
            let head = s.childNode(withName: "head")
            switch verdict {
            case .cheer: // 양팔 번쩍 + 폴짝 ×2
                armL?.run(.rotate(toAngle: 2.5, duration: 0.15))
                armR?.run(.rotate(toAngle: -2.5, duration: 0.15))
                s.run(.sequence([
                    .wait(forDuration: Double(i) * 0.07),
                    .repeat(
                        .sequence([.moveBy(x: 0, y: 8, duration: 0.14), .moveBy(x: 0, y: -8, duration: 0.14)]),
                        count: 3
                    ),
                ]))
            case .clap: // 손을 가슴 앞에서 짝짝
                armL?.run(.rotate(toAngle: 1.3, duration: 0.15))
                armR?.run(.sequence([
                    .rotate(toAngle: -1.3, duration: 0.15),
                    .repeat(
                        .sequence([.rotate(toAngle: -0.9, duration: 0.1), .rotate(toAngle: -1.3, duration: 0.1)]),
                        count: 5
                    ),
                ]))
            case .groan: // 고개 푹, 팔 축
                head?.run(.moveBy(x: 0, y: -3.5, duration: 0.35))
                armL?.run(.rotate(toAngle: 0.15, duration: 0.3))
                armR?.run(.rotate(toAngle: -0.15, duration: 0.3))
                s.run(.rotate(toAngle: CGFloat(s.xScale) * 0.12, duration: 0.35))
            }
        }
        switch verdict {
        case .cheer: SoundKit.shared.cheer()
        case .clap: SoundKit.shared.clap()
        case .groan: SoundKit.shared.groan()
        }
        if terminal == .none { // 홀인·입수는 그쪽 토스트가 우선
            toast(verdict == .cheer ? "와아—!" : verdict == .clap ? "짝짝짝" : "우우…", sub: nil)
        }
        afterSurprise(2.6) { [weak self] in self?.galleryLeave() }
        if demoMode {
            print("GALLERY \(verdict) gain \(Int(gain))/\(Int(before)) \(surface)")
            fflush(stdout)
        }
    }

    /// 공이 멈춘 샷에서 갤러리가 반응 중이면 스틱맨 반응을 보여줄 씬 점유가 필요하다 (GameScene 정지 분기)
    func galleryWantsScene() -> Bool {
        guard let g = galleryState else { return false }
        return g.phase == .reacting && !g.sceneTaken
    }

    func galleryReact() {
        guard var g = galleryState, let v = g.verdict else {
            startWalk()
            return
        }
        g.sceneTaken = true
        galleryState = g
        mode = .surprise
        react(v == .cheer ? .shoo : v == .groan ? .slump : .nod) // 훠이훠이 = 관중에게 손 흔들기
        afterSurprise(1.7) { [weak self] in self?.finishSurprise() }
    }

    private func galleryLeave() {
        guard var g = galleryState, g.phase != .leaving else { return }
        g.phase = .leaving
        galleryState = g
        let node = g.node
        var longest = 0.0
        for (i, s) in node.children.enumerated() {
            s.removeAllActions()
            let x0 = s.position.x
            let edgeX: CGFloat = x0 < size.width / 2 ? -40 : size.width + 40
            s.xScale = (edgeX < x0 ? 1 : -1) * abs(s.xScale)
            let dur = Double(abs(edgeX - x0)) / 150 + Double(i) * 0.12
            longest = max(longest, dur)
            s.run(groundWalk(from: x0, to: edgeX, dur: dur))
        }
        afterSurprise(longest + 0.2) { [weak self] in // 고정 4s는 화면 중앙(≈6.7s 걷기)에서 중간 증발 (리뷰 m3)
            node.removeFromParent()
            if self?.galleryState?.node === node {
                self?.galleryState = nil
            }
        }
    }

    // ── 생물: 거위 떼 (공 정지, common) ──

    /// 예고 = 화면 밖에서 꽥꽥 · 사건 = 다섯 마리가 줄지어 건너다 둘째가 공 위에 앉는다, 훠이훠이에 날아 흩어지며 공을 톡,
    /// 알 하나를 남긴다(연출) · 반응 = 훠이훠이
    func playGeese() {
        let ballPx = px(ball.x)
        let fromRight = dir > 0 // 홀 쪽(스틱맨 반대편)에서 들어와 공에 먼저 닿는다 — 스틱맨 다리 사이를 지나지 않게 (캡처 1차)
        let tdir: CGFloat = fromRight ? -1 : 1 // 이동 방향
        let edgeX: CGFloat = fromRight ? size.width + 30 : -30
        let startLead = fromRight ? min(edgeX, ballPx + 420) : max(edgeX, ballPx - 420)
        let flock = SKNode()
        flock.name = Self.surpriseNodeName
        flock.zPosition = 4
        addChild(flock)
        let n = 5
        let spacing: CGFloat = 26
        let leadTarget = ballPx + tdir * 30
        let dur = min(5.0, max(1.6, Double(abs(leadTarget - startLead)) / 75))
        var geese: [SKNode] = []
        for i in 0 ..< n {
            let g = makeGoose()
            g.xScale = tdir
            let sx = startLead - tdir * spacing * CGFloat(i)
            g.position = CGPoint(x: sx, y: groundY(Double(sx) / Double(pxPerM)))
            g.alpha = 0
            flock.addChild(g)
            geese.append(g)
            g.run(.fadeIn(withDuration: 0.3))
            g.run(
                groundWalk(from: sx, to: leadTarget - tdir * spacing * CGFloat(i), dur: dur, bob: 1.2, stepsPerSec: 5),
                withKey: "walk"
            )
            g.run(.repeatForever(.sequence([ // 뒤뚱
                .rotate(toAngle: 0.1, duration: 0.1), .rotate(toAngle: -0.1, duration: 0.1),
            ])), withKey: "waddle")
        }
        SoundKit.shared.honk()
        afterSurprise(0.6) { SoundKit.shared.honk() }
        toast("거위?", sub: nil)
        let sitter = geese[1] // 둘째가 공 자리에 선다 (leadTarget − spacing ≈ 공 + 4px)
        flock.run(.sequence([
            .wait(forDuration: dur),
            .run { [weak self] in // 둘째가 공 위에 앉고 나머지는 멈춘다
                guard let self else { return }
                for g in geese {
                    g.removeAction(forKey: "waddle")
                    g.zRotation = 0
                }
                sitter.run(.group([.scaleY(to: 0.78, duration: 0.25), .moveBy(x: 0, y: -2, duration: 0.25)]))
                SoundKit.shared.honk()
                toast("거위 떼!", sub: "한 마리가 공 위에 앉았다")
            },
            .wait(forDuration: 0.5),
            .run { [weak self] in
                self?.react(.shoo)
                SoundKit.shared.honk()
            },
            .wait(forDuration: 1.2),
            .run { [weak self] in // 흩어진다 — 앉았던 놈이 날아오르며 공을 툭, 알 하나를 남긴다
                guard let self else { return }
                for (i, g) in geese.enumerated() {
                    g.removeAllActions()
                    let flap = SKAction.repeatForever(.sequence([
                        .scaleY(to: 0.6, duration: 0.09), .scaleY(to: 1.0, duration: 0.09),
                    ]))
                    let fly = SKAction.moveBy(
                        x: tdir * CGFloat.random(in: 140 ... 280), y: 240 + CGFloat(i) * 22, duration: 1.1
                    )
                    fly.timingMode = .easeIn
                    g.run(.group([fly, flap, .sequence([.wait(forDuration: 0.7), .fadeOut(withDuration: 0.35)])]))
                }
                SoundKit.shared.honk()
                afterSurprise(0.25) { SoundKit.shared.honk() }
                let kick = Double(tdir) * Double.random(in: 0.4 ... 1.5)
                let newX = outOfWater(min(max(ball.x + kick, 6), hole.worldW - 6))
                SoundKit.shared.bounce(speed: 1.5, surface: hole.surface(at: ball.x))
                let egg = SKShapeNode(ellipseOf: CGSize(width: 5, height: 7)) // 공보다 작고 어두워야 내 공과 안 헷갈린다
                egg.fillColor = NSColor(white: 0.78, alpha: 0.95)
                egg.strokeColor = .clear
                egg.position = CGPoint(x: ballPx - tdir * 11, y: groundY(ball.x) + 3.5)
                egg.zPosition = 1
                egg.name = Self.surpriseNodeName
                addChild(egg)
                egg.run(.sequence([.wait(forDuration: 6), .fadeOut(withDuration: 1), .removeFromParent()]))
                ball = BallState(x: newX, y: hole.ground(at: newX))
                let roll = SKAction.move(to: CGPoint(x: px(newX), y: groundY(newX) + 5.5), duration: 0.5)
                roll.timingMode = .easeOut
                ballNode.run(roll)
                if demoMode {
                    print(String(format: "GEESE scatter kick %.1f → %.1f", kick, newX))
                    fflush(stdout)
                }
            },
            .wait(forDuration: 1.3),
            .removeFromParent(),
            .run { [weak self] in self?.finishSurprise() },
        ]))
    }

    // ── 셰이프: 게임 회색 실루엣 문법 ──

    /// 거위: 납작한 몸통 + 긴 목 + 머리·부리 (+x를 본다, xScale로 방향)
    private func makeGoose() -> SKNode {
        let goose = SKNode()
        let white = NSColor(white: 0.9, alpha: 0.95)
        let body = SKShapeNode(ellipseOf: CGSize(width: 20, height: 10))
        body.position = CGPoint(x: 0, y: 6)
        body.fillColor = white
        body.strokeColor = .clear
        let neck = SKShapeNode()
        let np = CGMutablePath()
        np.move(to: CGPoint(x: 7, y: 8))
        np.addQuadCurve(to: CGPoint(x: 11, y: 21), control: CGPoint(x: 12, y: 12))
        neck.path = np
        neck.strokeColor = white
        neck.lineWidth = 2.6
        neck.lineCap = .round
        let head = SKShapeNode(circleOfRadius: 3.2)
        head.position = CGPoint(x: 11.5, y: 22)
        head.fillColor = white
        head.strokeColor = .clear
        let beak = SKShapeNode()
        let bp = CGMutablePath()
        bp.move(to: CGPoint(x: 14, y: 22))
        bp.addLine(to: CGPoint(x: 19, y: 21))
        beak.path = bp
        beak.strokeColor = NSColor(white: 0.62, alpha: 0.95)
        beak.lineWidth = 2
        beak.lineCap = .round
        let legs = SKShapeNode()
        let lp = CGMutablePath()
        for lx in [-3.0, 3.0] {
            lp.move(to: CGPoint(x: lx, y: 3))
            lp.addLine(to: CGPoint(x: lx - 1, y: 0))
        }
        legs.path = lp
        legs.strokeColor = NSColor(white: 0.62, alpha: 0.95)
        legs.lineWidth = 1.6
        legs.lineCap = .round
        for n in [legs, body, neck, head, beak] as [SKNode] {
            goose.addChild(n)
        }
        return goose
    }

    /// 관중: 작은 스틱맨 — 머리·몸·다리 + 어깨에서 도는 팔 둘("armL"·"armR"), 머리("head"). 키·모자가 조금씩 다르다
    private func makeSpectator(variant: Int) -> SKNode {
        let s = SKNode()
        let gray = NSColor(white: 0.8, alpha: 0.8)
        let h: CGFloat = [22, 25, 20, 24][variant % 4]
        let body = SKShapeNode()
        let bp = CGMutablePath()
        bp.move(to: CGPoint(x: -4, y: 0))
        bp.addLine(to: CGPoint(x: 0, y: h * 0.45))
        bp.addLine(to: CGPoint(x: 4, y: 0))
        bp.move(to: CGPoint(x: 0, y: h * 0.45))
        bp.addLine(to: CGPoint(x: 0, y: h))
        body.path = bp
        body.strokeColor = gray
        body.lineWidth = 2.2
        body.lineCap = .round
        body.lineJoin = .round
        let head = SKShapeNode(circleOfRadius: 3.4)
        head.position = CGPoint(x: 0, y: h + 4.5)
        head.fillColor = gray
        head.strokeColor = .clear
        head.name = "head"
        if variant % 2 == 1 { // 모자 챙
            let brim = SKShapeNode(rect: CGRect(x: -5, y: 2.6, width: 10, height: 1.6))
            brim.fillColor = gray
            brim.strokeColor = .clear
            head.addChild(brim)
        }
        for (name, sx) in [("armL", -1.0), ("armR", 1.0)] {
            let arm = SKShapeNode()
            let ap = CGMutablePath()
            ap.move(to: .zero)
            ap.addLine(to: CGPoint(x: sx * 2, y: -8))
            arm.path = ap
            arm.strokeColor = gray
            arm.lineWidth = 2.2
            arm.lineCap = .round
            arm.position = CGPoint(x: 0, y: h * 0.9)
            arm.name = name
            s.addChild(arm)
        }
        s.addChild(body)
        s.addChild(head)
        s.setScale([0.95, 1.05, 0.9, 1.0][variant % 4]) // 0.7대는 17px라 반응이 안 읽혔다 (캡처 1차) — 스틱맨의 절반 남짓
        return s
    }

    /// 택배 상자: 몸통 + 왼쪽 경첩 뚜껑("lid") + 낙하산("chute")
    private func makeParcel() -> SKNode {
        let parcel = SKNode()
        let box = SKShapeNode(rect: CGRect(x: -11, y: -8, width: 22, height: 16), cornerRadius: 1.5)
        box.fillColor = NSColor(white: 0.86, alpha: 0.95)
        box.strokeColor = NSColor(white: 0.55, alpha: 0.9)
        box.lineWidth = 1.2
        let tape = SKShapeNode(rect: CGRect(x: -1.2, y: -8, width: 2.4, height: 16))
        tape.fillColor = NSColor(white: 0.6, alpha: 0.6)
        tape.strokeColor = .clear
        let lid = SKShapeNode()
        let lp = CGMutablePath()
        lp.move(to: .zero)
        lp.addLine(to: CGPoint(x: 23, y: 0))
        lid.path = lp
        lid.strokeColor = NSColor(white: 0.55, alpha: 0.95)
        lid.lineWidth = 3
        lid.lineCap = .round
        lid.position = CGPoint(x: -11.5, y: 8.5)
        lid.name = "lid"
        let chute = SKNode()
        chute.name = "chute"
        let canopy = SKShapeNode()
        let cp = CGMutablePath()
        cp.addArc(center: CGPoint(x: 0, y: 30), radius: 17, startAngle: 0, endAngle: .pi, clockwise: false)
        canopy.path = cp
        canopy.strokeColor = NSColor(white: 0.8, alpha: 0.9)
        canopy.fillColor = NSColor(white: 0.8, alpha: 0.25)
        canopy.lineWidth = 1.6
        let lines = SKShapeNode()
        let ln = CGMutablePath()
        for x in [-17.0, 17.0] {
            ln.move(to: CGPoint(x: x, y: 30))
            ln.addLine(to: CGPoint(x: x * 0.6, y: 8))
        }
        lines.path = ln
        lines.strokeColor = NSColor(white: 0.7, alpha: 0.8)
        lines.lineWidth = 1
        chute.addChild(canopy)
        chute.addChild(lines)
        for n in [chute, box, tape, lid] as [SKNode] {
            parcel.addChild(n)
        }
        parcel.zPosition = 6
        return parcel
    }
}
