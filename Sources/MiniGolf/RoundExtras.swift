import AppKit
import GolfCore
import SpriteKit

// ═══════════════════════════════════════════════════════════════
// M6 라운드 변주 (2026-10-05): 홀 미션 · 날씨 라운드 · 고스트 라이벌
// 규칙·판정은 GolfCore(Mission·Weather·Rival), 여기는 화면에 올리는 일만.
// 셋 다 라운드 시드에서 정해져 9홀 내내 고정이고, 1번 홀 시작 안내(홀 인트로)부터 보인다 —
// 실플레이 기록상 9홀 완주가 드물어 뒤쪽 홀에만 나오는 기능은 못 본 채 끝난다.
// ═══════════════════════════════════════════════════════════════

/// 라운드 변주 상태 한 묶음 (Surprise3State와 같은 패턴 — 씬의 저장 프로퍼티는 하나만 늘린다)
struct RoundExtras {
    var weather = Weather.clear
    var missionPlan: [MissionKind] = []
    var mission: MissionTracker?
    var preShotMission: MissionTracker? // 멀리건이 직전 샷을 무르면 미션 진행도 함께 되돌린다
    var missionsCleared = 0 // 이번 라운드
    var missionsDone = 0 // 끝난 홀 수 (성공 + 실패)
    var rival: [Int] = [] // 라이벌의 홀별 타수 (라운드 시작에 봇이 미리 돈다)
    var rivalSkill = 1.0
    var won = 0, lost = 0, tied = 0 // 홀별 승부
    var cardShown = false // 라운드 종료 카드가 떠 있다 — 하단 띠를 숨긴다
}

extension GameScene {
    // ── 라운드·홀 시작 ──

    /// 새 라운드: 날씨 → 바람 반영 코스 → 미션 편성 → 라이벌 선행 플레이. 연습장은 전부 끈다
    func beginRoundExtras(seed: UInt32, course: inout [Hole]) {
        extras = RoundExtras()
        extras.weather = demo.weather ?? Weather.pick(seed: seed)
        course = course.map { $0.withWind(extras.weather.wind(base: $0.wind)) }
        extras.missionPlan = MissionKind.plan(course: course, seed: seed)
        extras.rivalSkill = Rival.skill(forOverPar: Records.shared.rivalTargetOverPar)
        extras.rival = Rival.playRound(course, seed: seed, weather: extras.weather, skill: extras.rivalSkill)
        PlayLog.note(String(
            format: "ROUND seed %u weather %@ rival-skill %.1f rival %@",
            seed, extras.weather.rawValue, extras.rivalSkill, extras.rival.map(String.init).joined(separator: ",")
        ))
    }

    /// 홀 시작: 이 홀의 미션을 걸고 인트로를 띄운다
    func beginHoleExtras() {
        let kind = demo.mission ?? extras.missionPlan[holeIdx]
        extras.mission = MissionTracker(kind: kind, par: hole.par)
        extras.preShotMission = nil
        PlayLog.note("MISSION \(kind.rawValue) start · rival \(extras.rival[holeIdx])")
        updateRoundStrip()
    }

    /// 홀 인트로 — 티 꽂기 의식 동안 화면 가운데에 홀 이름·미션·라이벌 목표를 한 번 보여 준다. 1번 홀은 날씨 안내가 첫 줄
    func showHoleIntro() {
        var lines: [String] = []
        if holeIdx == 0 || demo.active, let cue = extras.weather.cue {
            lines.append(cue)
        }
        if let m = extras.mission {
            lines.append(L("미션 · ", "Mission · ") + m.kind.title(par: m.par))
        }
        lines.append(rivalTargetLine)
        let name = hole.signature.map { " · \($0.displayName)" } ?? ""
        toast(
            L("\(holeIdx + 1)번 홀 · 파 \(hole.par)", "Hole \(holeIdx + 1) · Par \(hole.par)") + name,
            sub: lines.joined(separator: "\n"), titleScale: 0.72, hold: 2.2
        )
    }

    // ── 미션 ──

    /// 미션 상태가 방금 바뀌었으면 HUD를 갱신하고, 성공이면 알린다. 반환: 방금 성공했는가
    @discardableResult
    private func missionChanged(from before: MissionTracker.State?) -> Bool {
        guard let m = extras.mission, m.state != before, m.state != .active else { return false }
        PlayLog.note("MISSION \(m.kind.rawValue) \(m.state.rawValue) strokes \(strokes)")
        extras.missionsDone += 1
        updateRoundStrip()
        guard m.state == .cleared else { return false }
        extras.missionsCleared += 1
        SoundKit.shared.chime()
        missionLabel.removeAllActions() // 성공한 줄이 한 번 커졌다 돌아온다 — 시선이 공에 있어도 하단 띠가 움직여 보인다
        missionLabel.run(.sequence([.scale(to: 1.35, duration: 0.14), .scale(to: 1, duration: 0.5)]))
        recordMissionCleared()
        return true
    }

