import Foundation
import GolfCore

/// 스틱맨 뼈대 — 점 리그(Rig) 위에 뼈 길이를 강제하는 렌더 직전 후처리.
///
/// 스윙 P-System·걷기 빌더·의식·잔동작은 여전히 '점 좌표'로 목표를 말하고, 여기서
/// 몸통·허벅지·정강이·위팔·아래팔 5개 뼈의 길이를 고정한 채 무릎·팔꿈치를 IK로 푼다.
/// 원칙: **발은 절대 옮기지 않는다**(노슬립 게이트 불변) — 다리가 사거리를 넘으면 힙을 내린다
/// (도립 진자: 접지 순간 몸이 가장 낮다). 손은 사거리 안으로 당긴다(클럽은 손을 따라간다).
/// 리서치·설계: docs/research-stickman-rig.md
enum Skeleton {
    static let torso = 25.0 // 힙→어깨 (직립 25.0 · 스윙 포즈 24.0(임팩트)~28.3(팔로스루 tilt 18)을 정규화)
    static let upperArm = 17.5
    static let foreArm = 17.5 // 합 35 — 어드레스 handD 34가 거의 완전 신전
    static let thigh = 23.25
    static let shin = 23.25 // 합 46.5 — 직립 힙 높이 43.5에서 무릎이 살짝 굽는다
    static let legReach = (thigh + shin) * 0.995
    static let kneePole = (x: 1.0, y: 0.0) // 무릎은 바라보는 쪽(앞)으로 굽는다
    static let elbowPole = (x: -0.6, y: -0.8) // 팔꿈치는 뒤·아래로 (매달린 팔·오버헤드 모두 자연)

    struct Joints {
        var knee1 = CGPoint.zero
        var knee2 = CGPoint.zero
        var elbowLead = CGPoint.zero
        var elbowTrail = CGPoint.zero
        var hipDrop = 0.0 // 다리 사거리 때문에 힙을 내린 양(px)
        var clampLead = 0.0 // 리드 손(그립)을 사거리 안으로 당긴 양
        var clampTrail = 0.0 // 트레일 손을 당긴 양
        var legStretch = 0.0 // 힙을 바닥까지 내려도 발이 닿지 않은 잔여(비정상 — 계측용)
    }

    /// 리그를 제자리에서 보정하고 관절 위치를 돌려준다. 좌표는 facing 기준(+x = 바라보는 쪽).
    static func solve(_ r: inout Rig) -> Joints {
        var j = Joints()

        // 1. 몸통: 힙 고정, 어깨는 같은 기울기 방향으로 길이만 맞춘다 (머리는 어깨 상대라 따라온다)
        let tx = r.shoulder.x - r.hip.x
        let ty = r.shoulder.y - r.hip.y
        let tl = (tx * tx + ty * ty).squareRoot()
        if tl > 1e-6 {
            r.shoulder = CGPoint(x: r.hip.x + tx / tl * torso, y: r.hip.y + ty / tl * torso)
        }

        // 2. 다리 사거리: 발은 고정, 힙 높이를 두 다리 모두 닿는 곳까지 내린다
        var drop = 0.0
        for foot in [r.foot1, r.foot2] {
            let dx = foot.x - r.hip.x
            let dy = r.hip.y - foot.y
            let d = (dx * dx + dy * dy).squareRoot()
            guard d > legReach else { continue }
            if abs(dx) < legReach {
                let maxHipY = foot.y + (legReach * legReach - dx * dx).squareRoot()
                drop = max(drop, r.hip.y - maxHipY)
            } else {
                j.legStretch = max(j.legStretch, d - legReach)
            }
        }
        if drop > 0 {
            j.hipDrop = drop
            r.hip.y -= drop
            r.shoulder.y -= drop // 상체가 함께 내려온다 (손 목표는 그대로 — 팔이 조금 더 굽는다)
        }

        /// 3. 무릎: 힙→발 2-bone IK (발 위치는 해의 말단이 아니라 원래 값을 쓴다 — 노슬립)
        func knee(_ foot: CGPoint) -> CGPoint {
            let s = TwoBoneIK.solve(
                rootX: r.hip.x, rootY: r.hip.y, targetX: foot.x, targetY: foot.y,
                l1: thigh, l2: shin, poleX: kneePole.x, poleY: kneePole.y, softStart: 1
            )
            return CGPoint(x: s.jointX, y: s.jointY)
        }
        j.knee1 = knee(r.foot1)
        j.knee2 = knee(r.foot2)
        r.knee1 = j.knee1
        r.knee2 = j.knee2

        /// 4. 팔: 어깨→손 2-bone IK, 손은 사거리 안으로 당겨진다 (완전 신전 근처 tanh 소프트닝)
        func arm(_ hand: inout CGPoint) -> (elbow: CGPoint, clamp: Double) {
            let s = TwoBoneIK.solve(
                rootX: r.shoulder.x, rootY: r.shoulder.y, targetX: hand.x, targetY: hand.y,
                l1: upperArm, l2: foreArm, poleX: elbowPole.x, poleY: elbowPole.y, softStart: 0.9
            )
            hand = CGPoint(x: s.endX, y: s.endY)
            return (CGPoint(x: s.jointX, y: s.jointY), s.shortfall)
        }
        let lead = arm(&r.grip)
        j.elbowLead = lead.elbow
        j.clampLead = lead.clamp
        let trail = arm(&r.handTrail)
        j.elbowTrail = trail.elbow
        j.clampTrail = trail.clamp
        return j
    }
}
