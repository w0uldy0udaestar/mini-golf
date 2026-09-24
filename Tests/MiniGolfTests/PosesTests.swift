import GolfCore
@testable import MiniGolf
import XCTest

/// 포즈 테이블 불변식 — 어드레스·임팩트에서 클럽 헤드가 공 접촉 기하를 지키는가 (HANDOFF 2단계 후속 제안).
/// 리그 공간은 공이 원점(RigBuilder.fromPose: 몸은 공 뒤 ballFwd+5px), 공 중심 (0, 5.5)·뒤쪽 가장자리 x = −5.5.
/// 헤드 팁(호젤) = 그립 + 길이 × (sin φ, −cos φ), 페이스는 팁에서 타깃 쪽으로 헤드 길이만큼(StickmanNode.headParams와 같은 식).
/// 퍼터는 실측 자세에서 "팁 = 공 뒤 5px·공 높이"로 손 각을 수치 해로 맞췄고(gen_table2.py), 풀스윙은 tilt·hipDx 변화를 handA로
/// 상쇄해 손·클럽 기하를 고정했다(docs/research-swing-styles.md). 테이블을 손으로 고칠 때 이 접촉이 깨지는 것을 잡는다.
/// 기준 대역은 2026-09-16 현재 테이블(사용자 판정 통과)을 여유 있게 덮는다 — 어드레스 페이스 [−7, 7], 임팩트 [−7, 11], 팁 높이 [−1.5, 6.5].
final class PosesTests: XCTestCase {
    private func tip(_ p: Pose, ballFwd: Double, clubLen: Double) -> CGPoint {
        let r = RigBuilder.fromPose(p, ballFwd: ballFwd, clubLen: clubLen)
        return CGPoint(x: r.grip.x + sin(r.clubPhi) * r.clubLen, y: r.grip.y - cos(r.clubPhi) * r.clubLen)
    }

    /// 팁에서 페이스까지의 타깃 방향 길이(px) — StickmanNode.headParams의 캡슐 기하를 φ≈0 기준으로 편 값
    private func faceReach(_ club: Club) -> Double {
        switch club.cat {
        case .wood: // 중심 = 팁 + 4.5, 캡슐 반길이 (w−h)/2 + 선폭 h/2 (h = 0.8w)
            let w = 17 - (club.loft - 10.5) * 0.5
            return 4.5 + 0.5 * w
        case .iron, .wedge: // 패들 길이 × cos(로프트 0.9) + 선폭/2
            let len = 8.5 + max(0, club.loft - 42) * 0.11
            let lo = club.loft * 0.9 * .pi / 180
            return len * cos(lo) + (5 + max(0, club.loft - 42) * 0.055) / 2
        case .putter:
            return 6.5 + 3.25
        }
    }

    func testPutterAddressTipIsFiveBehindBallAndImpactOnBall() {
        for style in SwingStyle.allCases {
            let k = PutterKeyframes.table(style)
            let a = tip(k.a, ballFwd: k.ballFwd, clubLen: k.len)
            XCTAssertEqual(a.x, -5, accuracy: 1.0, "\(style) 퍼터 어드레스: 팁이 공 뒤 5px에서 벗어남 \(a)")
            let imp = tip(k.imp, ballFwd: k.ballFwd, clubLen: k.len)
            XCTAssertGreaterThan(imp.x, -4.5, "\(style) 퍼터 임팩트: 헤드가 공에 못 미침 \(imp)")
            XCTAssertLessThan(imp.x, 0, "\(style) 퍼터 임팩트: 헤드가 공을 지나침 \(imp)")
            for (name, t) in [("어드레스", a), ("임팩트", imp)] {
                XCTAssertGreaterThan(t.y, 1.5, "\(style) 퍼터 \(name): 헤드가 지면 아래 \(t)")
                XCTAssertLessThan(t.y, 6.5, "\(style) 퍼터 \(name): 헤드가 공 위로 떠 있음 \(t)")
            }
        }
    }

