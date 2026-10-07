import Foundation

/// 장치 그린·지형 장애물 (2026-10-05 M7 1차 화산 → 2026-10-07 2차 지형 장애물). 큰 지형 하나가 그 홀의 과제를 바꾼다 — 미니골프의 문법을
/// 실제 크기 홀에 얹는다. 사용자 판정(2026-10-06): 깔때기 "너무 쉬워질 것 같다" → 편성 제외, 벽 구멍·풍차·대포는 "골프가 아니라 코스 퍼즐" →
/// 장치형 전부 제외, "TGL 리그 코스처럼 **지형이 장애물**". 화산은 "재밌다, 그대로"(10-07).
/// 지금까지 플레이 판정을 통과한 것은 전부 큰 지형(절벽 티·급사면·화산)이고 실패한 것은 전부 미세한 수치였다 — 생김새부터 보여야 한다.
/// 코스 생성기(난수 스트림·불변식·밸런스 표)는 건드리지 않고 완성된 홀에 덧씌운다(`Hole.withGimmick`) — 날씨의 `withWind`와 같은 층
public enum GimmickKind: String, Sendable, CaseIterable {
    case volcano // 화산 — 봉우리 꼭대기 분화구 안에 컵. 분화구에 떨어뜨리면 굴러 들어가고, 빗나가면 비탈을 굴러 내려간다
    case funnel // 깔때기 — 분지 전체가 컵으로 기울어 있다. 분지에만 넣으면 굴러 들어간다 (편성 제외)
    case mesa // 메사 — 평평한 꼭대기 위 그린, 양쪽이 절벽. 올려서 세워야 한다: 짧으면 절벽에 맞고 발치로, 길면 뒤로 굴러 떨어진다. 퍼팅은 남는다
    case dune // 거대 사구 — 그린 앞 큰 모래 언덕. 넘기거나 발치에 끊거나. 앞면에 떨어지면 모래를 타고 발치로 내려온다
    case potBunker // 항아리 벙커 — 깊고 가파른 모래 구덩이. 파4·5는 드라이브 착지 지대(풀 드라이버는 넘기고 덜 친 드라이브는 빠진다), 파3는 그린 앞

    /// 홀 이름 자리에 뜨는 말
    public var displayName: String {
        switch self {
        case .volcano: L("화산", "Volcano")
        case .funnel: L("깔때기", "Punchbowl")
        case .mesa: L("메사", "Mesa")
        case .dune: L("거대 사구", "Giant Dune")
        case .potBunker: L("항아리 벙커", "Pot Bunker")
        }
    }

    /// 홀 시작 안내 한 줄 — 무엇을 해야 하는지
    public var cue: String {
        switch self {
        case .volcano: L("분화구에 떨어뜨리면 컵으로 굴러 들어간다", "Land it in the crater and it rolls into the cup")
        case .funnel: L("분지에만 넣으면 컵으로 굴러 들어간다", "Get it in the bowl and it rolls into the cup")
        case .mesa: L(
                "꼭대기 그린에 올려 세워야 한다 — 짧으면 절벽, 길면 뒤로 떨어진다",
                "Hold the plateau — short hits the cliff, long rolls off the back"
            )
        case .dune: L("그린 앞 모래 언덕을 넘기거나, 발치에 끊고 띄워 넘긴다", "Carry the dune, or lay up at its foot and lob over")
        case .potBunker: L(
                "항아리 벙커에 빠지면 띄워서만 나온다 — 넘기거나 앞에 끊는다",
                "Fall in the pot bunker and only a lofted escape gets out — carry it or lay up"
            )
        }
    }

    /// 컵이 분지 바닥에 있는 장치 — "분지에 들어온 공은 굴러 들어간다"의 물리 규칙 셋(그린 위 정지 금지·바닥 정지 = 홀인·립아웃 뒤 홀인)이 여기에만 걸린다
    public var isBowl: Bool {
        self == .volcano || self == .funnel
    }

    /// 그린 자리를 통째로 바꾸는 장치(컵이 중심). 아니면 그린·에이프런은 그대로 두고 그 앞이나 착지 지대에 서는 장애물
    public var replacesGreen: Bool {
        !(self == .dune || self == .potBunker)
    }

    /// 바닥에서 솟는 장치 (비탈 발치가 있다). 깔때기·항아리는 파인다
    public var isRaised: Bool {
        self == .volcano || self == .mesa || self == .dune
    }

