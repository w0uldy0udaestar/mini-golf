import Foundation

/// 코스 전략 설계 — 실제 물리 시뮬레이션으로 잰 클럽별 도달 거리를 해저드 배치 앵커로 쓴다.
/// 실코스 설계 관례(2026-08-15 사용자 설계): 해저드는 '평균적인 티샷이 떨어지는 곳'에 있어야
/// "지를까, 끊어갈까"라는 선택이 생긴다. 시뮬레이션 앵커라 클럽 밸런스가 바뀌면 배치도 따라온다.
public enum CourseStrategy {
    /// 평지 풀샷 도달 거리 (m) — 결정론적 시뮬레이션 1회, 캐시.
    /// ⚠️ 전제 (리뷰 S-2): flatTest()는 장애물이 없어야 하고 launch/step은 RNG가 없어야 한다 —
    /// 둘 중 하나라도 깨지면 앵커가 흔들려 모든 코스 배치가 달라진다
    public static let anchors: [String: (carry: Double, total: Double)] = {
        var out: [String: (carry: Double, total: Double)] = [:]
        let flat = Hole.flatTest()
        for club in ClubTable.all where !club.isPutter {
            var b = BallState(x: 50, y: 0)
            Ballistics.launch(&b, club: club, heightPct: 1, lie: .fairway, dir: 1)
            var carry: Double?
            var t = 0.0
            while b.phase != .rest, t < 60 {
                let ev = Ballistics.step(&b, hole: flat)
                if carry == nil, case .bounce = ev {
                    carry = b.x - 50
                }
                t += Phys.dt
            }
            out[club.id] = (carry ?? (b.x - 50), b.x - 50)
        }
        return out
    }()

    public static func total(of id: String) -> Double {
        anchors[id]?.total ?? 200
    }

    public static func carry(of id: String) -> Double {
        anchors[id]?.carry ?? 180
    }
}
