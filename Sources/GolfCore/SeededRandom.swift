/// mulberry32 — HTML 프로토타입과 동일한 시드 난수 (코스 재현 결과를 맞추기 위해 알고리즘 유지)
public struct SeededRandom {
    private var state: UInt32

    public init(seed: UInt32) {
        state = seed
    }

    /// [0, 1) 균등 난수
    public mutating func next() -> Double {
        state = state &+ 0x6D2B_79F5
        var t = (state ^ (state >> 15)) &* (state | 1)
        t = (t &+ ((t ^ (t >> 7)) &* (t | 61))) ^ t
        return Double(t ^ (t >> 14)) / 4_294_967_296.0
    }

    /// [lo, hi) 균등 난수
    public mutating func next(_ lo: Double, _ hi: Double) -> Double {
        lo + next() * (hi - lo)
    }
}
