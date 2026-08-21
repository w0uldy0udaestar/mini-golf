import Foundation

/// 지면 밴드: [from, to) 구간의 라이
public struct Segment: Sendable, Equatable {
    public let from: Double
    public let to: Double
    public let type: Surface

    public init(from: Double, to: Double, type: Surface) {
        self.from = from
        self.to = to
        self.type = type
    }
}

/// 코스 위 장애물 — 나무(트렁크+캐노피)·바위 (2026-08-15 사용자 요청 4번)
public struct Obstacle: Sendable, Equatable {
    public enum Kind: Sendable {
        case tree, rock
    }

    public let kind: Kind
    public let x: Double
    public let size: Double // 나무: 캐노피 반지름(m) · 바위: 반지름(m)

    public init(kind: Kind, x: Double, size: Double) {
        self.kind = kind
        self.x = x
        self.size = size
    }

    /// 트렁크 높이(m) — 캐노피 밑 공간이 펀치샷 창이 된다
    public var trunkHeight: Double {
        kind == .tree ? size * 1.15 : 0
    }

    /// 캐노피 중심 높이 (지면 기준)
    public func canopyCenterY(above groundY: Double) -> Double {
        groundY + trunkHeight + size * 0.75
    }

    /// 바위 중심 높이 — 일부가 땅에 묻혀 둔덕처럼 솟는다
    public func rockCenterY(above groundY: Double) -> Double {
        groundY + size * 0.3
    }
}

/// 홀 하나 — 세그먼트(라이 밴드)와 1m 간격 지형 표고 샘플을 가진다
/// 시그니처 홀 아키타입 (2026-08-20 사용자 요청): 화면 세로 전체를 쓰는 다이나믹 지형.
/// 설계 원칙 — 공이 '설 수 있는' 평탄한 트레드(페어웨이)와 가파른 라이저(러프)의 계단 조합.
/// 지속 급경사면은 굴림 물리상 공이 정지 불가(마찰 < 중력 성분)라 계단이 유일한 정답.
public enum SignatureKind: String, Sendable, CaseIterable {
    case skyTee // 절벽 위 티 — 대낙차 드롭 티샷
    case summitGreen // 산정 그린 — 벤치 계단을 밟고 오르는 등정
    case canyon // 대협곡 — 중원의 깊은 골 (바닥에 워터 60%)
    case terraces // 계단 대지 — 내려가는 거대 테라스 3~4단
}

public struct Hole: Sendable {
    public let par: Int
    public let dist: Double
    public let holeX: Double
    public let teeX: Double // 티 위치 — 미러 홀은 오른쪽 끝에서 시작한다
    public let worldW: Double
    public let greenStart: Double
    public let greenEnd: Double
    public let apronStart: Double
    public let segments: [Segment]
    public let elevation: [Double] // 1m 간격 표고 샘플
    public let waterRange: ClosedRange<Double>?
    public let greenSlope: Double // 그린 브레이크 (경사율)
    public let obstacles: [Obstacle]
    public let signature: SignatureKind? // 시그니처 홀이면 아키타입
    public let wind: Double // 바람 (m/s, +x 방향 절대 좌표 — 비행 항력·양력의 상대속도 기준)

    public init(
        par: Int, dist: Double, holeX: Double, worldW: Double,
        greenStart: Double, greenEnd: Double, apronStart: Double,
        segments: [Segment], elevation: [Double],
        waterRange: ClosedRange<Double>?, greenSlope: Double,
        teeX: Double = CourseGenerator.teeX,
        obstacles: [Obstacle] = [],
        signature: SignatureKind? = nil,
        wind: Double = 0
    ) {
        self.par = par
        self.dist = dist
        self.holeX = holeX
        self.teeX = teeX
        self.worldW = worldW
        self.greenStart = greenStart
        self.greenEnd = greenEnd
        self.apronStart = apronStart
        self.segments = segments
        self.elevation = elevation
        self.waterRange = waterRange
        self.greenSlope = greenSlope
        self.obstacles = obstacles
        self.signature = signature
        self.wind = wind
    }

    public func surface(at x: Double) -> Surface {
        for s in segments where x >= s.from && x < s.to {
            return s.type
        }
        return .rough
    }

    /// 지형 표고 (선형 보간)
    public func ground(at x: Double) -> Double {
        let xi = max(0, min(Double(elevation.count - 2), x))
        let i = Int(xi)
        return elevation[i] + (elevation[i + 1] - elevation[i]) * (xi - Double(i))
    }

