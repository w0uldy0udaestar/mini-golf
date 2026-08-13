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

    public var restitution: Double {
        switch self {
        case .tee, .fairway: 0.42
        case .rough: 0.25
        case .apron: 0.38
        case .green: 0.35
        case .bunker: 0.05 // 공이 박힘
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
