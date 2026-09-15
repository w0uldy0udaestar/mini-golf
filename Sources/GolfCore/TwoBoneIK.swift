import Foundation

/// 2D 2-bone 해석적 IK — 뼈 길이가 입력 상수라 팔·다리가 늘어날 방법이 구조적으로 없다.
///
/// 수식: Ryan Juckett, "Analytic Two-Bone IK in 2D" (2008-12-29, 갱신 2020-11-29,
/// 상업 이용·개작·재배포 허용 라이선스). 코사인 법칙으로 관절각을 닫힌 해로 구한다.
/// 사이드뷰라 3D의 pole 벡터는 '선호 방향(pole)'과의 내적으로 두 해 중 하나를 고르는 것으로 축약된다
/// (무릎은 앞, 팔꿈치는 뒤·아래). 도달 불가는 코사인 클램프 대신 목표를 사거리 안으로 당기며,
/// 완전 신전 근처는 tanh로 부드럽게 압축한다(ozz-animation `soften`·Kaufmann "L1+L2−ε" 관용구) —
/// 팔이 '딱' 펴지는 순간의 각속도 발산(스냅)을 없앤다. 리서치: docs/research-stickman-rig.md
public enum TwoBoneIK {
    public struct Solution: Equatable {
        /// 중간 관절(무릎·팔꿈치) 위치
        public var jointX: Double
        public var jointY: Double
        /// 말단(발·손) 위치 — 사거리 안이면 목표와 같고, 밖이면 사거리 안으로 당겨진 점
        public var endX: Double
        public var endY: Double
        /// 목표를 당긴 거리 (0 = 정확히 도달)
        public var shortfall: Double
        /// 신전 비율 0~1 (1 = 완전 신전)
        public var extensionRatio: Double
    }

    /// - Parameters:
    ///   - pole: 두 해 중 이 방향(root 기준)으로 더 치우친 관절을 고른다. 영벡터면 첫 해.
    ///   - softStart: 사거리의 이 비율부터 tanh 소프트닝 시작 (1 = 소프트닝 없음, 경성 클램프)
    public static func solve(
        rootX: Double, rootY: Double,
        targetX: Double, targetY: Double,
        l1: Double, l2: Double,
        poleX: Double, poleY: Double,
        softStart: Double = 0.9
    ) -> Solution {
        let lmax = l1 + l2
        let lmin = abs(l1 - l2)
        let dx = targetX - rootX
        let dy = targetY - rootY
        var d = (dx * dx + dy * dy).squareRoot()
        var ux: Double
        var uy: Double
        if d < 1e-9 { // 목표가 뿌리 위 — 방향이 없으니 pole 반대쪽(접힌 팔)으로 두고 거리 0으로 푼다
            let pl = (poleX * poleX + poleY * poleY).squareRoot()
            if pl > 1e-9 {
                ux = -poleX / pl
                uy = -poleY / pl
            } else {
                ux = 1
                uy = 0
            }
            d = 0
        } else {
            ux = dx / d
            uy = dy / d
        }

        // 도달 거리: 소프트닝 구간 [s, lmax)에서 tanh 압축 — 연속·단조, lmax에 점근
        var reach = d
        let s = min(max(softStart, 0), 1) * lmax
        if softStart < 1, d > s {
            reach = s + (lmax - s) * tanh((d - s) / max(lmax - s, 1e-9))
        } else if d > lmax {
            reach = lmax
        }
        reach = max(reach, lmin)

        let endX = rootX + ux * reach
        let endY = rootY + uy * reach
        // 코사인 법칙: 뿌리에서 관절까지의 현 방향 투영 a, 수직 높이 h (reach 0 = 완전히 접힘: 관절은 l1 앞)
        let a = reach > 1e-9 ? (l1 * l1 - l2 * l2 + reach * reach) / (2 * reach) : l1
        let h = max(0, l1 * l1 - a * a).squareRoot()
        let px = rootX + ux * a
        let py = rootY + uy * a
        let nx = -uy
        let ny = ux
        let jAx = px + nx * h, jAy = py + ny * h
        let jBx = px - nx * h, jBy = py - ny * h
        let dotA = (jAx - rootX) * poleX + (jAy - rootY) * poleY
        let dotB = (jBx - rootX) * poleX + (jBy - rootY) * poleY
        let useA = dotA >= dotB
        return Solution(
            jointX: useA ? jAx : jBx,
            jointY: useA ? jAy : jBy,
            endX: endX,
            endY: endY,
            shortfall: max(0, d - reach),
            extensionRatio: lmax > 0 ? reach / lmax : 1
        )
    }
}