    /// 지형 경사 (dz/dx)
    public func slope(at x: Double) -> Double {
        ground(at: x + 0.5) - ground(at: x - 0.5)
    }

    /// 물리 테스트용 평지 홀
    public static func flatTest(worldW: Double = 10000, holeX: Double = 9999, wind: Double = 0) -> Hole {
        Hole(
            par: 4, dist: holeX - CourseGenerator.teeX, holeX: holeX, worldW: worldW,
            greenStart: holeX - 12, greenEnd: holeX + 8, apronStart: holeX - 17,
            segments: [Segment(from: 0, to: worldW, type: .fairway)],
            elevation: [Double](repeating: 0, count: Int(worldW) + 2),
            waterRange: nil, greenSlope: 0,
            wind: wind
        )
    }
}

public enum CourseGenerator {
    public static let teeX: Double = 25 // 백스윙 포즈가 화면 왼쪽에서 잘리지 않는 여유
    static let parComposition = [3, 3, 4, 4, 4, 4, 4, 5, 5] // 파 36
    /// 백 티·화이트 티 중간 실거리 (2026-08-15 사용자 결정 — 드라이버 306m 원온 밸런스 보정:
    /// 파4 대부분은 2온 게임, 짧은 파4만 원온 도전 여지)
    static let distRange: [Int: ClosedRange<Double>] = [3: 130 ... 185, 4: 290 ... 400, 5: 460 ... 560]

    /// 표준 지형: 성격(완만~험준) 롤 + 랜덤 제어점 — 표고 [-10, 15] 클램프
    static func baseElevation(worldW: Double, teeEnd: Double, rand: inout SeededRandom) -> [Double] {
        let ruggedness = rand.next() // 0 = 완만, 1 = 험준
        let stepAmp = 3.0 + 4.0 * ruggedness // 제어점당 표고 변화 (±3~7m)
        let gapLo = 40.0 - 22 * ruggedness // 험준할수록 제어점이 촘촘 (18~40m)
        let gapHi = 55.0 - 27 * ruggedness // (28~55m)
        // 내리막 티샷(40%): 티가 솟은 채 시작 — 드라이브가 시원하게 내려다보인다
        let teeLift = rand.next() < 0.4 ? rand.next(3, 9) : 0
        var nodes: [(x: Double, e: Double)] = [(0, teeLift), (teeEnd + 8, teeLift)]
        var nx = teeEnd + 8.0
        var ne = teeLift
        while nx < worldW {
            nx += rand.next(gapLo, gapHi)
            ne = max(-10, min(15, ne + (rand.next() * 2 - 1) * stepAmp))
            nodes.append((min(nx, worldW), ne))
        }
        return interpolate(nodes: nodes, worldW: worldW)
    }

    /// 제어점 → 1m 표고 샘플 (cos 완충 보간)
    static func interpolate(nodes: [(x: Double, e: Double)], worldW: Double) -> [Double] {
        var elev = [Double](repeating: 0, count: Int(ceil(worldW)) + 2)
        var ni = 0
        for i in 0 ..< elev.count {
            while ni < nodes.count - 2, Double(i) > nodes[ni + 1].x {
                ni += 1
            }
            let a = nodes[ni]
            let b = nodes[min(ni + 1, nodes.count - 1)]
            let u = b.x == a.x ? 0 : min(1, max(0, (Double(i) - a.x) / (b.x - a.x)))
            elev[i] = a.e + (b.e - a.e) * (0.5 - 0.5 * cos(u * .pi))
        }
        return elev
    }

    /// 파·거리에 맞는 시그니처 아키타입 선택 (짧은 파3에 협곡·테라스는 물리적으로 안 들어간다)
    static func pickSignatureKind(par: Int, dist: Double, rand: inout SeededRandom) -> SignatureKind {
        if par == 3 {
            return dist >= 150 && rand.next() < 0.6 ? .skyTee : .summitGreen
        }
        let r = rand.next()
        if par == 4 {
            if r < 0.28 {
                return .skyTee
            }
            if r < 0.58 {
                return .canyon
            }
            if r < 0.80 {
                return .terraces
            }
            return .summitGreen
        }
        if r < 0.30 {
            return .canyon
        }
        if r < 0.58 {
            return .terraces
        }
        if r < 0.85 {
            return .summitGreen
        }
        return .skyTee
    }

