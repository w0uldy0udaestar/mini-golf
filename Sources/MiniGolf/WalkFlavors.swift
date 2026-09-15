import Foundation

/// ═══════════════════════════════════════════════════════════════
/// 걷기 랜덤 모션 37종 (2026-09-15 재설계 — 사용자 피드백 4번 "이름만 다르고 다 비슷해" → "전부 확 다르게").
/// 구 100종은 같은 오프셋 채널(머리·어깨 몇 px, 손 위로 몇 px)에 같은 종 모양 엔벨로프였고 팔꿈치가 없어
/// 흔들기·지목·환호가 전부 '팔 한 줄 올렸다 내리기'였다. 재설계 원칙:
/// ① 관절 뼈대(Skeleton IK) 위에서 손 목표를 어깨 기준 극좌표(각도·뻗음)로 잡아 팔꿈치가 접히는 실루엣
/// ② 리듬을 다르게 — 스냅·홀드, 예비동작→본동작, 진동, 펄스 ③ 일부는 걸음 자체를 바꾼다(보폭 배율·정지·
/// 점프·발끝) ④ 8묶음 안에서 실루엣이 겹치는 것은 합쳤다. 발 접지 게이트는 건드리지 않는다.
/// 각도 규약: 0 = 손이 어깨 바로 아래, + = 앞(바라보는 쪽), π = 바로 위. 뻗음 1 = 팔 길이 35px.
/// ═══════════════════════════════════════════════════════════════
enum WalkFlavorKind: CaseIterable {
    /// ── A 클럽 곡예 (6) ──
    case twirl, helicopter, clubBalance, clubDrag, clubSword, clubCane
    /// ── B 에어 골프 (3) ──
    case airSwing, airPutt, clubInspect
    /// ── C 머리·시선 (3) ──
    case lookBack, skyGaze, doubleTake
    /// ── D 팔 제스처 (7) ──
    case wave, fistPump, skyPoint, facepalm, shrug, stretch, chinStroke
    /// ── E 상체·자세 (4) ──
    case bow, leanBack, crouchSneak, yawn
    /// ── F 리듬·스텝 (6) ──
    case skip, hopscotch, marchStep, tipToe, strut, stumble
    /// ── G 감정 (4) ──
    case cheer, dejected, laugh, nervous
    /// ── H 관찰·잡동사니 (4) ──
    case windCheck, distanceScan, watchCheck, sneeze

    /// 클럽이 손에 있어야 하는 모션 (어깨 캐리 중 금지)
    var needsClub: Bool {
        switch self {
        case .twirl, .helicopter, .clubBalance, .clubDrag, .clubSword, .clubCane,
             .airSwing, .airPutt, .clubInspect, .skyPoint, .shrug, .stretch, .bow,
             .crouchSneak, .marchStep, .cheer, .dejected:
            true
        default:
            false
        }
    }

    /// 걸음을 멈추고 하는 모션 — 게이트가 쇼피스와 같은 연속 동결 램프를 건다. 발동 가중치도 낮다
    var stopsWalking: Bool {
        switch self {
        case .clubBalance, .airSwing, .airPutt, .bow, .windCheck, .distanceScan: true
        default: false
        }
    }

    var duration: Double {
        switch self {
        case .skip: 0.8
        case .twirl: 1.0
        case .sneeze: 1.1
        case .doubleTake, .stumble: 1.2
        case .fistPump: 1.3
        case .shrug, .hopscotch, .laugh: 1.4
        case .clubSword, .wave, .skyPoint: 1.5
        case .helicopter, .clubInspect, .facepalm, .cheer: 1.6
        case .stretch, .chinStroke, .yawn, .airPutt, .distanceScan, .watchCheck, .nervous: 1.8
        case .clubBalance, .airSwing, .lookBack, .skyGaze, .bow, .leanBack, .marchStep: 2.0
        case .clubDrag, .clubCane, .tipToe: 2.2
        case .crouchSneak, .strut, .dejected, .windCheck: 2.4
        }
    }

    /// 스케줄러 가중치 — 멈추는 모션은 드물게 (걷기가 자꾸 끊기면 개그가 아니라 버그로 읽힌다)
    var weight: Double {
        stopsWalking ? 0.35 : 1
    }

    static func weightedRandom() -> WalkFlavorKind {
        let total = allCases.reduce(0) { $0 + $1.weight }
        var r = Double.random(in: 0 ..< total)
        for k in allCases {
            r -= k.weight
            if r < 0 {
                return k
            }
        }
        return allCases.last!
    }

