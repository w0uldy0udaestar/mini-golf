import Foundation
import GolfCore

// ═══════════════════════════════════════════════════════════════
// 기록·도전과제·해금 (2026-08-21 재미 확장 2번)
// 누적 통계 + 배지 + 배지 개수로 해금되는 스틱맨 모자 — 라운드가 쌓이는 이유를 만든다.
// 저장: UserDefaults JSON 한 키 (시크릿·PII 없음, 실패해도 게임은 그대로 돈다)
// ═══════════════════════════════════════════════════════════════

enum Badge: String, CaseIterable, Codable {
    case firstRound // 첫 라운드 완주
    case firstBirdie
    case firstEagle
    case holeInOne
    case underPar // 언더파 라운드
    case dryRound // 워터 벌타 없는 라운드
    case canyonTamer // 대협곡 홀 파 이하
    case summiteer // 산정 그린 홀 파 이하
    case century // 누적 100홀
    case memeWitness // 밈 쇼피스 10회 목격
    case marathoner // 라운드 10회 완주
    case valleyWalker // 계곡 홀 파 이하 (2026-09-29 잔손질 2라운드 — 새 아키타입 4종)
    case ridgeRunner // 능선
    case cascadeDiver // 폭포
    case forestRanger // 숲

    var title: String {
        switch self {
        case .firstRound: L("첫 라운드", "First round")
        case .firstBirdie: L("첫 버디", "First birdie")
        case .firstEagle: L("이글", "Eagle")
        case .holeInOne: L("홀인원", "Hole in one")
        case .underPar: L("언더파 라운드", "Under-par round")
        case .dryRound: L("무입수 라운드", "Dry round")
        case .canyonTamer: L("협곡 정복", "Canyon tamer")
        case .summiteer: L("등정가", "Summiteer")
        case .century: L("100홀 달성", "100 holes")
        case .memeWitness: L("밈 목격자 ×10", "Meme witness ×10")
        case .marathoner: L("10라운드 마라톤", "10-round marathon")
        case .valleyWalker: L("계곡 정복", "Valley walker")
        case .ridgeRunner: L("능선 정복", "Ridge runner")
        case .cascadeDiver: L("폭포 정복", "Cascade diver")
        case .forestRanger: L("숲 정복", "Forest ranger")
        }
    }
}

/// 스틱맨 모자 — 배지 개수로 해금. 선바이저만 미션 성공 수로 (2026-10-05 M6 홀 미션의 보상)
enum Hat: String, CaseIterable, Codable {
    case none, visor, straw, propeller, top, crown // 메뉴 순서. 선바이저를 앞에 — 배지 모자 자동 착용이 `unlockedHats.last`를 본다

    static let visorMissions = 3 // 한두 라운드 안에 닿는 수 — 미션의 보상이 일찍 보여야 한다

    var need: Int { // 필요 배지 수 (선바이저는 배지와 무관 — `unlocked(in:)`)
        switch self {
        case .none, .visor: 0
        case .straw: 2
        case .propeller: 6 // 배지 11 → 15종 (2026-09-29) — 간격 재배분, 왕관은 전부 모아야
        case .top: 10
        case .crown: Badge.allCases.count // 전부 모아야 (리뷰 F9)
        }
    }

    func unlocked(in r: Records) -> Bool {
        self == .visor ? r.missionsCleared >= Self.visorMissions : need <= r.badges.count
    }

    /// 잠긴 모자의 해금 조건 한마디
    var lockHint: String {
        self == .visor ? L("미션 \(Self.visorMissions)개", "\(Self.visorMissions) missions") : L(
            "배지 \(need)개",
            "\(need) badges"
        )
    }

    var title: String {
        switch self {
        case .none: L("맨머리", "No hat")
        case .visor: L("선바이저", "Sun visor")
        case .straw: L("밀짚모자", "Straw hat")
        case .propeller: L("프로펠러캡", "Propeller cap")
        case .top: L("실크햇", "Top hat")
        case .crown: L("왕관", "Crown")
        }
    }

    /// 옛 버전이 읽을 수 있는 값 — 0.8.9 이하는 모르는 모자 이름 하나에 기록 전체 디코딩이 실패한다(그 상태로 저장하면 기록이 초기화).
    /// 새 모자는 `hatV2` 키에 따로 쓰고, 옛 `hat` 키에는 이 값을 쓴다
    var legacy: Hat {
        self == .visor ? .none : self
    }
}