    /// 발사 순간 (launchBall — 타수 증가 전). 멀리건용 스냅샷도 여기서
    func missionShot(lie: Surface) {
        extras.preShotMission = extras.mission
        let before = extras.mission?.state
        extras.mission?.shot(
            club: club, shape: club.isPutter ? .standard : shotShape, lie: lie,
            remain: abs(hole.holeX - ball.x), fromX: ball.x
        )
        missionChanged(from: before)
    }

    /// 공 정지 — 방금 성공했으면 true (호출측이 다른 토스트와 겹치지 않을 때 알린다)
    func missionRest() -> Bool {
        let before = extras.mission?.state
        extras.mission?.rest(surface: hole.surface(at: ball.x), strokes: strokes, x: ball.x, holeX: hole.holeX)
        return missionChanged(from: before)
    }

    func missionWater() {
        let before = extras.mission?.state
        extras.mission?.water(strokes: strokes)
        missionChanged(from: before)
    }

    /// 홀아웃·기권으로 미션을 마감하고 결과 한마디를 돌려준다 (이미 정해졌으면 그 결과)
    func missionFinish(gaveUp: Bool) -> String? {
        let before = extras.mission?.state
        if gaveUp {
            extras.mission?.gaveUp()
        } else {
            extras.mission?.holed(strokes: strokes)
        }
        missionChanged(from: before)
        switch extras.mission?.state {
        case .cleared: return L("미션 성공", "Mission cleared")
        case .failed: return L("미션 실패", "Mission failed")
        default: return nil
        }
    }

    /// 멀리건: 직전 샷이 없던 일이 되면 그 샷이 만든 미션 판정도 되돌린다 (성공 카운트 포함)
    func missionUndoLastShot() {
        guard let snap = extras.preShotMission, let now = extras.mission, snap != now else { return }
        if now.state != .active, snap.state == .active {
            extras.missionsDone -= 1
            if now.state == .cleared {
                extras.missionsCleared -= 1
                recordMissionCleared(undo: true)
            }
        }
        extras.mission = snap
        updateRoundStrip()
    }

    /// 미션 성공 토스트 (샷 직후, 다른 연출이 화면을 쓰지 않을 때)
    func toastMissionCleared() {
        guard let m = extras.mission else { return }
        toast(L("미션 성공", "Mission cleared"), sub: m.kind.title(par: m.par), titleScale: 0.9)
    }

    /// 기록: 누적 성공 수 + 선바이저 해금 (실플레이 전용)
    private func recordMissionCleared(undo: Bool = false) {
        guard !demo.active else { return }
        var r = Records.shared
        r.missionsCleared = max(0, r.missionsCleared + (undo ? -1 : 1))
        Records.shared = r
        r.save()
        if !undo, r.missionsCleared == Hat.visorMissions {
            pendingNotices.append((
                L("선바이저 해금", "Sun visor unlocked"),
                L("미션 \(Hat.visorMissions)개 성공 — ⛳️ 메뉴 → 모자", "\(Hat.visorMissions) missions cleared — ⛳️ menu → Hat")
            ))
            if Records.shared.hat == .none { // 첫 해금은 자동 착용 (배지 해금과 같은 규칙)
                Records.shared.hat = .visor
                Records.shared.save()
                stickman.setHat(.visor)
            }
        }
    }

    // ── 라이벌 ──

    /// "라이벌 · 이 홀 버디(3타)"
    var rivalTargetLine: String {
        let s = extras.rival[holeIdx]
        let name = s >= Phys.maxStrokes ? L("기권", "gave up") : scoreName(strokes: s, par: hole.par)
        return L("라이벌 · 이 홀 \(name)(\(s)타)", "Rival · \(name) here (\(s))")
    }

    /// 홀 승부 판정 — 홀아웃·기권 때 한 번. 반환: 토스트에 붙일 한마디
    func settleRivalHole(gaveUp: Bool) -> String {
        let mine = gaveUp ? Phys.maxStrokes : strokes
        let theirs = extras.rival[holeIdx]
        let word: String
        if mine < theirs {
            extras.won += 1
            word = L("승", "won")
        } else if mine > theirs {
            extras.lost += 1
            word = L("패", "lost")
        } else {
            extras.tied += 1
            word = L("비김", "halved")
        }
        PlayLog
            .note(
                "RIVAL hole \(holeIdx + 1) me \(mine) rival \(theirs) \(mine < theirs ? "W" : mine > theirs ? "L" : "T")"
            )
        if !demo.active {
            var r = Records.shared
            r.rivalWon += mine < theirs ? 1 : 0
            r.rivalLost += mine > theirs ? 1 : 0
            r.rivalTied += mine == theirs ? 1 : 0
            Records.shared = r
            r.save()
        }
        updateRoundStrip()
        return L("라이벌 \(theirs)타 — \(word)", "Rival \(theirs) — \(word)")
    }