    /// ── 시그니처 지형: 트레드(평지) + 라이저(급경사, 최대 ≈0.95) 계단 프로파일 ──
    /// 표고 예산 0.34×worldW — 16:9~21:9 화면 세로에 들어가는 상한
    /// (32:9 초울트라와이드는 상단이 잘릴 수 있음 — 알려진 한계)
    static func signatureElevation(
        kind: SignatureKind, par: Int, worldW: Double, teeEnd: Double, apronStart: Double,
        rand: inout SeededRandom
    ) -> (elev: [Double], water: ClosedRange<Double>?, risers: [ClosedRange<Double>]) {
        let budget = 0.34 * worldW
        let riserRatio = 1.65 // 라이저 폭 = 낙차 × 1.65 → cos 보간 중앙 최대 경사 ≈ 0.95
        var nodes: [(x: Double, e: Double)] = []
        var risers: [ClosedRange<Double>] = []
        var water: ClosedRange<Double>? = nil

        /// 현재 끝에서 rise만큼 오르거나(+) 내리는(−) 라이저를 붙이고 새 x를 반환
        func addRiser(from x: Double, rise: Double) -> Double {
            let w = abs(rise) * riserRatio
            let e0 = nodes.last?.e ?? 0
            nodes.append((x + w, e0 + rise))
            risers.append(x ... (x + w))
            return x + w
        }
        /// 완만한 저지대 굴곡 (트레드 사이·전후 연결) — 마지막 노드까지 최소 16m 간격 유지
        /// (좁은 간격에 진폭이 실리면 라이저가 아닌 곳에 급경사 스파이크가 생긴다)
        func rolls(from x0: Double, to x1: Double, around base: Double, amp: Double) {
            var x = x0
            while true {
                let nx = x + rand.next(28, 44)
                if nx > x1 - 16 {
                    break
                }
                nodes.append((nx, base + (rand.next() * 2 - 1) * amp))
                x = nx
            }
            nodes.append((x1, base))
        }

        switch kind {
        case .skyTee:
            let cliffTop = teeEnd + rand.next(8, 16)
            let room = apronStart - 32 - cliffTop
            let teeH = max(18, min(budget * rand.next(0.82, 0.98), room / 1.9))
            nodes = [(0, teeH), (cliffTop, teeH)]
            var x = cliffTop
            if teeH > 48, room > teeH * 2.2 { // 2단 절벽 — 중간 벤치가 레이업 지점이 된다
                let d1 = teeH * rand.next(0.55, 0.68)
                x = addRiser(from: x, rise: -d1)
                let bench = rand.next(18, 26)
                nodes.append((x + bench, nodes.last!.e))
                x += bench
                x = addRiser(from: x, rise: -(teeH - d1 - rand.next(0, 2)))
            } else {
                x = addRiser(from: x, rise: -(teeH - rand.next(0, 3)))
            }
            rolls(from: x, to: worldW, around: max(0, nodes.last!.e), amp: 2.2)

        case .summitGreen:
            // 오르막 완화 (2026-08-21 실플레이 판정 "올리는 게 불가능"): 라이저 ≤20m —
            // 5I(정점 33m)~웨지까지 널리 넘길 수 있는 높이. 트레드 30~40m — 착지 관대
            let treadW = rand.next(30, 40)
            let climbEnd = apronStart - 8
            // 티샷 낙하 공간 — 파3는 티샷이 곧 어프로치라 짧아도 된다 (상승량 확보 우선)
            let minTeeRun = max(par == 3 ? 35 : 60, (apronStart - teeEnd) * 0.30)
            let available = climbEnd - (teeEnd + minTeeRun)
            var totalRise = min(budget * rand.next(0.80, 0.95), 100)
            func span(_ rise: Double) -> Double {
                rise * riserRatio + Double(max(1, Int(ceil(rise / 20)))) * treadW
            }
            while span(totalRise) > available, totalRise > 18 {
                totalRise *= 0.87
            }
            // 파3 최소 상승 보장 — 티런을 조금 내주더라도 다이나믹은 지킨다
            // (climbStart는 최악에도 teeEnd+8보다 한참 오른쪽 — 기하 검산 2026-08-20)
            totalRise = max(totalRise, 18)
            let n = max(1, Int(ceil(totalRise / 20)))
            let step = totalRise / Double(n)
            var x = climbEnd - span(totalRise)
            nodes = [(0, 0), (teeEnd + 8, 0)]
            rolls(from: teeEnd + 8, to: x, around: 0, amp: 2.2)
            for i in 0 ..< n {
                x = addRiser(from: x, rise: step)
                let tw = treadW
                if i < n - 1 { // 중간 트레드: 접시 모양 — 공이 중앙으로 모인다 (착지 관대)
                    let e = nodes.last!.e
                    nodes.append((x + 3, e + 0.6))
                    nodes.append((x + tw / 2, e))
                    nodes.append((x + tw - 3, e + 0.6))
                }
                x += tw
                nodes.append((x, nodes.last!.e - (i < n - 1 ? 0.6 : 0)))
            }
            let top = nodes.last!.e
            // 정상 그린 뒤 백스톱 언덕 — 오버샷이 튕겨 돌아온다 (관대한 산)
            let backstop = min(6, budget + 1 - top)
            if worldW > climbEnd + 30, backstop > 1.5 {
                nodes.append((climbEnd + 22, top))
                nodes.append((climbEnd + 30, top + backstop))
                nodes.append((worldW, top + backstop * 0.7))
            } else {
                nodes.append((worldW, top)) // 그린은 정상 트레드 위
            }

        case .canyon:
            let midLo = teeEnd + 55
            let midHi = apronStart - 45
            let floorW = rand.next(24, 40)
            let rim = rand.next(0, 3)
            // 탈출 가능 상한: 림 높이·워터 딥(1.2m)까지 합쳐 총 36m — SW 최고 탄도(정점 ≈43m)로
            // 바닥에서 나올 수 있어야 한다 (2026-08-21 오르막 완화: 드라마는 폭으로, 좌절은 제거)
            let depth = max(15, min(
                budget * rand.next(0.72, 0.92),
                36 - rim,
                (midHi - midLo - floorW) / (2 * riserRatio)
            ))
            let gorgeW = floorW + depth * 2 * riserRatio
            let cLo = midLo + gorgeW / 2
            let cHi = midHi - gorgeW / 2
            let cx = cHi > cLo ? rand.next(cLo, cHi) : (midLo + midHi) / 2
            nodes = [(0, rim), (teeEnd + 8, rim)]
            var x = cx - gorgeW / 2
            rolls(from: teeEnd + 8, to: x, around: rim, amp: 2.2)
            x = addRiser(from: x, rise: -depth - rim)
            nodes.append((x + floorW, nodes.last!.e)) // 협곡 바닥 트레드
            if rand.next() < 0.6 { // 바닥의 워터 — 캐리 실패의 대가
                water = (x + 4) ... (x + floorW - 4)
            }
            x += floorW
            x = addRiser(from: x, rise: depth + rim)
            rolls(from: x, to: worldW, around: rim, amp: 2.2)

        case .terraces:
            let n = rand.next() < 0.5 ? 3 : 4
            let spanFrom = teeEnd + rand.next(10, 18)
            let spanTo = apronStart - 22
            var teeH = budget * rand.next(0.75, 0.92)
            while ((spanTo - spanFrom) - teeH * riserRatio) / Double(n) < 16, teeH > 20 {
                teeH *= 0.87 // 트레드 최소폭(16m 착지 가능) 확보까지 축소
            }
            let treadW = max(16, ((spanTo - spanFrom) - teeH * riserRatio) / Double(n))
            let step = teeH / Double(n)
            nodes = [(0, teeH), (spanFrom, teeH)]
            var x = spanFrom
            for _ in 0 ..< n {
                x = addRiser(from: x, rise: -step)
                x += treadW * rand.next(0.85, 1.15)
                nodes.append((x, nodes.last!.e))
            }
            nodes.append((worldW, max(0, nodes.last!.e)))
        }

        var elev = interpolate(nodes: nodes, worldW: worldW)
        for i in 0 ..< elev.count { // 예산 클램프 (+2는 그린 브레이크 여유)
            elev[i] = max(-budget, min(budget + 2, elev[i]))
        }
        return (elev, water, risers)
    }

