import Foundation

/// 장치 그린 (2026-10-05, M7). 그린 자리를 한눈에 읽히는 큰 장치로 바꾼다 — 미니골프의 문법을 실제 크기 홀에 얹는다.
/// 사용자 요청 "벙커에 홀이 있거나, 벽 구멍을 통과해야 하거나, 뾰족하게 튀어나온 홀에 딱 맞게 쳐서 넣어야 하거나… 누구나 재밌게".
/// 지금까지 플레이 판정을 통과한 것은 전부 큰 지형(절벽 티·급사면)이고 실패한 것은 전부 미세한 수치였다 — 장치는 생김새부터 보여야 한다.
/// 코스 생성기(난수 스트림·불변식·밸런스 표)는 건드리지 않고 완성된 홀에 덧씌운다(`Hole.withGimmick`) — 날씨의 `withWind`와 같은 층
public enum GimmickKind: String, Sendable, CaseIterable {
    case volcano // 화산 — 봉우리 꼭대기 분화구 안에 컵. 분화구에 떨어뜨리면 굴러 들어가고, 빗나가면 비탈을 굴러 내려간다
    case funnel // 깔때기 — 분지 전체가 컵으로 기울어 있다. 분지에만 넣으면 굴러 들어간다

    /// 홀 이름 자리에 뜨는 말
    public var displayName: String {
        switch self {
        case .volcano: L("화산", "Volcano")
        case .funnel: L("깔때기", "Punchbowl")
        }
    }

    /// 홀 시작 안내 한 줄 — 무엇을 해야 하는지
    public var cue: String {
        switch self {
        case .volcano: L("분화구에 떨어뜨리면 컵으로 굴러 들어간다", "Land it in the crater and it rolls into the cup")
        case .funnel: L("분지에만 넣으면 컵으로 굴러 들어간다", "Get it in the bowl and it rolls into the cup")
        }
    }
}

public extension GimmickKind {
    /// 이 홀에 걸 수 있는 장치인가. 깔때기는 파3에 걸지 않는다 — 분지에만 넣으면 들어가는 홀이라 티샷 한 번에 홀인원이 흔해진다
    /// (프로브: 가장 맞는 클럽으로 백스윙 세기의 14%가 들어간다. 화산은 5%)
    func fits(_ hole: Hole) -> Bool {
        !(self == .funnel && hole.par == 3) && hole.withGimmick(self) != nil
    }

