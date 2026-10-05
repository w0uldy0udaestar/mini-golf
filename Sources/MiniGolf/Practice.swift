import AppKit
import GolfCore
import SpriteKit

// ═══════════════════════════════════════════════════════════════
// 연습장 (2026-10-05, M6 — IDEAS "연습장 모드: 홀 없이 드라이빙 레인지, 클럽별 비거리 표시")
// 실플레이 기록에서 13개 클럽 중 드라이버·샌드웨지·퍼터가 65%였다. 중간 클럽을 안 쓰는 이유가 "얼마나 가는지 몰라서"라면
// 재 볼 자리가 필요하다. 평지 한 줄에서 치면 공이 멈춘 자리에 클럽 표식이 남고, 캐리·총거리가 HUD에 뜬 뒤 공이 티로 돌아온다.
// 거리는 친 **뒤에** 나오는 측정값이라 조준 어시스트(수치 비노출 원칙)와는 다르다. 기록·미션·날씨·서프라이즈는 전부 꺼진다
// ═══════════════════════════════════════════════════════════════

struct PracticeState {
    var carryX: Double? // 이번 샷의 첫 착지 자리
    var last: (club: String, carry: Double?, total: Double)? // 직전 샷
    var best: [String: Double] = [:] // 클럽별 최고 총거리 (이번 연습 동안)
    var marks: [String: Double] = [:] // 클럽별 직전 정지 자리 (m) — 지면 위 표식
    var shots = 0
}

extension GameScene {
    static let rangeMarkName = "rangeMark"

    /// 공이 멈췄다: 거리를 재고 표식을 남긴 뒤 잠깐 보여 주고 티로 되돌린다 (걷지 않는다 — 연습장은 제자리에서 반복)
    func practiceRest() {
        guard var p = practice else { return }
        let id = club.id
        let total = abs(ball.x - hole.teeX)
        let carry = p.carryX.map { abs($0 - hole.teeX) }
        p.last = (id, club.isPutter ? nil : carry, total)
        p.best[id] = max(p.best[id] ?? 0, total)
        p.marks[id] = ball.x
        p.carryX = nil
        p.shots += 1
        practice = p
        PlayLog.note(String(
            format: "RANGE %@ h%.2f%@ carry %.0f total %.0f", id, heightPct,
            club.isPutter || shotShape == .standard ? "" : " \(shotShape.rawValue)", carry ?? 0, total
        ))
        drawRangeMarks()
        // 공 위에 총거리가 잠깐 뜬다 — 시선이 공에 있을 때 바로 읽힌다
        let label = GlassLabel(font: HUDFont.medium, size: 14)
        label.setText("\(Int(total.rounded()))m")
        label.name = Self.surpriseNodeName
        label.zPosition = 8
        label.position = CGPoint(x: min(size.width - 40, max(40, px(ball.x))), y: groundY(ball.x) + 58) // 클럽 표식 글자 위
        label.alpha = 0
        addChild(label)
        label.run(.sequence([
            .fadeIn(withDuration: 0.15), .wait(forDuration: 1.5), .fadeOut(withDuration: 0.4), .removeFromParent(),
        ]))
        mode = .surprise // 정지 분기가 다시 돌지 않게 씬을 잠깐 점유 (공 위치는 그대로 그려진 채)
        endShotTrail()
        updateHUD()
        afterSurprise(1.5) { [weak self] in self?.practiceReset() }
    }

    /// 공을 티로 돌려놓고 다시 조준
    private func practiceReset() {
        guard inPractice else { return }
        strokes = 0 // 연습장은 매번 티샷 (라이 = 티)
        ball = BallState(x: hole.teeX, y: hole.ground(at: hole.teeX))
        ballNode.removeAllActions()
        ballNode.alpha = 0
        ballNode.run(.fadeIn(withDuration: 0.25))
        if demo.active { // 관찰: 클럽을 돌아가며 친다 (표식이 여러 개 찍히게)
            clubIdx = (clubIdx + 3) % (ClubTable.all.count - 1)
        }
        enterAim()
    }

    /// 지형 재그리기 때 연습장 눈금(티에서 50m 간격)과 클럽 표식을 깐다
    func drawRangeScale() {
        guard inPractice else { return }
        let ticks = CGMutablePath()
        var d = 50.0
        let sgn: Double = hole.holeX >= hole.teeX ? 1 : -1
        while hole.teeX + sgn * d < hole.worldW - 6, hole.teeX + sgn * d > 6 {
            let x = hole.teeX + sgn * d
            let gy = groundY(x)
            ticks.move(to: CGPoint(x: px(x), y: gy))
            ticks.addLine(to: CGPoint(x: px(x), y: gy - 7))
            let num = GlassLabel(font: HUDFont.regular, size: 10.5, alpha: 0.6)
            num.setText("\(Int(d))")
            num.position = CGPoint(x: px(x), y: gy - 9)
            terrainNode.addChild(num)
            d += 50
        }
        let node = SKShapeNode(path: ticks)
        node.strokeColor = Palette.hairline.withAlphaComponent(0.7)
        node.lineWidth = 1.4
        node.lineCap = .round
        terrainNode.addChild(node)
        drawRangeMarks()
    }

    /// 클럽 표식: 그 클럽의 직전 샷이 멈춘 자리에 짧은 깃대 + 클럽 약어. 같은 클럽을 다시 치면 옮겨진다
    private func drawRangeMarks() {
        terrainNode.enumerateChildNodes(withName: Self.rangeMarkName) { node, _ in node.removeFromParent() }
        guard let p = practice else { return }
        let lastId = p.last?.club
        for (id, x) in p.marks {
            let mark = SKNode()
            mark.name = Self.rangeMarkName
            let stem = SKShapeNode(rect: CGRect(x: -0.6, y: 0, width: 1.2, height: 13), cornerRadius: 0.6)
            stem.fillColor = NSColor(white: 1, alpha: id == lastId ? 0.9 : 0.5)
            stem.strokeColor = .clear
            mark.addChild(stem)
            let label = GlassLabel(font: HUDFont.medium, size: 10.5, alpha: id == lastId ? 1 : 0.6)
            label.setText(id)
            label.position = CGPoint(x: 0, y: 27)
            mark.addChild(label)
            mark.position = CGPoint(x: px(x), y: groundY(x))
            terrainNode.addChild(mark)
        }
    }

    /// 연습장 HUD 오른쪽 아랫줄: 직전 샷 결과 (없으면 안내)
    var practiceResultLine: String {
        guard let l = practice?.last, let c = ClubTable.all.first(where: { $0.id == l.club }) else {
            return L("클럽을 바꿔 가며 쳐 보세요 · R = 새 라운드", "Try each club · R = new round")
        }
        let carry = l.carry.map { L("캐리 \(Int($0.rounded()))m · ", "carry \(Int($0.rounded())) m · ") } ?? ""
        let best = practice?.best[l.club] ?? l.total
        return "\(c.displayName) · " + carry + L("총 \(Int(l.total.rounded()))m", "total \(Int(l.total.rounded())) m")
            + L(" · 최고 \(Int(best.rounded()))m", " · best \(Int(best.rounded())) m")
    }
}