    /// 비탈 발치의 평평한 띠에 서면 샌드웨지 로브가 자동으로 잡히는 장치 — 띄워 올려야 하는 자리
    public var lobsFromFoot: Bool {
        isRaised
    }
}

public extension GimmickKind {
    /// 라운드 편성에 들어가는 장치. 깔때기는 빠져 있다 — 사용자 판정(2026-10-06, 그림 목록을 보고) "너무 홀이 쉬워질 것 같다":
    /// 어프로치의 17%가 자동으로 들어가는 '쉬운 홀'이 본질이라 조여도 성격이 안 바뀐다. 코드는 남긴다(`--gimmick funnel`로 관찰 가능).
    /// 2차(10-07): 메사·거대 사구·항아리 벙커 — 전부 어려워지는 쪽(화산은 퍼팅이 없어 1타쯤 쉬웠다)
    static let inRotation: [GimmickKind] = [.volcano, .mesa, .dune, .potBunker]

    /// 이 홀에 걸 수 있는 장치인가. 깔때기는 파3에 걸지 않는다 — 분지에만 넣으면 들어가는 홀이라 티샷 한 번에 홀인원이 흔해진다
    /// (프로브: 가장 맞는 클럽으로 백스윙 세기의 17%가 들어간다. 화산은 4%)
    func fits(_ hole: Hole) -> Bool {
        !(self == .funnel && hole.par == 3) && hole.withGimmick(self) != nil
    }

    /// 9홀에 장치를 입힌 코스. 라운드의 앞(1·2번)·가운데(4~6번)·뒤(7~9번) 세 토막에 하나씩, 종류는 라운드마다 섞어 겹치지 않게(네 종류 중 셋 —
    /// 같은 장치 세 번이면 질린다). 첫 장치는 1·2번 홀 안에(실플레이 기록상 9홀 완주가 드물어 뒤쪽 홀에만 나오는 것은 못 본 채 끝난다).
    /// 자리가 안 맞으면 다른 종류로, 그래도 안 맞으면 이미 쓴 종류라도 한 번 더. 코스 생성 난수와 별도 해시 — 같은 시드의 지형은 그대로.
    /// forced: 관찰용 — 걸 수 있는 홀 전부에 그 장치 (편성에서 뺀 종류도 볼 수 있다, 깔때기는 여기서도 파3 제외)
    static func dress(course: [Hole], seed: UInt32, forced: GimmickKind? = nil) -> [Hole] {
        if let forced {
            return course.map { forced.fits($0) ? $0.withGimmick(forced) ?? $0 : $0 }
        }
        var rand = SeededRandom(seed: seed ^ 0xC2B2_AE35)
        _ = rand.next()
        var out = course
        let n = course.count
        var groups = [Array(0 ..< min(2, n)), Array(min(3, n) ..< min(6, n)), Array(min(6, n) ..< n)]
        var kinds = inRotation
        for i in stride(from: kinds.count - 1, through: 1, by: -1) { // 종류 순서는 라운드마다 섞는다
            kinds.swapAt(i, Int(rand.next() * Double(i + 1)))
        }
        var used: Set<GimmickKind> = []
        for group in groups where !group.isEmpty {
            var order = group
            for i in stride(from: order.count - 1, through: 1, by: -1) { // 토막 안에서 어느 홀인지는 섞는다
                order.swapAt(i, Int(rand.next() * Double(i + 1)))
            }
            placing: for kind in kinds.filter({ !used.contains($0) }) + kinds.filter({ used.contains($0) }) {
                for i in order where kind.fits(course[i]) {
                    out[i] = course[i].withGimmick(kind) ?? course[i]
                    used.insert(kind)
                    break placing
                }
            }
        }
        return out
    }
}