    /// 9홀에 장치를 입힌 코스. 라운드의 앞·가운데·뒤 세 토막에 하나씩 — 첫 장치는 1·2번 홀 안에 둔다(실플레이 기록상 9홀 완주가 드물어
    /// 뒤쪽 홀에만 나오는 것은 못 본 채 끝난다). 종류는 번갈아, 자리가 안 맞으면 다른 종류로. 코스 생성 난수와 별도 해시 — 같은 시드의 지형은 그대로.
    /// forced: 관찰용 — 들어가는 홀 전부에 그 장치
    static func dress(course: [Hole], seed: UInt32, forced: GimmickKind? = nil) -> [Hole] {
        if let forced {
            return course.map { $0.withGimmick(forced) ?? $0 }
        }
        var rand = SeededRandom(seed: seed ^ 0xC2B2_AE35)
        _ = rand.next()
        var out = course
        let n = course.count
        let groups = [Array(0 ..< min(2, n)), Array(min(3, n) ..< min(6, n)), Array(min(6, n) ..< n)]
        var kinds = allCases
        if rand.next() < 0.5 {
            kinds.reverse()
        }
        for (g, group) in groups.enumerated() where !group.isEmpty {
            var order = group
            for i in stride(from: order.count - 1, through: 1, by: -1) { // 토막 안에서 어느 홀인지는 섞는다
                order.swapAt(i, Int(rand.next() * Double(i + 1)))
            }
            let want = kinds[g % kinds.count]
            placing: for kind in [want] + kinds.filter({ $0 != want }) {
                for i in order where kind.fits(course[i]) {
                    out[i] = course[i].withGimmick(kind) ?? course[i]
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
    public var height: Double // 화산: 바닥에서 분화구 테두리까지 · 깔때기: 분지 깊이
    public var bowlHalf: Double // 컵으로 기운 면(분화구·분지)의 반폭
    public var bowlSlope: Double // 그 면의 경사 — 공이 서지 못하고 컵까지 굴러야 한다(그린 0.17·페어웨이 0.34보다 가파르게)
    public var greenHalf: Double // 그 가운데 그린으로 까는 반폭 (화산은 분화구 전체)
    public var coneSlope: Double // 화산 바깥 비탈 경사 (깔때기는 0)
    public var collar: Double // 장치 둘레의 평평한 띠 폭

    public static func volcano(worldW: Double) -> GimmickShape {
        let half = min(7, max(4.5, 0.015 * worldW))
        return GimmickShape(
            height: min(9, max(4.5, 0.02 * worldW)), bowlHalf: half, bowlSlope: 0.22, greenHalf: half, coneSlope: 0.55,
            collar: 5
        )
    }

    /// 깔때기: 가파른 V(경사 0.6)에 벽은 페어웨이 잔디. 그린 잔디(굴림 저항 1.1)·경사 0.3으로 깔면 공이 컵을 지나쳐 반대편 벽을 오르내리는
    /// 시계추가 10초 넘게 갔고(첫 실측: 홀인까지 중앙 11.3초), 분지가 넓어(반폭 12~20m) 60m에서 백스윙 세기의 절반 이상이 들어갔다.
    /// 좁고 깊게 — 화면에서도 V자 골이 또렷하다
    public static func funnel(worldW: Double) -> GimmickShape {
        let depth = min(6, max(4, 0.013 * worldW))
        return GimmickShape(
            height: depth,
            bowlHalf: depth / 0.6,
            bowlSlope: 0.6,
            greenHalf: 2.5,
            coneSlope: 0,
            collar: 5
        )
    }

    /// 지형을 고쳐 쓰는 반폭 (컵 중심에서)
    public var footprint: Double {
        coneSlope > 0 ? bowlHalf + height / coneSlope + collar : bowlHalf + collar
    }
}

public extension Hole {
    static let gimmickBlend = 8.0 // 장치 바깥을 원래 지형에 잇는 길이

    /// 장치의 꺾이는 자리 (x, m). 표고 샘플이 1m 간격이라 테두리·발치를 정수 자리에 맞춘다 — 어긋나면 꼭짓점이 뭉개져
    /// 테두리 안쪽 1.5m의 경사가 0.17(그린에서 공이 설 수 있는 경사)까지 누웠다 (첫 불변식 테스트가 잡았다)
    struct GimmickKnots: Sendable, Equatable {
        public let rim: ClosedRange<Double> // 컵으로 기운 면의 양 끝 (분화구 테두리·분지 가장자리)
        public let foot: ClosedRange<Double> // 화산 비탈이 바닥에 닿는 자리 (깔때기는 rim과 같다)
        public let collar: ClosedRange<Double> // 평평한 띠의 바깥 끝
    }

    static func gimmickKnots(cup c: Double, shape: GimmickShape) -> GimmickKnots {
        let rimLo = (c - shape.bowlHalf).rounded(), rimHi = (c + shape.bowlHalf).rounded()
        let coneW = shape.coneSlope > 0 ? (shape.height / shape.coneSlope).rounded() : 0
        let collar = shape.collar.rounded()
        return GimmickKnots(
            rim: rimLo ... rimHi, foot: (rimLo - coneW) ... (rimHi + coneW),
            collar: (rimLo - coneW - collar) ... (rimHi + coneW + collar)
        )
    }

    /// 장치 그린을 얹은 사본. 얹을 자리가 안 나오면 nil — 물·절벽에 걸치거나 월드 밖으로 나가는 홀
    func withGimmick(_ kind: GimmickKind, shape custom: GimmickShape? = nil) -> Hole? {
        let shape = custom ?? (kind == .volcano ? GimmickShape.volcano(worldW: worldW) : .funnel(worldW: worldW))
        let c = holeX
        let k = Self.gimmickKnots(cup: c, shape: shape)
        let lo = k.collar.lowerBound - Self.gimmickBlend, hi = k.collar.upperBound + Self.gimmickBlend
        // 티 쪽으로는 티샷이 설 자리(40m)를 남기고, 반대쪽은 월드 안에
        let teeSide = teeX < holeX ? lo - teeX : teeX - hi
        guard gimmick == nil, teeSide >= 40, lo >= 1, hi <= worldW - 1 else { return nil }
        guard !segments.contains(where: { $0.type == .water && $0.to > lo && $0.from < hi }) else { return nil }
        let z0 = ground(at: c)
        // 원래 지형이 장치 자리에서 크게 오르내리면(절벽·사면 위) 얹지 않는다 — 평평한 바닥을 깔 수 없다
        let span = stride(from: lo, through: hi, by: 1).map { abs(ground(at: $0) - z0) }.max() ?? 0
        guard span <= 4, z0 + shape.height <= CourseGenerator.elevClamp else { return nil }

        let bowlDepth = kind == .volcano ? shape.bowlSlope * shape.bowlHalf : shape.height
        let rimZ = kind == .volcano ? shape.height : 0.0
        /// 자리 x의 높이 (z0 기준) — 띠 안쪽만
        func profile(_ x: Double) -> Double {
            if k.rim.contains(x) { // 컵으로 기운 면: 테두리에서 컵까지 곧은 비탈 (양쪽 폭이 반올림만큼 다를 수 있다)
                let side = x < c ? c - k.rim.lowerBound : k.rim.upperBound - c
                return rimZ - bowlDepth * (1 - abs(x - c) / side)
            }
            if x < k.rim.lowerBound, x > k.foot.lowerBound { // 화산 바깥 비탈
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
                let u = min(1, (x < c ? k.collar.lowerBound - x : x - k.collar.upperBound) / Self.gimmickBlend)
                elev[i] = z0 + (elevation[i] - z0) * (u * u * (3 - 2 * u))
            }
        }
        var segs: [Segment]
        let (cl, cr) = (k.collar.lowerBound, k.collar.upperBound)
        switch kind {
        case .volcano: // 발치는 에이프런 띠, 바깥 비탈은 러프 — 빗나간 공이 멀리 달아나지 않고 발치에 선다
            segs = CourseGenerator.carve(segments, from: cl, to: cr, type: .apron)
            segs = CourseGenerator.carve(segs, from: k.foot.lowerBound, to: k.foot.upperBound, type: .rough)
        case .funnel: // 둘레는 러프 띠 — 짧게 떨어져 굴러오는 공은 여기서 죽는다. 벽은 페어웨이 (GimmickShape.funnel 주석)
            segs = CourseGenerator.carve(segments, from: cl, to: cr, type: .rough)
            segs = CourseGenerator.carve(segs, from: k.rim.lowerBound, to: k.rim.upperBound, type: .fairway)
        }
        let green = kind == .volcano ? k.rim : (c - shape.greenHalf) ... (c + shape.greenHalf)
        segs = CourseGenerator.carve(segs, from: green.lowerBound, to: green.upperBound, type: .green)
        return Hole(
            par: par, dist: dist, holeX: holeX, worldW: worldW,
            greenStart: green.lowerBound, greenEnd: green.upperBound, apronStart: teeX < holeX ? cl : cr,
            segments: segs.sorted { $0.from < $1.from }, elevation: elev,
            waterRange: waterRange, greenSlope: 0,
            teeX: teeX,
            obstacles: obstacles.filter { $0.x + $0.size < lo || $0.x - $0.size > hi },
            signature: signature, wind: wind, gimmick: kind
        )
    }
}
