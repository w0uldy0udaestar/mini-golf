import AppKit
import GolfCore
import SpriteKit

/// 서프라이즈 이벤트 (2026-09-15 ⑤ 개편). 사용자 판정 "그냥 앞에 공을 놓는다던지 … 색다른 이벤트 같지 않아".
/// 놀라움의 조건 세 가지(아티팩트 5절): ① 결과의 **종류**가 달라야 한다 — 위치만이 아니라 물리·규칙·캐릭터·데스크탑
/// ② **예고 → 사건 → 반응** 3박자 ③ **등급** — 자주 작게, 드물게 크게, 라운드에 한 번 나오는 대형 사건.
/// 계열별 대표: 물리 `gust` · 규칙 `mulligan` · 스틱맨 `nap` · 데스크탑 `cursorCat` · 생물 `frogRescue` + 기존 새·두더지에 예고·반응.
enum SurpriseTier {
    case common, rare, epic

    var weight: Double {
        switch self {
        case .common: 3
        case .rare: 2
        case .epic: 1
        }
    }

    /// 라운드당 종류별 상한
    var perRoundCap: Int {
        switch self {
        case .common: 3
        case .rare: 1
        case .epic: 1
        }
    }
}

/// 발동 시점 — 서프라이즈마다 끼어드는 순간이 다르다 (전부 "공이 멈춘 뒤"였던 것이 같은 결과로 보인 원인 중 하나)
enum SurpriseHook {
    case ballRest // 샷이 끝나 공이 멈춤 (그린 밖)
    case inFlight // 발사 직후 — 비행에 개입
    case aimIdle // 조준을 오래 방치
    case water // 공이 물에 빠짐
}

enum SurpriseKind: String, CaseIterable {
    case birdSteal // 새가 공을 물고 날아가 랜덤 지점에 드롭 (생물)
    case moleNudge // 두더지가 쏙 나와 공을 톡 밀고 사라진다 (생물)
    case frogRescue // 워터에 빠진 공을 개구리가 물고 나온다 — 벌타 면제 (생물·규칙)
    case gust // 비행 중 돌풍 — 낙엽이 날리고 탄도가 꺾인다 (물리)
    case mulligan // 카드가 팔랑 내려오면 직전 샷을 공짜로 다시 (규칙)
    case nap // 어드레스에서 꾸벅 잠들고, 키를 눌러야 깬다 (스틱맨)
    case cursorCat // 진짜 마우스 커서를 쫓는 고양이 — 공 옆이면 앞발로 툭 (데스크탑)
    // 2차 (2026-09-16, Surprises2.swift — 계열별 1종)
    case windowTunnel // 공이 앱 창 속으로 들어가 다른 창에서 나온다 (데스크탑)
    case pinMove // 깃발이 다리를 내고 그린 위를 걸어가 컵이 옮겨진다 (규칙)
    case ballSwap // 택배 상자에서 고무공·볼링공 — 다음 한 샷만 물리가 다르다 (물리)
    case gallery // 관중이 몰려와 다음 샷을 보고 환호·박수·야유 (스틱맨)
    case geese // 거위 떼가 줄지어 건너다 한 마리가 공 위에 앉는다 (생물)

    var tier: SurpriseTier {
        switch self {
        case .birdSteal, .moleNudge, .nap, .gallery, .geese: .common
        case .frogRescue, .gust, .mulligan, .pinMove, .ballSwap: .rare
        case .cursorCat, .windowTunnel: .epic
        }
    }

    var hook: SurpriseHook {
        switch self {
        case .birdSteal, .moleNudge, .mulligan, .cursorCat, .pinMove, .ballSwap, .gallery, .geese: .ballRest
        case .gust, .windowTunnel: .inFlight
        case .nap: .aimIdle
        case .frogRescue: .water
        }
    }

    /// 씬을 점유하는가 (mode = .surprise, 끝나면 걷기). 돌풍·낮잠·창 터널·갤러리는 비행·조준·다음 샷 위에 얹힌다
    var ownsScene: Bool {
        switch self {
        case .gust, .nap, .windowTunnel, .gallery: false
        default: true
        }
    }
}

extension GameScene {
    // ── 발동 ──

    /// 훅마다 호출 — 발동이면 종류를 돌려주고 라운드 카운트를 올린다. 홀인 직전(그린 위)은 제외 (부당함 방지)
    func rollSurprise(hook: SurpriseHook) -> SurpriseKind? {
        if hook == .ballRest, hole.surface(at: ball.x) == .green {
            return nil
        }
        let candidates = SurpriseKind.allCases.filter { $0.hook == hook && surpriseEligible($0) }
        let pick: SurpriseKind?
        if let forced = demoSurpriseKind { // --surprise KIND: 그 종류를 해당 훅마다
            pick = forced.hook == hook ? forced : nil
        } else if demoSurpriseForce { // --demo-surprise: 훅별로 순환 (관찰용)
            let pool = SurpriseKind.allCases.filter { $0.hook == hook }
            guard !pool.isEmpty else { return nil }
            if hook == .ballRest {
                surpriseCursor += 1
                pick = pool[surpriseCursor % pool.count]
            } else {
                pick = pool[0]
            }
        } else {
            let chance = switch hook {
            case .ballRest: 0.08 // 라운드(≈25~35샷)에 2~3번 (2026-08-21 실플레이 피드백)
            case .inFlight: 0.06
            case .aimIdle: 0.6 // 12~20초 방치했을 때만 굴린다
            case .water: 0.4
            }
            guard !candidates.isEmpty, Double.random(in: 0 ..< 1) < chance else { return nil }
            // 등급 가중 추첨 — 흔한 것이 자주, 대형이 드물게
            let total = candidates.reduce(0.0) { $0 + $1.tier.weight }
            var r = Double.random(in: 0 ..< total)
            var chosen = candidates[0]
            for c in candidates {
                r -= c.tier.weight
                if r < 0 {
                    chosen = c
                    break
                }
            }
            pick = chosen
        }
        guard let kind = pick else { return nil }
        surpriseCounts[kind, default: 0] += 1
        return kind
    }

