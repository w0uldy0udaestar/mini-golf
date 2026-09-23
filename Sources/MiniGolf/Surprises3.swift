import AppKit
import GolfCore
import SpriteKit

// 서프라이즈 3차 (2026-09-23, 계열별 1종) — 1·2차 프레임워크(Surprises.swift·Surprises2.swift) 위에 다섯 종류를 더한다.
// 물리 `sprinkler` · 규칙 `windReverse` · 스틱맨 `caddie` · 데스크탑 `cuckoo` · 생물 `dog`.
// 강아지만 씬을 점유하고, 나머지는 비행(스프링클러·바람 역전)·조준(캐디·뻐꾸기) 위에 얹힌다.
// 지연 실행은 서프라이즈 노드의 액션 또는 `afterSurprise`로만 — 씬 직접 run은 R 새 라운드 뒤에도 살아남는다.
// 3박자는 각 함수 주석에: 예고 → 사건 → 반응.

/// 3차 상태 묶음 — GameScene에는 이 한 필드만 둔다 (다른 작업과의 머지 충돌 최소화)
struct Surprise3State {
    var sprinkler: SprinklerState?
    var caddie: CaddieState?
    var clockNode: SKNode? // 뻐꾸기 시계·반딧불 — 진행 중이면 다시 굴리지 않는다
    var dogCarrying = false // 강아지가 공을 물고 있다 — 공 노드 숨김
    var lastClockPoll: TimeInterval = 0
    var demoHour: Int? // --demo-hour H: 뻐꾸기 시각 고정 (밤 대체 연출 관찰용) — 정리에서 지우지 않는다
}

/// 스프링클러 — 물줄기 구간(머리 ±halfW m, 지면 위 sprayH m)을 지나는 비행 공은 속도가 깎이고, 젖은 구간을 구르는 공은 더 빨리 선다
struct SprinklerState {
    let x: Double
    let halfW: Double
    let sprayH: Double
    let node: SKNode
    let wet: SKNode
    var spraying = false
    var hit = false
    var wetRoll = false
    var retracting = false
    var inSpray = false
    var vxIn = 0.0
}

/// 캐디 — 도착 → 건네기 → 퇴장. 도착 전에 조준이 끝나면(스윙) 아무것도 안 하고 돌아간다
struct CaddieState {
    enum Phase { case arriving, handing, leaving }
    let node: SKNode
    let side: CGFloat // 들어온 쪽 (-1 왼쪽, +1 오른쪽)
    var phase: Phase
}

extension GameScene {
    // ── 공통 ──

    /// 매 프레임 (updateSurprises에서) — 스프링클러 물리·캐디 중단·정각 감시
    func updateSurprises3(dt: Double, currentTime: TimeInterval) {
        updateSprinkler(dt: dt)
        if let c = surprise3.caddie, c.phase != .leaving, mode != .aim { // 스윙이 시작되면 건네기 취소 — 조용히 돌아간다
            caddieLeave(aborted: true)
        }
        pollClock(currentTime: currentTime)
    }

    /// 홀 시작·새 라운드 정리 (cancelSurprises에서). 노드는 이름(surprise)으로 이미 지워진다 — 여기선 상태만
    func cancelSurprises3() {
        let active = [
            surprise3.sprinkler != nil ? "sprinkler" : nil,
            surprise3.caddie != nil ? "caddie" : nil,
            surprise3.clockNode != nil ? "cuckoo" : nil,
            surprise3.dogCarrying ? "dog" : nil,
        ].compactMap(\.self)
        surprise3.sprinkler = nil
        surprise3.caddie = nil
        surprise3.clockNode = nil
        surprise3.dogCarrying = false
        ballNode.isHidden = false
        if demoMode, !active.isEmpty {
            print("SURPRISE3 cancel \(active.joined(separator: ","))")
            fflush(stdout)
        }
    }

    /// 데모 봇이 캐디의 건네기를 기다린다 (관찰용 — 실플레이는 언제든 칠 수 있고, 치면 캐디가 돌아간다)
    var caddieHoldsAim: Bool {
        surprise3.caddie.map { $0.phase != .leaving } ?? false
    }

    private func log3(_ s: String) {
        guard demoMode else { return }
        print(s)
        fflush(stdout)
    }

    // ── 물리: 스프링클러 (비행 훅, common) ──

    /// 이 샷의 첫 착지점 예측 — 공 상태 사본을 같은 물리로 굴린다 (결정론: launch 뒤엔 RNG가 없다)
    private func predictLanding() -> (x: Double, surface: Surface)? {
        var b = ball
        var t = 0.0
        while t < 30 {
            let ev = Ballistics.step(&b, hole: hole, bumpers: shotBumpers, wind: gustWind, kind: ballKind)
            switch ev {
            case let .bounce(_, surface): return (b.x, surface)
            case .water: return (b.x, .water)
            case .holed: return nil
            default: break
            }
            if b.phase != .fly {
                return (b.x, hole.surface(at: b.x))
            }
            t += Phys.dt
        }
        return nil
    }

    /// 물줄기 반폭 (m) — 화면에서 70px로 읽히게 (긴 홀 4px/m에서도 보이도록 px 기준)
    private var sprayHalfW: Double {
        70 / Double(pxPerM)
    }

    /// 스프링클러 자리: 예측 착지점에서 진행 반대쪽으로 반폭의 30% — 내려오는 공이 물줄기를 지나 젖은 구간에 떨어진다.
    /// 페어웨이·러프가 아니면 nil (실플레이 전제 조건)
    func sprinklerSpot() -> Double? {
        guard let land = predictLanding(), land.surface == .fairway || land.surface == .rough else { return nil }
        let travel: Double = ball.vx >= 0 ? 1 : -1
        let x = land.x - travel * sprayHalfW * 0.3
        let s = hole.surface(at: x)
        return s == .fairway || s == .rough ? x : nil
    }