struct Records: Codable {
    var roundsCompleted = 0
    var holesPlayed = 0
    var totalStrokes = 0
    var bestRound: Int? // ±파 (완주 라운드만)
    var holeInOnes = 0
    var eagles = 0
    var birdies = 0
    var waterBalls = 0
    var showpiecesSeen = 0
    var badges: Set<Badge> = []
    var hat: Hat = .none
    // ── M6 (2026-10-05): 미션·라이벌. 전부 없는 키는 기본값이라 옛 기록과 호환 ──
    var missionsCleared = 0
    var rivalWon = 0, rivalLost = 0, rivalTied = 0 // 홀별 승부 누적
    var totalPar = 0 // 홀아웃한 홀의 파 합 — 평균 실력(파 대비) 계산용. 옛 기록은 홀당 4로 추정해 채운다
    var recentOver: [Int] = [] // 최근 홀아웃의 타수−파 (최대 27홀) — 라이벌 실력이 지금 실력을 따라온다

    private static let key = "records"

    enum CodingKeys: String, CodingKey {
        case roundsCompleted, holesPlayed, totalStrokes, bestRound, holeInOnes, eagles, birdies, waterBalls
        case showpiecesSeen, badges, hat, hatV2, missionsCleared, rivalWon, rivalLost, rivalTied, totalPar, recentOver
    }

    init() {}