/// 장치의 치수 (m). 화면 축척이 홀 길이에 반비례하므로(긴 홀일수록 1m가 작게 그려진다) 월드 폭에 비례해 키운다 — 어느 홀에서나 비슷한 크기로 보이게.
/// 값은 `GimmickProbe` 실측으로 정했다 (Tests/GolfCoreTests)
public struct GimmickShape: Sendable, Equatable {
    public var height: Double // 화산·메사·사구: 바닥에서 꼭대기까지 · 깔때기·항아리: 깊이
    public var bowlHalf: Double // 컵으로 기운 면(분화구·분지·구덩이)의 반폭 · 메사: 평평한 꼭대기의 반폭 · 사구: 0 (마루는 꼭짓점)
    public var bowlSlope: Double // 그 면의 경사 — 공이 서지 못하고 바닥까지 굴러야 한다(그린 0.17·페어웨이 0.34보다 가파르게). 메사 꼭대기·사구는 0
    public var greenHalf: Double // 그 가운데 그린으로 까는 반폭 (화산은 분화구 전체, 메사는 꼭대기 전체, 장애물은 0)
    public var coneSlope: Double // 바깥 비탈 경사 (화산 0.8 · 메사 절벽 1.6 · 사구 1.3 · 깔때기·항아리 0)
    public var collar: Double // 티 쪽 평평한 띠 폭
    public var collarFar: Double // 반대쪽 띠 폭 (대칭 장치는 collar와 같다 — 사구·항아리는 그린 쪽을 짧게)
    public var blendMin: Double // 바깥 이음 띠의 최소 길이 (낙차에 비례해 늘어난다). 그린 앞 장애물은 그린과 가깝게 4

    /// 화산 비탈은 경사 0.8 — 뾰족하게 솟고, 빗나간 공이 눈에 보이게 굴러 내려온다(0.55에선 러프 잔디에 붙어 기다가 2.5초 뒤 발치로 옮겨졌다).
    /// 발치 띠는 러프 7m: 굴러 내려온 공(발치에서 8m/s 안팎)이 띠 안에서 선다. 비탈이 짧아져 반대편 발치가 월드 끝에서 26m 이상 —
    /// 화면 끝 릴리프(46px, 폭 1280pt·620m 월드에서 22m)가 공을 비탈 위에 올려놓지 않는다 (리뷰 M-2)
    public static func volcano(worldW: Double) -> GimmickShape {
        let half = min(7, max(4.5, 0.015 * worldW))
        return GimmickShape(
            height: min(9, max(4.5, 0.02 * worldW)), bowlHalf: half, bowlSlope: 0.22, greenHalf: half, coneSlope: 0.8,
            collar: 7, collarFar: 7, blendMin: 8
        )
    }

    /// 깔때기: 가파른 V(경사 0.6)에 벽은 페어웨이 잔디. 그린 잔디(굴림 저항 1.1)·경사 0.3으로 깔면 공이 컵을 지나쳐 반대편 벽을 오르내리는
    /// 시계추가 10초 넘게 갔고(첫 실측: 홀인까지 중앙 11.3초), 분지가 넓어(반폭 12~20m) 60m에서 백스윙 세기의 절반 이상이 들어갔다.
    /// 좁고 깊게 — 화면에서도 V자 골이 또렷하다
    public static func funnel(worldW: Double) -> GimmickShape {
        let depth = min(6, max(4, 0.013 * worldW))
        return GimmickShape(
            height: depth, bowlHalf: depth / 0.6, bowlSlope: 0.6, greenHalf: 2.5, coneSlope: 0, collar: 5, collarFar: 5,
            blendMin: 8
        )
    }

    /// 메사: 화산과 같은 높이의 평평한 꼭대기(그린, 보통 그린 18~28m보다 좁은 14~24m)에 경사 1.6의 절벽. 짧은 공은 절벽에 맞고 되튀어
    /// 발치 띠(러프 7m)에 서고, 긴 공은 뒤 절벽으로 굴러 떨어져 반대편 발치에 선다 — 양쪽 발치에서 샌드웨지 로브로 다시 올린다
    public static func mesa(worldW: Double) -> GimmickShape {
        let half = min(12, max(7, 0.02 * worldW))
        return GimmickShape(
            height: min(9, max(4.5, 0.02 * worldW)), bowlHalf: half, bowlSlope: 0, greenHalf: half, coneSlope: 1.6,
            collar: 7, collarFar: 7, blendMin: 8
        )
    }