    /// 세그먼트 배열에서 [from, to) 구간을 지정 타입으로 대체 (겹치는 밴드는 쪼갬)
    static func carve(_ segments: [Segment], from: Double, to: Double, type: Surface) -> [Segment] {
        var out: [Segment] = []
        for s in segments {
            if s.to <= from || s.from >= to {
                out.append(s); continue
            }
            if s.from < from {
                out.append(Segment(from: s.from, to: from, type: s.type))
            }
            if s.to > to {
                out.append(Segment(from: to, to: s.to, type: s.type))
            }
        }
        out.append(Segment(from: from, to: to, type: type))
        return out.sorted { $0.from < $1.from }
    }

    /// 9홀 랜덤 코스 — 화이트 티 실거리, 지형 고저, 그린 브레이크, 벙커, 워터
    public static func makeCourse(seed: UInt32) -> [Hole] {
        var rand = SeededRandom(seed: seed)
        var pars = parComposition
        for i in stride(from: pars.count - 1, through: 1, by: -1) { // 셔플
            let j = Int(rand.next() * Double(i + 1))
            pars.swapAt(i, j)
        }
        // 전 홀 다이나믹 (2026-08-20 사용자 판정 2차: "모든 홀 전부 다이나믹하게") —
        // 평지 브리더 없음. 표준 지형 경로(baseElevation)는 향후 클래식 모드용으로 보존
        // 아키타입 덱: 다 뽑을 때까지 중복 없이 — 한 라운드 안에서 4종이 골고루 나온다
        // (파3는 지형 제약이 있어 덱을 소비하지 않고 자체 규칙으로 뽑는다)
        var deck: [SignatureKind] = []
        func drawKind() -> SignatureKind {
            if deck.isEmpty {
                deck = SignatureKind.allCases
                for i in stride(from: deck.count - 1, through: 1, by: -1) {
                    let j = Int(rand.next() * Double(i + 1))
                    deck.swapAt(i, j)
                }
            }
            return deck.removeLast()
        }
        return pars.map { par in
            let preferred: SignatureKind? = par >= 4 ? drawKind() : nil
            return makeHole(par: par, rand: &rand, signatureRoll: true, preferredKind: preferred)
        }
    }