    /// 저장본 복원 — 없는 키는 기본값, 사라진 배지 이름은 건너뛴다 (창 범퍼 제거 2026-09-28: 옛 `bumperBank`·`bumperHits`가
    /// 남은 기록을 통째로 잃지 않게. 기본 디코딩은 모르는 enum 값 하나에 전체 실패한다)
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        roundsCompleted = try c.decodeIfPresent(Int.self, forKey: .roundsCompleted) ?? 0
        holesPlayed = try c.decodeIfPresent(Int.self, forKey: .holesPlayed) ?? 0
        totalStrokes = try c.decodeIfPresent(Int.self, forKey: .totalStrokes) ?? 0
        bestRound = try c.decodeIfPresent(Int.self, forKey: .bestRound)
        holeInOnes = try c.decodeIfPresent(Int.self, forKey: .holeInOnes) ?? 0
        eagles = try c.decodeIfPresent(Int.self, forKey: .eagles) ?? 0
        birdies = try c.decodeIfPresent(Int.self, forKey: .birdies) ?? 0
        waterBalls = try c.decodeIfPresent(Int.self, forKey: .waterBalls) ?? 0
        showpiecesSeen = try c.decodeIfPresent(Int.self, forKey: .showpiecesSeen) ?? 0
        let names = try c.decodeIfPresent([String].self, forKey: .badges) ?? []
        badges = Set(names.compactMap(Badge.init(rawValue:)))
        // 모자도 이름으로 관대하게 — 새 키가 있으면 그쪽이 진짜 (legacy 주석 참고)
        let hatName = try c.decodeIfPresent(String.self, forKey: .hatV2) ?? c.decodeIfPresent(String.self, forKey: .hat)
        hat = hatName.flatMap(Hat.init(rawValue:)) ?? .none
        missionsCleared = try c.decodeIfPresent(Int.self, forKey: .missionsCleared) ?? 0
        rivalWon = try c.decodeIfPresent(Int.self, forKey: .rivalWon) ?? 0
        rivalLost = try c.decodeIfPresent(Int.self, forKey: .rivalLost) ?? 0
        rivalTied = try c.decodeIfPresent(Int.self, forKey: .rivalTied) ?? 0
        totalPar = try c.decodeIfPresent(Int.self, forKey: .totalPar) ?? holesPlayed * 4 // 9홀 파 36 = 홀당 4
        recentOver = try c.decodeIfPresent([Int].self, forKey: .recentOver) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(roundsCompleted, forKey: .roundsCompleted)
        try c.encode(holesPlayed, forKey: .holesPlayed)
        try c.encode(totalStrokes, forKey: .totalStrokes)
        try c.encodeIfPresent(bestRound, forKey: .bestRound)
        try c.encode(holeInOnes, forKey: .holeInOnes)
        try c.encode(eagles, forKey: .eagles)
        try c.encode(birdies, forKey: .birdies)
        try c.encode(waterBalls, forKey: .waterBalls)
        try c.encode(showpiecesSeen, forKey: .showpiecesSeen)
        try c.encode(badges, forKey: .badges)
        try c.encode(hat.legacy, forKey: .hat)
        try c.encode(hat.rawValue, forKey: .hatV2)
        try c.encode(missionsCleared, forKey: .missionsCleared)
        try c.encode(rivalWon, forKey: .rivalWon)
        try c.encode(rivalLost, forKey: .rivalLost)
        try c.encode(rivalTied, forKey: .rivalTied)
        try c.encode(totalPar, forKey: .totalPar)
        try c.encode(recentOver, forKey: .recentOver)
    }

    /// 홀아웃 한 번을 실력 통계에 반영
    mutating func noteHoleOut(strokes: Int, par: Int) {
        totalPar += par
        recentOver.append(strokes - par)
        if recentOver.count > 27 {
            recentOver.removeFirst(recentOver.count - 27)
        }
    }

    /// 기권(12타 초과)한 홀도 최근 실력에 넣는다 — 빼면 못 치는 플레이어일수록 평균이 좋아 보여 라이벌이 강해진다 (리뷰).
    /// 한 홀이 평균을 삼키지 않게 +4로 친다. 누적 통계(홀·타수)는 홀아웃한 홀만 세던 그대로
    mutating func noteGiveUp() {
        recentOver.append(4)
        if recentOver.count > 27 {
            recentOver.removeFirst(recentOver.count - 27)
        }
    }

    /// 라이벌의 목표 실력 (홀당 평균 파 대비): 내 최근 실력보다 0.15타 못 치는 상대 — 반쯤 이기고 가끔 진다.
    /// 최근 9홀 이상이면 최근 평균, 아니면 누적 평균, 그것도 9홀 미만(처음)이면 보기 플레이어(+0.9)
    var rivalTargetOverPar: Double {
        let mine: Double
        if recentOver.count >= 9 {
            mine = Double(recentOver.reduce(0, +)) / Double(recentOver.count)
        } else if holesPlayed >= 9 {
            mine = Double(totalStrokes - totalPar) / Double(holesPlayed)
        } else {
            return 0.9
        }
        return min(1.8, max(-0.1, mine + 0.15))
    }

    static var shared: Records = {
        guard let data = UserDefaults.standard.data(forKey: key),
              let r = try? JSONDecoder().decode(Records.self, from: data)
        else { return Records() }
        return r
    }()

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Records.key)
        }
    }

    /// 배지 부여 — 새로 얻었을 때만 true (호출측이 토스트 연출)
    @discardableResult
    mutating func award(_ badge: Badge) -> Bool {
        guard !badges.contains(badge) else { return false }
        badges.insert(badge)
        save()
        return true
    }

    var unlockedHats: [Hat] { // 쓰고 있는 모자는 유지 — 해금 기준이 오르면(배지 11 → 15) 이미 얻은 왕관이 '잠김'이 되던 회귀 (리뷰 F3)
        Hat.allCases.filter { $0.unlocked(in: self) || $0 == hat }
    }

    /// 기록 카드 본문 (메뉴 → 기록)
    var summaryLines: [String] {
        var lines = [
            L(
                "라운드 \(roundsCompleted) · 홀 \(holesPlayed) · 총 \(totalStrokes)타",
                "Rounds \(roundsCompleted) · Holes \(holesPlayed) · \(totalStrokes) strokes"
            ),
            bestRound.map { b in
                let s = b > 0 ? "+\(b)" : b == 0 ? L("이븐 파", "even par") : "\(b)"
                return L("베스트 라운드 \(s)", "Best round \(s)")
            } ?? L("베스트 라운드 —", "Best round —"),
            L(
                "홀인원 \(holeInOnes) · 이글 \(eagles) · 버디 \(birdies)",
                "Holes in one \(holeInOnes) · Eagles \(eagles) · Birdies \(birdies)"
            ),
            L(
                "입수 \(waterBalls)회 · 밈 목격 \(showpiecesSeen)회",
                "Water balls \(waterBalls) · Memes seen \(showpiecesSeen)"
            ),
            L("미션 성공 \(missionsCleared)회", "Missions cleared \(missionsCleared)")
                + " · " + L(
                    "라이벌 상대 \(rivalWon)승 \(rivalLost)패 \(rivalTied)무",
                    "vs rival \(rivalWon)W \(rivalLost)L \(rivalTied)T"
                ),
            "",
            L("배지 \(badges.count)/\(Badge.allCases.count)", "Badges \(badges.count)/\(Badge.allCases.count)"),
        ]
        let earned = Badge.allCases.filter { badges.contains($0) }.map(\.title)
        if !earned.isEmpty {
            lines.append(earned.joined(separator: " · "))
        }
        if let next = Hat.allCases.first(where: { !$0.unlocked(in: self) }) {
            lines.append(L("다음 해금: \(next.title) (\(next.lockHint))", "Next unlock: \(next.title) (\(next.lockHint))"))
        }
        return lines
    }
}