    /// 걸음 수정자 — 게이트가 매 프레임 묻는다. stride: 보폭 배율(케이던스는 거리 구동이라 자동 반비례),
    /// stop: 전진 동결 비율 0~1 (쇼피스와 같은 in 0.35s / out 0.5s 램프)
    func gait(u: Double) -> (stride: Double, stop: Double) {
        guard u > 0, u < 1 else { return (1, 0) }
        var stop = 0.0
        if stopsWalking {
            let t = u * duration
            let inR = smoothstep(min(1, t / 0.35))
            let outR = smoothstep(min(1, max(0, (t - (duration - 0.5)) / 0.5)))
            stop = inR * (1 - outR * outR)
        }
        let k: Double = switch self {
        case .lookBack, .marchStep: 0.9
        case .facepalm: 0.85
        case .clubSword, .yawn: 0.8
        case .clubCane: 0.75
        case .clubInspect, .chinStroke, .stumble, .dejected: 0.7
        case .hopscotch, .nervous: 0.6
        case .crouchSneak: 0.55
        case .tipToe: 0.5
        case .leanBack: 1.25
        case .strut: 1.35
        case .watchCheck: 1 + 0.3 * smoothstep(seg(u, 0.55, 0.7)) * (1 - smoothstep(seg(u, 0.9, 1)))
        default: 1
        }
        return (1 + (k - 1) * env(u, in: 0.25, out: 0.3), stop)
    }