    /// 예고 = 착지점 근처 지면에서 '틱틱' 소리와 함께 작은 헤드가 솟는다 · 사건 = 물줄기가 부채꼴로 뿜어져 지나는 공을 붙잡고
    /// (비행 속도 감쇠), 젖은 잔디가 굴림을 줄인다(반짝임) · 반응 = 화들짝 → 샷이 끝나면 헤드가 들어간다
    func playSprinkler() {
        let halfW = sprayHalfW
        let sx: Double
        if let spot = sprinklerSpot() {
            sx = spot
        } else { // 강제 관찰 모드에서만 오는 경로 — 착지 예측이 물·그린이면 가까운 물가 밖, 없으면 공 앞 60m
            let travel: Double = ball.vx >= 0 ? 1 : -1
            let guess = predictLanding()?.x ?? (ball.x + travel * 60)
            sx = outOfWater(min(max(guess - travel * halfW * 0.3, 4), hole.worldW - 4))
        }
        let sprayH = 55 / Double(pxPerM)
        let base = CGPoint(x: px(sx), y: groundY(sx))
        let node = SKNode()
        node.name = Self.surpriseNodeName
        node.position = base
        node.zPosition = 4
        addChild(node)
        let head = SKShapeNode(rect: CGRect(x: -2.5, y: 0, width: 5, height: 7), cornerRadius: 1.2)
        head.fillColor = NSColor(white: 0.62, alpha: 0.95)
        head.strokeColor = .clear
        let nozzle = SKShapeNode(rect: CGRect(x: -4, y: 6, width: 8, height: 1.8))
        nozzle.fillColor = NSColor(white: 0.5, alpha: 0.95)
        nozzle.strokeColor = .clear
        head.addChild(nozzle)
        head.position = CGPoint(x: 0, y: -7)
        head.alpha = 0
        head.name = "head"
        node.addChild(head)

        // 젖은 구간 — 지면을 따라 옅은 광택 선 + 반짝이 (분사가 시작되면 번진다)
        let wet = SKNode()
        wet.name = Self.surpriseNodeName
        wet.zPosition = 1
        wet.alpha = 0
        let sheen = SKShapeNode()
        let path = CGMutablePath()
        var x = sx - halfW
        path.move(to: CGPoint(x: px(x), y: groundY(x) + 1))
        while x < sx + halfW {
            x = min(sx + halfW, x + 1)
            path.addLine(to: CGPoint(x: px(x), y: groundY(x) + 1))
        }
        sheen.path = path
        sheen.strokeColor = NSColor(white: 1, alpha: 0.45)
        sheen.lineWidth = 2.2
        sheen.lineCap = .round
        wet.addChild(sheen)
        for i in 0 ..< 9 {
            let gx = sx + halfW * (Double(i) / 4 - 1) * 0.92
            let spark = SKShapeNode(circleOfRadius: 1.3)
            spark.fillColor = NSColor(white: 1, alpha: 0.95)
            spark.strokeColor = .clear
            spark.position = CGPoint(x: px(gx), y: groundY(gx) + 2.5)
            spark.alpha = 0
            wet.addChild(spark)
            spark.run(.sequence([
                .wait(forDuration: Double(i) * 0.13),
                .repeatForever(.sequence([
                    .group([.fadeAlpha(to: 1, duration: 0.18), .scale(to: 1.6, duration: 0.18)]),
                    .group([.fadeAlpha(to: 0, duration: 0.35), .scale(to: 0.6, duration: 0.35)]),
                    .wait(forDuration: Double.random(in: 0.3 ... 0.9)),
                ])),
            ]))
        }
        addChild(wet)
        surprise3.sprinkler = SprinklerState(x: sx, halfW: halfW, sprayH: sprayH, node: node, wet: wet)

        // 물방울: 헤드에서 양옆으로 포물선 — 20Hz로 3방울씩
        let halfPx = CGFloat(halfW) * pxPerM
        let hPx = CGFloat(sprayH) * pxPerM
        let emit = SKAction.run { [weak node] in
            guard let node else { return }
            for _ in 0 ..< 3 {
                let drop = SKShapeNode(circleOfRadius: 1.3)
                drop.fillColor = NSColor(white: 0.95, alpha: 0.8)
                drop.strokeColor = .clear
                drop.position = CGPoint(x: 0, y: 7)
                node.addChild(drop)
                let dx = CGFloat.random(in: -1 ... 1) * halfPx
                let apex = hPx * CGFloat.random(in: 0.55 ... 1.0)
                let life = Double.random(in: 0.45 ... 0.7)
                drop.run(.sequence([
                    SKAction.customAction(withDuration: life) { n, t in
                        let u = CGFloat(Double(t) / life)
                        n.position = CGPoint(x: dx * u, y: 7 * (1 - u) + 4 * apex * u * (1 - u))
                    },
                    .removeFromParent(),
                ]))
            }
        }
        SoundKit.shared.tick()
        head.run(.sequence([
            .group([.fadeIn(withDuration: 0.2), .moveTo(y: 0, duration: 0.3)]),
            .run { SoundKit.shared.tick() },
            .wait(forDuration: 0.15),
            .run { [weak self, weak wet] in // 분사 시작 — 물리 구간이 켜진다
                guard let self else { return }
                SoundKit.shared.tick()
                SoundKit.shared.sprinkler(dur: 2.6)
                surprise3.sprinkler?.spraying = true
                wet?.run(.fadeIn(withDuration: 0.6))
                log3(String(format: "SPRINKLER spray x %.1f half %.1fm h %.1fm", sx, halfW, sprayH))
            },
            .repeatForever(.sequence([emit, .wait(forDuration: 0.05)])),
        ]), withKey: "spray")
        toast("틱틱…?", sub: nil)
        log3(String(format: "SPRINKLER up x %.1f (ball %.1f vx %.1f)", sx, ball.x, ball.vx))
    }

