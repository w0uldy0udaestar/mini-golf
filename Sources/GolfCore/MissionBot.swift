import Foundation

/// 미션 가능성 판정용 봇 (2026-10-05, M6). "N타 안에 그린 올리기" 미션을 걸기 전에 오차 없는 봇이 그 홀·그 날씨를 실제로 쳐 본다.
/// 원래는 고스트 라이벌(같은 코스를 미리 도는 보이지 않는 상대, 홀별 승부)의 봇이었다 — 라이벌은 첫 실플레이 판정
/// "갑자기 라이벌은 뭐여"로 같은 날 삭제했고(사람다운 오차 모델·실력 표·기록 포함), 미션이 쓰던 오차 없는 정책만 남겼다.
///
/// 정책은 코스 밸런스 봇(Tests/GolfCoreTests/CourseBalanceProbe — 표고 인지 버전)과 같은 결이다. 밸런스 프로브는 회귀 기준선이라
/// 건드리지 않고 정책을 여기 따로 둔다(프로브가 바뀌면 지난 실측 표와 비교가 끊긴다). 난수를 쓰지 않는다 — 같은 (홀, 날씨)면 같은 결과
enum MissionBot {
    /// 나무 캐노피가 샷 방향에 드리우는 정도 0~1 — GameScene.treePunchT와 같은 식 (자동 펀치)
    static func treeT(_ hole: Hole, x: Double, dir: Double) -> Double {
        var t = 0.0
        for ob in hole.obstacles where ob.kind == .tree {
            let ahead = (ob.x - x) * dir
            if ahead > -ob.size, ahead < ob.size + 14 {
                t = max(t, 1 - max(0, ahead - ob.size) / 14)
            }
        }
        return t
    }

    /// 봇이 레귤레이션(파−2타) 안에 그린에 올리는가 — "N타 안에 그린 올리기" 미션을 걸 수 있는 홀의 판정.
    /// 봇이 해냈으면 가능하다는 증명이고, 못 했으면 불가능의 증명은 아니지만 미션은 걸지 않는다(긴 오르막·맞바람 홀)
    static func reachesGreenInRegulation(_ hole: Hole, weather: Weather) -> Bool {
        simulate(hole, weather: weather).onGreenAt.map { $0 <= hole.par - 2 } ?? false
    }

    /// 봇 한 홀 (상한 Phys.maxStrokes). onGreenAt: 공이 처음 그린에 멈춘(또는 그대로 들어간) 시점의 타수(벌타 포함)
    static func simulate(_ hole: Hole, weather: Weather) -> (strokes: Int, onGreenAt: Int?) {
        var b = BallState(x: hole.teeX, y: hole.ground(at: hole.teeX))
        var strokes = 0
        var onGreenAt: Int?
        var lastMoved = 999.0 // 직전 샷 이동 거리 — 벽에 막혀 제자리면 웨지로 탈출
        let minR = Phys.minPowerRatio
        let clubs = ClubTable.all
        func club(_ id: String) -> Club {
            clubs.first { $0.id == id } ?? clubs[0]
        }
        while strokes < Phys.maxStrokes {
            let dir = hole.holeX >= b.x ? 1.0 : -1.0
            let remain = abs(hole.holeX - b.x)
            let dz = hole.ground(at: hole.holeX) - hole.ground(at: b.x)
            let lie = strokes == 0 ? Surface.tee : hole.surface(at: b.x)
            var pick: Club
            var h: Double
            if lie == .green || (remain < 25 && (lie == .apron || lie == .fairway || lie == .tee)) {
                pick = clubs[clubs.count - 1] // 퍼터 (그린 밖 25m 안쪽은 텍사스 웨지)
                let roll = Surface.green.roll * weather.rollScale
                let v = sqrt(2 * roll * remain * 1.08 + 2 * Phys.g * 0.85 * max(0, dz) * 1.2) + 0.3
                h = min(1, max(0.02, (v / pick.power - Phys.putterMinRatio) / (1 - Phys.putterMinRatio)))
            } else if lie == .bunker {
                pick = club("SW")
                h = 1
            } else if lastMoved < 3, treeT(hole, x: b.x, dir: dir) >= 0.25 {
                pick = club("4I") // 캐노피 밑 — 롱아이언 펀치로 낮게
                h = 1
            } else if lastMoved < 3 {
                pick = club("PW") // 벽에 막혔다 — 피칭으로 넘긴다
                h = 1
            } else {
                let target = max(20, remain + dz) // 표고차는 1m ≈ 1m로 읽는다
                let full = clubs.filter { !$0.isPutter && (lie == .tee || $0.id != "DR") }
                    .map { ($0, CourseStrategy.total(of: $0.id) * (lie == .rough ? 0.8 : 1)) }
                if let c = full.filter({ $0.1 >= target }).min(by: { $0.1 < $1.1 }) {
                    pick = c.0
                    let ratio = sqrt(target / c.1) // 토탈 ∝ v0² 근사
                    h = min(1, max(0.02, (ratio - minR) / (1 - minR)))
                } else {
                    pick = full[0].0 // 가장 긴 클럽 풀샷
                    h = 1
                }
            }
            let slope = pick.isPutter ? 0 : hole.slope(at: b.x) * Phys.stanceSlopeRatio
            let punch = pick.isPutter ? 0 : treeT(hole, x: b.x, dir: dir) * 0.85
            let fromX = b.x
            Ballistics.launch(
                &b, club: pick, heightPct: h, lie: lie, dir: dir, punch: punch, slope: slope,
                roughLie: lie == .rough ? hole.roughLie(at: b.x) : .normal
            )
            strokes += 1
            var t = 0.0
            var ended = false
            var wet = false
            while !ended, t < 60 {
                switch Ballistics.step(&b, hole: hole, weather: weather) {
                case .holed:
                    return (strokes, onGreenAt ?? strokes)
                case .water:
                    strokes += 1
                    let dropX = hole.waterDropX(from: b.x)
                    b = BallState(x: dropX, y: hole.ground(at: dropX))
                    ended = true
                    wet = true
                default:
                    ended = b.phase == .rest
                }
                t += Phys.dt
            }
            if !ended { // 60초 비종결 가드
                b.phase = .rest
                b.vx = 0
                b.vy = 0
            }
            if onGreenAt == nil, !wet, hole.surface(at: b.x) == .green {
                onGreenAt = strokes
            }
            // 입수로 같은 둑에 되돌아온 것은 "벽에 막힘"이 아니다 — 0m로 읽으면 풀 PW가 발동해 같은 물에 다시 빠지고, 그린 앞뒤가
            // 물인 홀에서 12타까지 반복했다(리뷰 실측: seed 1 8번 홀 `PW 162→162(W)` × 9). 드롭 뒤에는 보통 정책으로 다시 고른다
            lastMoved = wet ? 999 : abs(b.x - fromX)
        }
        return (Phys.maxStrokes, onGreenAt)
    }
}