    /// 모션 레시피 — u: 정규화 진행 (트월 계열은 완료 후에도 호출되어 누적각 유지)
    func apply(u: Double, into f: inout WalkFlavor) {
        let ss = smoothstep(min(1, u))
        // 트월 계열: 되감기 없음 — u ≥ 1에서도 누적각을 남긴다
        switch self {
        case .twirl:
            f.twirlAngle += 2 * .pi * ss
            if u < 1 {
                f.gripLift += 0.3 * bell(u)
            }
            return
        case .helicopter: // 머리 위에서 두 바퀴 — 그립을 머리 위 앞으로 들어 올린 채 회전
            f.twirlAngle += 4 * .pi * ss
            if u < 1 {
                let e = env(u, in: 0.2, out: 0.2)
                f.setClubHand(angle: 2.75, reach: 0.8, w: e)
                f.headDyOff += 2 * e
            }
            return
        default:
            break
        }
        guard u < 1 else { return }
        let e = env(u)
        switch self {
        // ── A 클럽 곡예 ──
        case .clubBalance: // 클럽을 손바닥 위에 수직으로 세우고 반대팔로 균형 — 걸음 멈춤, 흔들흔들
            let w = env(u, in: 0.2, out: 0.25)
            f.clubUpBlend = max(f.clubUpBlend, w)
            f.setClubHand(angle: 1.3, reach: 0.6, w: w)
            f.setFreeHand(angle: 1.9, reach: 0.8, w: w)
            f.headDyOff += 3 * w
            f.hipXOff += 1.5 * sin(4 * .pi * u) * w
        case .clubDrag: // 지친 골퍼 — 클럽 헤드를 뒤로 질질 끌며 어깨 처짐
            let w = env(u, in: 0.25, out: 0.3)
            f.setClubHand(angle: -0.45, reach: 0.75, w: w)
            f.setClubPhi(-2.35, w: w)
            f.shoulderYOff -= 2 * w
            f.headDyOff -= 2.5 * w
            f.armAmpBoost -= 0.5 * w
        case .clubSword: // 검처럼 앞으로 겨누고 두 번 찌르기 (몸이 앞으로 쏠린다)
            let w = env(u, in: 0.15, out: 0.2)
            f.setClubHand(angle: 1.5, reach: 0.6, w: w)
            f.setClubPhi(.pi / 2, w: w)
            let lunge = abs(sin(2 * .pi * seg(u, 0.2, 0.8))) * w
            f.hipXOff += 6 * lunge
            f.shoulderXOff += 3 * lunge
            f.headDxOff += 1.5 * w
        case .clubCane: // 지팡이 — 클럽을 앞에 짚고 구부정하게, 보폭 짧게
            let w = env(u, in: 0.25, out: 0.3)
            f.setClubHand(angle: 0.35, reach: 0.65, w: w)
            f.setClubPhi(-0.25, w: w)
            f.shoulderXOff += 5 * w
            f.shoulderYOff -= 2 * w
            f.hipYOff -= 3 * w
            f.headDyOff -= 1.5 * w
        // ── B 에어 골프 ──
        case .airSwing: // 멈춰 서서 풀 연습 스윙: 어드레스 → 백스윙 → 다운(급가속) → 팔로스루 → 풀기
            let w = env(u, in: 0.12, out: 0.15)
            let addr = smoothstep(seg(u, 0.05, 0.2)) * (1 - smoothstep(seg(u, 0.85, 0.95)))
            f.shoulderXOff += 5 * addr
            f.headDyOff -= 2 * addr
            let angle: Double
            let phi: Double
            let reach: Double
            if u < 0.25 {
                angle = 0.35; phi = 0.2; reach = 0.9
            } else if u < 0.5 {
                let s = smoothstep(seg(u, 0.25, 0.5))
                angle = mix(0.35, -2.0, s); phi = mix(0.2, -2.9, s); reach = mix(0.9, 0.7, s)
            } else if u < 0.6 {
                let s = seg(u, 0.5, 0.6)
                angle = mix(-2.0, 0.35, s * s); phi = mixAngle(-2.9, 0.1, s * s); reach = mix(0.7, 0.9, s)
            } else if u < 0.85 {
                let s = smoothstep(seg(u, 0.6, 0.85))
                angle = mix(0.35, 2.4, s); phi = mixAngle(0.1, 2.9, s); reach = mix(0.9, 0.7, s)
            } else {
                let s = smoothstep(seg(u, 0.85, 1))
                angle = mix(2.4, 0.35, s); phi = mixAngle(2.9, 0.2, s); reach = mix(0.7, 0.9, s)
            }
            f.setClubHand(angle: angle, reach: reach, w: w)
            f.setFreeHand(angle: angle, reach: reach - 0.03, w: w) // 두 손 다 그립에
            f.setClubPhi(phi, w: w)
            f.hipXOff += (u < 0.5 ? -2 * smoothstep(seg(u, 0.25, 0.5)) : 5 * smoothstep(seg(u, 0.5, 0.75))) * w
                * (1 - smoothstep(seg(u, 0.85, 1)))
        case .airPutt: // 퍼팅 자세로 두 번 스트로크 — 상체 숙이고 클럽 펜듈럼
            let w = env(u, in: 0.2, out: 0.2)
            f.shoulderXOff += 6 * w
            f.headDyOff -= 2.5 * w
            f.headDxOff += 2 * w
            f.setClubHand(angle: 0.25, reach: 0.95, w: w)
            f.setFreeHand(angle: 0.25, reach: 0.92, w: w)
            let inStroke = u > 0.25 && u < 0.85 ? 1.0 : 0.0
            f.setClubPhi(0.05 + 0.4 * sin(4 * .pi * seg(u, 0.25, 0.85)) * inStroke, w: w)
        case .clubInspect: // 클럽을 뒤로 잡고 헤드를 얼굴 앞으로 세워 살핀다, 반대손으로 헤드를 문지른다
            let w = env(u, in: 0.2, out: 0.25)
            f.setClubHand(angle: -0.55, reach: 0.6, w: w)
            f.setClubPhi(2.68, w: w)
            f.headDxOff += 1 * w
            f.headDyOff -= 1 * w
            let rub = smoothstep(seg(u, 0.4, 0.5)) * (1 - smoothstep(seg(u, 0.75, 0.85)))
            f.setFreeHand(angle: 2.5 + 0.1 * sin(12 * .pi * u), reach: 0.45, w: rub)
        // ── C 머리·시선 ──
        case .lookBack: // 오래 뒤돌아보며 걷는다 — 어깨도 살짝 따라간다
            let w = env(u, in: 0.2, out: 0.25)
            f.lookBack = max(f.lookBack, w)
            f.shoulderXOff -= 4 * w
            f.headDyOff += 1 * w
            f.setFreeHand(angle: -0.6, reach: 0.6, w: w) // 자유 손도 뒤로 — 상체가 따라 돈다
        case .skyGaze: // 하늘 보며 걷다가 삐끗 — 팔을 앞으로 휘저으며 회복
            let w = env(u, in: 0.2, out: 0.25)
            f.headDyOff += 4 * w
            f.headDxOff += 2 * w
            f.armAmpBoost -= 0.5 * w
            let st = smoothstep(seg(u, 0.6, 0.68)) * (1 - smoothstep(seg(u, 0.75, 0.9)))
            f.hipXOff += 5 * st
            f.shoulderXOff += 6 * st
            f.hipYOff -= 3 * st
            f.headDyOff -= 5 * st
            f.setFreeHand(angle: 1.8, reach: 0.9, w: st)
        case .doubleTake: // 봤다가, 다시 한 번(스냅) — 두 번째는 어깨가 움찔
            let l1 = smoothstep(seg(u, 0.05, 0.15)) * (1 - smoothstep(seg(u, 0.3, 0.4)))
            let l2 = smoothstep(seg(u, 0.5, 0.56)) * (1 - smoothstep(seg(u, 0.85, 0.95)))
            f.lookBack = max(f.lookBack, max(l1, l2))
            f.shoulderYOff += 2.5 * l2
            f.shoulderXOff -= 3 * l2
            f.headDyOff += 1 * l2
        // ── D 팔 제스처 ──
        case .wave: // 팔꿈치 접고 손을 머리 옆에서 앞뒤로 흔든다
            let w = env(u, in: 0.15, out: 0.2)
            f.setFreeHand(angle: 2.6 + 0.35 * sin(10 * .pi * u), reach: 0.55, w: w)
            f.headDxOff += 1 * w
            f.shoulderYOff += 1 * w
        case .fistPump: // 웅크리며 주먹을 가슴에 모았다가 하늘로 스냅
            let a = smoothstep(seg(u, 0.05, 0.2)) * (1 - smoothstep(seg(u, 0.3, 0.4)))
            let p = smoothstep(seg(u, 0.35, 0.42)) * (1 - smoothstep(seg(u, 0.8, 0.95)))
            f.hipYOff -= 5 * a
            f.shoulderXOff += 3 * a
            if u < 0.38 {
                f.setFreeHand(angle: 0.93, reach: 0.3, w: a)
            } else {
                f.setFreeHand(angle: 2.95, reach: 0.95, w: p)
            }
            f.hipYOff += 2 * p
            f.shoulderYOff += 2 * p
            f.headDyOff += 2 * p
        case .skyPoint: // 팔 쭉 뻗어 하늘 지목, 고개 위로, 클럽 손은 허리에
            let w = env(u, in: 0.15, out: 0.25)
            f.setFreeHand(angle: 2.35, reach: 0.95, w: w)
            f.headDyOff += 4 * w
            f.headDxOff += 3 * w
            f.setClubHand(angle: -0.15, reach: 0.62, w: w)
            f.setClubPhi(-0.9, w: w)
            f.shoulderXOff -= 2 * w
        case .facepalm: // 아이고… 손으로 얼굴, 고개 푹, 어깨 처짐
            let w = env(u, in: 0.2, out: 0.3)
            f.setFreeHand(angle: 2.75, reach: 0.37, w: w)
            f.headDyOff -= 3 * w
            f.headDxOff += 1.5 * w
            f.shoulderYOff -= 2 * w
            f.shoulderXOff += 2 * w
        case .shrug: // 양손 벌려 손바닥 위로 + 어깨 으쓱, 고개 갸웃
            let w = env(u, in: 0.2, out: 0.25)
            f.shoulderYOff += 4 * w
            f.headDxOff -= 2 * w
            f.headDyOff -= 1.5 * w
            f.setFreeHand(angle: 1.6, reach: 0.62, w: w)
            f.setClubHand(angle: -1.6, reach: 0.62, w: w)
            f.setClubPhi(-0.9, w: w)
            f.armAmpBoost -= 1 * w
        case .stretch: // 양팔(클럽까지) 하늘로 쭉, 허리 젖히고 기지개
            let w = env(u, in: 0.3, out: 0.3)
            f.setFreeHand(angle: 3.0, reach: 0.95, w: w)
            f.setClubHand(angle: 3.05, reach: 0.95, w: w)
            f.setClubPhi(2.9, w: w)
            f.shoulderXOff -= 3 * w
            f.headDyOff += 2 * w
            f.headDxOff -= 2 * w
            f.hipYOff += 1 * w
            f.armAmpBoost -= 1 * w
        case .chinStroke: // 턱 쓰다듬으며 생각에 잠긴 느린 걸음
            let w = env(u, in: 0.25, out: 0.3)
            f.setFreeHand(angle: 2.45, reach: 0.23 + 0.03 * sin(6 * .pi * u), w: w)
            f.headDyOff -= 1 * w
            f.headDxOff -= 1 * w
            f.shoulderXOff += 1 * w
            f.armAmpBoost -= 0.8 * w
        // ── E 상체·자세 ──
        case .bow: // 멈춰 서서 정중히 허리 굽혀 인사 — 팔은 아래로 늘어뜨린다
            let b = env(u, in: 0.3, out: 0.3)
            f.shoulderXOff += 14 * b
            f.shoulderYOff -= 12 * b
            f.headDyOff -= 3 * b
            f.headDxOff += 2 * b
            f.setFreeHand(angle: 0.15, reach: 0.9, w: b)
            f.setClubHand(angle: 0.3, reach: 0.85, w: b)
            f.setClubPhi(0.2, w: b)
            f.hipXOff -= 3 * b
        case .leanBack: // 뒤로 젖히고 가슴 펴고 느긋한 긴 보폭 — 으스댐
            let w = env(u, in: 0.25, out: 0.3)
            f.shoulderXOff -= 9 * w
            f.shoulderYOff += 1 * w
            f.headDyOff += 2 * w
            f.headDxOff -= 2 * w
            f.armAmpBoost += 1.2 * w
            f.hipXOff += 2 * w
        case .crouchSneak: // 웅크려 살금살금 — 무릎 굽고 상체 숙임, 짧고 빠른 걸음, 클럽은 뒤로 눕힌다
            let w = env(u, in: 0.25, out: 0.3)
            f.hipYOff -= 10 * w
            f.shoulderXOff += 5 * w
            f.headDxOff += 3 * w
            f.headDyOff -= 1 * w
            f.setFreeHand(angle: 1.2, reach: 0.5, w: w)
            f.setClubHand(angle: -0.5, reach: 0.5, w: w)
            f.setClubPhi(-1.55, w: w)
        case .yawn: // 손으로 입 가리고 고개 젖힘 → 팔 쭉 뻗는 기지개
            let m = smoothstep(seg(u, 0.05, 0.2)) * (1 - smoothstep(seg(u, 0.45, 0.6)))
            let s = smoothstep(seg(u, 0.5, 0.65)) * (1 - smoothstep(seg(u, 0.85, 1)))
            if u < 0.5 {
                f.setFreeHand(angle: 2.42, reach: 0.3, w: m)
            } else {
                f.setFreeHand(angle: 2.3, reach: 0.9, w: s)
            }
            let k = max(m, s)
            f.headDyOff += 2.5 * k
            f.headDxOff -= 1.5 * k
            f.shoulderYOff += 1.5 * k
            f.shoulderXOff -= 2 * s
        // ── F 리듬·스텝 ──
        case .skip:
            f.skip = max(f.skip, bell(u))
        case .hopscotch: // 두 발 모아 세 번 깡충 — 팔은 옆으로
            let w = env(u, in: 0.15, out: 0.2)
            f.jump += 7 * abs(sin(3 * .pi * seg(u, 0.1, 0.9))) * w
            f.setFreeHand(angle: 1.5, reach: 0.5, w: 0.5 * w)
        case .marchStep: // 행진 — 무릎 높이, 팔 크게, 클럽은 소총처럼 세워서
            let w = env(u, in: 0.25, out: 0.25)
            f.skip = max(f.skip, 0.6 * w)
            f.armAmpBoost += 2.5 * w
            f.shoulderYOff += 1.5 * w
            f.headDyOff += 1 * w
            f.clubUpBlend = max(f.clubUpBlend, 0.8 * w)
        case .tipToe: // 발끝 살금살금 — 뒤꿈치 들고 팔 벌려 균형, 잰걸음
            let w = env(u, in: 0.3, out: 0.3)
            f.heelLift += 3 * w
            f.hipYOff += 3 * w
            f.setFreeHand(angle: 1.7, reach: 0.7, w: w)
            f.headDyOff += 1 * w
        case .strut: // 으스대는 긴 보폭 — 어깨·힙 엇갈려 흔들기
            let w = env(u, in: 0.3, out: 0.3)
            f.shoulderXOff += 4 * sin(4 * .pi * u) * w
            f.hipXOff -= 5 * sin(4 * .pi * u) * w
            f.armAmpBoost += 1.2 * w
            f.headDyOff += 2 * w
            f.shoulderYOff += 1.5 * w
            f.headDxOff += 2 * sin(4 * .pi * u) * w
        case .stumble: // 걸려서 앞으로 쏠리고 팔 휘저음 → 아무 일 없었다는 듯 두리번
            let st = smoothstep(seg(u, 0.1, 0.2)) * (1 - smoothstep(seg(u, 0.45, 0.7)))
            f.shoulderXOff += 8 * st
            f.hipXOff += 4 * st
            f.headDxOff += 3 * st
            f.headDyOff -= 2 * st
            f.setFreeHand(angle: 1.9, reach: 0.9, w: st)
            let r = smoothstep(seg(u, 0.65, 0.8)) * (1 - smoothstep(seg(u, 0.9, 1)))
            f.shoulderYOff -= 1.5 * r
            f.lookBack = max(f.lookBack, 0.5 * r)
        // ── G 감정 ──
        case .cheer: // 양팔 V(클럽까지 하늘로) + 두 번 점프
            let w = env(u, in: 0.15, out: 0.25)
            f.setFreeHand(angle: 2.65, reach: 0.95, w: w)
            f.setClubHand(angle: -2.65, reach: 0.95, w: w)
            f.setClubPhi(2.5, w: w)
            f.jump += 8 * abs(sin(2 * .pi * seg(u, 0.1, 0.8))) * w
            f.headDyOff += 2 * w
        case .dejected: // 낙담 — 어깨·고개 축, 팔 늘어뜨리고 클럽 끌며 터덜터덜
            let w = env(u, in: 0.3, out: 0.35)
            f.shoulderYOff -= 4 * w
            f.headDyOff -= 4 * w
            f.headDxOff += 1 * w
            f.armAmpBoost -= 0.9 * w
            f.setFreeHand(angle: 0.05, reach: 0.9, w: w)
            f.setClubHand(angle: -0.45, reach: 0.75, w: w)
            f.setClubPhi(-2.35, w: w)
        case .laugh: // 고개 젖히고 어깨 들썩, 손은 배에
            let w = env(u, in: 0.2, out: 0.25)
            f.headDyOff += 3.5 * w
            f.headDxOff -= 3 * w
            f.shoulderYOff += 3 * abs(sin(8 * .pi * u)) * w
            f.shoulderXOff -= 5 * w
            f.setFreeHand(angle: 0.55, reach: 0.45, w: w)
            f.hipYOff += 1.2 * abs(sin(8 * .pi * u)) * w
            f.armAmpBoost -= 0.8 * w
        case .nervous: // 움츠리고 빠르게 두리번, 손은 가슴 앞에서 꼼지락, 종종걸음
            let w = env(u, in: 0.2, out: 0.25)
            f.headDxOff += 4.5 * sin(12 * .pi * u) * w
            f.headDyOff -= 2 * w
            f.shoulderYOff -= 3.5 * w
            f.shoulderXOff += 3 * w
            f.hipYOff -= 2 * w
            f.setFreeHand(angle: 1.0 + 0.2 * sin(14 * .pi * u), reach: 0.32, w: w)
            f.armAmpBoost -= 1 * w
        // ── H 관찰·잡동사니 ──
        case .windCheck: // 멈춰서 풀 뜯어 → 위로 뿌리고 → 날아가는 걸 본다
            let p = smoothstep(seg(u, 0.05, 0.2)) * (1 - smoothstep(seg(u, 0.3, 0.42)))
            let t = smoothstep(seg(u, 0.45, 0.55)) * (1 - smoothstep(seg(u, 0.7, 0.85)))
            f.shoulderXOff += 6 * p
            f.shoulderYOff -= 6 * p
            f.hipYOff -= 4 * p
            if u < 0.44 {
                f.setFreeHand(angle: 0.5, reach: 0.95, w: p)
            } else {
                f.setFreeHand(angle: 2.6, reach: 0.9, w: t)
            }
            let watch = smoothstep(seg(u, 0.5, 0.6)) * (1 - smoothstep(seg(u, 0.85, 1)))
            f.headDyOff += 3 * watch
            f.headDxOff += 2 * watch
        case .distanceScan: // 멈춰서 손차양 대고 먼 곳 훑어보기
            let w = env(u, in: 0.2, out: 0.25)
            f.setFreeHand(angle: 2.72, reach: 0.42, w: w)
            f.headDyOff += 1 * w
            f.headDxOff += (3 + 2 * sin(2 * .pi * u)) * w
            f.shoulderXOff += 2 * w
        case .watchCheck: // 손목시계 보고 → 서두른다 (보폭·팔 진폭 증가)
            let l = smoothstep(seg(u, 0.05, 0.2)) * (1 - smoothstep(seg(u, 0.45, 0.6)))
            f.setFreeHand(angle: 1.95, reach: 0.45, w: l)
            f.headDyOff -= 2 * l
            f.headDxOff += 1 * l
            let h = smoothstep(seg(u, 0.55, 0.7)) * (1 - smoothstep(seg(u, 0.9, 1)))
            f.armAmpBoost += 1 * h
            f.shoulderXOff += 2 * h
        case .sneeze: // 에— (고개 젖힘) 취! (앞으로 확, 손으로 얼굴)
            let a = smoothstep(seg(u, 0.1, 0.3)) * (1 - smoothstep(seg(u, 0.35, 0.42)))
            f.headDyOff += 3 * a
            f.shoulderXOff -= 2 * a
            let s = smoothstep(seg(u, 0.4, 0.46)) * (1 - smoothstep(seg(u, 0.65, 0.85)))
            f.headDyOff -= 4 * s
            f.shoulderXOff += 6 * s
            f.hipYOff -= 2 * s
            f.setFreeHand(angle: 2.55, reach: 0.4, w: s)
        case .twirl, .helicopter:
            break // 첫 번째 switch에서 처리 — default 없이 명시해 새 케이스 추가 시 컴파일러가 누락을 잡는다
        }
        _ = e
    }

