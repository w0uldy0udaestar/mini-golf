import Foundation

/// 고스트 라이벌 (2026-10-05, M6 라운드 변주). 화면에 그리지 않는 상대 — 라운드 시작 때 같은 코스·같은 날씨를 봇이 미리 돌고,
/// 홀마다 그 타수가 HUD에 목표로 뜬다(홀별 승부). 두 번째 스틱맨을 그리는 '라이벌' 원안(리그 파이프라인 분리 필요)의 가벼운 판.
///
/// 정책은 코스 밸런스 봇(Tests/GolfCoreTests/CourseBalanceProbe — 표고 인지 버전)과 같은 결이고, 사람다운 오차를 얹는다:
/// 거리 오판(클럽 선택)·파워 오차·미스힛·퍼팅 거리감. `skill`이 오차 배율이라 클수록 못 친다 — 앱이 플레이어의 누적 평균에 맞춰 고른다.
/// 밸런스 프로브는 회귀 기준선이라 건드리지 않고 정책을 여기 따로 둔다(프로브가 바뀌면 지난 실측 표와 비교가 끊긴다).
/// 결정론적: 같은 (홀, 시드, 날씨, skill)이면 같은 타수 — 라운드 도중 값이 바뀌지 않는다
public enum Rival {
    /// 오차 배율 → 9홀 평균 파 대비(홀당) 실측표 (맑음, 시드 1~200 × 9홀, 2026-10-05 — 입수 반복 수정·타수 하한 반영 뒤 재측정).
    /// 앱이 목표 실력에서 배율을 역산한다. 60시드로 재면 ±0.12까지 흔들려 "0.15타 못 치는 상대"라는 설계 여유와 같은 크기였다 — 200시드로.
    /// 비는 +0.2~0.4, 강풍은 +0.1~0.4 더 친다(봇은 바람을 읽지 않는다 — 사람도 궂은 날엔 더 친다). 11을 넘기면 비에서 기권이 3%를
    /// 넘어 상한으로 둔다. 갱신: `swift test --filter RivalProbe`의 RIVALCAL(60시드 감시용) — 표를 고칠 땐 측정 시드를 200으로 늘려 잰다
    public static let calibration: [(skill: Double, overPar: Double)] = [
        (0.0, -0.19), (1.0, -0.05), (2.0, 0.22), (3.0, 0.44), (4.5, 0.70), (6.0, 0.93), (8.0, 1.30), (11.0, 1.79),
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

    /// 한 홀 타수 (상한 Phys.maxStrokes = 기권). 하한은 `floor(par:)` — 유령의 홀인원은 내지 않는다
    public static func play(_ hole: Hole, seed: UInt32, weather: Weather = .clear, skill: Double = 1) -> Int {
        max(floor(par: hole.par), simulate(hole, seed: seed, weather: weather, skill: skill).strokes)
    }

    /// 라이벌 타수의 하한: 파3 2타(버디)·파4 2타·파5 3타(이글). 컵 캡처가 넉넉하고 봇이 핀을 정조준해 파3 홀인원이 5~13%
    /// 나왔다(리뷰 실측 — 보기 플레이어 상대가 라운드 다섯에 한 번 홀인원). 화면에 보이지 않는 상대의 홀인원은 "이 홀은 못 이긴다"만 남긴다
    static func floor(par: Int) -> Int {
        max(2, par - 2)
    }

    /// 오차 없는 봇(skill 0)이 레귤레이션(파−2타) 안에 그린에 올리는가 — "N타 안에 그린 올리기" 미션을 걸 수 있는 홀의 판정.
    /// 봇이 해냈으면 가능하다는 증명이고, 못 했으면 불가능의 증명은 아니지만 미션은 걸지 않는다(긴 오르막·맞바람 홀)
    static func reachesGreenInRegulation(_ hole: Hole, weather: Weather) -> Bool {
        simulate(hole, seed: 1, weather: weather, skill: 0).onGreenAt.map { $0 <= hole.par - 2 } ?? false
    }

    /// 봇 한 홀. onGreenAt: 공이 처음 그린에 멈춘(또는 그대로 들어간) 시점의 타수(벌타 포함)
    static func simulate(
        _ hole: Hole,
        seed: UInt32,
        weather: Weather,
        skill: Double
    ) -> (strokes: Int, onGreenAt: Int?) {
        var rand = SeededRandom(seed: seed)
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
