import Foundation

/// ═══════════════════════════════════════════════════════════════
/// 랜덤 걷기 모션 100종 (2026-08-15 사용자 요청 5번: "완전 창의적으로, 재밌게")
/// 각 모션 = WalkFlavor 채널들의 시간 엔벨로프 레시피. 발 접지 게이트는 건드리지 않는다.
/// 엔벨로프 어휘: bell(부드러운 in-hold-out) · wob2/3/F(2·3·5회 진동) · pulse2/3(봉우리 2·3개)
/// ═══════════════════════════════════════════════════════════════
enum WalkFlavorKind: CaseIterable {
    // ── 클럽 트월·곡예 (14) ──
    case twirl, twirlDouble, twirlReverse, twirlTriple, twirlHigh, twirlLow
    case wristRoll, clubRaise, clubTapShoulder, clubPoint, clubPointHold
    case clubBalance, clubConduct, clubHelicopter
    // ── 에어 골프·클럽 장난 (6) ──
    case airSwingMini, airPutt, clubInspect, clubSpinCatch, clubBat, clubSword
    // ── 머리·시선 (12) ──
    case lookBack, lookBackLong, lookSky, lookHole, headBob, headTilt
    case lookDown, doubleTake, nodYes, shakeNo, birdWatch, stargaze
    // ── 팔·손 (12) ──
    case hatTouch, armSwing, armSwingBig, fistPump, fistPumpDouble, wave, waveBig
    case airDrum, scratchHead, pointAhead, shadowBox, palmCheck
    // ── 상체·자세 (14) ──
    case shrug, slump, stretch, chestPuff, leanBack, leanForward, bowSlight
    case squatDip, squatDeep, torsoTwist, shoulderRoll, neckStretch, backArch, wiggle
    // ── 리듬·스텝 (16) ──
    case skip, skipJoy, hipSway, bounce, moonBounce, strut, shimmy, grooveNod
    case hopSmall, doubleHop, danceStep, waddle, springStep, tipToe, marchStep, slideGlide
    // ── 감정 표현 (14) ──
    case cheer, celebrate, facepalm, dejected, determined, nervous, whistle
    case yawn, laugh, grumble, psyched, zen, sneeze, hiccup
    // ── 관찰·잡동사니 (12) ──
    case butterflyWatch, windCheck, distanceScan, watchAdjust, kneeSlap, chinStroke
    case pocketPat, stumbleCatch, skyPoint, crowdWave, tada, bowFinish

    /// 클럽이 손에 있어야 하는 모션 (어깨 캐리 중 금지)
    var needsClub: Bool {
        switch self {
        case .twirl, .twirlDouble, .twirlReverse, .twirlTriple, .twirlHigh, .twirlLow,
             .wristRoll, .clubRaise, .clubTapShoulder, .clubPoint, .clubPointHold,
             .clubBalance, .clubConduct, .clubHelicopter,
             .airSwingMini, .airPutt, .clubInspect, .clubSpinCatch, .clubBat, .clubSword:
            true
        default:
            false
        }
    }

    var duration: Double {
        switch self {
        case .hopSmall: 0.5
        case .skip, .stumbleCatch: 0.7
        case .shrug, .sneeze: 0.9
        case .twirl, .twirlReverse, .headTilt, .doubleHop, .hiccup, .nodYes, .shakeNo: 1.0
        case .hatTouch, .wiggle, .kneeSlap, .pocketPat, .palmCheck: 1.1
        case .lookHole, .headBob, .wristRoll, .airPutt, .fistPump, .lookDown, .squatDip,
             .bounce, .springStep, .tada, .skyPoint:
            1.2
        case .lookBack, .shoulderRoll, .clubRaise, .clubPoint, .clubBalance, .leanBack,
             .leanForward, .torsoTwist, .grooveNod, .whistle, .determined, .nervous,
             .laugh, .grumble, .watchAdjust, .chinStroke:
            1.3
        case .lookSky, .hipSway, .clubTapShoulder, .doubleTake, .airSwingMini, .clubBat,
             .neckStretch, .backArch, .shimmy, .danceStep, .waddle, .psyched, .windCheck,
             .distanceScan, .crowdWave, .bowSlight, .twirlHigh, .twirlLow:
            1.4
        case .twirlDouble, .stretch, .chestPuff, .clubSpinCatch, .clubSword, .marchStep,
             .tipToe, .slideGlide:
            1.5
        case .armSwing, .slump, .skipJoy, .squatDeep, .yawn, .facepalm, .cheer, .strut,
             .fistPumpDouble, .clubInspect, .scratchHead, .airDrum, .shadowBox, .pointAhead,
             .bowFinish, .clubConduct:
            1.6
        case .armSwingBig, .waveBig, .clubHelicopter, .clubPointHold, .celebrate: 1.8
        case .twirlTriple, .moonBounce, .butterflyWatch, .dejected, .birdWatch: 2.0
        case .lookBackLong, .stargaze: 2.2
        case .zen: 2.4
        case .wave: 1.4
        }
    }