    /// 거대 사구: 그린 앞 모래 언덕(양면 모래, 경사 1.3). 모래의 굴림 저항 8.0이 경사 1.0의 중력 성분(8.3)과 맞먹어 공이 면 위에서 0.3m/s²로
    /// 기어 내려와 발치 꼭짓점 0.2m 안에 섰고, 그 자리는 경사 측정(±0.5m)에 모래면이 섞여 스탠스가 −0.3으로 기울어 로브가 수직으로 올라갔다
    /// 돌아왔다(프로브: 한 홀 창 0칸). 1.3이면 2.8m/s²로 눈에 보이게 굴러 내려 발치 띠 2~3m 안쪽에 선다 — 화산이 0.55→0.8로 세운 것과 같은 이유.
    /// 앞면에 떨어진 공은 모래가 튐을 죽여 발치 러프 띠(7m)로 내려오고, 넘긴 공은 뒷면을 타고 그린 쪽으로 간다. 그린 쪽 띠는 페어웨이 3m —
    /// 그 뒤 이음 띠(≥ 4m)가 에이프런 앞에서 끝난다
    public static func dune(worldW: Double) -> GimmickShape {
        GimmickShape(
            height: min(9, max(5, 0.02 * worldW)), bowlHalf: 0, bowlSlope: 0, greenHalf: 0, coneSlope: 1.3,
            collar: 7, collarFar: 3, blendMin: 4
        )
    }

    /// 항아리 벙커: 깊이 4~5.5m의 V자 모래 구덩이(경사 0.5, 폭 16~22m). 어디에 떨어져도 모래 바닥(V 꼭짓점)으로 굴러 내려오고, 거기서는
    /// 샌드웨지(모래 파워 45%)로만 나온다. 양쪽 띠는 페어웨이 2m — 테두리 꼭짓점이 깨끗하게 서게
    public static func potBunker(worldW: Double) -> GimmickShape {
        let depth = min(5.5, max(4, 0.012 * worldW))
        return GimmickShape(
            height: depth, bowlHalf: depth / 0.5, bowlSlope: 0.5, greenHalf: 0, coneSlope: 0, collar: 2, collarFar: 2,
            blendMin: 4
        )
    }

    public static func shape(for kind: GimmickKind, worldW: Double) -> GimmickShape {
        switch kind {
        case .volcano: volcano(worldW: worldW)
        case .funnel: funnel(worldW: worldW)
        case .mesa: mesa(worldW: worldW)
        case .dune: dune(worldW: worldW)
        case .potBunker: potBunker(worldW: worldW)
        }
    }
}

public extension Hole {
    static let gimmickBlend = 8.0 // 바깥 이음 띠 기본 길이 (화산·깔때기·메사) — 장애물은 `GimmickShape.blendMin`

    /// 착지 지대 항아리 벙커: 풀 드라이버 캐리가 반대쪽 테두리를 이만큼 넘긴다. 캐리의 2.5%(250m에서 6m) — 한 칸(4%) 덜 친 드라이브는 캐리가
    /// 20m쯤 짧아 빠진다(6%·15m로 두면 한 칸 덜 쳐도 83%가 넘겨 장애물이 아니었다 — 프로브). 깨끗한 풀 드라이버만 넘긴다
    static func driveClearMargin(carry: Double) -> Double {
        max(6, 0.025 * carry)
    }

    /// 장치의 꺾이는 자리 (x, m). 표고 샘플이 1m 간격이라 테두리·발치를 정수 자리에 맞춘다 — 어긋나면 꼭짓점이 뭉개져
    /// 테두리 안쪽 1.5m의 경사가 0.17(그린에서 공이 설 수 있는 경사)까지 누웠다 (첫 불변식 테스트가 잡았다)
    struct GimmickKnots: Sendable, Equatable {
        public let rim: ClosedRange<Double> // 안쪽 면의 양 끝 (분화구 테두리·분지 가장자리·메사 꼭대기 끝·항아리 테두리) — 사구는 마루 한 점
        public let foot: ClosedRange<Double> // 비탈이 바닥에 닿는 자리 (비탈이 없는 장치는 rim과 같다)
        public let collar: ClosedRange<Double> // 평평한 띠의 바깥 끝
    }

    /// dir: 티가 왼쪽이면 +1 (티 쪽 띠가 `shape.collar`, 반대쪽이 `collarFar`). 대칭 장치는 무관
    static func gimmickKnots(center c: Double, shape: GimmickShape, dir: Double = 1) -> GimmickKnots {
        let rimLo = (c - shape.bowlHalf).rounded(), rimHi = (c + shape.bowlHalf).rounded()
        let coneW = shape.coneSlope > 0 ? (shape.height / shape.coneSlope).rounded() : 0
        let near = shape.collar.rounded(), far = shape.collarFar.rounded()
        let (left, right) = dir > 0 ? (near, far) : (far, near)
        return GimmickKnots(
            rim: rimLo ... rimHi, foot: (rimLo - coneW) ... (rimHi + coneW),
            collar: (rimLo - coneW - left) ... (rimHi + coneW + right)
        )
    }