    /// 라운드 상한(종류별·전체 5)과 종류별 전제 조건
    private func surpriseEligible(_ kind: SurpriseKind) -> Bool {
        if demoSurpriseKind != nil || demoSurpriseForce {
            return true
        }
        let count = surpriseCounts[kind, default: 0]
        guard count < kind.tier.perRoundCap else { return false }
        guard surpriseCounts.values.reduce(0, +) < 5 else { return false }
        switch kind {
        case .mulligan: // 직전 샷이 나빴을 때만 — 3m도 못 나갔거나 벙커에 들어갔거나
            let remain = abs(hole.holeX - ball.x)
            return strokes >= 1 && (remain > preShot.remain - 3 || hole.surface(at: ball.x) == .bunker)
        case .cursorCat: // 커서가 이 화면에 있어야 쫓을 게 있다
            return mouseInScene() != nil
        case .frogRescue: // 마지막 타에 빠진 공까지 구해 주진 않는다 (onWater는 즉시 기권)
            return strokes + 1 < Phys.maxStrokes
        case .windowTunnel: // 지날 창이 있어야 한다 (범퍼 모드 켜짐 + 샷 순간 스냅샷)
            return Theme.windowBumpers && !shotBumpers.isEmpty
        case .pinMove: // 옮길 만한 그린 폭 + 아직 먼 거리 (옮겨도 티가 나야 한다)
            return hole.greenEnd - hole.greenStart >= 12 && abs(hole.holeX - ball.x) > 25
        case .ballSwap: // 다음 샷이 있고, 그 샷이 의미 있을 만큼 멀 때
            return strokes + 1 < Phys.maxStrokes && abs(hole.holeX - ball.x) > 30
        case .gallery: // 지켜볼 샷이 남아 있어야, 이미 와 있으면 안 겹친다
            return strokes + 1 < Phys.maxStrokes && galleryState == nil
        default:
            return true
        }
    }

    func playSurprise(_ kind: SurpriseKind) {
        if kind.ownsScene {
            mode = .surprise
        }
        if demoMode {
            print("SURPRISE \(kind.rawValue) @\(Int(ball.x)) tier \(kind.tier)")
            fflush(stdout)
            if let t = demoRestartIn { // 인터럽트 정리 관찰: T초 뒤 R과 같은 경로
                run(.sequence([.wait(forDuration: t), .run { [weak self] in
                    print("DEMO restart (newRound) during \(kind.rawValue)")
                    fflush(stdout)
                    self?.newRound()
                }]))
            }
        }
        switch kind {
        case .birdSteal: playBirdSteal()
        case .moleNudge: playMoleNudge()
        case .frogRescue: playFrogRescue()
        case .gust: startGust()
        case .mulligan: playMulligan()
        case .nap: startNap()
        case .cursorCat: playCursorCat()
        case .windowTunnel: playWindowTunnel()
        case .pinMove: playPinMove()
        case .ballSwap: playBallSwap()
        case .gallery: playGallery()
        case .geese: playGeese()
        }
    }

    func finishSurprise() {
        guard mode == .surprise else { return } // 새 라운드 등으로 이미 전환됐으면 무시
        startWalk()
    }

    /// 홀 시작(R 새 라운드 포함)에서 진행 중인 서프라이즈를 전부 걷어낸다 — 노드를 지우면 대기 중인 .run 클로저도 함께 사라진다.
    /// 안 하면 새가 문 공의 드롭·멀리건의 타수 복원이 새 홀에서 실행돼 상태를 오염시켰다 (리뷰 M2)
    func cancelSurprises() {
        enumerateChildNodes(withName: Self.surpriseNodeName) { node, _ in node.removeFromParent() }
        catState?.node.removeFromParent()
        catState = nil
        gustWind = nil
        napping = false
        napIdle = .infinity
        napNode?.removeFromParent()
        napNode = nil
        cancelSurprises2()
    }

    static let surpriseNodeName = "surprise"

    /// 조준 중 매 프레임 — 마지막 입력 뒤 napIdle초 방치하면 굴려서 발동 (카운트는 실제 발동 때만 소모, 리뷰 M1)
    func tickNap() {
        guard mode == .aim, !napping, aimTime - lastInputAim >= napIdle else { return }
        if rollSurprise(hook: .aimIdle) == .nap {
            startNap()
        } else {
            napIdle = .infinity // 이번 조준은 안 잔다
        }
    }

    /// 매 프레임 — 돌풍 만료·고양이 추적·낮잠 자동 기상(데모)
    func updateSurprises(dt: Double, currentTime: TimeInterval) {
        if gustWind != nil, currentTime >= gustUntil {
            gustWind = nil
        }
        if let c = catState {
            updateCat(c, dt: dt, currentTime: currentTime)
        }
        if napping, demoMode, aimTime - napStart >= 2.5 {
            wakeUp() // 관찰 모드는 키가 없으니 스스로 깬다
        }
        updateSurprises2(currentTime: currentTime)
    }