    /// "2승 1패 1무"
    var rivalTally: String {
        L("\(extras.won)승 \(extras.lost)패", "\(extras.won)W \(extras.lost)L")
            + (extras.tied > 0 ? L(" \(extras.tied)무", " \(extras.tied)T") : "")
    }

    /// 라운드 종료 한 줄: "라이벌에 2홀 차 승 · 미션 4/9"
    var roundExtrasSummary: String {
        let d = extras.won - extras.lost
        let match = d > 0 ? L("라이벌에 \(d)홀 차 승", "Beat the rival by \(d)")
            : d < 0 ? L("라이벌에 \(-d)홀 차 패", "Lost to the rival by \(-d)")
            : L("라이벌과 비김", "Tied with the rival")
        return match + " · " + L(
            "미션 \(extras.missionsCleared)/\(results.count)",
            "Missions \(extras.missionsCleared)/\(results.count)"
        )
    }

    // ── HUD 하단 띠 가운데: 미션 한 줄 + 라이벌 한 줄 ──

    func updateRoundStrip() {
        roundStrip.isHidden = inPractice || extras.cardShown
        guard !roundStrip.isHidden, holeIdx < extras.rival.count else { return }
        if let m = extras.mission {
            let head = switch m.state {
            case .active: L("미션", "Mission")
            case .cleared: L("미션 성공", "Mission cleared")
            case .failed: L("미션 실패", "Mission failed")
            }
            missionLabel.setText(head + " · " + m.kind.title(par: m.par))
            missionLabel.alpha = m.state == .failed ? 0.45 : 1
        }
        let played = extras.won + extras.lost + extras.tied
        rivalLabel.setText(rivalTargetLine + (played > 0 ? " · " + rivalTally : ""))
    }

    // ── 날씨 그림: 지면 위 띠에만 — 화면 위쪽(사용자 데스크탑)은 건드리지 않는다 ──

    static let weatherBand: ClosedRange<CGFloat> = 55 ... 120 // 빗줄기가 시작하는 높이 (지면 위 px)

    /// 지형이 다시 그려질 때마다 (홀 시작·화면 크기 변화) 날씨 노드를 새로 깐다
    func rebuildWeatherFX() {
        weatherNode.removeAllChildren()
        guard !inPractice, !demo.motionShowcase else { return }
        switch extras.weather {
        case .clear:
            return
        case .rain:
            let count = min(80, Int(size.width / 32))
            let lean = CGFloat(max(-5, min(5, hole.wind * 0.9))) // 바람에 기운다
            for _ in 0 ..< count {
                let drop = SKShapeNode()
                let p = CGMutablePath()
                p.move(to: .zero)
                p.addLine(to: CGPoint(x: -lean, y: 9))
                drop.path = p
                drop.strokeColor = NSColor(white: 1, alpha: 0.6)
                drop.lineWidth = 1.1
                drop.lineCap = .round
                drop.alpha = 0
                let splash = SKShapeNode() // 물방울이 닿은 자리의 작은 'ㅅ' — 줄기마다 하나를 돌려 쓴다 (런타임 노드 생성 0)
                let s = CGMutablePath()
                s.move(to: CGPoint(x: -3, y: 2.5))
                s.addLine(to: CGPoint(x: 0, y: 0))
                s.addLine(to: CGPoint(x: 3, y: 2.5))
                splash.path = s
                splash.strokeColor = NSColor(white: 1, alpha: 0.7)
                splash.lineWidth = 1
                splash.lineCap = .round
                splash.alpha = 0
                weatherNode.addChild(drop)
                weatherNode.addChild(splash)
                drop.run(.sequence([
                    .wait(forDuration: Double.random(in: 0 ... 0.8)),
                    .run { [weak self, weak drop, weak splash] in
                        guard let self, let drop, let splash else { return }
                        rainLoop(drop, splash: splash, lean: lean)
                    },
                ]))
            }
        case .gale:
            let count = max(6, min(18, Int(size.width / 150)))
            for _ in 0 ..< count {
                let streak = SKShapeNode()
                streak.strokeColor = NSColor(white: 1, alpha: 0.5)
                streak.lineWidth = 1
                streak.lineCap = .round
                streak.alpha = 0
                weatherNode.addChild(streak)
                streak.run(.sequence([
                    .wait(forDuration: Double.random(in: 0 ... 1.6)),
                    .run { [weak self, weak streak] in
                        guard let self, let streak else { return }
                        galeLoop(streak)
                    },
                ]))
            }
        }
    }

