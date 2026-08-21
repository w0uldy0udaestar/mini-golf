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
    case bumperBank // 창 범퍼 뱅크샷 홀인
    case century // 누적 100홀
    case memeWitness // 밈 쇼피스 10회 목격
    case marathoner // 라운드 10회 완주

    var title: String {
        switch self {
        case .firstRound: "첫 라운드"
        case .firstBirdie: "첫 버디"
        case .firstEagle: "이글"
        case .holeInOne: "홀인원"
        case .underPar: "언더파 라운드"
        case .dryRound: "무입수 라운드"
        case .canyonTamer: "협곡 정복"
        case .summiteer: "등정가"
        case .bumperBank: "창문 뱅크샷"
        case .century: "100홀 달성"
        case .memeWitness: "밈 목격자 ×10"
        case .marathoner: "10라운드 마라톤"
        }
    }
}

/// 스틱맨 모자 — 배지 개수로 해금
enum Hat: String, CaseIterable, Codable {
    case none, straw, propeller, top, crown

    var need: Int { // 필요 배지 수
        switch self {
        case .none: 0
        case .straw: 2
        case .propeller: 5
        case .top: 8
        case .crown: 11
        }
    }

    var title: String {
        switch self {
        case .none: "맨머리"
        case .straw: "밀짚모자"
        case .propeller: "프로펠러캡"
        case .top: "실크햇"
        case .crown: "왕관"
        }
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
    var bumperHits = 0
    var showpiecesSeen = 0
    var badges: Set<Badge> = []
    var hat: Hat = .none

    private static let key = "records"

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

    var unlockedHats: [Hat] {
        Hat.allCases.filter { $0.need <= badges.count }
    }

    /// 기록 카드 본문 (메뉴 → 기록)
    var summaryLines: [String] {
        var lines = [
            "라운드 \(roundsCompleted) · 홀 \(holesPlayed) · 총 \(totalStrokes)타",
            bestRound.map { "베스트 라운드 \($0 > 0 ? "+\($0)" : $0 == 0 ? "이븐 파" : "\($0)")" }
                ?? "베스트 라운드 —",
            "홀인원 \(holeInOnes) · 이글 \(eagles) · 버디 \(birdies)",
            "창 범퍼 \(bumperHits)회 · 입수 \(waterBalls)회 · 밈 목격 \(showpiecesSeen)회",
            "",
            "배지 \(badges.count)/\(Badge.allCases.count)",
        ]
        let earned = Badge.allCases.filter { badges.contains($0) }.map(\.title)
        if !earned.isEmpty {
            lines.append(earned.joined(separator: " · "))
        }
        if let next = Hat.allCases.first(where: { $0.need > badges.count }) {
            lines.append("다음 해금: \(next.title) (배지 \(next.need)개)")
        }
        return lines
    }
}
