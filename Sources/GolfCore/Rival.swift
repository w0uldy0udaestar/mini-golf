import Foundation

/// 고스트 라이벌 (2026-10-05, M6 라운드 변주). 화면에 그리지 않는 상대 — 라운드 시작 때 같은 코스·같은 날씨를 봇이 미리 돌고,
/// 홀마다 그 타수가 HUD에 목표로 뜬다(홀별 승부). 두 번째 스틱맨을 그리는 '라이벌' 원안(리그 파이프라인 분리 필요)의 가벼운 판.
///
/// 정책은 코스 밸런스 봇(Tests/GolfCoreTests/CourseBalanceProbe — 표고 인지 버전)과 같은 결이고, 사람다운 오차를 얹는다:
/// 거리 오판(클럽 선택)·파워 오차·미스힛·퍼팅 거리감. `skill`이 오차 배율이라 클수록 못 친다 — 앱이 플레이어의 누적 평균에 맞춰 고른다.
/// 밸런스 프로브는 회귀 기준선이라 건드리지 않고 정책을 여기 따로 둔다(프로브가 바뀌면 지난 실측 표와 비교가 끊긴다).
/// 결정론적: 같은 (홀, 시드, 날씨, skill)이면 같은 타수 — 라운드 도중 값이 바뀌지 않는다
public enum Rival {
    /// 오차 배율 → 9홀 평균 파 대비(홀당) 실측표 (Tests/GolfCoreTests/RivalProbe, 60시드×9홀, 맑음, 2026-10-05). 앱이 목표 실력에서
    /// 배율을 역산한다. 비는 +0.1~0.3, 강풍은 +0.1~0.4 더 친다(봇은 바람을 읽지 않는다 — 사람도 궂은 날엔 더 친다). 11을 넘기면
    /// 기권이 3%를 넘어 상한으로 둔다
    public static let calibration: [(skill: Double, overPar: Double)] = [
        (0.0, -0.11), (1.0, -0.01), (2.0, 0.22), (3.0, 0.44), (4.5, 0.70), (6.0, 0.97), (8.0, 1.34), (11.0, 1.82),
    ]

    /// 목표 파 대비(홀당 평균) → 오차 배율. 표 밖은 양 끝으로 클램프
    public static func skill(forOverPar target: Double) -> Double {
        let t = min(max(target, calibration[0].overPar), calibration[calibration.count - 1].overPar)
        for i in 1 ..< calibration.count {
            let a = calibration[i - 1], b = calibration[i]
            if t <= b.overPar {
                return a.skill + (b.skill - a.skill) * (t - a.overPar) / max(1e-9, b.overPar - a.overPar)
            }
        }
        return calibration[calibration.count - 1].skill
    }

    /// 9홀 타수. 홀마다 시드를 갈라 쓴다 — 한 홀의 난수 소비량이 다음 홀 결과를 바꾸지 않게
    public static func playRound(
        _ course: [Hole],
        seed: UInt32,
        weather: Weather = .clear,
        skill: Double = 1
    ) -> [Int] {
        course.enumerated().map { i, hole in
            play(hole, seed: seed &+ UInt32(i + 1) &* 2_654_435_761, weather: weather, skill: skill)
        }
    }

    /// 정규분포 근사 (uniform 3개 평균 — GameScene.launchBall의 미스힛과 같은 식), 대략 [-1, 1]·σ ≈ 0.33
    private static func gauss(_ r: inout SeededRandom) -> Double {
        (r.next(-1, 1) + r.next(-1, 1) + r.next(-1, 1)) / 3
    }

    /// 나무 캐노피가 샷 방향에 드리우는 정도 0~1 — GameScene.treePunchT와 같은 식 (자동 펀치)
    private static func treeT(_ hole: Hole, x: Double, dir: Double) -> Double {
        var t = 0.0
        for ob in hole.obstacles where ob.kind == .tree {
            let ahead = (ob.x - x) * dir
            if ahead > -ob.size, ahead < ob.size + 14 {
                t = max(t, 1 - max(0, ahead - ob.size) / 14)
            }
        }
        return t
    }

    /// 한 홀 타수 (상한 Phys.maxStrokes = 기권)
    public static func play(_ hole: Hole, seed: UInt32, weather: Weather = .clear, skill: Double = 1) -> Int {
        var rand = SeededRandom(seed: seed)
        var b = BallState(x: hole.teeX, y: hole.ground(at: hole.teeX))
        var strokes = 0
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
                let felt = v * (1 + 0.10 * skill * gauss(&rand)) // 퍼팅 거리감
                h = min(1, max(0.02, (felt / pick.power - Phys.putterMinRatio) / (1 - Phys.putterMinRatio)))
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
                let judged = (remain + dz) * (1 + 0.06 * skill * gauss(&rand)) // 거리 오판 (표고차는 1m ≈ 1m로 읽는다)
                let target = max(20, judged)
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
            if !pick.isPutter {
                h = min(1, max(0.02, h + 0.04 * skill * gauss(&rand))) // 파워 오차
            }
            // 미스힛: 플레이어와 같은 풀파워 리스크 식에 실력 배율
            let overdrive = max(0, (h - 0.8) / 0.2)
            let mishit = pick.isPutter ? 0 : max(-1, min(1, (0.25 + 0.75 * pow(overdrive, 1.6)) * skill * gauss(&rand)))
            let slope = pick.isPutter ? 0 : hole.slope(at: b.x) * Phys.stanceSlopeRatio
            let punch = pick.isPutter ? 0 : treeT(hole, x: b.x, dir: dir) * 0.85
            let fromX = b.x
            Ballistics.launch(
                &b, club: pick, heightPct: h, lie: lie, dir: dir, mishit: mishit, punch: punch, slope: slope,
                roughLie: lie == .rough ? hole.roughLie(at: b.x) : .normal
            )
            strokes += 1
            var t = 0.0
            var ended = false
            while !ended, t < 60 {
                switch Ballistics.step(&b, hole: hole, weather: weather) {
                case .holed:
                    return strokes
                case .water:
                    strokes += 1
                    let dropX = hole.waterDropX(from: b.x)
                    b = BallState(x: dropX, y: hole.ground(at: dropX))
                    ended = true
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
            lastMoved = abs(b.x - fromX)
        }
        return Phys.maxStrokes
    }
}