    /// 빗줄기 하나: 임의 자리의 지면 위에서 떨어져 지면에 닿고, 같은 노드로 다음 자리에서 반복
    private func rainLoop(_ drop: SKShapeNode, splash: SKShapeNode, lean: CGFloat) {
        let x = CGFloat.random(in: 4 ... max(5, size.width - 4))
        let gy = groundY(Double(x / pxPerM))
        let top = gy + CGFloat.random(in: Self.weatherBand)
        let dur = Double(top - gy) / 330
        drop.position = CGPoint(x: x - lean * (top - gy) / 9, y: top)
        drop.alpha = 0
        drop.run(.sequence([
            .group([
                .move(to: CGPoint(x: x, y: gy + 1), duration: dur),
                .sequence([.fadeAlpha(to: 0.75, duration: dur * 0.35), .wait(forDuration: dur * 0.65)]),
            ]),
            .run { [weak self, weak drop, weak splash] in
                guard let self, let drop, let splash, drop.parent != nil else { return }
                splash.removeAllActions()
                splash.position = CGPoint(x: x, y: gy + 1)
                splash.alpha = 0.8
                splash.setScale(0.5)
                splash.run(.group([.scale(to: 1.3, duration: 0.2), .fadeOut(withDuration: 0.2)]))
                rainLoop(drop, splash: splash, lean: lean)
            },
        ]))
    }

    /// 바람 줄기 하나: 지면 위 띠에서 바람 방향으로 짧게 흐르다 사라진다
    private func galeLoop(_ streak: SKShapeNode) {
        let sgn: CGFloat = hole.wind < 0 ? -1 : 1
        let len = CGFloat.random(in: 16 ... 34)
        let p = CGMutablePath()
        p.move(to: .zero)
        p.addQuadCurve(to: CGPoint(x: sgn * len, y: 0), control: CGPoint(x: sgn * len * 0.5, y: 2.2))
        streak.path = p
        let x = CGFloat.random(in: 20 ... max(21, size.width - 20))
        let y = groundY(Double(x / pxPerM)) + CGFloat.random(in: 26 ... Self.weatherBand.upperBound)
        streak.position = CGPoint(x: x, y: y)
        streak.alpha = 0
        let travel = sgn * CGFloat.random(in: 110 ... 180)
        let dur = Double.random(in: 0.7 ... 1.1)
        streak.run(.sequence([
            .group([
                .moveBy(x: travel, y: 0, duration: dur),
                .sequence([
                    .fadeAlpha(to: 0.7, duration: dur * 0.3),
                    .wait(forDuration: dur * 0.3),
                    .fadeOut(withDuration: dur * 0.4),
                ]),
            ]),
            .wait(forDuration: Double.random(in: 0.3 ... 1.4)),
            .run { [weak self, weak streak] in
                guard let self, let streak, streak.parent != nil else { return }
                galeLoop(streak)
            },
        ]))
    }

    // ── 알림 대기열 (C7 배지 알림 타이밍) ──

    /// 대기 중인 알림을 하나씩 — 다음 홀 조준이 시작된 뒤(홀 인트로가 걷힌 다음)에 띄운다.
    /// 구 방식은 홀아웃 2.2초 뒤 화면 가운데 2초였는데 다음 홀 전환(1.7초 뒤)과 겹쳐 놓쳤다 (2026-09-29 판정 "배지 토스트 못 느낌" —
    /// 기록엔 3종이 수여돼 있었다). 라운드 끝(스코어카드)에서는 카드 위쪽에 띄운다
    func flushNotices(after delay: Double, aboveCard: Bool = false) {
        guard !pendingNotices.isEmpty else { return }
        let notices = pendingNotices
        pendingNotices = []
        var t = delay
        for n in notices {
            afterNotice(t) { [weak self] in
                guard let self else { return }
                toast(n.title, sub: n.sub, titleScale: 1.0, hold: 2.6, y: aboveCard ? size.height * 0.5 + 190 : nil)
                SoundKit.shared.chime()
                if demo.active {
                    print("NOTICE \(n.title) / \(n.sub)")
                    fflush(stdout)
                }
            }
            t += 3.4
        }
    }

    /// 알림 타이머는 전용 노드에 건다 — 새 라운드(R)가 지우지 않는다(이미 얻은 배지 알림은 라운드를 넘어서도 보여야 한다)
    private func afterNotice(_ delay: Double, _ block: @escaping () -> Void) {
        let timer = SKNode()
        addChild(timer)
        timer.run(.sequence([.wait(forDuration: delay), .run(block), .removeFromParent()]))
    }
}
