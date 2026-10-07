import Foundation

/// 홀 미션 (2026-10-05, M6 라운드 변주). 홀마다 한 줄 목표 하나 — 라운드 시드로 정해진다.
/// 실플레이 기록(09-23~29, 501샷)에서 드라이버·샌드웨지·퍼터가 65%, 샷 종류(Tab)는 7%였다 — 미션은 "스코어를 내라"가 아니라
/// **다른 클럽·다른 샷을 꺼내게** 하는 쪽으로 고른다. 대부분 한두 샷 안에 성패가 갈려 1번 홀에서도 결과가 보인다.
/// 판정은 이벤트(샷·정지·입수·홀아웃)만 받는 순수 상태기계라 화면 없이 테스트한다 (`MissionTracker`)
public enum MissionKind: String, Sendable, CaseIterable {
    case noDriver // 드라이버 없이 파 이하 (파4·5)
    case fairwayTee // 티샷을 페어웨이에 (파4·5)
    case longDrive // 티샷 250m 넘기기 (파4·5, 330m 이상 홀)
    case greenInReg // 파−2타 안에 그린 올리기
    case midIronGreen // 5~8번 아이언으로 그린 올리기
    case shapeShot // 펀치나 로브로 그린 올리기
    case closeApproach // 40m 밖에서 핀 5m 안에 붙이기
    case noBunker // 벙커에 안 빠지고 홀아웃 (벙커 있는 홀)
    case birdie // 버디 이상

    public static let longDriveMeters = 250.0
    public static let closeMeters = 5.0
    public static let approachMinMeters = 40.0
    static let midIrons: Set<String> = ["5I", "6I", "7I", "8I"]

    /// 장타 미션을 걸려면 깨끗한 드라이버 샷이 백스윙 90~100% 구간의 다섯 점 중 **넷 이상**에서 250m를 넘겨야 한다.
    /// 풀샷 한 점만 보면 "100%에선 연못을 넘기고 90%에선 빠지는" 홀이 걸린다(60시드 실측 7건) — 풀파워는 미스힛 위험이 가장 큰
    /// 자리라 사실상 운이 된다. 다섯 다가 아닌 이유: 지형(벙커·단차) 때문에 거리가 파워에 단조롭지 않아 한 점이 주머니에 빠질 수 있다
    static let longDrivePowers = [0.9, 0.925, 0.95, 0.975, 1.0]

    static func longDriveReachable(_ hole: Hole, weather: Weather) -> Bool {
        longDrivePowers.filter { cleanDrive(hole, weather: weather, heightPct: $0) >= longDriveMeters }.count >= 4
    }

    /// 이 홀·이 날씨에 낼 수 있는 미션인가. "깰 수 있는" 미션만 건다 — 파·홀 길이만 보던 첫 판은 장타 미션의 26%(맑음)~43%(강풍)가
    /// 오르막·캐노피·맞바람 때문에 어떤 샷으로도 불가능했다(리뷰 전수 탐색, 2026-10-05). 물리로 갈리는 둘은 그 홀에서 실제로 쳐 보고 정한다
    public func eligible(for hole: Hole, weather: Weather = .clear) -> Bool {
        switch self {
        case .noDriver, .fairwayTee: hole.par >= 4
        case .longDrive:
            hole.par >= 4 && hole.dist >= 330 && Self.longDriveReachable(hole, weather: weather)
        case .greenInReg: MissionBot.reachesGreenInRegulation(hole, weather: weather)
        case .noBunker: hole.gimmick != .dune && hole.segments
            .contains { $0.type == .bunker } // 사구 모래면엔 공이 서지 않아 무조건 성공 (리뷰 F7)
        default: true
        }
    }

    /// 미스힛 없는 드라이버 풀샷이 티에서 멈춘 자리까지의 거리(m). 물·벙커에 빠지면 0(항아리 벙커 바닥에 선 드라이브는 깨끗하지 않다 — 리뷰 F2).
    /// 경사 라이·캐노피 자동 펀치는 게임과 같은 규칙
    static func cleanDrive(_ hole: Hole, weather: Weather, heightPct: Double = 1) -> Double {
        guard let x = driveRest(hole, weather: weather, heightPct: heightPct),
              hole.surface(at: x) != .bunker else { return 0 }
        return abs(x - hole.teeX)
    }