    /// 분사 중 — 물줄기 속 비행 공은 속도 감쇠, 젖은 구간의 굴림은 마찰 증가. 샷이 끝나면 헤드를 거둔다
    private func updateSprinkler(dt: Double) {
        guard var s = surprise3.sprinkler else { return }
        if s.spraying, !s.retracting, mode == .motion, tunnelTransit == nil {
            let inZone = abs(ball.x - s.x) < s.halfW
            let inColumn = ball.phase == .fly && inZone && ball.y - hole.ground(at: ball.x) < s.sprayH
            if s.inSpray, !inColumn { // 물줄기를 빠져나옴 — 감쇠량 계측
                s.inSpray = false
                log3(String(format: "SPRINKLER out vx %.1f → %.1f (%@)", s.vxIn, ball.vx, "\(ball.phase)"))
            }
            if inColumn {
                if !s.inSpray {
                    s.inSpray = true
                    s.vxIn = ball.vx
                    log3(String(format: "SPRINKLER in (%.1f, %.1f) vx %.1f", ball.x, ball.y, ball.vx))
                }
                if !s.hit {
                    s.hit = true
                    toast("물줄기!", sub: "공이 젖었다")
                    if !(swingStyle.clubTwirl && lastShotGood) { // 트월 리그와 겹치면 트월 우선 (돌풍과 같은 규칙)
                        react(.startled)
                    }
                    FX.ripple(on: self, at: CGPoint(x: px(ball.x), y: py(ball.y) + 5.5))
                }
                let k = exp(-2.2 * dt) // 물줄기 저항 — 수평은 크게, 수직은 아래로 살짝 눌린다
                ball.vx *= k
                ball.vy -= 3 * dt
            } else if ball.phase == .roll, inZone {
                if !s.wetRoll {
                    s.wetRoll = true
                    log3(String(format: "SPRINKLER wet roll x %.1f vx %.1f", ball.x, ball.vx))
                }
                ball.vx *= exp(-2.4 * dt) // 젖은 잔디 = 굴림 마찰 ↑
            }
        }
        if !s.retracting, mode != .motion { // 샷 종료(정지·홀인·입수·서프라이즈 점유) — 1초 더 뿌리고 들어간다
            s.retracting = true
            let node = s.node, wet = s.wet
            let hit = s.hit, wetRoll = s.wetRoll
            afterSurprise(1.0) { [weak self] in
                node.childNode(withName: "head")?.removeAction(forKey: "spray")
                node.run(.sequence([
                    .wait(forDuration: 0.6), // 떠 있던 물방울이 떨어질 시간
                    .run { SoundKit.shared.tick() },
                    .fadeOut(withDuration: 0.3),
                    .removeFromParent(),
                ]))
                wet.run(.sequence([.wait(forDuration: 3.5), .fadeOut(withDuration: 1.2), .removeFromParent()]))
                self?.log3("SPRINKLER done hit \(hit) wetRoll \(wetRoll)")
                self?.afterSurprise(0.9) { [weak self] in
                    if self?.surprise3.sprinkler?.node === node {
                        self?.surprise3.sprinkler = nil
                    }
                }
            }
        }
        surprise3.sprinkler = s
    }

    // ── 규칙: 바람 역전 (비행 훅, rare) ──

    /// 예고 = 발사 직후 휭 하는 소리와 깃발이 부르르 · 사건 = 0.9초 뒤 풍향이 반전된다 — 홀 데이터(Hole.withWind 사본)를 바꿔
    /// 깃발 방향·HUD·남은 비행의 물리가 한 출처에서 함께 뒤집힌다. **이 홀이 끝날 때까지 유지**(다음 홀은 새 바람) · 반응 = 화들짝
    func playWindReverse() {
        let old = hole.wind
        // 무풍이면(강제 관찰에서만 — 실플레이 전제는 |바람| ≥ 1.5) 뒤집을 게 없으니 4m/s가 일어난다
        let new = abs(old) < 1.5 ? (Bool.random() ? 4.0 : -4.0) : -old
        SoundKit.shared.gust(dur: 0.9)
        if let cloth = flagNode.children.last {
            FX.flagWave(cloth)
        }
        toast("바람이…?", sub: nil)
        log3(String(format: "WINDREV warn wind %+.1f", old))
        afterSurprise(0.9) { [weak self] in
            guard let self else { return }
            replaceHole(hole.withWind(new))
            SoundKit.shared.gust(dur: 1.1)
            func arrow(_ w: Double) -> String {
                abs(w) < 0.5 ? "무풍" : "\(w > 0 ? "→" : "←") \(Int(abs(w).rounded()))m/s"
            }
            toast("바람이 돌았다!", sub: "이제 \(arrow(new)) · 이 홀 끝까지")
            if !(swingStyle.clubTwirl && lastShotGood) {
                react(.startled)
            }
            windSwirl(toward: new > 0 ? 1 : -1)
            updateHUD()
            log3(String(format: "WINDREV %+.1f → %+.1f phase %@", old, hole.wind, "\(ball.phase)"))
        }
    }

    /// 낙엽이 옛 바람 방향으로 가다 되돌아 새 방향으로 쓸려 간다
    private func windSwirl(toward sign: CGFloat) {
        for i in 0 ..< 8 {
            let leaf = SKShapeNode(ellipseOf: CGSize(width: 7, height: 4))
            leaf.name = Self.surpriseNodeName
            leaf.fillColor = NSColor(white: 0.8, alpha: 0.85)
            leaf.strokeColor = .clear
            leaf.zPosition = 6
            let x0 = size.width * CGFloat.random(in: 0.2 ... 0.8)
            leaf.position = CGPoint(x: x0, y: size.height * CGFloat.random(in: 0.3 ... 0.65))
            addChild(leaf)
            let back = SKAction.moveBy(x: -sign * 40, y: CGFloat.random(in: 10 ... 30), duration: 0.35)
            back.timingMode = .easeOut
            let sweep = SKAction.moveBy(x: sign * size.width * 0.5, y: CGFloat.random(in: -50 ... 20), duration: 1.2)
            sweep.timingMode = .easeIn
            leaf.run(.repeatForever(.rotate(byAngle: .pi * 2, duration: Double.random(in: 0.3 ... 0.6))))
            leaf.run(.sequence([
                .wait(forDuration: Double(i) * 0.04),
                back, sweep,
                .fadeOut(withDuration: 0.2),
                .removeFromParent(),
            ]))
        }
    }

    // ── 스틱맨: 캐디 (조준 시작 훅, common) ──

    /// 조준 진입 때마다 (GameScene.enterAim 끝) — 티샷·그린 위는 제외
    func onAimStart() {
        guard strokes > 0, mode == .aim, surprise3.caddie == nil, hole.surface(at: ball.x) != .green else { return }
        if let kind = rollSurprise(hook: .aimStart) {
            playSurprise(kind)
        }
    }

