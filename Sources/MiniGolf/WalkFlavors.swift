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
        case .waveBig: f.freeHandYOff += 32 * bell; f.freeHandXOff += 12 * wob2
        case .airDrum: f.freeHandYOff += 8 * bell + 6 * wobF // 에어 드럼
        case .scratchHead: f.hatTouch = max(f.hatTouch, bell); f.headDxOff += 0.8 * wobF // 머리 긁적
        case .pointAhead: f.freeHandXOff += 18 * bell; f.freeHandYOff += 8 * bell // 손가락 지목
        case .shadowBox: f.freeHandXOff += 17 * wobF; f.freeHandYOff += 6 * abs(wobF); f.shoulderXOff += 2 * wob3; f
            .skip = max(
                f.skip,
                0.25 * bell
            ) // 섀도복싱
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
        case .wiggle: f.hipXOff += 3.5 * wobF; f.shoulderXOff += 0.8 * wobF
        // 리듬·스텝
        case .skip, .hopSmall: f.skip = max(f.skip, bell)
        case .skipJoy: f.skip = max(f.skip, bell); f.freeHandYOff += 14 * bell; f.hipYOff += 1.2 * pulse2
        case .hipSway: f.hipXOff += 3.5 * wob2; f.shoulderXOff -= 0.8 * wob2
        case .bounce: f.hipYOff += 2 * (1 - cos(4 * .pi * u)) / 2 * bell
        case .moonBounce: // 달 위를 걷는 듯한 느린 큰 바운스
            f.hipYOff += 5 * (1 - cos(2 * .pi * u)) / 2 * bell
            f.skip = max(f.skip, 0.7 * bell)
        case .strut: // 으스대는 걸음
            f.shoulderYOff += 2 * bell
            f.hipXOff += 1.5 * wob2
            f.armAmpBoost += bell
        case .shimmy: f.shoulderXOff += 2.2 * wobF; f.shoulderYOff += 1.5 * wobF; f.hipXOff += 1.5 * wobF
        case .grooveNod: f.headDxOff += 1.5 * wob3; f.hipXOff += 1.5 * wob3 // 그루브 타기
        case .doubleHop: f.skip = max(f.skip, pulse2)
        case .danceStep: f.hipXOff += 4.5 * wob2; f.freeHandYOff += 12 * wob2; f.skip = max(f.skip, 0.3 * bell)
        case .waddle: f.hipXOff += 3 * wob3; f.shoulderXOff -= wob3 // 뒤뚱뒤뚱
        case .springStep: f.skip = max(f.skip, 0.5 * bell); f.hipYOff += 1.5 * bell
        case .tipToe: f.hipYOff += 2 * bell; f.skip = max(f.skip, 0.3 * bell) // 발끝 살금살금
        case .marchStep: f.armAmpBoost += 2 * bell; f.skip = max(f.skip, 0.4 * bell) // 행진
        case .slideGlide: f.armAmpBoost -= 0.6 * bell; f.shoulderXOff -= bell // 미끄러지듯 여유
        // 감정 표현
        case .cheer: // 환호
            f.freeHandYOff += 32 * bell
            f.headDyOff += 3 * bell
            f.skip = max(f.skip, 0.8 * bell)
        case .celebrate: f.freeHandYOff += 30 * pulse2; f.hipYOff += 2.2 * (1 - cos(4 * .pi * u)) / 2 * bell; f
            .skip = max(
                f.skip,
                0.4 * bell
            )
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
        case .psyched: f.skip = max(f.skip, bell); f.freeHandYOff += 20 * pulse3; f.hipYOff += 1.5 * pulse3 // 신남 폭발
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
            f.freeHandXOff += 10 * bell
            f.freeHandYOff += 28 * bell
            f.headDyOff += 4 * bell
        case .crowdWave: f.freeHandYOff += 27 * sin(.pi * u) * bell; f.freeHandXOff += 14 * sin(2 * .pi * u) * bell; f
            .hipYOff += 1.2 * abs(sin(2 * .pi * u)) * bell
        case .tada: // 짜잔 — 양팔 펼치기
            f.freeHandXOff -= 9 * bell
            f.freeHandYOff += 14 * bell
            f.shoulderYOff += 3 * bell
            f.headDyOff += 1.5 * bell
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
