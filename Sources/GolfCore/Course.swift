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

/// 홀 하나 — 세그먼트(라이 밴드)와 1m 간격 지형 표고 샘플을 가진다
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

    public init(
        par: Int, dist: Double, holeX: Double, worldW: Double,
        greenStart: Double, greenEnd: Double, apronStart: Double,
        segments: [Segment], elevation: [Double],
        waterRange: ClosedRange<Double>?, greenSlope: Double,
        teeX: Double = CourseGenerator.teeX
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
    public static func flatTest(worldW: Double = 10000, holeX: Double = 9999) -> Hole {
        Hole(
            par: 4, dist: holeX - CourseGenerator.teeX, holeX: holeX, worldW: worldW,
            greenStart: holeX - 12, greenEnd: holeX + 8, apronStart: holeX - 17,
            segments: [Segment(from: 0, to: worldW, type: .fairway)],
            elevation: [Double](repeating: 0, count: Int(worldW) + 2),
            waterRange: nil, greenSlope: 0
        )
    }
}

public enum CourseGenerator {
    public static let teeX: Double = 25 // 백스윙 포즈가 화면 왼쪽에서 잘리지 않는 여유
    static let parComposition = [3, 3, 4, 4, 4, 4, 4, 5, 5] // 파 36
    static let distRange: [Int: ClosedRange<Double>] = [3: 110 ... 170, 4: 250 ... 360, 5: 430 ... 500]

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
        return pars.map { par in makeHole(par: par, rand: &rand) }
    }

    static func makeHole(par: Int, rand: inout SeededRandom) -> Hole {
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

        // ── 지형 고저: 30~50m 간격 제어점에 완만한 언덕·계곡, 티는 평지 ──
        var nodes: [(x: Double, e: Double)] = [(0, 0), (teeEnd + 8, 0)]
        var nx = teeEnd + 8.0
        var ne = 0.0
        while nx < worldW {
            nx += rand.next(30, 50)
            ne = max(-5, min(7, ne + (rand.next() * 2 - 1) * 3.5))
            nodes.append((min(nx, worldW), ne))
        }
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

        // ── 워터 해저드: 파4·5의 중반부에 35% 확률, 평평한 저지대 ──
        var waterRange: ClosedRange<Double>? = nil
        if par >= 4, rand.next() < 0.35 {
            let wFrom = teeEnd + 40 + rand.next() * (apronStart - teeEnd - 100)
            let wTo = wFrom + rand.next(15, 30)
            if wTo < apronStart - 25 {
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

        /// ── 벙커: 그린 앞 1개(60%) + 페어웨이 중반 1개(35%), 얕은 모래 구덩이 ──
        func addBunker(from bFrom: Double, width: Double) {
            let bTo = bFrom + width
            if let wr = waterRange, bFrom < wr.upperBound + 6, bTo > wr.lowerBound - 6 {
                return
            }
            if bTo >= greenStart - 1 || bFrom <= teeEnd + 5 {
                return
            }
            segments = carve(segments, from: bFrom, to: bTo, type: .bunker)
            let mid = (bFrom + bTo) / 2
            for i in Int(bFrom) ... min(Int(ceil(bTo)), elev.count - 1) {
                let d = 1 - abs(Double(i) - mid) / (width / 2 + 0.5) // 가운데가 깊게
                elev[i] -= max(0, d) * 0.9
            }
        }
        if rand.next() < 0.6 {
            addBunker(from: greenStart - 4 - rand.next(3, 8), width: rand.next(5, 8))
        }
        if rand.next() < 0.35 {
            addBunker(
                from: teeEnd + 50 + rand.next() * (apronStart - teeEnd - 90),
                width: rand.next(6, 10)
            )
        }

        // ── 그린: 주변 지형 흐름을 따르는 미세 경사(브레이크) ──
        let gFrom = Int(apronStart - 2)
        let gTo = min(Int(ceil(greenEnd + 6)), elev.count - 1)
        let trend: Double = elev[gTo] >= elev[gFrom] ? 1 : -1
        let gSlope = trend * rand.next(0.02, 0.06) // 2~6% 브레이크
        let gBase = elev[gFrom]
        for i in gFrom ... gTo {
            elev[i] = gBase + gSlope * Double(i - gFrom)
        }
        for k in 1 ... 5 { // 그린 뒤 러프와 자연 연결
            let ri = gTo + k
            if ri < elev.count {
                elev[ri] = elev[gTo] * Double(5 - k) / 5 + elev[ri] * Double(k) / 5
            }
        }

        let hole = Hole(
            par: par, dist: dist, holeX: holeX, worldW: worldW,
            greenStart: greenStart, greenEnd: greenEnd, apronStart: apronStart,
            segments: segments, elevation: elev,
            waterRange: waterRange, greenSlope: gSlope
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
            teeX: w - h.teeX // 인스턴스 teeX (static 상수 아님 — 리뷰 S-1)
        )
    }
}