    /// 부드러운 in-hold-out 종 모양 (0.3 경사)
    private func bell(_ u: Double) -> Double {
        smoothstep(min(1, min(u, 1 - u) / 0.3))
    }

    /// 스냅-인 · 홀드 · 이즈아웃 엔벨로프
    private func env(_ u: Double, in inW: Double = 0.15, out outW: Double = 0.2) -> Double {
        smoothstep(min(1, u / inW)) * (1 - smoothstep(min(1, max(0, (u - (1 - outW)) / outW))))
    }

    /// 구간 [a, b] 안의 정규화 진행 (밖이면 0/1로 클램프)
    private func seg(_ u: Double, _ a: Double, _ b: Double) -> Double {
        min(1, max(0, (u - a) / (b - a)))
    }
}

/// 각도 보간 — 최단 경로 (샤프트 각처럼 2π로 감기는 값)
func mixAngle(_ a: Double, _ b: Double, _ u: Double) -> Double {
    a + (b - a).remainder(dividingBy: 2 * .pi) * u
}

/// ═══════════════════════════════════════════════════════════════
/// 쇼피스 밈 모션 (2026-08-20 사용자 요청): 걷기를 멈추고(게이트 동결 램프 —
/// 트립과 같은 메커니즘) 2~3초 크게 추는 희귀 이벤트. 걷기당 최대 1개.
/// 선정: 밈 리서치(Trend Researcher, 2026-08) — 옆모습 실루엣 판독성 상위
/// + 골프 클럽 시너지 우선, 글로벌+K-밈 혼합 (사용자 선택).
/// 명명: 특정 게임 이모트 명칭 미사용, 동작은 어휘 수준으로 추상화한 오마주
/// (Hanagami v. Epic 판례 — 리서치 법적 권고).
/// ═══════════════════════════════════════════════════════════════
enum ShowpieceKind: String, CaseIterable {
    case whiffSpin // 헛스윙 개그 — 진지한 어드레스 → 헛스윙 휘릭 → 아무렇지 않게 잔댄스
    case auraFarm // 아우라 파밍 — 클럽 짚고 낮게, 팔 스윕마다 정지 홀드 (보트 소년)
    case siuJump // 도약 세리머니 — 웅크림 → 점프 → 양팔 뒤로 착지 홀드
    case tripleBeat // 퉁퉁퉁 — 클럽 수직 3연타 찍기 + 바운스 (사후르 오마주)
    case scubaDance // 스쿠버 — 한 손 코 막고 바운스, 클럽 부채질
    case heelGroove // 힐 그루브 — 뒤꿈치 바운스 8박 + 자유팔 루프
    case dabPose // 댑 — 스냅으로 팔꿈치에 고개 파묻고 클럽 팔 사선 홀드
    case horseDance // 말춤 — 양손 고삐 바운스 + 올가미 돌리기 (K-클래식)
    case coffinMarch // 관짝 행진 — 클럽 어깨에 메고 제자리 바운스 행진
    case clubFlip // 클럽 플립 — 던져 수직 착지, 짜잔 (보틀 플립 번안)
    case freezeFrame // 마네킹 — 걷다가 완전 정지, 끝에 두리번 (이스터에그)
    case cheerSeesaw // 응원 시소 — 양손 교대 상하 + 힙 리듬 (삐끼삐끼풍)