    /// 장치의 중심 x — 그린을 바꾸는 장치는 컵, 아니면 얹을 때 정한 자리
    var gimmickCenter: Double {
        gimmickX ?? holeX
    }

    var gimmickShape: GimmickShape? {
        gimmick.map { GimmickShape.shape(for: $0, worldW: worldW) }
    }

    /// 이 홀의 장치 꺾이는 자리 (없으면 nil)
    var gimmickKnots: GimmickKnots? {
        gimmickShape.map { Self.gimmickKnots(center: gimmickCenter, shape: $0, dir: holeX >= teeX ? 1 : -1) }
    }

    /// 티에서 풀 드라이버의 캐리(첫 착지까지, m) — 착지 지대 장애물의 자리를 잡는 기준. 바람·표고는 이 홀 그대로, **나무는 뺀 사본**으로 잰다:
    /// 캐노피 충돌도 `.bounce`라 숲 홀에서 캐리가 185~205m로 잘렸고, 그 자리에 놓인 구덩이는 이음 띠에 걸친 나무까지 지워 어떤 드라이브도
    /// 안 빠지는 가짜 해저드가 됐다(리뷰 F1, 60시드 420홀 중 4홀). 착지 없이 끝나면 nil
    func fullDriveCarry() -> Double? {
        guard let driver = ClubTable.all.first(where: { $0.id == "DR" }) else { return nil }
        let bare = Hole(
            par: par, dist: dist, holeX: holeX, worldW: worldW, greenStart: greenStart, greenEnd: greenEnd,
            apronStart: apronStart,
            segments: segments, elevation: elevation, waterRange: waterRange, greenSlope: greenSlope, teeX: teeX,
            obstacles: [],
            signature: signature, wind: wind, gimmick: gimmick, gimmickX: gimmickX
        )
        let dir: Double = holeX >= teeX ? 1 : -1
        var b = BallState(x: teeX, y: ground(at: teeX))
        Ballistics.launch(
            &b,
            club: driver,
            heightPct: 1,
            lie: .tee,
            dir: dir,
            slope: slope(at: teeX) * Phys.stanceSlopeRatio
        )
        var t = 0.0
        while t < 20 {
            switch Ballistics.step(&b, hole: bare) {
            case .bounce, .water, .holed: return abs(b.x - teeX)
            case .wall: return nil
            default: break
            }
            t += Phys.dt
        }
        return nil
    }

    /// 착지 지대 항아리가 진짜 해저드인가 — 얹은 뒤 게임과 같은 드라이브(캐노피 자동 펀치·스탠스 경사 포함)로 확인한다:
    /// 풀 드라이버(1.0)는 반대쪽 테두리를 넘겨 모래 밖에 서고, 한두 칸 덜 친 드라이브(0.88~0.96) 중 하나는 구덩이에 빠져야 한다.
    /// 아니면 그 자리는 버린다(다음 후보로) — 캐리를 나무 없이 재도 실제 드라이브가 다른 나무에 걸리는 홀이 있다
    func potBunkerTrapWorks() -> Bool {
        guard gimmick == .potBunker, par >= 4, let k = gimmickKnots else { return true }
        let dir: Double = holeX >= teeX ? 1 : -1
        let farRim = dir > 0 ? k.rim.upperBound : k.rim.lowerBound
        func rest(_ power: Double) -> (x: Double, inPit: Bool)? {
            guard let x = MissionKind.driveRest(self, weather: .clear, heightPct: power) else { return nil }
            return (x, k.rim.contains(x) && surface(at: x) == .bunker)
        }
        guard let full = rest(1.0), !full.inPit, (full.x - farRim) * dir > 0 else { return false }
        return [0.88, 0.92, 0.96].contains { rest($0)?.inPit == true }
    }