    /// 스틱맨 반응 시작 (예고→사건→**반응**) — 홀아웃 반응과 같은 채널
    func react(_ kind: ReactionKind) {
        reactionKind = kind
        reactionAt = lastTime
    }

    // ── 예고: 새 그림자·두더지 땅 울림 ──

    /// 새 도둑: 유불리 랜덤 드롭 (골프 규칙 18-1 '외부 요인' — 놓인 자리에서 플레이).
    /// 예고 = 1초 전 그림자가 공 위를 스치고 지저귐 · 반응 = 훠이훠이(낚아채는 순간 화들짝)
    private func playBirdSteal() {
        let bird = makeBird()
        bird.name = Self.surpriseNodeName
        let ballPos = CGPoint(x: px(ball.x), y: groundY(ball.x) + 5.5)
        // 드롭 지점: 홀 방향 ±35m 랜덤 — 도움일 수도, 배신일 수도
        let delta = Double.random(in: -35 ... 35)
        var dropX = ball.x + delta
        dropX = min(max(dropX, 8), hole.worldW - 8)
        if hole.surface(at: dropX) == .water { // 물에는 안 떨어뜨린다 (벌타 사건은 과함)
            dropX = ball.x - delta.magnitude * 0.4
        }
        let dropPos = CGPoint(x: px(dropX), y: groundY(dropX) + 5.5)
        let entryY = size.height * 0.86
        let fromRight = ballPos.x < size.width / 2
        bird.position = CGPoint(x: fromRight ? size.width + 40 : -40, y: entryY)
        addChild(bird) // 화면 밖에 미리 — 씬 밖 노드는 액션이 진행되지 않는다

        // 예고: 그림자가 공 위를 스치고 지저귐 (1.0s)
        let shadow = SKShapeNode(ellipseOf: CGSize(width: 26, height: 7))
        shadow.fillColor = NSColor(white: 0.1, alpha: 0.28)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: ballPos.x + (fromRight ? 260 : -260), y: groundY(ball.x) - 1)
        shadow.zPosition = 1
        addChild(shadow)
        SoundKit.shared.chirp()
        let sweep = SKAction.moveTo(x: ballPos.x + (fromRight ? -200 : 200), duration: 1.0)
        sweep.timingMode = .easeInEaseOut
        shadow.run(.sequence([sweep, .fadeOut(withDuration: 0.2), .removeFromParent()]))

        let swoopIn = SKAction.move(to: ballPos, duration: 0.9)
        swoopIn.timingMode = .easeInEaseOut
        let carry = SKAction.move(to: CGPoint(x: dropPos.x, y: dropPos.y + 130), duration: 1.1)
        carry.timingMode = .easeInEaseOut
        let exitX = bird.position.x // 들어온 쪽으로 되돌아 나간다
        let leave = SKAction.move(to: CGPoint(x: exitX, y: size.height * 0.95), duration: 0.9)
        leave.timingMode = .easeIn