    var duration: Double {
        switch self {
        case .dabPose: 2.0
        case .clubFlip: 2.4
        case .siuJump, .heelGroove: 2.6
        case .tripleBeat, .scubaDance, .cheerSeesaw: 2.8
        case .whiffSpin, .freezeFrame: 3.0
        case .auraFarm, .horseDance: 3.2
        case .coffinMarch: 3.4
        }
    }

    /// 구간 [a, b] 안의 정규화 진행 (밖이면 0/1로 클램프)
    private func seg(_ u: Double, _ a: Double, _ b: Double) -> Double {
        min(1, max(0, (u - a) / (b - a)))
    }

    /// in-hold-out 엔벨로프 — 시작 스냅, 끝 이즈아웃
    private func env(_ u: Double, in inW: Double = 0.12, out outW: Double = 0.15) -> Double {
        smoothstep(min(1, u / inW)) * (1 - smoothstep(max(0, (u - (1 - outW)) / outW)))
    }

    /// 쇼피스 레시피 — u: 정규화 진행. 걷기 채널 위에 크게 얹는다 (동결 중이라 겹침 없음)
    func apply(u: Double, into f: inout WalkFlavor) {
        guard u > 0, u < 1 else { return }
        let e = env(u)
        switch self {
        case .whiffSpin:
            // 진지한 어드레스(0~0.28) → 백스윙(0.28~0.42) → 헛스윙(0.42~0.52) →
            // 클럽 휘릭 한 바퀴(관성, 0.52~0.72) → 아무렇지 않게 잔댄스(0.72~1)
            let address = smoothstep(seg(u, 0.02, 0.14)) * (1 - smoothstep(seg(u, 0.66, 0.8)))
            f.shoulderXOff += 3.5 * address
            f.headDyOff -= 2.5 * address
            let back = smoothstep(seg(u, 0.28, 0.42)) * (1 - smoothstep(seg(u, 0.42, 0.5)))
            f.gripLift += back
            f.phiWobble += -1.7 * back
            f.phiWobble += 2.4 * smoothstep(seg(u, 0.42, 0.5)) * (1 - smoothstep(seg(u, 0.62, 0.78)))
            f.twirlAngle += 2 * .pi * smoothstep(seg(u, 0.52, 0.72)) // 헛친 관성에 클럽만 휘릭
            f.hipXOff += 4 * sin(3 * .pi * seg(u, 0.52, 0.68)) * e
            let dance = smoothstep(seg(u, 0.74, 0.82)) * e
            f.skip = max(f.skip, dance * abs(sin(4 * .pi * seg(u, 0.74, 1))))
            f.freeHandYOff += 14 * dance * abs(sin(4 * .pi * seg(u, 0.74, 1)))
        case .auraFarm:
            // 클럽을 삿대처럼 수직으로 짚고 무게 낮춤 — 팔 스윕 2회, 스윕 끝마다 완전 정지
            f.clubUpBlend = max(f.clubUpBlend, e)
            f.hipYOff -= 5.5 * e
            f.shoulderXOff -= 2.5 * e
            let w = seg(u, 0.1, 0.85) * 2
            let sweep = w < 1 ? smoothstep(min(1, w / 0.6)) : smoothstep(min(1, (w - 1) / 0.6))
            let dir: Double = w < 1 ? 1 : -1
            f.freeHandXOff += 26 * sweep * dir * e
            f.freeHandYOff += (14 - 20 * sweep) * e
            f.lookBack = max(f.lookBack, smoothstep(seg(u, 0.86, 0.95)) * e) // 마지막: 카메라 응시
        case .siuJump:
            let crouch = smoothstep(seg(u, 0.05, 0.28)) * (1 - smoothstep(seg(u, 0.3, 0.42)))
            f.hipYOff -= 9 * crouch
            f.shoulderXOff += 3 * crouch
            let air = smoothstep(seg(u, 0.3, 0.4)) * (1 - smoothstep(seg(u, 0.52, 0.62)))
            f.skip = max(f.skip, air)
            f.hipYOff += 12 * air
            let land = smoothstep(seg(u, 0.56, 0.68)) * e // 착지 — 양팔 뒤, 가슴 활짝, 홀드
            f.shoulderXOff -= 6 * land
            f.shoulderYOff += 3 * land
            f.headDyOff += 2.5 * land
            f.freeHandXOff -= 14 * land
            f.freeHandYOff -= 8 * land
            f.phiWobble += -1.2 * land // 클럽 팔도 뒤로
        case .tripleBeat:
            f.clubUpBlend = max(f.clubUpBlend, e * (1 - smoothstep(seg(u, 0.72, 0.84))))
            let beats = abs(sin(3 * .pi * seg(u, 0.08, 0.66))) // 3연타
            let inBeat = u > 0.08 && u < 0.66 ? 1.0 : 0.0
            f.phiWobble += -0.55 * beats * inBeat * e
            f.hipYOff -= 3.5 * beats * inBeat * e
            f.headDyOff -= 2 * beats * inBeat * e
            f.shoulder = max(f.shoulder, smoothstep(seg(u, 0.78, 0.9)) * e) // 마무리: 어깨에 척
            f.skip = max(f.skip, 0.5 * smoothstep(seg(u, 0.82, 0.92)) * e)
        case .scubaDance:
            f.hatTouch = max(f.hatTouch, e) // 자유손이 코로
            f.hipYOff += 3 * (1 - cos(8 * .pi * u)) / 2 * e // 바운스 4회
            f.hipXOff += 3 * sin(4 * .pi * u) * e
            f.phiWobble += 0.5 * sin(6 * .pi * u) * e // 클럽 부채질
            f.gripLift += 0.5 * e
            f.headDxOff += 2 * sin(4 * .pi * u) * e
        case .heelGroove:
            f.hipYOff += 2.2 * (1 - cos(16 * .pi * u)) / 2 * e // 8박 뒤꿈치 바운스
            f.freeHandXOff += 10 * sin(8 * .pi * u) * e // 팔 루프 (원 궤적)
            f.freeHandYOff += (12 + 10 * cos(8 * .pi * u)) * e
            f.shoulderYOff += 1.5 * sin(8 * .pi * u) * e
            f.headDxOff += 1.5 * sin(8 * .pi * u) * e
            f.skip = max(f.skip, 0.35 * e)
        case .dabPose:
            let snap = smoothstep(seg(u, 0.06, 0.16)) * (1 - smoothstep(seg(u, 0.82, 0.95)))
            f.headDyOff -= 4.5 * snap // 고개를 팔꿈치에 파묻고
            f.headDxOff += 2.5 * snap
            f.shoulderXOff += 4.5 * snap
            f.hatTouch = max(f.hatTouch, snap) // 자유팔이 얼굴 앞으로
            f.gripLift += snap // 클럽 팔은 사선 위로 쭉
            f.phiWobble += -1.1 * snap
        case .horseDance:
            let ride = e
            f.freeHandXOff += 15 * ride // 고삐 쥔 손 앞으로
            f.freeHandYOff += 7 * abs(sin(6 * .pi * u)) * ride
            f.hipYOff += 3.2 * (1 - cos(12 * .pi * u)) / 2 * ride // 말 타는 바운스 6박
            f.skip = max(f.skip, 0.5 * abs(sin(6 * .pi * u)) * ride)
            let lasso = smoothstep(seg(u, 0.5, 0.6)) * (1 - smoothstep(seg(u, 0.78, 0.9))) // 올가미
            f.freeHandYOff += 20 * lasso
            f.freeHandXOff += 8 * sin(10 * .pi * u) * lasso
            f.headDyOff += 1.5 * ride
        case .coffinMarch:
            f.shoulder = max(f.shoulder, e) // 클럽을 관처럼 어깨에
            f.hipYOff += 3 * (1 - cos(10 * .pi * u)) / 2 * e // 바운스 행진 5박
            f.headDxOff += 2 * sin(5 * .pi * u) * e
            f.shoulderYOff += 1.2 * sin(10 * .pi * u) * e
            f.skip = max(f.skip, 0.45 * abs(sin(5 * .pi * u)) * e)
        case .clubFlip:
            f.twirlAngle += 3 * .pi * smoothstep(seg(u, 0.12, 0.48)) // 1.5회전 던지기
            f.gripLift += smoothstep(seg(u, 0.05, 0.15)) * (1 - smoothstep(seg(u, 0.4, 0.52)))
            f.clubUpBlend = max(f.clubUpBlend, smoothstep(seg(u, 0.48, 0.58)) * e) // 수직 착지!
            let tada = smoothstep(seg(u, 0.62, 0.74)) * e // 짜잔
            f.freeHandYOff += 26 * tada
            f.freeHandXOff -= 6 * tada
            f.headDyOff += 2.5 * tada
            f.shoulderYOff += 2 * tada
        case .freezeFrame:
            // 동결 자체가 개그 — 걷던 자세 그대로 3초. 끝에만 살짝 두리번
            f.headDxOff += 3 * sin(4 * .pi * seg(u, 0.85, 1)) * smoothstep(seg(u, 0.85, 0.9))
        case .cheerSeesaw:
            let beat = sin(7 * .pi * seg(u, 0.05, 0.95)) // 시소 3.5박
            f.freeHandYOff += 16 * beat * e
            f.gripLift += 0.45 * (1 - beat) / 2 * e // 클럽 팔은 반대 위상
            f.phiWobble += 0.3 * -beat * e
            f.hipXOff += 3 * beat * e
            f.headDxOff += 1.8 * beat * e
            f.hipYOff += 1.5 * abs(beat) * e
        }
    }
}
