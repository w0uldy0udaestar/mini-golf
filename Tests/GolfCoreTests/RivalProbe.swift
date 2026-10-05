@testable import GolfCore
import XCTest

/// 라이벌 실력 계측 (2026-10-05, M6): 오차 배율 skill별 홀당 평균 파 대비 — `Rival.calibration` 표의 출처.
/// `swift test --filter RivalProbe`의 `RIVALCAL` 표를 보고 표를 갱신한다. 물리·코스·봇 정책을 바꾸면 표가 어긋나므로 대역 단언으로 감시
final class RivalProbe: XCTestCase {
    /// (홀당 평균 파 대비, 기권율)
    static func measure(
        skill: Double,
        weather: Weather,
        seeds: ClosedRange<UInt32> = 1 ... 60
    ) -> (over: Double, stuck: Double) {
        var over = 0, stuck = 0, n = 0
        for seed in seeds {
            let course = CourseGenerator.makeCourse(seed: seed)
            let windy = course.map { $0.withWind(weather.wind(base: $0.wind)) } // 앱과 같은 순서: 날씨가 바람을 먼저 정한다
            for (hole, strokes) in zip(windy, Rival.playRound(windy, seed: seed, weather: weather, skill: skill)) {
                over += strokes - hole.par
                stuck += strokes >= Phys.maxStrokes ? 1 : 0
                n += 1
            }
        }
        return (Double(over) / Double(n), Double(stuck) / Double(n))
    }

    /// 표가 실측과 맞는가 (맑음 기준 ±0.12) · 못 칠수록 타수가 는다 · 어떤 날씨·실력에도 기권이 드물다.
    /// 표 갱신용으로 `RIVALCAL` 줄을 찍는다 — 맑음은 표의 전 행(60시드), 비·강풍은 세 지점만(20시드, 테스트 시간 절약)
    func testCalibrationTableMatches() {
        var lines: [String] = []
        var prev = -Double.infinity
        for row in Rival.calibration {
            let m = Self.measure(skill: row.skill, weather: .clear)
            lines.append(String(format: "skill %.1f  clear %+.2f (기권 %.1f%%)", row.skill, m.over, m.stuck * 100))
            XCTAssertEqual(m.over, row.overPar, accuracy: 0.12, "skill \(row.skill): 표 \(row.overPar) vs 실측 \(m.over)")
            XCTAssertGreaterThan(m.over, prev, "skill \(row.skill): 단조 증가가 깨짐")
            XCTAssertLessThanOrEqual(m.stuck, 0.03, "clear skill \(row.skill): 기권 \(m.stuck * 100)%")
            prev = m.over
        }
        for w in [Weather.rain, .gale] {
            for skill in [0.0, 2.0, 11.0] {
                let m = Self.measure(skill: skill, weather: w, seeds: 1 ... 20)
                lines.append(String(
                    format: "skill %.1f  %@ %+.2f (기권 %.1f%%)",
                    skill,
                    w.rawValue,
                    m.over,
                    m.stuck * 100
                ))
                XCTAssertLessThanOrEqual(m.stuck, 0.05, "\(w) skill \(skill): 기권 \(m.stuck * 100)%")
            }
        }
        print("RIVALCAL\n" + lines.joined(separator: "\n"))
    }
}