    static func makeHole(
        par: Int, rand: inout SeededRandom,
        signatureRoll: Bool = false, preferredKind: SignatureKind? = nil
    ) -> Hole {
        let range = distRange[par]!
        let dist = rand.next(range.lowerBound, range.upperBound)
        let holeX = teeX + dist
        let worldW = holeX + 45

        let greenStart = holeX - rand.next(10, 15)
        let greenEnd = holeX + rand.next(7, 11)
        let apronStart = greenStart - rand.next(4, 7)

        // 티~에이프런 사이를 페어웨이/러프 랜덤 밴드로 채움
        let teeEnd = teeX + 10
        var segments = [Segment(from: 0, to: teeEnd, type: .tee)]
        var x = teeEnd
        var cur: Surface = rand.next() < 0.75 ? .fairway : .rough
        while x < apronStart {
            let w = rand.next(30, 85)
            segments.append(Segment(from: x, to: min(x + w, apronStart), type: cur))
            x += w
            cur = cur == .fairway ? .rough : .fairway
        }
        segments.append(Segment(from: apronStart, to: greenStart, type: .apron))
        segments.append(Segment(from: greenStart, to: greenEnd, type: .green))
        segments.append(Segment(from: greenEnd, to: worldW, type: .rough))

        // ── 시그니처 홀: 표준 지형·클램프를 통째로 대체하는 대낙차 계단 프로파일 ──
        // 아키타입: 덱 우선(라운드 내 4종 골고루), 파3는 지형 제약 자체 규칙
        let signature: SignatureKind? = signatureRoll
            ? (preferredKind ?? pickSignatureKind(par: par, dist: dist, rand: &rand))
            : nil
        var sigWater: ClosedRange<Double>? = nil
        var sigRisers: [ClosedRange<Double>] = []

        // ── 지형 고저: 홀마다 성격(완만 링크스 ~ 험준 산악)을 뽑고 형상을 얹는다 ──
        // (2026-08-15 사용자 요청: 더 다이나믹하게 — 기복 폭·제어점 간격·지형 형상 다양화)
        var elev: [Double]
        if let sig = signature {
            (elev, sigWater, sigRisers) = signatureElevation(
                kind: sig, par: par, worldW: worldW, teeEnd: teeEnd, apronStart: apronStart, rand: &rand
            )
            for r in sigRisers { // 라이저(급경사면)는 러프 — 공이 구르다 트레드에 멎는다
                segments = carve(segments, from: r.lowerBound, to: r.upperBound, type: .rough)
            }
        } else {
            elev = baseElevation(worldW: worldW, teeEnd: teeEnd, rand: &rand)
        }
        // 지형 형상 오버레이 (55%): 능선·분지·플래토 하나를 중원에 — 홀마다 뚜렷한 얼굴을 만든다
        let midLo = teeEnd + 30.0
        let midHi = apronStart - 30.0
        if signature == nil, rand.next() < 0.55, midHi > midLo + 40 {
            let cx = rand.next(midLo + 15, midHi - 15)
            let halfW = rand.next(14, 26)
            let kindR = rand.next()
            let amp = rand.next(3.5, 7.0)
            for i in 0 ..< elev.count {
                let d = (Double(i) - cx) / halfW
                if kindR < 0.4 { // 능선 — 종 모양 봉우리: 넘길까, 앞에 끊을까
                    elev[i] += amp * exp(-d * d)
                } else if kindR < 0.75 { // 분지 — 공이 모여드는 움푹한 골
                    elev[i] -= amp * 0.85 * exp(-d * d)
                } else { // 플래토 — 램프로 올라서는 고원 (이후 지대가 한 단 높아진다)
                    let u = min(1, max(0, (Double(i) - (cx - halfW)) / (halfW * 1.2)))
                    elev[i] += amp * 0.8 * (u * u * (3 - 2 * u))
                }
            }
            for i in 0 ..< elev.count { // 오버레이 합산 후 경계 재클램프
                elev[i] = max(-10, min(15, elev[i]))
            }
        }

        // ── 해저드 전략 배치: 클럽 실측 도달 거리를 앵커로 (2026-08-15 사용자 설계) ──
        // 원칙: 티샷 낙하 지대에 리스크를, 티~레이업 지대에는 항상 안전선을 남긴다
        let drTotal = CourseStrategy.total(of: "DR")
        // 낙하 지대 앵커 = 이 홀에서 합리적인 최대 티샷: 드라이버 토탈 ±8%, 단 그린 60m 앞 상한
        // (짧은 홀에선 아무도 드라이버 풀샷을 안 친다 — 실코스 설계도 '치는 클럽' 기준으로 배치)
        let landing = teeX + min(drTotal * (0.92 + 0.16 * rand.next()), dist - 60)

        // 워터: 낙하 지대 직전을 가로지른다 — 풀드라이브는 캐리로 넘기고, 레이업은 그 앞에 선다
        // (시그니처 홀은 아키타입이 직접 배치 — 협곡 바닥 워터)
        var waterRange: ClosedRange<Double>? = nil
        if let sw = sigWater {
            waterRange = sw
            segments = carve(segments, from: sw.lowerBound, to: sw.upperBound, type: .water)
        }
        if signature == nil, par >= 4, rand.next() < 0.35 {
            let wTo = landing - rand.next(15, 25)
            let wFrom = wTo - rand.next(15, 30)
            if wFrom > teeEnd + 35, wTo < apronStart - 25 {
                waterRange = wFrom ... wTo
                segments = carve(segments, from: wFrom, to: wTo, type: .water)
                let wl = min(elev[Int(wFrom)], elev[Int(ceil(wTo))]) - 1.2
                for i in Int(wFrom) ... min(Int(ceil(wTo)), elev.count - 1) {
                    elev[i] = wl
                }
                for k in 1 ... 4 { // 물가 경사 자연스럽게
                    let uu = Double(k) / 5
                    let li = Int(wFrom) - k
                    let ri = Int(ceil(wTo)) + k
                    if li >= 0 {
                        elev[li] = wl * (1 - uu) + elev[li] * uu
                    }
                    if ri < elev.count {
                        elev[ri] = wl * (1 - uu) + elev[ri] * uu
                    }
                }
            }
        }

        /// ── 벙커: 얕은 모래 구덩이. 배치 성공 여부를 돌려줘 전략 배치가 재시도할 수 있게 ──
        @discardableResult
        func addBunker(from bFrom: Double, width: Double) -> Bool {
            let bTo = bFrom + width
            if let wr = waterRange, bFrom < wr.upperBound + 6, bTo > wr.lowerBound - 6 {
                return false
            }
            if bTo >= greenStart - 1 || bFrom <= teeEnd + 5 {
                return false
            }
            // 시그니처 홀: 라이저(급경사면) 위 벙커 금지 — 트레드에만 판다
            // (중앙만 검사하면 폭이 라이저에 '걸친' 벙커가 통과한다 — 양끝+중앙 3점)
            if signature != nil {
                for sx in [bFrom, (bFrom + bTo) / 2, bTo] {
                    let i = max(1, min(elev.count - 2, Int(sx)))
                    if abs(elev[i + 1] - elev[i - 1]) / 2 > 0.15 {
                        return false
                    }
                }
            }
            segments = carve(segments, from: bFrom, to: bTo, type: .bunker)
            let mid = (bFrom + bTo) / 2
            for i in Int(bFrom) ... min(Int(ceil(bTo)), elev.count - 1) {
                let d = 1 - abs(Double(i) - mid) / (width / 2 + 0.5) // 가운데가 깊게
                elev[i] -= max(0, d) * 0.9
            }
            return true
        }
        // 페어웨이 벙커: 드라이버 낙하 지대 그 자체를 지킨다 — 지르면 벙커 리스크, 끊으면 안전.
        // 그린·워터와 겹쳐 기각되면 낙하 지대 앞쪽으로 물러나며 재시도 (짧은 파4 대응)
        if par >= 4, rand.next() < 0.55 {
            let w = rand.next(6, 9)
            var bFrom = landing - rand.next(2, 10)
            for _ in 0 ..< 3 {
                if addBunker(from: bFrom, width: w) {
                    break
                }
                bFrom -= 13
            }
        }
        // 파5: 2온 도전 지점(드라이버+3우드 도달선)에 추가 리스크
        if par == 5, rand.next() < 0.4 {
            let second = teeX + drTotal + CourseStrategy.total(of: "3W") * rand.next(0.8, 0.95)
            addBunker(from: min(second, apronStart - 32), width: rand.next(7, 10))
        }
        // 그린 가드 벙커: 파3는 티샷 정밀도 시험이라 더 자주 (관례)
        if rand.next() < (par == 3 ? 0.65 : 0.6) {
            addBunker(from: greenStart - 4 - rand.next(3, 8), width: rand.next(5, 8))
        }

        // ── 그린: 주변 지형 흐름을 따르는 미세 경사(브레이크) ──
        let gFrom = Int(apronStart - 2)
        let gTo = min(Int(ceil(greenEnd + 6)), elev.count - 1)
        // 솟은 그린(45%) 또는 낮은 그린(25%): 어프로치가 오르막/내려다보기가 된다.
        // 램프 발치에 워터가 있으면 생략 (수면 주변 지형 왜곡 방지 — 리뷰 S-4)
        // 표고 상·하한 대비 여유분으로 lift/drop을 제한해 경계 초과를 구조적으로 차단
        let rampFrom = max(0, gFrom - 45)
        let waterAtRampFoot = waterRange.map { $0.upperBound > Double(rampFrom) - 4 } ?? false
        let greenRoll = rand.next()
        // 시그니처 홀은 생략 — 재클램프(±17)가 고지 그린을 뭉갠다
        if signature == nil, !waterAtRampFoot, greenRoll < 0.7 {
            let elevated = greenRoll < 0.45
            let mag = elevated
                ? min(rand.next(2, 7), 17 - elev[gFrom])
                : min(rand.next(2, 5), elev[gFrom] + 9)
            if mag > 0.5 {
                for i in rampFrom ... gTo where i < elev.count {
                    let u = min(1, Double(i - rampFrom) / Double(max(1, gFrom - rampFrom)))
                    elev[i] += (elevated ? mag : -mag) * (u * u * (3 - 2 * u)) // smoothstep 램프
                }
                // 램프 구간 재클램프 — 분지 오버레이가 어프로치에 걸친 채 낮은 그린이 겹치면
                // gFrom 기준 여유분만으로는 하한을 뚫을 수 있다 (리뷰 S-1). 상한 17은 그린
                // 슬로프 추가분(≤2.4)까지 더해도 테스트 상한 20 안에 남는 값
                for i in rampFrom ... gTo where i < elev.count {
                    elev[i] = max(-10, min(17, elev[i]))
                }
            }
        }
        let trend: Double = elev[gTo] >= elev[gFrom] ? 1 : -1
        let gSlope = trend * rand.next(0.02, 0.06) // 2~6% 브레이크
        let gBase = elev[gFrom]
        for i in gFrom ... gTo {
            // 그린 가드 벙커의 모래 딥은 보존 — 슬로프로 덮어쓰면 벙커가 평지가 된다 (리뷰 S-1)
            let inBunker = segments.contains { $0.type == .bunker && Double(i) >= $0.from && Double(i) < $0.to }
            if !inBunker {
                elev[i] = gBase + gSlope * Double(i - gFrom)
            }
        }
        for k in 1 ... 5 { // 그린 뒤 러프와 자연 연결
            let ri = gTo + k
            if ri < elev.count {
                elev[ri] = elev[gTo] * Double(5 - k) / 5 + elev[ri] * Double(k) / 5
            }
        }

        // ── 장애물: 나무는 어프로치 길목(넘기거나 밑으로 펀치), 바위는 중원 (요청 4번) ──
        var obstacles: [Obstacle] = []
        func hazardFree(_ x: Double, margin: Double) -> Bool {
            !segments.contains { s in
                (s.type == .water || s.type == .bunker || s.type == .green || s.type == .tee)
                    && x >= s.from - margin && x <= s.to + margin
            }
        }
        // 시그니처 홀: 라이저 경사면 위 나무·바위 금지 (허공에 뜬 듯 보인다)
        func gentleGround(_ x: Double) -> Bool {
            guard signature != nil else { return true }
            let i = max(1, min(elev.count - 2, Int(x)))
            return abs(elev[i + 1] - elev[i - 1]) / 2 < 0.25
        }
        if par >= 4, rand.next() < 0.4 {
            let size = rand.next(3.2, 5.0)
            let t = landing + (greenStart - landing) * rand.next(0.3, 0.65)
            // 마진은 캐노피 반지름 연동 — 큰 나무가 해저드 렌더와 겹쳐 보이지 않게 (리뷰 지적)
            if t > teeEnd + 30, t < apronStart - 18, hazardFree(t, margin: size + 1), gentleGround(t) {
                obstacles.append(Obstacle(kind: .tree, x: t, size: size))
            }
        }
        if par == 3, rand.next() < 0.25 {
            let size = rand.next(2.8, 3.8)
            let t = teeX + dist * rand.next(0.45, 0.7)
            if t < apronStart - 15, hazardFree(t, margin: size + 1), gentleGround(t) {
                obstacles.append(Obstacle(kind: .tree, x: t, size: size))
            }
        }
        if rand.next() < 0.3 {
            let rx = teeEnd + 35 + rand.next() * (apronStart - teeEnd - 70)
            if hazardFree(rx, margin: 3), gentleGround(rx) {
                obstacles.append(Obstacle(kind: .rock, x: rx, size: rand.next(1.2, 2.0)))
            }
        }

        // 바람 (2026-08-21 재미 확장 4번): 약풍이 흔하고 강풍은 드묾 — 매 샷의 판단 요소
        let wr = rand.next()
        let wind = (rand.next() < 0.5 ? -1.0 : 1.0) * wr * wr * 7.0
        let hole = Hole(
            par: par, dist: dist, holeX: holeX, worldW: worldW,
            greenStart: greenStart, greenEnd: greenEnd, apronStart: apronStart,
            segments: segments, elevation: elev,
            waterRange: waterRange, greenSlope: gSlope,
            obstacles: obstacles,
            signature: signature,
            wind: wind
        )
        // 진행 방향 좌우 랜덤: 절반은 미러 — 오른쪽 티에서 왼쪽 홀로 (2026-08-14 사용자 요청)
        return rand.next() < 0.5 ? mirrored(hole) : hole
    }

