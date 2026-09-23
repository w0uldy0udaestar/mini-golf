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

    /// 캐디 추천 클럽 (서프라이즈 3차) — 남은 거리를 바람·표고로 보정한 '유효 거리'를 풀샷 총거리로 넘는 가장 짧은 클럽.
    /// 드라이버는 티에서만, 벙커는 샌드 웨지(파워 ×0.45라 거리 표가 안 맞는다), 그린은 퍼터.
    /// 보정은 거친 어림: 뒷바람(+) 1m/s당 −2%, 오르막 1m당 +1m (코스 전략의 유효거리 k=1.0과 같은 결)
    public static func recommendedClub(distance: Double, tailwind: Double, rise: Double, lie: Surface) -> Club {
        let clubs = ClubTable.all
        if lie == .green {
            return clubs.first { $0.isPutter } ?? clubs[clubs.count - 1]
        }
        if lie == .bunker {
            return clubs.first { $0.id == "SW" } ?? clubs[clubs.count - 2]
        }
        let eff = max(0, distance * (1 - 0.02 * tailwind) + rise)
        let pool = clubs.filter { !$0.isPutter && (lie == .tee || $0.id != "DR") } // 긴 클럽 → 짧은 클럽 순
        return pool.last { total(of: $0.id) >= eff } ?? pool[0]
    }
}
