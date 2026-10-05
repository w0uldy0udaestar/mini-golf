/// 라운드 날씨 (2026-10-05, M6 라운드 변주). 라운드 시드로 정해져 9홀 내내 같다 — "라운드 간 차이가 시드뿐"(M5 진단)의 해결.
/// 비: 굴림 감속 ×1.8(라이저 제외 전 라이)·바운스 반발 ×0.6 — 드라이브가 덜 구르고 그린이 느리다. 평지 실측(RoundVarietyTests):
/// 드라이버 굴림 44 → 26m(총 287 → 270), 7번 아이언 12 → 7m. 첫 시도 ×1.35·×0.8은 굴림 −18%(드라이브 8m)라 화면에서 안 읽혔다.
/// 탄도(캐리)는 그대로라 협곡 탈출 규칙(pwRoughHeight)·표고 예산은 영향 없다. 강풍: 홀 바람을 4.5~8m/s로 끌어올린다(방향은 그 홀의 원래 방향).
/// 배율은 기존 물리에 곱하기만 한다 — 맑음은 전부 1이라 회귀 없음 (BallKind와 같은 패턴)
public enum Weather: String, Sendable, CaseIterable {
    case clear, rain, gale

    /// 라운드 시드 → 날씨. 맑음 50%·비 25%·강풍 25% (코스 생성 난수와 섞이지 않게 별도 해시 — 같은 시드의 코스는 그대로)
    public static func pick(seed: UInt32) -> Weather {
        var r = SeededRandom(seed: seed ^ 0x9E37_79B9)
        _ = r.next() // 인접 시드의 첫 값이 비슷하게 나오는 것을 한 번 섞는다
        let u = r.next()
        return u < 0.5 ? .clear : u < 0.75 ? .rain : .gale
    }

    /// 굴림 감속 배율 (Surface.roll에 곱한다)
    public var rollScale: Double {
        self == .rain ? 1.8 : 1
    }

    /// 바운스 반발 배율 (Surface.restitution에 곱한다)
    public var restitutionScale: Double {
        self == .rain ? 0.6 : 1
    }

    /// 이 날씨에서의 홀 바람 (m/s). 강풍만 바꾼다 — 원래 세기(0~7, 약풍 편중)를 4.5~8로 펴고 방향은 유지
    public func wind(base: Double) -> Double {
        guard self == .gale else { return base }
        let sign: Double = base < 0 ? -1 : 1
        return sign * (4.5 + 3.5 * min(1, abs(base) / 7).squareRoot())
    }

    /// HUD 단어 (맑음은 표시 없음)
    public var label: String? {
        switch self {
        case .clear: nil
        case .rain: L("비", "Rain")
        case .gale: L("강풍", "Gale")
        }
    }

    /// 라운드 시작 안내 한 줄 — 수치가 아니라 결과의 말
    public var cue: String? {
        switch self {
        case .clear: nil
        case .rain: L("비 오는 라운드 — 공이 덜 구르고 그린이 느리다", "Rainy round — less roll, slower greens")
        case .gale: L("강풍 라운드 — 홀마다 바람이 세다", "Gale round — strong wind on every hole")
        }
    }
}
