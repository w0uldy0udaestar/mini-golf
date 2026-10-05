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

    /// 표가 실측과 맞는가 · 못 칠수록 타수가 는다 · 어떤 날씨·실력에도 기권이 드물다.
    /// 표는 200시드로 잰 값이고 여기서는 시간 때문에 60시드만 다시 잰다 — 표본 차이가 최대 0.12라 허용 ±0.2 (봇·물리·코스가 바뀌어
    /// 표가 어긋났는지 보는 감시). `RIVALCAL` 줄은 참고용: 맑음은 표의 전 행, 비·강풍은 세 지점만(20시드)
    func testCalibrationTableMatches() {
        var lines: [String] = []
        var prev = -Double.infinity
        for row in Rival.calibration {
            let m = Self.measure(skill: row.skill, weather: .clear)
            lines.append(String(
                format: "skill %.1f  clear %+.2f (기권 %.1f%%)  표 %+.2f",
                row.skill,
                m.over,
                m.stuck * 100,
                row.overPar
            ))
            XCTAssertEqual(
                m.over,
                row.overPar,
                accuracy: 0.2,
                "skill \(row.skill): 표 \(row.overPar) vs 60시드 실측 \(m.over)"
            )
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

    /// 유령의 홀인원은 없다 — 어떤 실력·날씨에도 타수 하한(파3 2 · 파4 2 · 파5 3)을 지킨다 (리뷰: 파3 홀인원 5~13%)
    func testRivalNeverBeatsTheFloor() {
        var raw = 0
        for seed: UInt32 in 1 ... 30 {
            let course = CourseGenerator.makeCourse(seed: seed)
            for skill in [0.0, 1.0, 5.5] {
                for (hole, strokes) in zip(course, Rival.playRound(course, seed: seed, skill: skill)) {
                    XCTAssertGreaterThanOrEqual(
                        strokes,
                        max(2, hole.par - 2),
                        "seed \(seed) par \(hole.par) skill \(skill)"
                    )
                }
            }
            for (i, hole) in course.enumerated() where hole.par == 3 {
                raw += Rival.simulate(hole, seed: seed &+ UInt32(i + 1) &* 2_654_435_761, weather: .clear, skill: 5.5)
                    .strokes == 1 ? 1 : 0
            }
        }
        XCTAssertGreaterThan(raw, 0, "하한이 실제로 일하는지 — 하한 없는 시뮬에는 파3 홀인원이 있어야 이 테스트가 의미 있다")
    }

    /// 입수로 같은 둑에 되돌아온 것을 '벽에 막힘'으로 읽어 풀 PW를 12타까지 반복하던 홀 (리뷰 재현: seed 1 8번 홀, 그린 앞뒤가 물)
    func testRivalDoesNotLoopAfterWaterDrop() {
        let course = CourseGenerator.makeCourse(seed: 1)
        let hole = course[7]
        XCTAssertEqual(hole.par, 3)
        XCTAssertTrue(hole.segments.contains { $0.type == .water }, "이 홀은 물이 있어야 재현 조건이 맞는다 (코스 생성기가 바뀌면 시드를 다시 찾는다)")
        for w in Weather.allCases {
            let strokes = Rival.play(hole, seed: 1 &+ 8 &* 2_654_435_761, weather: w, skill: 5.5)
            XCTAssertLessThan(strokes, Phys.maxStrokes, "\(w): 기권 (입수 반복)")
        }
    }
}
