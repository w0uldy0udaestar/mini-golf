/// 클럽 카테고리 — 스윙 폭·볼 위치·피니시 연출 구분에도 쓰인다
public enum ClubCategory: String, Sendable {
    case wood, iron, wedge, putter
}

/// 클럽 데이터. loft: 발사각(도), spin: 백스핀(rpm), power: 최대 볼스피드(m/s)
/// UI에는 수치를 노출하지 않는다 (조준 어시스트 배제 — 골프의 매력 보존)
public struct Club: Sendable, Equatable {
    public let id: String
    public let name: String
    public let cat: ClubCategory
    public let loft: Double
    public let spin: Double
    public let power: Double

    public var isPutter: Bool {
        cat == .putter
    }
}

public enum ClubTable {
    public static let all: [Club] = [
        Club(id: "DR", name: "드라이버", cat: .wood, loft: 10.5, spin: 2700, power: 75),
        Club(id: "3W", name: "3번 우드", cat: .wood, loft: 15, spin: 3600, power: 70),
        Club(id: "5W", name: "5번 우드", cat: .wood, loft: 18, spin: 4300, power: 66),
        Club(id: "3I", name: "3번 아이언", cat: .iron, loft: 21, spin: 4600, power: 62),
        Club(id: "4I", name: "4번 아이언", cat: .iron, loft: 24, spin: 5000, power: 59),
        Club(id: "5I", name: "5번 아이언", cat: .iron, loft: 27, spin: 5400, power: 56),
        Club(id: "6I", name: "6번 아이언", cat: .iron, loft: 30, spin: 6100, power: 53),
        Club(id: "7I", name: "7번 아이언", cat: .iron, loft: 34, spin: 7000, power: 50),
        Club(id: "8I", name: "8번 아이언", cat: .iron, loft: 38, spin: 7900, power: 47),
        Club(id: "9I", name: "9번 아이언", cat: .iron, loft: 42, spin: 8500, power: 44),
        Club(id: "PW", name: "피칭 웨지", cat: .wedge, loft: 46, spin: 9300, power: 41),
        Club(id: "SW", name: "샌드 웨지", cat: .wedge, loft: 56, spin: 10500, power: 35),
        Club(id: "PT", name: "퍼터", cat: .putter, loft: 0, spin: 0, power: 13),
    ]
}