    /// 예고 = 흠흠 소리와 함께 작은 캐디가 스탠스 뒤로 걸어온다 · 사건 = 남은 거리(바람·표고 보정)에 맞는 클럽을 건네거나 —
    /// 이미 그 클럽이면 한 줄 조언 · 반응 = 끄덕. 도착 전에 스윙하면 아무것도 안 하고 돌아간다
    func playCaddie() {
        let stickPx = px(stickX)
        var side = CGFloat(-dir) // 스탠스 뒤
        if stickPx + side * 70 < 24 || stickPx + side * 70 > size.width - 24 {
            side = CGFloat(dir) // 뒤에 자리가 없으면 앞쪽
        }
        let targetX = stickPx + side * (side == CGFloat(-dir) ? 58 : 80)
        let edgeX: CGFloat = side < 0 ? -30 : size.width + 30
        let startX = side < 0 ? max(edgeX, targetX - 300) : min(edgeX, targetX + 300)
        let node = makeCaddie()
        node.name = Self.surpriseNodeName
        node.xScale = side < 0 ? 1 : -1 // 스틱맨 쪽을 본다
        node.position = CGPoint(x: startX, y: groundY(Double(startX) / Double(pxPerM)))
        node.alpha = 0
        addChild(node)
        surprise3.caddie = CaddieState(node: node, side: side, phase: .arriving)
        SoundKit.shared.hmm()
        toast("캐디가 온다", sub: nil)
        let dur = Double(abs(targetX - startX)) / 130
        node.run(.sequence([
            .group([.fadeIn(withDuration: 0.25), groundWalk(from: startX, to: targetX, dur: dur)]),
            .run { [weak self] in self?.caddieHandOver() },
        ]))
        log3("CADDIE arrive side \(Int(side)) walk \(String(format: "%.1f", dur))s")
    }

    private func caddieHandOver() {
        guard var c = surprise3.caddie, c.phase == .arriving, mode == .aim else { return }
        c.phase = .handing
        surprise3.caddie = c
        let remain = abs(hole.holeX - ball.x)
        let lie = hole.surface(at: ball.x)
        let rise = hole.ground(at: hole.holeX) - hole.ground(at: ball.x)
        let tail = hole.wind * dir // + = 뒷바람
        let rec = CourseStrategy.recommendedClub(distance: remain, tailwind: tail, rise: rise, lie: lie)
        let current = ClubTable.all[clubIdx]
        SoundKit.shared.hmm()
        if rec != current, let idx = ClubTable.all.firstIndex(of: rec) {
            // 클럽이 캐디 손에서 스틱맨 손으로 포물선 — 도착하면 HUD의 클럽이 바뀐다
            let from = CGPoint(x: c.node.position.x + c.side * -6, y: c.node.position.y + 16)
            let to = CGPoint(x: stickman.position.x, y: stickman.position.y + 40)
            let club = SKShapeNode()
            let cp = CGMutablePath()
            cp.move(to: CGPoint(x: 0, y: -9))
            cp.addLine(to: CGPoint(x: 0, y: 9))
            cp.addLine(to: CGPoint(x: 4, y: 10))
            club.path = cp
            club.strokeColor = NSColor(white: 0.9, alpha: 0.95)
            club.lineWidth = 1.6
            club.lineCap = .round
            club.position = from
            club.zPosition = 7
            club.name = Self.surpriseNodeName
            addChild(club)
            c.node.childNode(withName: "clubInHand")?.isHidden = true
            club.run(.group([.rotate(byAngle: .pi * 2, duration: 0.5), arcHop(from: from, to: to, lift: 34, dur: 0.5)]))
            club.run(.sequence([
                .wait(forDuration: 0.5),
                .run { [weak self] in
                    guard let self, mode == .aim, surprise3.caddie?.node === c.node else { return }
                    clubIdx = idx
                    updateHUD()
                    SoundKit.shared.pluck()
                    react(.nod)
                    toast(
                        "캐디: \(rec.name) 어때요?",
                        sub: "\(Int(remain.rounded()))m" + caddieWindNote(tail: tail, rise: rise)
                    )
                    log3(
                        "CADDIE club \(current.id) → \(rec.id) remain \(Int(remain)) lie \(lie) tail \(String(format: "%+.1f", tail)) rise \(String(format: "%+.1f", rise))"
                    )
                },
                .removeFromParent(),
            ]))
        } else {
            let advice = caddieAdvice(lie: lie, tail: tail, rise: rise)
            react(.nod)
            toast("캐디: \(advice)", sub: nil)
            log3("CADDIE advice \"\(advice)\" club \(current.id) remain \(Int(remain))")
        }
        afterSurprise(1.8) { [weak self] in self?.caddieLeave(aborted: false) }
    }

    private func caddieWindNote(tail: Double, rise: Double) -> String {
        if abs(tail) >= 2 {
            return tail < 0 ? " · 맞바람 \(Int(abs(tail).rounded()))m/s" : " · 뒷바람 \(Int(tail.rounded()))m/s"
        }
        if abs(rise) >= 4 {
            return rise > 0 ? " · 오르막 \(Int(rise.rounded()))m" : " · 내리막 \(Int((-rise).rounded()))m"
        }
        return ""
    }

    /// 클럽이 이미 맞을 때의 한 줄 — 가장 결정적인 변수 하나만
    private func caddieAdvice(lie: Surface, tail: Double, rise: Double) -> String {
        if lie == .bunker {
            return "모래는 파워가 반이에요 — 백스윙 크게"
        }
        if tail <= -2 {
            return "맞바람 \(Int(abs(tail).rounded()))m/s — 넉넉하게요"
        }
        if tail >= 2 {
            return "뒷바람이에요 — 조금 덜 쳐도 돼요"
        }
        if rise >= 4 {
            return "오르막 \(Int(rise.rounded()))m — 한 클럽 더 본다 생각하고"
        }
        if rise <= -4 {
            return "내리막이라 굴러가요 — 살살"
        }
        if lie == .rough {
            return "러프예요 — 조금 세게"
        }
        return "좋은 선택이에요. 믿고 치세요"
    }