    /// 홀 좌우 미러 — 모든 x를 worldW 기준으로 뒤집는다. 물리·렌더는 방향 무관하게 작성돼 있어
    /// 지형 데이터만 뒤집으면 오른쪽→왼쪽 진행 홀이 된다
    static func mirrored(_ h: Hole) -> Hole {
        let w = h.worldW
        var elev = [Double](repeating: 0, count: h.elevation.count)
        for i in 0 ..< elev.count {
            elev[i] = h.ground(at: w - Double(i)) // 보간 샘플링 — worldW가 정수가 아니어도 안전
        }
        let segments = h.segments
            .map { Segment(from: w - $0.to, to: w - $0.from, type: $0.type) }
            .sorted { $0.from < $1.from }
        return Hole(
            par: h.par, dist: h.dist, holeX: w - h.holeX, worldW: w,
            // 그린 경계는 공간 순서 유지, 에이프런은 미러 후 그린 오른쪽의 바깥 경계
            greenStart: w - h.greenEnd, greenEnd: w - h.greenStart, apronStart: w - h.apronStart,
            segments: segments, elevation: elev,
            waterRange: h.waterRange.map { (w - $0.upperBound) ... (w - $0.lowerBound) },
            greenSlope: -h.greenSlope,
            teeX: w - h.teeX, // 인스턴스 teeX (static 상수 아님 — 리뷰 S-1)
            obstacles: h.obstacles.map { Obstacle(kind: $0.kind, x: w - $0.x, size: $0.size) },
            signature: h.signature,
            wind: h.wind // 바람은 세계 절대 좌표 — 미러와 무관
        )
    }
}