        bird.run(.sequence([
            .wait(forDuration: 1.0),
            .run { [weak self] in self?.toast("새다!", sub: nil) },
            swoopIn,
            .run { [weak self] in // 낚아채기 — 공이 새를 따라간다
                guard let self else { return }
                SoundKit.shared.wall(speed: 3)
                react(.startled)
                ballNode.removeAllActions()
                ballNode.run(SKAction.customAction(withDuration: 2.0) { [weak self, weak bird] node, _ in
                    guard let bird else { return }
                    node.position = CGPoint(x: bird.position.x, y: bird.position.y - 9)
                    self?.shadowNode.isHidden = true
                })
            },
            .wait(forDuration: 0.4),
            .run { [weak self] in
                self?.react(.shoo)
                self?.toast("새가 공을 물어갔다!", sub: nil)
            },
            SKAction.group([carry, .wait(forDuration: 0.7)]),
            .run { [weak self] in // 드롭
                guard let self else { return }
                ball = BallState(x: dropX, y: hole.ground(at: dropX))
                ballNode.removeAllActions()
                let fall = SKAction.move(to: dropPos, duration: 0.42)
                fall.timingMode = .easeIn
                ballNode.run(.sequence([fall, .run { [weak self] in
                    guard let self else { return }
                    SoundKit.shared.bounce(speed: 3, surface: hole.surface(at: dropX))
                    FX.dust(on: self, at: dropPos, surface: hole.surface(at: dropX), intensity: 0.4)
                }]))
            },
            leave,
            .removeFromParent(),
            .run { [weak self] in self?.finishSurprise() },
        ]))
        // 날갯짓 — 위아래 파닥임
        bird.run(.repeatForever(.sequence([
            .scaleY(to: 0.55, duration: 0.12), .scaleY(to: 1.0, duration: 0.12),
        ])))
    }

    /// 두더지: 공을 1~3m 톡 — 사소한 참견. 예고 = 땅이 두 번 울렁이고 흙이 튄다 · 반응 = 화들짝
    private func playMoleNudge() {
        let mole = makeMole()
        mole.name = Self.surpriseNodeName
        let side: Double = Bool.random() ? 1 : -1
        let moleX = ball.x - side * 1.2
        let groundPt = CGPoint(x: px(moleX), y: groundY(moleX))
        mole.position = CGPoint(x: groundPt.x, y: groundPt.y - 14)
        mole.setScale(0.1)
        addChild(mole)
        let popUp = SKAction.group([
            SKAction.move(to: CGPoint(x: groundPt.x, y: groundPt.y + 4), duration: 0.3),
            SKAction.scale(to: 1, duration: 0.3),
        ])
        popUp.timingMode = .easeOut
        let nudgeDist = side * Double.random(in: 1.2 ... 3.0)
        let newX = outOfWater(min(max(ball.x + nudgeDist, 6), hole.worldW - 6))
        let sink = SKAction.group([
            SKAction.move(to: CGPoint(x: groundPt.x, y: groundPt.y - 14), duration: 0.25),
            SKAction.scale(to: 0.1, duration: 0.25),
        ])
        sink.timingMode = .easeIn
        let rumble = SKAction.run { [weak self] in // 예고: 땅 울림 + 흙
            guard let self else { return }
            SoundKit.shared.thump()
            FX.dust(on: self, at: groundPt, surface: .rough, intensity: 0.5)
        }

        mole.run(.sequence([
            rumble, .wait(forDuration: 0.45), rumble, .wait(forDuration: 0.4),
            popUp,
            .run { [weak self] in
                self?.react(.startled)
                self?.toast("두더지!", sub: nil)
            },
            .wait(forDuration: 0.35),
            .run { [weak self] in // 톡 — 공이 짧게 굴러간다
                guard let self else { return }
                SoundKit.shared.bounce(speed: 2, surface: hole.surface(at: ball.x))
                ball = BallState(x: newX, y: hole.ground(at: newX))
                let roll = SKAction.move(
                    to: CGPoint(x: px(newX), y: groundY(newX) + 5.5), duration: 0.5
                )
                roll.timingMode = .easeOut
                ballNode.run(roll)
            },
            .wait(forDuration: 0.5),
            sink,
            .removeFromParent(),
            .run { [weak self] in self?.finishSurprise() },
        ]))
    }

    // ── 생물·규칙: 개구리 구조 (워터 훅) ──

    /// 공이 물에 빠졌는데 개구리가 물고 나온다 — 벌타 면제. 예고 = 물결 두 번 · 사건 = 세 번 뛰어 둑에 놓기 · 반응 = 주먹
    private func playFrogRescue() {
        endShotTrail()
        roundHadWater = true // 물에 들어간 건 사실 — 무입수 배지는 안 주고 통계도 센다 (벌타만 면제)
        if !demoMode {
            Records.shared.waterBalls += 1
            Records.shared.save()
        }
        SoundKit.shared.splash()
        let splashPt = CGPoint(x: px(ball.x), y: groundY(ball.x))
        FX.ripple(on: self, at: splashPt)
        let wr = hole.waterRange ?? (ball.x - 3) ... (ball.x + 3)
        let bankX = dir > 0 ? wr.lowerBound - 2.5 : wr.upperBound + 2.5
        let bankPt = CGPoint(x: px(bankX), y: groundY(bankX))
        let frog = makeFrog()
        frog.name = Self.surpriseNodeName
        frog.position = CGPoint(x: splashPt.x, y: splashPt.y - 12)
        frog.xScale = bankPt.x < splashPt.x ? -1 : 1
        frog.alpha = 0
        addChild(frog)
        ballNode.removeAllActions()
        shadowNode.isHidden = true

        func hop(to p: CGPoint, dur: Double) -> SKAction {
            let up = SKAction.move(
                to: CGPoint(x: (frog.position.x + p.x) / 2, y: max(frog.position.y, p.y) + 26),
                duration: dur * 0.5
            )
            up.timingMode = .easeOut
            let down = SKAction.move(to: p, duration: dur * 0.5)
            down.timingMode = .easeIn
            return .sequence([up, down])
        }
        let n = 3
        var hops: [SKAction] = []
        for i in 1 ... n {
            let u = Double(i) / Double(n)
            let p = CGPoint(x: mix(splashPt.x, bankPt.x, u), y: mix(splashPt.y, bankPt.y, u) + 2)
            hops.append(.run { SoundKit.shared.ribbit() })
            hops.append(.run { [weak frog] in
                guard let frog else { return }
                frog.run(hop(to: p, dur: 0.5))
            })
            hops.append(.wait(forDuration: 0.62))
        }
        var back: [SKAction] = []
        for i in 1 ... n {
            let u = Double(i) / Double(n)
            let p = CGPoint(x: mix(bankPt.x, splashPt.x, u), y: mix(bankPt.y, splashPt.y, u) + 2)
            back.append(.run { [weak frog] in
                guard let frog else { return }
                frog.run(hop(to: p, dur: 0.45))
            })
            back.append(.wait(forDuration: 0.5))
        }
        frog.run(.sequence([
            .wait(forDuration: 0.5),
            .run { [weak self] in
                guard let self else { return }
                FX.ripple(on: self, at: splashPt)
            },
            .wait(forDuration: 0.5),
            .run { [weak self] in
                guard let self else { return }
                FX.ripple(on: self, at: splashPt)
                SoundKit.shared.ribbit()
                toast("개구리?", sub: nil)
            },
            SKAction.group([.fadeIn(withDuration: 0.3), .moveBy(x: 0, y: 12, duration: 0.3)]),
            .run { [weak self, weak frog] in // 공을 물고 간다
                guard let self, let frog else { return }
                ballNode.isHidden = false
                ballNode.run(SKAction.customAction(withDuration: 2.5) { [weak frog] node, _ in
                    guard let frog else { return }
                    node.position = CGPoint(x: frog.position.x + frog.xScale * 6, y: frog.position.y + 8)
                })
            },
            .wait(forDuration: 0.4),
            .sequence(hops),
            .run { [weak self] in // 둑에 내려놓는다
                guard let self else { return }
                ball = BallState(x: bankX, y: hole.ground(at: bankX))
                ballNode.removeAllActions()
                ballNode.position = CGPoint(x: bankPt.x, y: bankPt.y + 5.5)
                SoundKit.shared.bounce(speed: 1.5, surface: hole.surface(at: bankX))
                toast("개구리 구조!", sub: "벌타 면제")
                react(.fistPump)
            },
            .run { [weak frog] in frog?.xScale *= -1 },
            .wait(forDuration: 0.3),
            .sequence(back),
            SKAction.group([.fadeOut(withDuration: 0.3), .moveBy(x: 0, y: -12, duration: 0.3)]),
            .removeFromParent(),
            .run { [weak self] in self?.finishSurprise() },
        ]))
    }

    // ── 물리: 돌풍 (비행 훅) ──

    /// 비행 중 1.3초 돌풍 — 깃발이 홱 돌고 낙엽이 날리며 탄도가 꺾인다. 물리는 Ballistics.step의 바람 덮어쓰기로
    private func startGust() {
        let sign: Double = Bool.random() ? 1 : -1
        let strength = Double.random(in: 7 ... 10)
        gustWind = sign * strength
        gustUntil = lastTime + 1.3
        SoundKit.shared.gust(dur: 1.3)
        toast("돌풍!", sub: sign > 0 ? "→ \(Int(strength))m/s" : "← \(Int(strength))m/s")
        if !(swingStyle.clubTwirl && lastShotGood) { // 타이거 트월과 리그가 겹치면 트월을 우선 (리뷰 m5)
            react(.startled)
        }
        // 깃발이 홱 — 깃대 흔들림
        let jolt = SKAction.sequence([
            .rotate(byAngle: -0.35 * sign, duration: 0.12),
            .rotate(byAngle: 0.5 * sign, duration: 0.25),
            .rotate(byAngle: -0.15 * sign, duration: 0.3),
        ])
        jolt.timingMode = .easeInEaseOut
        flagNode.run(jolt)
        // 낙엽: 화면 위쪽에서 바람 방향으로 흩날린다
        for i in 0 ..< 10 {
            let leaf = SKShapeNode(ellipseOf: CGSize(width: 7, height: 4))
            leaf.fillColor = NSColor(white: 0.8, alpha: 0.85)
            leaf.strokeColor = .clear
            leaf.zPosition = 6
            let startX = sign > 0 ? -20 - Double(i) * 30 : size.width + 20 + Double(i) * 30
            leaf.position = CGPoint(x: startX, y: size.height * Double.random(in: 0.25 ... 0.7))
            addChild(leaf)
            let travel = Double(size.width) * 0.6 + Double.random(in: 0 ... 200)
            let fly = SKAction.moveBy(x: sign * travel, y: Double.random(in: -60 ... 30), duration: 1.3)
            fly.timingMode = .easeIn
            let tumble = SKAction.repeatForever(.rotate(byAngle: .pi * 2, duration: Double.random(in: 0.3 ... 0.6)))
            leaf.run(tumble)
            leaf.run(.sequence([
                .wait(forDuration: Double(i) * 0.05),
                fly,
                .fadeOut(withDuration: 0.2),
                .removeFromParent(),
            ]))
        }
    }

    // ── 규칙: 멀리건 (공이 멈춘 뒤, 나쁜 샷 한정) ──

    /// 카드가 팔랑 내려오면 직전 샷을 공짜로 다시 — 공은 원래 자리로, 타수는 하나 돌려받는다
    private func playMulligan() {
        let card = makeCard()
        card.name = Self.surpriseNodeName
        let sx = px(stickX)
        card.position = CGPoint(x: sx - dir * 70, y: size.height * 0.92)
        card.alpha = 0
        addChild(card)
        SoundKit.shared.flutter()
        // 팔랑팔랑: 좌우로 흔들리며 내려온다
        var fall: [SKAction] = []
        let landY = groundY(stickX) + 22
        let steps = 6
        for i in 0 ..< steps {
            let y = mix(Double(size.height * 0.92), Double(landY), Double(i + 1) / Double(steps))
            let x = Double(sx) - Double(dir) * 70 + (i % 2 == 0 ? 28.0 : -28.0)
            let m = SKAction.move(to: CGPoint(x: x, y: y), duration: 0.42)
            m.timingMode = .easeInEaseOut
            fall.append(.group([m, .rotate(toAngle: i % 2 == 0 ? 0.35 : -0.35, duration: 0.42)]))
        }
        let restore = preShot
        card.run(.sequence([
            .fadeIn(withDuration: 0.3),
            .sequence(fall),
            .rotate(toAngle: 0, duration: 0.2),
            .run { [weak self] in
                guard let self else { return }
                react(.laugh)
                toast("멀리건!", sub: "직전 샷 무료 · 공이 돌아간다")
                SoundKit.shared.chime()
            },
            .wait(forDuration: 0.6),
            .run { [weak self] in // 공이 사라졌다가 원래 자리에
                guard let self else { return }
                let target = CGPoint(x: px(restore.x), y: groundY(restore.x) + 5.5)
                ballNode.run(.sequence([
                    .fadeOut(withDuration: 0.25),
                    .move(to: target, duration: 0),
                    .fadeIn(withDuration: 0.25),
                ]))
                ball = BallState(x: restore.x, y: hole.ground(at: restore.x))
                strokes = restore.strokes
                updateHUD()
            },
            .wait(forDuration: 0.6),
            .fadeOut(withDuration: 0.3),
            .removeFromParent(),
            .run { [weak self] in self?.finishSurprise() },
        ]))
    }

    // ── 스틱맨: 낮잠 (조준 방치) ──

    /// 조준을 오래 방치하면 꾸벅 잠든다. 아무 키나 누르면 화들짝 깨고 그제야 조준이 이어진다
    func startNap() {
        napping = true
        napStart = aimTime
        let z = SKNode()
        z.name = Self.surpriseNodeName
        z.zPosition = 8
        for i in 0 ..< 3 {
            let label = SKLabelNode(fontNamed: HUDFont.light)
            label.text = "z"
            label.fontSize = CGFloat(11 + i * 4)
            label.fontColor = NSColor(white: 0.95, alpha: 0.9)
            label.alpha = 0
            z.addChild(label)
            let rise = SKAction.sequence([
                .wait(forDuration: Double(i) * 0.7),
                .repeatForever(.sequence([
                    .group([.fadeIn(withDuration: 0.3), .move(to: CGPoint(x: 6 + i * 7, y: 4 + i * 9), duration: 0)]),
                    .group([
                        .moveBy(x: 8, y: 22, duration: 1.8),
                        .sequence([.wait(forDuration: 1.2), .fadeOut(withDuration: 0.6)]),
                    ]),
                ])),
            ])
            label.run(rise)
        }
        z.position = CGPoint(x: stickman.position.x - CGFloat(dir) * 6, y: stickman.position.y + 92)
        addChild(z)
        napNode = z
        SoundKit.shared.snore()
        z.run(.repeatForever(.sequence([.wait(forDuration: 2.4), .run { SoundKit.shared.snore() }])))
        toast("쿨쿨…", sub: nil)
        if demoMode {
            print("SURPRISE nap start aim \(String(format: "%.1f", aimTime))")
            fflush(stdout)
        }
    }

    /// 아무 키나 → 화들짝 (키는 소비된다)
    func wakeUp() {
        guard napping else { return }
        napping = false
        napIdle = .infinity // 조준당 한 번 — 기상 직후 같은 프레임에 다시 잠들던 소프트락 (리뷰 C1)
        napNode?.removeFromParent()
        napNode = nil
        react(.startled)
        SoundKit.shared.chirp()
        toast("앗!", sub: nil)
        if demoMode {
            print("SURPRISE nap wake")
            fflush(stdout)
        }
    }

    /// 조준 리그 위에 얹는 졸음 — 서서히 꾸벅, 호흡, 클럽 축 늘어짐
    func applyNap(_ rig: inout Rig) {
        let t = aimTime - napStart
        let d = smoothstep(min(1, max(0, t / 1.4)))
        let breathe = sin(2 * .pi * 0.35 * t) * d
        rig.shoulder.y -= 3 * d - 0.6 * breathe
        rig.hip.y -= 1.5 * d
        rig.headDy -= 5 * d
        rig.headDx -= 3 * d
        rig.grip.y -= 4 * d
        rig.handTrail.y -= 4 * d
        rig.clubPhi = mix(rig.clubPhi, -0.2, d)
    }

    // ── 데스크탑: 커서 쫓는 고양이 (공이 멈춘 뒤, 라운드에 한 번) ──

    /// 이 게임만 할 수 있는 것 — 진짜 마우스 커서를 쫓는다. 커서가 공 근처면 앞발로 툭. 커서를 못 따라잡아도 결국 공을 건드린다
    private func playCursorCat() {
        let cat = makeCat()
        cat.name = Self.surpriseNodeName
        let fromRight = px(ball.x) < size.width / 2
        let y = groundY(ball.x)
        cat.position = CGPoint(x: fromRight ? size.width + 40 : -40, y: y)
        addChild(cat)
        catState = CatState(
            node: cat,
            startedAt: lastTime,
            vx: 0,
            facing: fromRight ? -1 : 1,
            phase: .chasing,
            lastMeow: lastTime
        )
        SoundKit.shared.meow()
        toast("고양이가 왔다", sub: "커서를 쫓는다…")
    }

    private func updateCat(_ c: CatState, dt: Double, currentTime: TimeInterval) {
        var c = c
        let elapsed = currentTime - c.startedAt
        let ballPx = Double(px(ball.x))
        var targetX: Double
        switch c.phase {
        case .chasing:
            let mouse = mouseInScene()
            let giveUp = elapsed > 5.0
            if let m = mouse, !giveUp {
                targetX = Double(m.x)
            } else {
                targetX = ballPx + Double(c.facing) * -18 // 공 앞에 선다
                c.phase = .toBall
            }
            // 커서가 공 옆에 머물면 공을 툭 (커서 60px 안 + 고양이 26px 안)
            let nearBall = abs(Double(c.node.position.x) - ballPx) < 26
            let cursorNearBall = mouse.map { abs(Double($0.x) - ballPx) < 60 } ?? false
            if nearBall, cursorNearBall, elapsed > 1.2 {
                pawBall(&c)
            }
            if abs(Double(c.node.position.x) - Double(px(stickX))) < 120,
               reactionKind == .none || reactionKind == .dejected {
                react(.shoo)
            }
        case .toBall:
            targetX = ballPx - Double(c.facing) * 18
            if abs(Double(c.node.position.x) - targetX) < 6 {
                pawBall(&c)
            }
        case .leaving:
            targetX = c.facing > 0 ? Double(size.width) + 60 : -60
            if c.node.position.x < -50 || c.node.position.x > size.width + 50 {
                c.node.removeFromParent()
                catState = nil
                finishSurprise()
                return
            }
        case .pawing:
            targetX = Double(c.node.position.x)
        }
        // 이동: 목표를 향해 가속, 최대 240px/s, 방향에 따라 몸을 돌린다
        let dx = targetX - Double(c.node.position.x)
        let want = max(-240, min(240, dx * 3))
        c.vx += (want - c.vx) * min(1, 6 * dt)
        if abs(c.vx) > 12 {
            c.facing = c.vx > 0 ? 1 : -1
            c.node.xScale = CGFloat(c.facing)
        }
        c.node.position.x += CGFloat(c.vx * dt)
        c.node.position.y = groundY(Double(c.node.position.x) / Double(pxPerM)) + 2 * abs(sin(currentTime * 9)) * min(
            1,
            abs(c.vx) / 80
        )
        if demoMode, Int(currentTime * 2) != Int((currentTime - dt) * 2) { // 관찰: 0.5s마다 위치·목표·커서
            let mx = mouseInScene().map { String(format: "%.0f", $0.x) } ?? "-"
            print(String(
                format: "CAT %@ x %.0f target %.0f mouse %@ ball %.0f",
                String(describing: c.phase),
                Double(c.node.position.x),
                targetX,
                mx,
                ballPx
            ))
            fflush(stdout)
        }
        if currentTime - c.lastMeow > 2.2, c.phase == .chasing {
            c.lastMeow = currentTime
            SoundKit.shared.meow()
        }
        catState = c
    }

    private func pawBall(_ c: inout CatState) {
        c.phase = .pawing
        let facing = Double(c.facing)
        let paw = c.node.childNode(withName: "paw")
        paw?.run(.sequence([.rotate(toAngle: 0.9, duration: 0.12), .rotate(toAngle: 0, duration: 0.18)]))
        let dist = facing * Double.random(in: 1.5 ... 3.0)
        let newX = outOfWater(min(max(ball.x + dist, 6), hole.worldW - 6))
        SoundKit.shared.bounce(speed: 2, surface: hole.surface(at: ball.x))
        ball = BallState(x: newX, y: hole.ground(at: newX))
        let roll = SKAction.move(to: CGPoint(x: px(newX), y: groundY(newX) + 5.5), duration: 0.6)
        roll.timingMode = .easeOut
        ballNode.run(roll)
        react(.shoo)
        toast("툭.", sub: "고양이가 공을 건드렸다")
        if demoMode {
            print("SURPRISE cat paw → \(Int(newX))")
            fflush(stdout)
        }
        let leaveFacing = c.facing
        c.node.run(.sequence([.wait(forDuration: 0.9), .run { [weak self] in
            guard let self, var cc = catState else { return }
            cc.phase = .leaving
            cc.facing = leaveFacing
            catState = cc
        }]))
    }

    /// 두더지·고양이가 공을 물속으로 밀지 않게 — 워터 범위 안이면 가까운 물가 밖으로 (리뷰 m3)
    func outOfWater(_ x: Double) -> Double {
        guard let wr = hole.waterRange, wr.contains(x) else { return x }
        return x - wr.lowerBound < wr.upperBound - x ? wr.lowerBound - 2.5 : wr.upperBound + 2.5
    }

    /// 실제 마우스 커서를 씬 좌표로 — 이 화면 밖이면 nil
    func mouseInScene() -> CGPoint? {
        guard let view, let window = view.window else { return nil }
        let inWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let inView = view.convert(inWindow, from: nil)
        let p = convertPoint(fromView: inView)
        guard p.x >= -40, p.x <= size.width + 40, p.y >= -40, p.y <= size.height + 40 else { return nil }
        return p
    }

    // ── 셰이프: 게임 회색 실루엣 문법 ──

    private func makeBird() -> SKNode {
        let bird = SKNode()
        let body = SKShapeNode(ellipseOf: CGSize(width: 16, height: 9))
        body.fillColor = NSColor(white: 0.82, alpha: 0.95)
        body.strokeColor = .clear
        let wing = SKShapeNode()
        let wp = CGMutablePath()
        wp.move(to: CGPoint(x: -10, y: 6))
        wp.addLine(to: CGPoint(x: -1, y: 1))
        wp.addLine(to: CGPoint(x: 8, y: 6))
        wing.path = wp
        wing.strokeColor = NSColor(white: 0.82, alpha: 0.95)
        wing.lineWidth = 2.4
        wing.lineCap = .round
        let beak = SKShapeNode()
        let bp = CGMutablePath()
        bp.move(to: CGPoint(x: 8, y: 1))
        bp.addLine(to: CGPoint(x: 13, y: -1))
        beak.path = bp
        beak.strokeColor = NSColor(white: 0.7, alpha: 0.95)
        beak.lineWidth = 2
        beak.lineCap = .round
        bird.addChild(body)
        bird.addChild(wing)
        bird.addChild(beak)
        bird.zPosition = 5
        return bird
    }

    private func makeMole() -> SKNode {
        let mole = SKNode()
        let head = SKShapeNode()
        let hp = CGMutablePath()
        hp.addArc(
            center: .zero, radius: 9,
            startAngle: 0, endAngle: .pi, clockwise: false
        )
        hp.closeSubpath()
        head.path = hp
        head.fillColor = NSColor(white: 0.55, alpha: 0.95)
        head.strokeColor = .clear
        let nose = SKShapeNode(circleOfRadius: 2.2)
        nose.position = CGPoint(x: 0, y: 8)
        nose.fillColor = NSColor(white: 0.35, alpha: 0.95)
        nose.strokeColor = .clear
        mole.addChild(head)
        mole.addChild(nose)
        mole.zPosition = 4
        return mole
    }

    /// 개구리: 납작한 몸통 + 툭 튀어나온 눈 두 개 (xScale로 방향)
    private func makeFrog() -> SKNode {
        let frog = SKNode()
        let body = SKShapeNode(ellipseOf: CGSize(width: 20, height: 11))
        body.fillColor = NSColor(white: 0.66, alpha: 0.95)
        body.strokeColor = .clear
        frog.addChild(body)
        for x in [3.0, 8.0] {
            let eye = SKShapeNode(circleOfRadius: 2.6)
            eye.position = CGPoint(x: x, y: 5.5)
            eye.fillColor = NSColor(white: 0.9, alpha: 0.95)
            eye.strokeColor = .clear
            let pupil = SKShapeNode(circleOfRadius: 1.1)
            pupil.position = CGPoint(x: 0.8, y: 0.3)
            pupil.fillColor = NSColor(white: 0.2, alpha: 0.95)
            pupil.strokeColor = .clear
            eye.addChild(pupil)
            frog.addChild(eye)
        }
        let legs = SKShapeNode()
        let lp = CGMutablePath()
        lp.move(to: CGPoint(x: -8, y: -3))
        lp.addLine(to: CGPoint(x: -14, y: 2))
        lp.addLine(to: CGPoint(x: -12, y: -6))
        legs.path = lp
        legs.strokeColor = NSColor(white: 0.66, alpha: 0.95)
        legs.lineWidth = 2.2
        legs.lineCap = .round
        legs.lineJoin = .round
        frog.addChild(legs)
        frog.zPosition = 5
        return frog
    }

    /// 고양이: 몸통·머리·귀·꼬리·앞발("paw" — 툭 칠 때 회전)
    private func makeCat() -> SKNode {
        let cat = SKNode()
        let gray = NSColor(white: 0.74, alpha: 0.95)
        let body = SKShapeNode(ellipseOf: CGSize(width: 34, height: 14))
        body.position = CGPoint(x: 0, y: 9)
        body.fillColor = gray
        body.strokeColor = .clear
        let head = SKShapeNode(circleOfRadius: 7.5)
        head.position = CGPoint(x: 17, y: 16)
        head.fillColor = gray
        head.strokeColor = .clear
        let ears = SKShapeNode()
        let ep = CGMutablePath()
        for ex in [13.0, 20.0] {
            ep.move(to: CGPoint(x: ex, y: 21))
            ep.addLine(to: CGPoint(x: ex + 2.5, y: 28))
            ep.addLine(to: CGPoint(x: ex + 5, y: 21))
        }
        ears.path = ep
        ears.fillColor = gray
        ears.strokeColor = .clear
        let tail = SKShapeNode()
        let tp = CGMutablePath()
        tp.move(to: CGPoint(x: -16, y: 10))
        tp.addQuadCurve(to: CGPoint(x: -28, y: 26), control: CGPoint(x: -30, y: 8))
        tail.path = tp
        tail.strokeColor = gray
        tail.lineWidth = 3
        tail.lineCap = .round
        tail.run(.repeatForever(.sequence([
            .rotate(toAngle: 0.25, duration: 0.6),
            .rotate(toAngle: -0.25, duration: 0.6),
        ])))
        let legs = SKShapeNode()
        let lp = CGMutablePath()
        for lx in [-11.0, -6.0, 6.0] {
            lp.move(to: CGPoint(x: lx, y: 6))
            lp.addLine(to: CGPoint(x: lx, y: 0))
        }
        legs.path = lp
        legs.strokeColor = gray
        legs.lineWidth = 3
        legs.lineCap = .round
        let paw = SKShapeNode()
        let pp = CGMutablePath()
        pp.move(to: .zero)
        pp.addLine(to: CGPoint(x: 0, y: -7))
        paw.path = pp
        paw.position = CGPoint(x: 12, y: 7)
        paw.strokeColor = gray
        paw.lineWidth = 3
        paw.lineCap = .round
        paw.name = "paw"
        let eye = SKShapeNode(circleOfRadius: 1.2)
        eye.position = CGPoint(x: 20, y: 17)
        eye.fillColor = NSColor(white: 0.15, alpha: 0.95)
        eye.strokeColor = .clear
        for n in [tail, legs, body, paw, head, ears, eye] as [SKNode] {
            cat.addChild(n)
        }
        cat.zPosition = 5
        return cat
    }

    /// 멀리건 카드: 둥근 사각 + 글자
    private func makeCard() -> SKNode {
        let card = SKShapeNode(rectOf: CGSize(width: 46, height: 62), cornerRadius: 6)
        card.fillColor = NSColor(white: 0.95, alpha: 0.95)
        card.strokeColor = NSColor(white: 0.6, alpha: 0.9)
        card.lineWidth = 1.5
        let label = SKLabelNode(fontNamed: HUDFont.semibold)
        label.text = "M"
        label.fontSize = 26
        label.fontColor = NSColor(white: 0.25, alpha: 1)
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: 0, y: 6)
        let sub = SKLabelNode(fontNamed: HUDFont.regular)
        sub.text = "멀리건"
        sub.fontSize = 8
        sub.fontColor = NSColor(white: 0.4, alpha: 1)
        sub.verticalAlignmentMode = .center
        sub.position = CGPoint(x: 0, y: -16)
        card.addChild(label)
        card.addChild(sub)
        card.zPosition = 7
        return card
    }
}

/// 고양이 추적 상태 (매 프레임 갱신 — SKAction보다 커서 추적에 맞다)
struct CatState {
    enum Phase { case chasing, toBall, pawing, leaving }
    let node: SKNode
    let startedAt: TimeInterval
    var vx: Double
    var facing: Int
    var phase: Phase
    var lastMeow: TimeInterval
}