    /// 장치의 중심 후보 — 그린을 바꾸는 장치는 컵 하나. 사구는 마루가 에이프런 앞 (반대쪽 발치 + 띠 + 최소 이음) 만큼 앞에서 시작해
    /// 자리가 안 나오면(그린 앞이 사면·절벽) 4m씩 최대 20m 더 앞으로. 항아리는 파3면 테두리가 같은 간격으로 에이프런 앞, 파4·5면 반대쪽 테두리가
    /// 풀 드라이버 캐리에서 `driveClearMargin` 앞 — 안 맞으면 5m씩 최대 20m 티 쪽으로(넘기기는 그만큼 쉬워진다)
    internal func gimmickAnchors(_ kind: GimmickKind, shape: GimmickShape) -> [Double] {
        let dir: Double = holeX >= teeX ? 1 : -1
        switch kind {
        case .volcano, .funnel, .mesa:
            return [holeX]
        case .dune:
            let coneW = (shape.height / shape.coneSlope).rounded()
            let first = apronStart - dir * (shape.collarFar + shape.blendMin + coneW)
            return stride(from: 0.0, through: 20, by: 4).map { (first - dir * $0).rounded() }
        case .potBunker:
            if par == 3 {
                let first = apronStart - dir * (shape.collarFar + shape.blendMin + shape.bowlHalf)
                return stride(from: 0.0, through: 20, by: 4).map { (first - dir * $0).rounded() }
            }
            guard let carry = fullDriveCarry() else { return [] }
            let first = teeX + dir * (carry - Self.driveClearMargin(carry: carry) - shape.bowlHalf)
            return stride(from: 0.0, through: 20, by: 5).map { (first - dir * $0).rounded() }
        }
    }

    /// 장치가 지형을 고쳐 쓰는 범위 — 중심, 꺾이는 자리, 원래 지형으로 이어 붙이는 바깥 띠의 끝. 얹을 자리가 안 나오면 nil
    internal func gimmickLayout(
        _ kind: GimmickKind,
        shape: GimmickShape
    ) -> (center: Double, knots: GimmickKnots, extent: ClosedRange<Double>)? {
        guard gimmick == nil else { return nil }
        for c in gimmickAnchors(kind, shape: shape) {
            if let layout = gimmickLayout(kind, shape: shape, center: c) {
                if kind == .potBunker, par >= 4,
                   dressed(kind, shape: shape, layout: layout).potBunkerTrapWorks() == false {
                    continue // 가짜 해저드가 되는 자리 — 다음 후보 (리뷰 F1)
                }
                return layout
            }
        }
        return nil
    }

    private func gimmickLayout(
        _ kind: GimmickKind, shape: GimmickShape, center c: Double
    ) -> (center: Double, knots: GimmickKnots, extent: ClosedRange<Double>)? {
        let dir: Double = holeX >= teeX ? 1 : -1
        let z0 = ground(at: c)
        let k = Self.gimmickKnots(center: c, shape: shape, dir: dir)
        /// 바깥 띠 길이는 그 띠 안에서 원래 지형이 바닥(z0)과 벌어지는 최대 낙차에 비례 — 낙차 ÷ 0.2 (smoothstep 정점 경사 0.3).
        /// 고정 8m는 낙차 4m에서 셀 경사가 0.75~0.92까지 났다 (리뷰 m-3). 띠가 길어지면 더 먼 지형이 들어오므로 길이가 멎을 때까지 다시 잰다
        func blend(from edge: Double, out: Double) -> Double {
            var len = shape.blendMin
            while len < 24 {
                let drop = stride(from: 1.0, through: len, by: 1)
                    .map { abs(ground(at: min(max(edge + out * $0, 0), worldW)) - z0) }.max() ?? 0
                let need = min(24, max(shape.blendMin, (drop / 0.2).rounded(.up)))
                if need <= len {
                    break
                }
                len = need
            }
            return len
        }
        let lo = k.collar.lowerBound - blend(from: k.collar.lowerBound, out: -1)
        let hi = k.collar.upperBound + blend(from: k.collar.upperBound, out: 1)
        // 티 쪽으로는 티샷이 설 자리(40m)를 남기고, 반대쪽은 월드 안에
        let near = dir > 0 ? lo : hi, far = dir > 0 ? hi : lo
        guard (near - teeX) * dir >= 40, lo >= 1, hi <= worldW - 1 else { return nil }
        // 그린을 두는 장애물은 그린 복합체(에이프런·그린)를 한 점도 건드리지 않는다 — 반대쪽 끝이 에이프런 앞에서 끝나야 한다.
        // 그 너머 30m 안에 물이 있으면(연못 뒤 그린) 얹지 않는다 — 발치에서 넘긴 로브가 곧장 입수했다 (프로브 seed 1 파3: 창 3칸, 전부 물)
        guard kind.replacesGreen || (apronStart - far) * dir >= 0 else { return nil }
        let beyond = dir > 0 ? far ... far + 30 : far - 30 ... far
        guard kind.replacesGreen || !segments
            .contains(where: { $0.type == .water && $0.to > beyond.lowerBound && $0.from < beyond.upperBound })
        else { return nil }
        guard !segments.contains(where: { $0.type == .water && $0.to > lo && $0.from < hi }) else { return nil }
        // 원래 지형이 장치 자리에서 크게 오르내리면(절벽·사면 위) 얹지 않는다 — 평평한 바닥을 깔 수 없다
        let span = stride(from: lo, through: hi, by: 1).map { abs(ground(at: $0) - z0) }.max() ?? 0
        let fitsClamp = kind.isRaised ? z0 + shape.height <= CourseGenerator.elevClamp : z0 - shape
            .height >= -CourseGenerator.elevClamp
        guard span <= 4, fitsClamp else { return nil }
        return (c, k, lo ... hi)
    }

