/// 지면(라이) 종류 — 실제 골프처럼 물리 차등
/// roll: 굴림 감속(m/s²), restitution: 바운스 반발, power/spin: 이 라이에서 칠 때 배율
public enum Surface: String, CaseIterable, Sendable {
    case tee, fairway, rough, apron, green, bunker, water

    public var label: String {
        switch self {
        case .tee: "티"
        case .fairway: "페어웨이"
        case .rough: "러프"
        case .apron: "에이프런"
        case .green: "그린"
        case .bunker: "벙커"
        case .water: "워터"
        }
    }

    public var roll: Double {
        switch self {
        case .tee: 2.0
        case .fairway: 2.2
        case .rough: 4.5
        case .apron: 1.6
        case .green: 1.1
        case .bunker: 8.0
        case .water: 99
        }
    }

    /// 반발계수 기저값 — 실제 반발은 낙하 속도에 따라 추가로 줄어든다 (Ballistics.step)
    /// 값은 Biber 2023 실측 피팅(잔디 0.147~0.26) 기반 + 게임 스케일 보정 (2026-08-14 리서치)
    public var restitution: Double {
        switch self {
        case .tee, .fairway: 0.30
        case .rough: 0.14
        case .apron: 0.34
        case .green: 0.30
        case .bunker: 0.05 // 공이 박힘
        case .water: 0
        }
    }

    /// Penner 유효 경사(rad) — 잔디가 변형되며 공을 받아내는 정도. 부드러울수록 크고,
    /// 클수록 같은 스핀에서도 체크·백업이 잘 나온다 (그린 굳기의 단일 튜닝 레버)
    public var bounceBeta: Double {
        switch self {
        case .tee, .fairway: 10 * .pi / 180
        case .apron: 11 * .pi / 180
        case .green: 18 * .pi / 180
        case .rough: 25 * .pi / 180 // 모든 것을 죽인다
        case .bunker: 30 * .pi / 180
        case .water: 0
        }
    }

    /// 이 라이에서 칠 때 파워 배율
    public var powerFactor: Double {
        switch self {
        case .rough: 0.75
        case .bunker: 0.45 // 탈출샷만 가능
        default: 1.0
        }
    }

    /// 이 라이에서 칠 때 스핀 배율
    public var spinFactor: Double {
        switch self {
        case .rough: 0.5
        case .bunker: 0.25
        case .apron, .green: 0.9
        default: 1.0
        }
    }
}

/// 러프 라이 이원화 (2026-09-29 잔손질, 스핀 리서치 §4 "러프의 본질은 평균이 아니라 분산"): 평탄한 러프를 3m 셀마다 결정론적으로
/// 러프 60% · 플라이어 20%(풀이 성겨 스핀이 빠지고 멀리 난다) · 깊은 러프 20%(풀에 감겨 짧고 높게)로 나눈다. 평균 파워·스핀은 구 러프(0.75·0.5)와 같다.
/// HUD에는 이름으로만(수치 어시스트 금지). 사면·라이저 러프(|경사| ≥ 0.12)는 항상 보통 — 협곡 탈출 규칙(pwRoughHeight)이 보통 러프 기준
public enum RoughLie: String, Sendable, CaseIterable {
    case normal, flier, deep

    /// 러프 powerFactor(0.75)에 곱하는 배율
    public var powerMul: Double {
        switch self {
        case .normal: 1.0
        case .flier: 1.12
        case .deep: 0.86
        }
    }

    /// 러프 spinFactor(0.5)에 곱하는 배율
    public var spinMul: Double {
        switch self {
        case .normal: 1.0
        case .flier: 0.6
        case .deep: 1.25
        }
    }

    /// 발사각 변화(도) — 풀이 페이스와 공 사이에 끼어 로프트가 는다
    public var loftDelta: Double {
        switch self {
        case .normal: 0
        case .flier: 2
        case .deep: 5
        }
    }

    public var label: String {
        switch self {
        case .normal: "러프"
        case .flier: "플라이어 러프"
        case .deep: "깊은 러프"
        }
    }
}