    private func caddieLeave(aborted: Bool) {
        guard var c = surprise3.caddie, c.phase != .leaving else { return }
        c.phase = .leaving
        surprise3.caddie = c
        let node = c.node
        node.removeAllActions()
        let x0 = node.position.x
        let edgeX: CGFloat = c.side < 0 ? -30 : size.width + 30
        node.xScale = c.side < 0 ? -1 : 1 // 돌아서서 왔던 쪽으로
        let dur = Double(abs(edgeX - x0)) / 150
        node.run(.sequence([
            groundWalk(from: x0, to: edgeX, dur: min(dur, 2.6)),
            .run { [weak self] in
                if self?.surprise3.caddie?.node === node {
                    self?.surprise3.caddie = nil
                }
                self?.log3("CADDIE leave\(aborted ? " (aborted — swing started)" : "")")
            },
            .removeFromParent(),
        ]))
    }

    // ── 데스크탑: 정각 뻐꾸기 (시계 훅, epic) ──

    /// 정각 ±30초면 그 정각의 시(0~23), 아니면 nil (59분 30초~ 는 다음 시)
    static func nearHour(_ date: Date) -> Int? {
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        guard let h = c.hour, let m = c.minute, let s = c.second else { return nil }
        if m == 0, s <= 30 {
            return h
        }
        if m == 59, s >= 30 {
            return (h + 1) % 24
        }
        return nil
    }

    /// 조준 중 1초마다 시계를 본다 — 라운드에 한 번 (epic 상한), 진행 중이면 건너뛴다.
    /// --surprise cuckoo(또는 --demo-surprise)는 시각 무관 강제 (라운드당 한 번)
    private func pollClock(currentTime: TimeInterval) {
        guard mode == .aim, aimTime > 0.6, currentTime - surprise3.lastClockPoll >= 1 else { return }
        surprise3.lastClockPoll = currentTime
        guard surprise3.clockNode == nil, surpriseCounts[.cuckoo, default: 0] == 0 else { return }
        let forced = demoSurpriseKind == .cuckoo || demoSurpriseForce
        guard forced || Self.nearHour(Date()) != nil else { return }
        if rollSurprise(hook: .clock) == .cuckoo {
            playSurprise(.cuckoo)
        }
    }

    /// 예고 = 화면 위에서 뻐꾸기 시계가 똑딱이며 내려온다 · 사건 = 문이 열리고 뻐꾸기가 시각만큼(12시간제) 운다 ·
    /// 반응 = 첫 울음에 화들짝, 끝나면 낄낄. 밤(20~05시)엔 시계 대신 반딧불 여섯 마리와 부엉 두 번 — 반응 = 끄덕
    func playCuckoo() {
        let hour = surprise3.demoHour ?? Self.nearHour(Date()) ?? Calendar.current.component(.hour, from: Date())
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        let night = hour >= 20 || hour < 5
        if night {
            playFireflies(hour: hour, h12: h12)
        } else {
            playCuckooClock(hour: hour, h12: h12)
        }
    }

    private func playCuckooClock(hour: Int, h12: Int) {
        let clock = makeCuckooClock()
        clock.name = Self.surpriseNodeName
        let cx = min(max(px(stickX) + CGFloat(dir) * 110, 60), size.width - 60)
        clock.setScale(1.6) // 1.0은 캡처에서 뻐꾸기가 안 읽혔다 (3차 캡처 1회차)
        let restY = size.height - 110
        clock.position = CGPoint(x: cx, y: size.height + 90)
        addChild(clock)
        surprise3.clockNode = clock
        let door = clock.childNode(withName: "door")
        let bird = clock.childNode(withName: "bird")
        let drop = SKAction.moveTo(y: restY, duration: 0.7)
        drop.timingMode = .easeOut
        var calls: [SKAction] = []
        for i in 1 ... h12 {
            calls.append(.run { [weak self, weak clock] in
                guard clock?.parent != nil else { return } // 같은 프레임 정리 (afterSurprise 주석)
                door?.run(.scaleX(to: 0.15, duration: 0.08))
                bird?.run(.sequence([ // 문 밖으로 쏙 — 부리를 벌리듯 앞으로 내밀었다 들어간다
                    .moveTo(x: 14, duration: 0.1), .wait(forDuration: 0.32), .moveTo(x: 0, duration: 0.12),
                ]))
                SoundKit.shared.cuckoo()
                guard let self else { return }
                if i == 1 {
                    react(.startled)
                    toast("\(h12)시 정각", sub: "뻐꾹 × \(h12)")
                }
                log3("CUCKOO call \(i)/\(h12)")
            })
            calls.append(.wait(forDuration: 0.55))
            calls.append(.run { door?.run(.scaleX(to: 1, duration: 0.08)) })
            calls.append(.wait(forDuration: 0.25))
        }
        let rise = SKAction.moveTo(y: size.height + 90, duration: 0.6)
        rise.timingMode = .easeIn
        clock.run(.sequence([
            .run { SoundKit.shared.tick() },
            drop,
            .run { SoundKit.shared.tick() },
            .wait(forDuration: 0.5),
            .sequence(calls),
            .run { [weak self] in self?.react(.laugh) },
            .wait(forDuration: 0.6),
            rise,
            .run { [weak self] in
                self?.surprise3.clockNode = nil
                self?.log3("CUCKOO done")
            },
            .removeFromParent(),
        ]))
        log3("CUCKOO day hour \(hour) count \(h12)")
    }