    /// 미스힛 없는 드라이버가 멈춘 자리 x (물에 빠지면 nil). 항아리 벙커 배치 검증(`Hole.potBunkerTrapWorks`)도 같은 샷을 쓴다
    static func driveRest(_ hole: Hole, weather: Weather, heightPct: Double = 1) -> Double? {
        guard let driver = ClubTable.all.first(where: { $0.id == "DR" }) else { return nil }
        let dir: Double = hole.holeX >= hole.teeX ? 1 : -1
        var b = BallState(x: hole.teeX, y: hole.ground(at: hole.teeX))
        Ballistics.launch(
            &b, club: driver, heightPct: heightPct, lie: .tee, dir: dir,
            punch: MissionBot.treeT(hole, x: b.x, dir: dir) * 0.85, slope: hole.slope(at: b.x) * Phys.stanceSlopeRatio
        )
        var t = 0.0
        while b.phase != .rest, t < 60 {
            if Ballistics.step(&b, hole: hole, weather: weather) == .water {
                return nil
            }
            t += Phys.dt
        }
        return b.x
    }

    /// 추첨 가중치 — 버디는 스코어 미션이라 드물게
    var weight: Double {
        self == .birdie ? 0.5 : 1
    }

    /// HUD 한 줄
    public func title(par: Int) -> String {
        switch self {
        case .noDriver: L("드라이버 없이 파 이하", "Par or better without the driver")
        case .fairwayTee: L("티샷을 페어웨이에", "Tee shot on the fairway")
        case .longDrive: L("티샷 \(Int(Self.longDriveMeters))m 넘기기", "Drive it past \(Int(Self.longDriveMeters)) m")
        case .greenInReg:
            par == 3 ? L("한 번에 그린 올리기", "On the green in one")
                : L("\(par - 2)타 안에 그린 올리기", "On the green in \(par - 2)")
        case .midIronGreen: L("5~8번 아이언으로 그린 올리기", "Hit the green with a 5–8 iron")
        case .shapeShot: L("펀치나 로브로 그린 올리기", "Hit the green with a punch or lob")
        case .closeApproach:
            L(
                "\(Int(Self.approachMinMeters))m 밖에서 핀 \(Int(Self.closeMeters))m 안에 붙이기",
                "From \(Int(Self.approachMinMeters)) m+, stop it inside \(Int(Self.closeMeters)) m"
            )
        case .noBunker: L("벙커에 안 빠지고 홀아웃", "Hole out without a bunker")
        case .birdie: L("버디 이상", "Birdie or better")
        }
    }

    /// 9홀 미션 편성 — 홀마다 그 홀의 날씨에서 가능한 것 중 가중 추첨, 바로 앞 홀과 같은 미션은 피한다. 코스 생성 난수와 별도 해시.
    /// weather: 홀별 날씨 (`Weather.plan`) — 모자란 홀은 맑음
    public static func plan(course: [Hole], seed: UInt32, weather: [Weather] = []) -> [MissionKind] {
        var rand = SeededRandom(seed: seed ^ 0x5BD1_E995)
        _ = rand.next()
        var out: [MissionKind] = []
        for (i, hole) in course.enumerated() {
            let w = i < weather.count ? weather[i] : .clear
            var pool = allCases.filter { $0 != out.last && $0.eligible(for: hole, weather: w) }
            if pool.isEmpty { // 도달 불가 — 조건 없는 미션이 넷(아이언·샷 종류·붙이기·버디)이라 직전 것을 빼도 남는다
                pool = [.birdie]
            }
            var r = rand.next() * pool.reduce(0) { $0 + $1.weight }
            var chosen = pool[pool.count - 1]
            for k in pool {
                r -= k.weight
                if r < 0 {
                    chosen = k
                    break
                }
            }
            out.append(chosen)
        }
        return out
    }
}

/// 한 홀의 미션 진행. 호출 순서: 샷마다 `shot` → (정지면 `rest` | 입수면 `water` | 홀인이면 `holed`), 12타 초과 기권은 `gaveUp`.
/// 한 번 성공·실패가 정해지면 뒤 이벤트는 무시한다
public struct MissionTracker: Sendable, Equatable {
    public enum State: String, Sendable { case active, cleared, failed }