    /// 장치를 얹은 사본. 얹을 자리가 안 나오면 nil — 물·절벽에 걸치거나 월드 밖으로 나가는 홀, 그린 앞 자리가 안 나오는 홀
    func withGimmick(_ kind: GimmickKind, shape custom: GimmickShape? = nil) -> Hole? {
        let shape = custom ?? GimmickShape.shape(for: kind, worldW: worldW)
        guard let layout = gimmickLayout(kind, shape: shape) else { return nil }
        return dressed(kind, shape: shape, layout: layout)
    }

    /// 정해진 자리에 장치를 얹는다 (검증 없음 — `gimmickLayout`이 자리를 고른다)
    private func dressed(
        _ kind: GimmickKind, shape: GimmickShape, layout: (
            center: Double,
            knots: GimmickKnots,
            extent: ClosedRange<Double>
        )
    ) -> Hole {
        let (c, k, extent) = layout
        let dir: Double = holeX >= teeX ? 1 : -1
        let z0 = ground(at: c)
        let lo = extent.lowerBound, hi = extent.upperBound

        let rimZ = kind.isRaised ? shape.height : 0.0 // 안쪽 면 가장자리의 높이
        let bowlDepth: Double = switch kind { // 가장자리에서 바닥까지
        case .volcano: shape.bowlSlope * shape.bowlHalf
        case .funnel, .potBunker: shape.height
        case .mesa, .dune: 0
        }
        /// 자리 x의 높이 (z0 기준) — 띠 안쪽만
        func profile(_ x: Double) -> Double {
            if k.rim.lowerBound < k.rim.upperBound, k.rim.contains(x) { // 안쪽 면: 가장자리에서 바닥까지 곧은 비탈 (메사는 평평한 꼭대기)
                let side = x < c ? c - k.rim.lowerBound : k.rim.upperBound - c
                return rimZ - bowlDepth * (1 - abs(x - c) / side)
            }
            if x == c { // 사구 마루 (안쪽 면이 한 점)
                return rimZ
            }
            if x < k.rim.lowerBound, x > k.foot.lowerBound { // 바깥 비탈
                return rimZ * (x - k.foot.lowerBound) / (k.rim.lowerBound - k.foot.lowerBound)
            }
            if x > k.rim.upperBound, x < k.foot.upperBound {
                return rimZ * (k.foot.upperBound - x) / (k.foot.upperBound - k.rim.upperBound)
            }
            return 0
        }
        var elev = elevation
        for i in max(0, Int(lo)) ... min(elev.count - 1, Int(hi)) {
            let x = Double(i)
            if k.collar.contains(x) {
                elev[i] = z0 + profile(x)
            } else { // 바깥 띠: 평평한 바닥에서 원래 지형으로
                let u = x < c ? (k.collar.lowerBound - x) / (k.collar.lowerBound - lo) : (x - k.collar.upperBound) /
                    (hi - k.collar.upperBound)
                let t = min(1, max(0, u))
                elev[i] = z0 + (elevation[i] - z0) * (t * t * (3 - 2 * t))
            }
        }
        // 그린을 바꾸는 장치: 원래 그린·에이프런은 장치가 대신한다 — 장치 밖에 남는 조각까지 페어웨이로 바꾼다. 남겨 두면(원래 그린은 18~28m에
        // 핀이 한쪽으로 치우쳐 깔때기 홀의 64%에서 띠 밖으로 삐져나왔다) 그 위에서 퍼터가 잡히고 '온그린'·미션 성공 판정이 났다.
        // 장치에 걸친 원래 벙커는 통째로 러프로 — 0.2m짜리 모래 토막이 남았다 (리뷰 M-1). 장애물은 그린·에이프런을 그대로 둔다
        // 장애물 너머에 남은 원래 벙커도 러프로 — 사구는 에이프런까지(넘긴 로브가 곧장 그린사이드 벙커에 떨어졌다, 프로브: 창 1칸), 항아리는 탈출 샷이
        // 닿는 40m까지만(착지 지대 항아리가 150m 떨어진 그린사이드 벙커까지 지웠다 — 리뷰 F4). 해저드는 하나면 된다
        let reach = kind == .dune ? apronStart : dir > 0 ? min(apronStart, hi + 40) : max(apronStart, lo - 40)
        let gap = kind.replacesGreen ? lo ... hi : dir > 0 ? lo ... reach : reach ... hi
        var segs = segments.map { seg -> Segment in
            switch seg.type {
            case .green where kind.replacesGreen, .apron where kind.replacesGreen: Segment(
                    from: seg.from,
                    to: seg.to,
                    type: .fairway
                )
            case .bunker where seg.to > gap.lowerBound && seg.from < gap.upperBound: Segment(
                    from: seg.from,
                    to: seg.to,
                    type: .rough
                )
            default: seg
            }
        }
        let nearCollar = dir > 0 ? k.collar.lowerBound ... k.foot.lowerBound : k.foot.upperBound ... k.collar.upperBound
        let farCollar = dir > 0 ? k.foot.upperBound ... k.collar.upperBound : k.collar.lowerBound ... k.foot.lowerBound
        var green: ClosedRange<Double>?
        switch kind {
        case .volcano: // 둘레 띠·비탈은 러프 — 굴러 내려온 공이 띠에서 선다. 분화구는 그린
            segs = CourseGenerator.carve(segs, from: k.collar.lowerBound, to: k.collar.upperBound, type: .rough)
            green = k.rim
        case .funnel: // 둘레 띠는 러프(짧게 떨어져 굴러오는 공이 선다), 분지 벽은 페어웨이, 바닥만 그린
            segs = CourseGenerator.carve(segs, from: k.collar.lowerBound, to: k.collar.upperBound, type: .rough)
            segs = CourseGenerator.carve(segs, from: k.rim.lowerBound, to: k.rim.upperBound, type: .fairway)
            green = (c - shape.greenHalf) ... (c + shape.greenHalf)
        case .mesa: // 발치 띠·절벽은 러프, 꼭대기는 그린
            segs = CourseGenerator.carve(segs, from: k.collar.lowerBound, to: k.collar.upperBound, type: .rough)
            green = k.rim
        case .dune: // 티 쪽 발치 띠는 러프(앞면에서 굴러 내려온 공이 선다), 양면은 모래, 그린 쪽 띠는 페어웨이
            segs = CourseGenerator.carve(segs, from: nearCollar.lowerBound, to: nearCollar.upperBound, type: .rough)
            segs = CourseGenerator.carve(segs, from: k.foot.lowerBound, to: k.foot.upperBound, type: .bunker)
            segs = CourseGenerator.carve(segs, from: farCollar.lowerBound, to: farCollar.upperBound, type: .fairway)
        case .potBunker: // 구덩이는 모래, 양쪽 띠는 페어웨이
            segs = CourseGenerator.carve(segs, from: k.collar.lowerBound, to: k.collar.upperBound, type: .fairway)
            segs = CourseGenerator.carve(segs, from: k.rim.lowerBound, to: k.rim.upperBound, type: .bunker)
        }
        if let green {
            segs = CourseGenerator.carve(segs, from: green.lowerBound, to: green.upperBound, type: .green)
        }
        return Hole(
            par: par, dist: dist, holeX: holeX, worldW: worldW,
            greenStart: green?.lowerBound ?? greenStart, greenEnd: green?.upperBound ?? greenEnd,
            apronStart: green == nil ? apronStart : dir > 0 ? k.collar.lowerBound : k.collar.upperBound,
            segments: segs.sorted { $0.from < $1.from }, elevation: elev,
            waterRange: waterRange, greenSlope: green == nil ? greenSlope : 0,
            teeX: teeX,
            obstacles: obstacles.filter { $0.x + $0.size < lo || $0.x - $0.size > hi },
            signature: signature, wind: wind, gimmick: kind, gimmickX: kind.replacesGreen ? nil : c
        )
    }
}