    private func playFireflies(hour: Int, h12: Int) {
        let swarm = SKNode()
        swarm.name = Self.surpriseNodeName
        swarm.zPosition = 6
        addChild(swarm)
        surprise3.clockNode = swarm
        let cx = px(stickX)
        let n = 6
        for i in 0 ..< n {
            let fly = SKNode()
            let glow = SKShapeNode(circleOfRadius: 5)
            glow.fillColor = NSColor(calibratedRed: 1, green: 0.95, blue: 0.7, alpha: 0.18)
            glow.strokeColor = .clear
            let core = SKShapeNode(circleOfRadius: 1.6)
            core.fillColor = NSColor(calibratedRed: 1, green: 0.97, blue: 0.8, alpha: 1)
            core.strokeColor = .clear
            fly.addChild(glow)
            fly.addChild(core)
            let x0 = cx + CGFloat.random(in: -220 ... 220)
            let y0 = groundY(Double(x0) / Double(pxPerM)) + CGFloat.random(in: 30 ... 110)
            fly.position = CGPoint(x: x0, y: y0)
            fly.alpha = 0
            swarm.addChild(fly)
            var wander: [SKAction] = []
            for _ in 0 ..< 6 {
                let m = SKAction.moveBy(
                    x: CGFloat.random(in: -40 ... 40),
                    y: CGFloat.random(in: -18 ... 18),
                    duration: 1.1
                )
                m.timingMode = .easeInEaseOut
                wander.append(m)
            }
            fly.run(.sequence(wander))
            fly.run(.sequence([
                .wait(forDuration: Double(i) * 0.35),
                .repeat(.sequence([
                    .fadeAlpha(to: 1, duration: 0.35), .fadeAlpha(to: 0.15, duration: 0.5),
                    .wait(forDuration: Double.random(in: 0.1 ... 0.4)),
                ]), count: 6),
                .fadeOut(withDuration: 0.4),
            ]))
        }
        swarm.run(.sequence([
            .wait(forDuration: 0.3),
            .run { [weak self] in
                SoundKit.shared.hoot()
                self?.toast("밤 \(h12)시", sub: "부엉— 반딧불이 날아든다")
                self?.log3("CUCKOO hoot 1")
            },
            .wait(forDuration: 1.6),
            .run { [weak self] in
                SoundKit.shared.hoot()
                self?.react(.nod)
                self?.log3("CUCKOO hoot 2")
            },
            .wait(forDuration: 5.2),
            .run { [weak self] in
                self?.surprise3.clockNode = nil
                self?.log3("CUCKOO done")
            },
            .removeFromParent(),
        ]))
        log3("CUCKOO night hour \(hour) fireflies \(n)")
    }

    // ── 생물: 강아지 (공 정지, common) ──

    /// 예고 = 화면 밖에서 멍멍 두 번 · 사건 = 강아지가 달려와 공을 물고(공 노드 숨김) 꼬리를 흔들며 ±15m(물 제외) 지점으로 달아나
    /// 떨어뜨린다 · 반응 = 물 때 화들짝·쫓을 때 훠이훠이, 떨어뜨린 자리가 가까우면 낄낄·멀면 처짐
    func playDog() {
        let ballPx = px(ball.x)
        let grabbedAt = ball.x
        let fromRight = ballPx < size.width / 2 // 넓은 쪽에서 들어온다
        let edgeX: CGFloat = fromRight ? size.width + 40 : -40
        let startX = fromRight ? min(edgeX, ballPx + 380) : max(edgeX, ballPx - 380)
        // 드롭 지점: ±15m (최소 4m — 티가 나게), 물 밖, 스틱맨이 설 수 있는 벽 릴리프(46px) 안
        let reliefM = 48 / Double(pxPerM)
        var delta = Double.random(in: 4 ... 15) * (Bool.random() ? 1 : -1)
        if ball.x + delta < reliefM || ball.x + delta > hole.worldW - reliefM {
            delta = -delta
        }
        let dropX = outOfWater(min(max(ball.x + delta, reliefM), hole.worldW - reliefM))
        let dropPx = px(dropX)
        let oldRemain = abs(hole.holeX - ball.x)
        let closer = abs(hole.holeX - dropX) < oldRemain

        let dog = makeDog()
        dog.name = Self.surpriseNodeName
        let inFacing: CGFloat = fromRight ? -1 : 1
        dog.xScale = inFacing
        dog.position = CGPoint(x: startX, y: groundY(Double(startX) / Double(pxPerM)))
        dog.alpha = 0
        addChild(dog)
        let mouthBall = dog.childNode(withName: "mouthBall")
        let grabX = ballPx - inFacing * 14 // 입이 공 위에 오도록 (머리가 몸 +14px)
        let runIn = Double(abs(grabX - startX)) / 280
        let outFacing: CGFloat = dropPx >= ballPx ? 1 : -1
        let carryFrom = grabX
        let carryTo = dropPx - outFacing * 14
        let carryDur = max(0.7, Double(abs(carryTo - carryFrom)) / 240)
        let exitEdge: CGFloat = outFacing > 0 ? size.width + 40 : -40

        SoundKit.shared.woof()
        afterSurprise(0.35) { SoundKit.shared.woof() }
        toast("멍멍!", sub: nil)
        log3(String(
            format: "DOG enter from %@ drop target %.1f (%+.1fm)",
            fromRight ? "right" : "left",
            dropX,
            dropX - ball.x
        ))
        dog.run(.sequence([
            .wait(forDuration: 0.7),
            .group([
                .fadeIn(withDuration: 0.2),
                groundWalk(from: startX, to: grabX, dur: runIn, bob: 3, stepsPerSec: 9),
            ]),
            .run { [weak self] in // 덥석 — 공이 입으로
                guard let self, dog.parent != nil else { return } // 같은 프레임 정리 (afterSurprise 주석)
                ballNode.removeAllActions()
                ballNode.isHidden = true
                shadowNode.isHidden = true
                mouthBall?.isHidden = false
                surprise3.dogCarrying = true
                SoundKit.shared.bounce(speed: 2, surface: hole.surface(at: ball.x))
                react(.startled)
                toast("강아지!", sub: "공을 물고 달아난다")
                log3(String(format: "DOG grab @%.1f", ball.x))
            },
            .wait(forDuration: 0.35),
            .run { [weak self] in
                dog.xScale = outFacing
                self?.react(.shoo)
                SoundKit.shared.woof()
            },
            groundWalk(from: carryFrom, to: carryTo, dur: carryDur, bob: 3, stepsPerSec: 9),
            .run { [weak self] in // 퉤 — 떨어뜨린다
                guard let self, dog.parent != nil else { return }
                mouthBall?.isHidden = true
                surprise3.dogCarrying = false
                ball = BallState(x: dropX, y: hole.ground(at: dropX))
                let dropPt = CGPoint(x: dropPx, y: groundY(dropX) + 5.5)
                ballNode.position = CGPoint(x: dropPt.x, y: dropPt.y + 12)
                ballNode.isHidden = false
                let fall = SKAction.move(to: dropPt, duration: 0.22)
                fall.timingMode = .easeIn
                ballNode.run(fall)
                SoundKit.shared.bounce(speed: 2.5, surface: hole.surface(at: dropX))
                updateHUD()
                let d = Int(abs(abs(hole.holeX - dropX) - oldRemain).rounded())
                toast("여기 놨다!", sub: closer ? "\(d)m 가까워졌다" : "\(d)m 멀어졌다")
                react(closer ? .laugh : .slump)
                log3(String(
                    format: "DOG drop %.1f → %.1f (%@ %dm)",
                    grabbedAt,
                    dropX,
                    closer ? "closer" : "farther",
                    d
                ))
            },
            .group([ // 앉아서 꼬리 흔들기 + 멍
                .sequence([.scaleY(to: 0.85, duration: 0.15), .wait(forDuration: 0.5), .scaleY(to: 1, duration: 0.12)]),
                .sequence([.wait(forDuration: 0.3), .run { SoundKit.shared.woof() }]),
            ]),
            .run { [weak self] in
                guard let self, dog.parent != nil else { return }
                let x0 = dog.position.x
                dog.run(groundWalk(
                    from: x0, to: exitEdge, dur: Double(abs(exitEdge - x0)) / 300, bob: 3, stepsPerSec: 9
                ), withKey: "exit")
                afterSurprise(Double(abs(exitEdge - x0)) / 300 + 0.05) { [weak self] in
                    dog.removeFromParent()
                    self?.log3("DOG leave")
                    self?.finishSurprise()
                }
            },
        ]))
    }