    public let kind: MissionKind
    public let par: Int
    public private(set) var state = State.active
    /// 직전 샷의 사실들 — 정지·홀인 판정이 읽는다
    private var lastClub = ""
    private var lastShaped = false
    private var lastLie = Surface.tee
    private var lastRemain = 0.0 // 치기 전 핀까지 거리
    private var lastFromX = 0.0
    private var shots = 0 // 친 횟수 (벌타 제외) — 티샷 판정용

    public init(kind: MissionKind, par: Int) {
        self.kind = kind
        self.par = par
    }

    /// 발사 순간. remain: 치기 전 핀까지 거리(m), fromX: 친 자리
    public mutating func shot(club: Club, shape: ShotShape, lie: Surface, remain: Double, fromX: Double) {
        shots += 1
        lastClub = club.id
        lastShaped = !club.isPutter && shape != .standard
        lastLie = lie
        lastRemain = remain
        lastFromX = fromX
        guard state == .active else { return }
        if kind == .noDriver, club.id == "DR" {
            state = .failed
        }
    }

    /// 그린 밖에서 친 샷인가 — 그린·에이프런에서 아이언으로 '퍼팅'해 올리는 꼼수 차단
    private var struckOffGreen: Bool {
        lastLie != .green && lastLie != .apron
    }

    /// 공이 멈췄다 (홀인·입수 제외). strokes: 벌타 포함 현재 타수, x: 멈춘 자리, holeX: 컵
    public mutating func rest(surface: Surface, strokes: Int, x: Double, holeX: Double) {
        guard state == .active else { return }
        switch kind {
        case .fairwayTee:
            if shots == 1 { // 짧은 파4의 원온·에이프런도 '페어웨이를 지켰다'로 친다
                state = surface == .fairway || surface == .apron || surface == .green ? .cleared : .failed
            }
        case .longDrive:
            if shots == 1 { // 항아리 벙커 바닥(250m 안팎)에 빠진 드라이브는 '넘긴' 게 아니다 (리뷰 F2)
                state = abs(x - lastFromX) >= MissionKind.longDriveMeters && surface != .bunker ? .cleared : .failed
            }
        case .greenInReg:
            if surface == .green, strokes <= par - 2 {
                state = .cleared
            } else if strokes >= par - 2 {
                state = .failed
            }
        case .midIronGreen:
            if surface == .green, struckOffGreen, MissionKind.midIrons.contains(lastClub) {
                state = .cleared
            }
        case .shapeShot:
            if surface == .green, struckOffGreen, lastShaped {
                state = .cleared
            }
        case .closeApproach:
            if lastClub != "PT", lastRemain >= MissionKind.approachMinMeters,
               abs(x - holeX) <= MissionKind.closeMeters {
                state = .cleared
            }
        case .noBunker:
            if surface == .bunker {
                state = .failed
            }
        case .noDriver, .birdie:
            break
        }
    }

    /// 입수 (벌타는 호출측). 티샷 미션은 실패, 레귤레이션은 남은 타수로 판정
    public mutating func water(strokes: Int) {
        guard state == .active else { return }
        switch kind {
        case .fairwayTee, .longDrive:
            if shots == 1 {
                state = .failed
            }
        case .greenInReg:
            if strokes >= par - 2 {
                state = .failed
            }
        default:
            break
        }
    }

    /// 홀아웃. 아직 정해지지 않은 미션은 여기서 갈린다 — 그린에 '올리기' 미션은 그 샷이 그대로 들어가도 성공
    public mutating func holed(strokes: Int) {
        guard state == .active else { return }
        switch kind {
        case .noDriver: state = strokes <= par ? .cleared : .failed
        case .birdie: state = strokes < par ? .cleared : .failed
        case .noBunker: state = .cleared
        case .fairwayTee, .longDrive: state = shots == 1 ? .cleared : .failed // 홀인원
        case .greenInReg: state = strokes <= par - 2 ? .cleared : .failed
        case .midIronGreen: state = struckOffGreen && MissionKind.midIrons.contains(lastClub) ? .cleared : .failed
        case .shapeShot: state = struckOffGreen && lastShaped ? .cleared : .failed
        case .closeApproach:
            state = lastClub != "PT" && lastRemain >= MissionKind.approachMinMeters ? .cleared : .failed
        }
    }

    /// 12타 초과 기권
    public mutating func gaveUp() {
        if state == .active {
            state = .failed
        }
    }
}