    /// 모션 레시피 — u: 정규화 진행 (트월 계열은 완료 후에도 호출되어 누적각 유지)
    func apply(u: Double, into f: inout WalkFlavor) {
        let ss = smoothstep(min(1, u))
        // 트월 계열: 되감기 없음 — u ≥ 1에서도 누적각을 남긴다
        switch self {
        case .twirl, .twirlLow:
            f.twirlAngle += 2 * .pi * ss
            if self == .twirlLow, u < 1 {
                f.hipYOff -= 2 * bellEnv(u) // 낮게 웅크리고 돌리기
            }
            return
        case .twirlDouble:
            f.twirlAngle += 4 * .pi * ss
            return
        case .twirlReverse:
            f.twirlAngle -= 2 * .pi * ss
            return
        case .twirlTriple:
            f.twirlAngle += 6 * .pi * ss
            return
        case .twirlHigh, .clubHelicopter:
            f.twirlAngle += (self == .clubHelicopter ? 4 : 2) * .pi * ss
            if u < 1 {
                f.gripLift += bellEnv(u) // 높이 들고 돌리는 헬리콥터
            }
            return
        default:
            break
        }
        guard u < 1 else { return }
        let bell = bellEnv(u)
        let wob2 = sin(4 * .pi * u) * bell
        let wob3 = sin(6 * .pi * u) * bell
        let wobF = sin(10 * .pi * u) * bell
        let pulse2 = abs(sin(2 * .pi * u)) * bell
        let pulse3 = abs(sin(3 * .pi * u)) * bell
        switch self {
        // 클럽 손짓
        case .wristRoll: f.phiWobble += 0.25 * wob2
        case .clubRaise: f.gripLift += bell; f.phiWobble += 0.35 * bell
        case .clubTapShoulder: f.gripLift += 0.8 * bell; f.phiWobble += 0.3 * wob2
        case .clubPoint: f.clubPointBlend = max(f.clubPointBlend, bell) // 전방 지목: "저기다"
        case .clubPointHold: f.clubPointBlend = max(f.clubPointBlend, bell) // 길게 겨눈다
        case .clubBalance: f.clubUpBlend = max(f.clubUpBlend, bell) // 수직 세워 균형 잡기
        case .clubConduct: f.gripLift += 0.5 * bell; f.phiWobble += 0.5 * wob3 // 오케스트라 지휘
        case .airSwingMini: // 걸으며 하는 미니 연습 스윙: 뒤로 감았다 앞으로
            f.gripLift += 0.4 * bell
            f.phiWobble += -1.1 * sin(.pi * min(1, u / 0.55)) * bell + (u > 0.55 ? 1.4 * bell * (u - 0.55) / 0.45 : 0)
        case .airPutt: f.phiWobble += 0.35 * wob2; f.headDyOff -= 1.5 * bell // 퍼팅 스트로크 흉내
        case .clubInspect: // 헤드를 눈앞에 들고 살핀다
            f.gripLift += bell
            f.clubPointBlend = max(f.clubPointBlend, 0.5 * bell)
            f.headDyOff -= 1.5 * bell
        case .clubSpinCatch: f.phiWobble += 1.5 * sin(2 * .pi * u) * bell // 반 바퀴 돌렸다 잡기
        case .clubBat: f.shoulderXOff -= 2 * bell; f.phiWobble += -0.8 * bell // 야구 타격 자세 장난
        case .clubSword: // 검처럼 겨누고 잔떨림
            f.clubPointBlend = max(f.clubPointBlend, bell)
            f.phiWobble += 0.08 * wobF
        // 머리·시선
        case .lookBack, .lookBackLong: f.lookBack = max(f.lookBack, bell)
        case .lookSky: f.headDxOff += 2 * bell; f.headDyOff += 3 * bell
        case .lookHole: f.headDxOff += 3.5 * bell
        case .headBob: f.headDxOff += 1.5 * sin(6 * .pi * u) * bell
        case .headTilt: f.headDyOff -= 2.5 * bell
        case .lookDown: f.headDyOff -= 3 * bell // 풀 관찰
        case .doubleTake: f.lookBack = max(f.lookBack, pulse2) // 봤다가, 다시 한 번
        case .nodYes: f.headDyOff += 1.5 * wob3
        case .shakeNo: f.headDxOff += 2 * wob3
        case .birdWatch: f.headDxOff += 3 * sin(.pi * u) * bell; f.headDyOff += 3 * bell // 새를 따라가는 시선
        case .stargaze: f.headDyOff += 3.5 * bell; f.shoulderYOff += bell // 별 구경
        // 팔·손
        case .hatTouch: f.hatTouch = max(f.hatTouch, bell)
        case .armSwing: f.armAmpBoost += 1.2 * bell
        case .armSwingBig: f.armAmpBoost += 2.2 * bell
        case .fistPump: f.freeHandYOff += 22 * bell; f.freeHandXOff += 4 * bell // 주먹 불끈
        case .fistPumpDouble: f.freeHandYOff += 20 * pulse2
        case .wave: f.freeHandYOff += 24 * bell; f.freeHandXOff += 5 * wob3 // 관객에게 인사
        case .waveBig: f.freeHandYOff += 26 * bell; f.freeHandXOff += 8 * wob2
        case .airDrum: f.freeHandYOff += 8 * bell + 6 * wobF // 에어 드럼
        case .scratchHead: f.hatTouch = max(f.hatTouch, bell); f.headDxOff += 0.8 * wobF // 머리 긁적
        case .pointAhead: f.freeHandXOff += 18 * bell; f.freeHandYOff += 8 * bell // 손가락 지목
        case .shadowBox: f.freeHandXOff += 10 * wobF; f.shoulderXOff += wob3 // 섀도복싱
        case .palmCheck: f.freeHandYOff += 10 * bell; f.headDyOff -= 1.5 * bell // 손금 보기
        // 상체·자세
        case .shrug: f.shoulderYOff += 2.5 * bell
        case .slump: f.shoulderYOff -= 2 * bell
        case .stretch:
            f.shoulderYOff += 1.5 * bell
            f.headDyOff += 2 * bell
            f.gripLift += 0.4 * bell
        case .chestPuff: // 가슴 활짝 — 으스대기
            f.shoulderYOff += 2.5 * bell
            f.shoulderXOff -= 1.5 * bell
            f.headDyOff += bell
        case .leanBack: f.shoulderXOff -= 3.5 * bell; f.headDyOff += 0.5 * bell
        case .leanForward: f.shoulderXOff += 3 * bell; f.headDyOff -= bell
        case .bowSlight: // 목례
            f.shoulderXOff += 2 * bell
            f.shoulderYOff -= 2.5 * bell
            f.headDyOff -= 2 * bell
        case .squatDip: f.hipYOff -= 4 * bell
        case .squatDeep: f.hipYOff -= 7 * bell
        case .torsoTwist: f.shoulderXOff += 2.5 * wob2
        case .shoulderRoll: f.shoulderYOff += 1.8 * wob2
        case .neckStretch: f.headDxOff += 2 * sin(2 * .pi * u) * bell; f.headDyOff += bell
        case .backArch: // 허리 젖혀 기지개
            f.shoulderXOff -= 2.5 * bell
            f.shoulderYOff += 1.5 * bell
            f.hipXOff += 2 * bell
        case .wiggle: f.hipXOff += 2 * wobF
        // 리듬·스텝
        case .skip, .hopSmall: f.skip = max(f.skip, bell)
        case .skipJoy: f.skip = max(f.skip, bell); f.freeHandYOff += 6 * bell
        case .hipSway: f.hipXOff += 2 * wob2
        case .bounce: f.hipYOff += 2 * (1 - cos(4 * .pi * u)) / 2 * bell
        case .moonBounce: // 달 위를 걷는 듯한 느린 큰 바운스
            f.hipYOff += 3 * (1 - cos(2 * .pi * u)) / 2 * bell
            f.skip = max(f.skip, 0.4 * bell)
        case .strut: // 으스대는 걸음
            f.shoulderYOff += 2 * bell
            f.hipXOff += 1.5 * wob2
            f.armAmpBoost += bell
        case .shimmy: f.shoulderXOff += 1.2 * wobF; f.shoulderYOff += 0.8 * wobF
        case .grooveNod: f.headDxOff += 1.5 * wob3; f.hipXOff += 1.5 * wob3 // 그루브 타기
        case .doubleHop: f.skip = max(f.skip, pulse2)
        case .danceStep: f.hipXOff += 2.5 * wob2; f.freeHandYOff += 6 * wob2
        case .waddle: f.hipXOff += 3 * wob3; f.shoulderXOff -= wob3 // 뒤뚱뒤뚱
        case .springStep: f.skip = max(f.skip, 0.5 * bell); f.hipYOff += 1.5 * bell
        case .tipToe: f.hipYOff += 2 * bell; f.skip = max(f.skip, 0.3 * bell) // 발끝 살금살금
        case .marchStep: f.armAmpBoost += 2 * bell; f.skip = max(f.skip, 0.4 * bell) // 행진
        case .slideGlide: f.armAmpBoost -= 0.6 * bell; f.shoulderXOff -= bell // 미끄러지듯 여유
        // 감정 표현
        case .cheer: // 환호
            f.freeHandYOff += 24 * bell
            f.headDyOff += 2 * bell
            f.skip = max(f.skip, 0.5 * bell)
        case .celebrate: f.freeHandYOff += 22 * pulse2; f.hipYOff += (1 - cos(4 * .pi * u)) / 2 * bell
        case .facepalm: // 아이고…
            f.hatTouch = max(f.hatTouch, bell)
            f.headDyOff -= 2.5 * bell
            f.shoulderYOff -= 1.5 * bell
        case .dejected: // 낙담 — 어깨도 팔도 축
            f.shoulderYOff -= 2.5 * bell
            f.headDyOff -= 3 * bell
            f.armAmpBoost -= 0.7 * bell
        case .determined: f.headDyOff += bell; f.freeHandYOff += 10 * bell; f.shoulderYOff += 1.5 * bell
        case .nervous: f.headDxOff += 2.5 * wobF; f.shoulderYOff += 0.5 * wobF // 안절부절 두리번
        case .whistle: f.headDyOff += 1.5 * bell; f.hipXOff += 1.2 * wob3 // 휘파람 스텝
        case .yawn: // 하품 — 손이 입으로, 고개 젖힘
            f.freeHandYOff += 16 * bell
            f.headDyOff += 2 * bell
            f.shoulderYOff += bell
        case .laugh: f.shoulderYOff += 1.2 * wobF; f.headDyOff += wobF // 어깨 들썩 웃음
        case .grumble: f.headDxOff += wob3; f.headDyOff -= 1.5 * bell; f.shoulderYOff -= bell
        case .psyched: f.skip = max(f.skip, 0.6 * bell); f.freeHandYOff += 12 * pulse3 // 신남 폭발
        case .zen: f.shoulderYOff += 1.5 * sin(.pi * u); f.headDyOff += sin(.pi * u) // 깊은 호흡
        case .sneeze: // 에취
            f.headDyOff -= 3 * bell
            f.shoulderXOff += 2 * bell
            f.hipYOff -= bell
        case .hiccup: f.hipYOff += 1.2 * pulse2; f.headDyOff += 0.8 * wob2
        // 관찰·잡동사니
        case .butterflyWatch: f.headDxOff += 3 * sin(2 * .pi * u) * bell; f.headDyOff += 2.5 * bell // 나비 쫓기
        case .windCheck: // 풀잎 던져 바람 읽기
            f.freeHandYOff += 20 * bell
            f.headDxOff += 2 * bell
            f.headDyOff += 2 * bell
        case .distanceScan: // 손차양으로 먼 곳 살피기
            f.freeHandYOff += 14 * bell
            f.freeHandXOff += 6 * bell
            f.headDyOff += bell
        case .watchAdjust: f.freeHandYOff += 12 * bell; f.headDyOff -= 2 * bell // 손목시계 확인
        case .kneeSlap: f.freeHandYOff -= 12 * bell; f.shoulderXOff += 2 * bell // 무릎 탁!
        case .chinStroke: f.hatTouch = max(f.hatTouch, 0.7 * bell); f.headDxOff += bell // 턱 쓰다듬기
        case .pocketPat: f.freeHandYOff -= 8 * pulse3 // 주머니 톡톡 (공 어디 갔지)
        case .stumbleCatch: // 살짝 비틀 — 그리고 아무 일 없었다는 듯
            f.hipXOff += 3 * bell * (1 - u)
            f.shoulderXOff += 3 * bell * (1 - u)
        case .skyPoint: // 하늘 지목 — 저 새 봐라
            f.freeHandXOff += 8 * bell
            f.freeHandYOff += 22 * bell
            f.headDyOff += 3 * bell
        case .crowdWave: f.freeHandYOff += 20 * sin(.pi * u) * bell; f.freeHandXOff += 10 * sin(2 * .pi * u) * bell
        case .tada: // 짜잔 — 양팔 펼치기
            f.freeHandXOff -= 6 * bell
            f.freeHandYOff += 8 * bell
            f.shoulderYOff += 2 * bell
        case .bowFinish: // 갤러리를 향한 정중한 인사
            f.shoulderXOff += 3 * bell
            f.shoulderYOff -= 3 * bell
            f.headDyOff -= 2.5 * bell
        // 트월 계열은 첫 번째 switch에서 처리 후 return — default 없이 명시해 새 케이스
        // 추가 시 컴파일러가 레시피 누락을 잡아준다 (리뷰 S-3)
        case .twirl, .twirlLow, .twirlDouble, .twirlReverse, .twirlTriple, .twirlHigh,
             .clubHelicopter:
            break
        }
    }

    /// 부드러운 in-hold-out 종 모양 (0.3 경사)
    private func bellEnv(_ u: Double) -> Double {
        smoothstep(min(1, min(u, 1 - u) / 0.3))
    }
}