    // ── 셰이프: 게임 회색 실루엣 문법 ──

    /// 캐디: 모자 쓴 작은 스틱맨 + 등에 멘 골프백(비스듬한 통 + 클럽 헤드 셋) + 손에 든 클럽("clubInHand") — +x를 본다
    private func makeCaddie() -> SKNode {
        let s = SKNode()
        let gray = NSColor(white: 0.82, alpha: 0.85)
        let h: CGFloat = 24
        let body = SKShapeNode()
        let bp = CGMutablePath()
        bp.move(to: CGPoint(x: -4, y: 0))
        bp.addLine(to: CGPoint(x: 0, y: h * 0.45))
        bp.addLine(to: CGPoint(x: 4, y: 0))
        bp.move(to: CGPoint(x: 0, y: h * 0.45))
        bp.addLine(to: CGPoint(x: 0, y: h))
        bp.move(to: CGPoint(x: 0, y: h * 0.9)) // 앞팔 — 클럽을 든다
        bp.addLine(to: CGPoint(x: 5, y: h * 0.62))
        body.path = bp
        body.strokeColor = gray
        body.lineWidth = 2.2
        body.lineCap = .round
        body.lineJoin = .round
        let head = SKShapeNode(circleOfRadius: 3.4)
        head.position = CGPoint(x: 0, y: h + 4.5)
        head.fillColor = gray
        head.strokeColor = .clear
        let cap = SKShapeNode(rect: CGRect(x: -3, y: 2.4, width: 9, height: 1.8)) // 앞으로 챙
        cap.fillColor = gray
        cap.strokeColor = .clear
        head.addChild(cap)
        let bag = SKShapeNode(rect: CGRect(x: -3, y: 0, width: 6, height: 17), cornerRadius: 2)
        bag.position = CGPoint(x: -6, y: h * 0.35)
        bag.zRotation = 0.3
        bag.fillColor = NSColor(white: 0.6, alpha: 0.8)
        bag.strokeColor = gray
        bag.lineWidth = 1
        for i in 0 ..< 3 { // 백 위로 삐죽 나온 헤드
            let clubTop = SKShapeNode(rect: CGRect(
                x: -2.2 + CGFloat(i) * 1.8,
                y: 17,
                width: 1.2,
                height: 4 + CGFloat(i % 2) * 2
            ))
            clubTop.fillColor = gray
            clubTop.strokeColor = .clear
            bag.addChild(clubTop)
        }
        let inHand = SKShapeNode()
        let ip = CGMutablePath()
        ip.move(to: CGPoint(x: 5, y: h * 0.62 + 7))
        ip.addLine(to: CGPoint(x: 5, y: h * 0.62 - 9))
        ip.addLine(to: CGPoint(x: 9, y: h * 0.62 - 10))
        inHand.path = ip
        inHand.strokeColor = NSColor(white: 0.9, alpha: 0.95)
        inHand.lineWidth = 1.6
        inHand.lineCap = .round
        inHand.name = "clubInHand"
        for n in [bag, body, head, inHand] as [SKNode] {
            s.addChild(n)
        }
        s.zPosition = -1 // 스틱맨 뒤
        return s
    }