    func testFullSwingAddressAndImpactFaceTouchesBall() {
        for style in SwingStyle.allCases {
            for club in ClubTable.all where !club.isPutter {
                let prof = SwingProfile.profile(for: club.cat, style: style)
                let reach = faceReach(club)
                let p1 = tip(prof.keys.p1, ballFwd: prof.ballFwd, clubLen: club.renderLength)
                let face1 = Double(p1.x) + reach
                XCTAssertGreaterThan(face1, -7, "\(style) \(club.id) 어드레스: 페이스가 공 뒤로 떨어짐 (팁 \(p1), 페이스 x \(face1))")
                XCTAssertLessThan(face1, 7, "\(style) \(club.id) 어드레스: 페이스가 공을 지나침 (팁 \(p1), 페이스 x \(face1))")
                let p7 = tip(prof.keys.p7, ballFwd: prof.ballFwd, clubLen: club.renderLength)
                let face7 = Double(p7.x) + reach
                XCTAssertGreaterThan(face7, -7, "\(style) \(club.id) 임팩트: 페이스가 공에 못 미침 (팁 \(p7), 페이스 x \(face7))")
                XCTAssertLessThan(face7, 11, "\(style) \(club.id) 임팩트: 페이스가 공을 한참 지나침 (팁 \(p7), 페이스 x \(face7))")
                for (name, t) in [("어드레스", p1), ("임팩트", p7)] {
                    XCTAssertGreaterThan(t.y, -1.5, "\(style) \(club.id) \(name): 헤드가 지면 아래 \(t)")
                    XCTAssertLessThan(t.y, 6.5, "\(style) \(club.id) \(name): 헤드가 공 위로 떠 있음 \(t)")
                }
            }
        }
    }

    /// 백스윙 프리뷰(조준 화면)·피니시가 유한한 값인지 — 테이블 typo(NaN·극단값)를 잡는 스모크
    func testBackswingAndFinishPosesAreSane() {
        for style in SwingStyle.allCases {
            for cat in [ClubCategory.wood, .iron, .wedge, .putter] {
                let prof = SwingProfile.profile(for: cat, style: style)
                for h in stride(from: 0.0, through: 1.0, by: 0.25) {
                    let p = backswingPose(heightPct: h, profile: prof)
                    XCTAssertTrue(
                        p.handA.isFinite && p.clubA.isFinite && abs(p.tilt) < 45,
                        "\(style) \(cat) 백스윙 h=\(h) \(p)"
                    )
                }
                let fin = finishPose(profile: prof, heightPct: 0.6)
                XCTAssertTrue(fin.handA.isFinite && fin.clubA.isFinite, "\(style) \(cat) 피니시 \(fin)")
            }
        }
    }

    /// 관찰용 표 — 실패 시 어느 세트가 얼마나 벗어났는지 한눈에 (테스트 출력, 단언 없음)
    func testPrintHeadTipTable() {
        var lines: [String] = []
        for style in SwingStyle.allCases {
            let k = PutterKeyframes.table(style)
            let ta = tip(k.a, ballFwd: k.ballFwd, clubLen: k.len)
            let ti = tip(k.imp, ballFwd: k.ballFwd, clubLen: k.len)
            lines.append(String(format: "%@ putt  a(%.1f, %.1f) imp(%.1f, %.1f)", "\(style)", ta.x, ta.y, ti.x, ti.y))
            for club in ClubTable.all where ["DR", "7I", "SW"].contains(club.id) {
                let prof = SwingProfile.profile(for: club.cat, style: style)
                let reach = faceReach(club)
                let t1 = tip(prof.keys.p1, ballFwd: prof.ballFwd, clubLen: club.renderLength)
                let t7 = tip(prof.keys.p7, ballFwd: prof.ballFwd, clubLen: club.renderLength)
                lines.append(String(
                    format: "%@ %@  p1 tip(%.1f, %.1f) face %.1f · p7 tip(%.1f, %.1f) face %.1f",
                    "\(style)", club.id, t1.x, t1.y, Double(t1.x) + reach, t7.x, t7.y, Double(t7.x) + reach
                ))
            }
        }
        print("HEADTIP\n" + lines.joined(separator: "\n"))
    }
}