    /// 뻐꾸기 시계: 천장 줄 + 삼각 지붕 집 + 문("door", 여닫이 = xScale) + 뻐꾸기("bird", 문 뒤에서 튀어나온다) + 추 두 개
    private func makeCuckooClock() -> SKNode {
        let clock = SKNode()
        clock.zPosition = 8
        let wood = NSColor(white: 0.72, alpha: 0.95)
        let string = SKShapeNode()
        let sp = CGMutablePath()
        sp.move(to: CGPoint(x: 0, y: 30))
        sp.addLine(to: CGPoint(x: 0, y: 200))
        string.path = sp
        string.strokeColor = NSColor(white: 0.8, alpha: 0.7)
        string.lineWidth = 1
        let house = SKShapeNode()
        let hp = CGMutablePath()
        hp.move(to: CGPoint(x: -18, y: -22))
        hp.addLine(to: CGPoint(x: 18, y: -22))
        hp.addLine(to: CGPoint(x: 18, y: 10))
        hp.addLine(to: CGPoint(x: 0, y: 28))
        hp.addLine(to: CGPoint(x: -18, y: 10))
        hp.closeSubpath()
        house.path = hp
        house.fillColor = wood
        house.strokeColor = NSColor(white: 0.5, alpha: 0.9)
        house.lineWidth = 1.2
        let face = SKShapeNode(circleOfRadius: 8)
        face.position = CGPoint(x: 0, y: -9)
        face.fillColor = NSColor(white: 0.95, alpha: 0.95)
        face.strokeColor = NSColor(white: 0.5, alpha: 0.9)
        face.lineWidth = 1
        let hands = SKShapeNode()
        let hn = CGMutablePath()
        hn.move(to: .zero)
        hn.addLine(to: CGPoint(x: 0, y: 6))
        hn.move(to: .zero)
        hn.addLine(to: CGPoint(x: 0, y: 4))
        hands.path = hn
        hands.strokeColor = NSColor(white: 0.25, alpha: 0.95)
        hands.lineWidth = 1.2
        face.addChild(hands)
        let bird = SKNode() // 문 뒤에 숨어 있다가 옆으로 튀어나온다
        bird.name = "bird"
        let bb = SKShapeNode(ellipseOf: CGSize(width: 10, height: 6))
        bb.fillColor = NSColor(white: 0.92, alpha: 0.95)
        bb.strokeColor = .clear
        let beak = SKShapeNode()
        let bkp = CGMutablePath()
        bkp.move(to: CGPoint(x: 3, y: 12.5))
        bkp.addLine(to: CGPoint(x: 5, y: 12))
        beak.path = bkp
        beak.strokeColor = NSColor(white: 0.55, alpha: 0.95)
        beak.lineWidth = 1.6
        bb.position = CGPoint(x: 0, y: 12)
        bird.addChild(bb)
        bird.addChild(beak)
        let door = SKShapeNode(rect: CGRect(x: 0, y: 0, width: 10, height: 9))
        door.position = CGPoint(x: -5, y: 8)
        door.fillColor = NSColor(white: 0.45, alpha: 0.95)
        door.strokeColor = .clear
        door.name = "door"
        let weights = SKShapeNode()
        let wp = CGMutablePath()
        for (x, len) in [(-6.0, 24.0), (6.0, 16.0)] {
            wp.move(to: CGPoint(x: x, y: -22))
            wp.addLine(to: CGPoint(x: x, y: -22 - len))
        }
        weights.path = wp
        weights.strokeColor = NSColor(white: 0.6, alpha: 0.8)
        weights.lineWidth = 1
        let pendulum = SKShapeNode()
        let pp = CGMutablePath()
        pp.move(to: .zero)
        pp.addLine(to: CGPoint(x: 0, y: -18))
        pendulum.path = pp
        pendulum.strokeColor = NSColor(white: 0.7, alpha: 0.9)
        pendulum.lineWidth = 1.2
        let bob = SKShapeNode(circleOfRadius: 3)
        bob.position = CGPoint(x: 0, y: -18)
        bob.fillColor = wood
        bob.strokeColor = .clear
        pendulum.addChild(bob)
        pendulum.position = CGPoint(x: 0, y: -22)
        pendulum.zRotation = -0.3
        pendulum.run(.repeatForever(.sequence([
            .rotate(toAngle: 0.3, duration: 0.5), .rotate(toAngle: -0.3, duration: 0.5),
        ])))
        for n in [string, weights, pendulum, house, face, bird, door] as [SKNode] {
            clock.addChild(n)
        }
        return clock
    }

    /// 강아지: 몸통·머리·늘어진 귀·꼬리("tail" 흔들기)·다리 네 개(두 쌍이 번갈아)·입에 문 공("mouthBall", 평소 숨김) — +x를 본다
    private func makeDog() -> SKNode {
        let dog = SKNode()
        let gray = NSColor(white: 0.7, alpha: 0.95)
        let body = SKShapeNode(ellipseOf: CGSize(width: 26, height: 11))
        body.position = CGPoint(x: 0, y: 10)
        body.fillColor = gray
        body.strokeColor = .clear
        let head = SKShapeNode(circleOfRadius: 6)
        head.position = CGPoint(x: 13, y: 17)
        head.fillColor = gray
        head.strokeColor = .clear
        let snout = SKShapeNode(ellipseOf: CGSize(width: 7, height: 4.5))
        snout.position = CGPoint(x: 5, y: -2)
        snout.fillColor = gray
        snout.strokeColor = .clear
        head.addChild(snout)
        let ear = SKShapeNode(ellipseOf: CGSize(width: 4, height: 8))
        ear.position = CGPoint(x: -2.5, y: 0)
        ear.zRotation = -0.35
        ear.fillColor = NSColor(white: 0.5, alpha: 0.95)
        ear.strokeColor = .clear
        head.addChild(ear)
        let eye = SKShapeNode(circleOfRadius: 1.1)
        eye.position = CGPoint(x: 2.5, y: 1.5)
        eye.fillColor = NSColor(white: 0.15, alpha: 0.95)
        eye.strokeColor = .clear
        head.addChild(eye)
        let tail = SKShapeNode()
        let tp = CGMutablePath()
        tp.move(to: .zero)
        tp.addQuadCurve(to: CGPoint(x: -7, y: 9), control: CGPoint(x: -8, y: 1))
        tail.path = tp
        tail.position = CGPoint(x: -12, y: 12)
        tail.strokeColor = gray
        tail.lineWidth = 2.6
        tail.lineCap = .round
        tail.name = "tail"
        tail.run(.repeatForever(.sequence([ // 신난 꼬리 — 빠르게
            .rotate(toAngle: 0.45, duration: 0.08), .rotate(toAngle: -0.3, duration: 0.08),
        ])))
        for (i, xs) in [[-8.0, 7.0], [-5.0, 10.0]].enumerated() { // 두 쌍이 반대 위상으로
            let pair = SKShapeNode()
            let lp = CGMutablePath()
            for x in xs {
                lp.move(to: CGPoint(x: x, y: 0))
                lp.addLine(to: CGPoint(x: x, y: -7))
            }
            pair.path = lp
            pair.position = CGPoint(x: 0, y: 7)
            pair.strokeColor = gray
            pair.lineWidth = 2.4
            pair.lineCap = .round
            dog.addChild(pair)
            pair.run(.repeatForever(.sequence([
                .wait(forDuration: Double(i) * 0.06),
                .rotate(toAngle: 0.35, duration: 0.06), .rotate(toAngle: -0.35, duration: 0.06),
            ])))
        }
        let mouthBall = SKShapeNode(circleOfRadius: 4)
        mouthBall.position = CGPoint(x: 21, y: 13)
        mouthBall.fillColor = .white
        mouthBall.strokeColor = NSColor(white: 0.4, alpha: 0.5)
        mouthBall.lineWidth = 0.8
        mouthBall.isHidden = true
        mouthBall.name = "mouthBall"
        for n in [tail, body, head, mouthBall] as [SKNode] {
            dog.addChild(n)
        }
        dog.zPosition = 5
        return dog
    }
}
