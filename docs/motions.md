# 걷기 랜덤 모션 카탈로그 (100종)

<img src="motions.gif" alt="걷는 동안 랜덤으로 발동하는 잔동작 — 실제 플레이" width="620">

스틱맨이 공을 향해 걷는 동안 확률적으로 발동하는 잉여 동작 전체 목록.
모든 모션은 `WalkFlavors.swift`의 채널 엔벨로프 레시피로 정의되며, 발 접지 게이트(노슬립)는
건드리지 않는다. 진폭은 `boostMotion(1.7)`로 일괄 증폭 (2026-08-20 사용자 판정 "동작이
완전 커야" — 오프셋 채널만, 트월 회전수·기능 포즈는 보존). GIF는 `--demo-motions` 시연 모드에서 실플레이를 프레임 캡처해 스틱맨 추적 크롭으로 조립한 것.

발동 규칙: 걷기당 최대 5개, 겹치지 않게 스케줄. 어깨 캐리 중엔 클럽 모션 금지.
별개로 아주 가끔(1~2%) [철푸덕 넘어지기](qa-report-2026-08-15.md)가 있다.

## 쇼피스 밈 모션 (12) — 걷기를 멈추고 춘다

잔동작과 달리 **걸음을 서서히 멈추고**(트립과 같은 연속 동결 램프) 2~3초 크게 추는
희귀 이벤트. 걷기가 넉넉할 때 8%, 걷기당 최대 1개, 트립·잔동작과 겹치지 않는다.
밈 리서치(2026-08) 기반 — 실루엣 판독성과 골프 클럽 시너지 우선, 동작은 오마주 수준으로
추상화(특정 게임 이모트 명칭 미사용). 시연: `--demo-memes`(12종 순환).

| 모션 | 설명 | 모습 |
|---|---|---|
| whiffSpin | 헛스윙 개그 — 진지한 어드레스, 헛스윙, 아무렇지 않게 잔댄스 | <img src="motions/whiffSpin.gif" width="240"> |
| auraFarm | 아우라 파밍 — 클럽 짚고 낮게, 스윕마다 정지 홀드 | <img src="motions/auraFarm.gif" width="240"> |
| siuJump | 도약 세리머니 — 웅크림, 점프, 양팔 뒤로 착지 홀드 | <img src="motions/siuJump.gif" width="240"> |
| tripleBeat | 퉁퉁퉁 — 클럽 수직 3연타 찍기, 마무리는 어깨에 척 | <img src="motions/tripleBeat.gif" width="240"> |
| scubaDance | 스쿠버 — 한 손 코 막고 바운스, 클럽 부채질 | <img src="motions/scubaDance.gif" width="240"> |
| heelGroove | 힐 그루브 — 뒤꿈치 바운스 8박 + 자유팔 루프 | <img src="motions/heelGroove.gif" width="240"> |
| dabPose | 댑 — 스냅으로 고개 파묻고 클럽 팔 사선 홀드 | <img src="motions/dabPose.gif" width="240"> |
| horseDance | 말춤 — 양손 고삐 바운스 + 올가미 (K-클래식) | <img src="motions/horseDance.gif" width="240"> |
| coffinMarch | 관짝 행진 — 클럽 어깨에 메고 제자리 바운스 | <img src="motions/coffinMarch.gif" width="240"> |
| clubFlip | 클럽 플립 — 던져서 수직 착지, 짜잔 | <img src="motions/clubFlip.gif" width="240"> |
| freezeFrame | 마네킹 — 걷다가 완전 정지 3초, 끝에 두리번 | <img src="motions/freezeFrame.gif" width="240"> |
| cheerSeesaw | 응원 시소 — 양손 교대 상하 + 힙 리듬 (삐끼삐끼풍) | <img src="motions/cheerSeesaw.gif" width="240"> |

## 클럽 트월·곡예 (14)

| 모션 | 설명 | 모습 |
|---|---|---|
| twirl | 클럽 한 바퀴 트월 | <img src="motions/twirl.gif" width="240"> |
| twirlDouble | 두 바퀴 트월 | <img src="motions/twirlDouble.gif" width="240"> |
| twirlReverse | 역방향 트월 | <img src="motions/twirlReverse.gif" width="240"> |
| twirlTriple | 세 바퀴 — 곡예급 | <img src="motions/twirlTriple.gif" width="240"> |
| twirlHigh | 높이 들고 트월 | <img src="motions/twirlHigh.gif" width="240"> |
| twirlLow | 낮게 웅크려 트월 | <img src="motions/twirlLow.gif" width="240"> |
| wristRoll | 손목 까딱까딱 | <img src="motions/wristRoll.gif" width="240"> |
| clubRaise | 클럽 살짝 들기 | <img src="motions/clubRaise.gif" width="240"> |
| clubTapShoulder | 어깨에 톡톡 | <img src="motions/clubTapShoulder.gif" width="240"> |
| clubPoint | 전방 지목 — "저기다" | <img src="motions/clubPoint.gif" width="240"> |
| clubPointHold | 길게 겨눈다 | <img src="motions/clubPointHold.gif" width="240"> |
| clubBalance | 수직으로 세워 균형 잡기 | <img src="motions/clubBalance.gif" width="240"> |
| clubConduct | 오케스트라 지휘 | <img src="motions/clubConduct.gif" width="240"> |
| clubHelicopter | 헬리콥터 — 들고 두 바퀴 | <img src="motions/clubHelicopter.gif" width="240"> |

## 에어 골프·클럽 장난 (6)

| 모션 | 설명 | 모습 |
|---|---|---|
| airSwingMini | 걸으며 미니 연습 스윙 | <img src="motions/airSwingMini.gif" width="240"> |
| airPutt | 퍼팅 스트로크 흉내 | <img src="motions/airPutt.gif" width="240"> |
| clubInspect | 헤드를 눈앞에 들고 살핀다 | <img src="motions/clubInspect.gif" width="240"> |
| clubSpinCatch | 반 바퀴 돌렸다 잡기 | <img src="motions/clubSpinCatch.gif" width="240"> |
| clubBat | 야구 타격 자세 장난 | <img src="motions/clubBat.gif" width="240"> |
| clubSword | 검처럼 겨누기 (잔떨림) | <img src="motions/clubSword.gif" width="240"> |

## 머리·시선 (12)

| 모션 | 설명 | 모습 |
|---|---|---|
| lookBack | 뒤돌아보기 | <img src="motions/lookBack.gif" width="240"> |
| lookBackLong | 오래 뒤돌아보기 | <img src="motions/lookBackLong.gif" width="240"> |
| lookSky | 하늘 보기 | <img src="motions/lookSky.gif" width="240"> |
| lookHole | 홀 쪽 응시 | <img src="motions/lookHole.gif" width="240"> |
| headBob | 머리 까딱까딱 | <img src="motions/headBob.gif" width="240"> |
| headTilt | 갸웃 | <img src="motions/headTilt.gif" width="240"> |
| lookDown | 풀 관찰 | <img src="motions/lookDown.gif" width="240"> |
| doubleTake | 봤다가, 다시 한 번 | <img src="motions/doubleTake.gif" width="240"> |
| nodYes | 끄덕끄덕 | <img src="motions/nodYes.gif" width="240"> |
| shakeNo | 절레절레 | <img src="motions/shakeNo.gif" width="240"> |
| birdWatch | 새를 따라가는 시선 | <img src="motions/birdWatch.gif" width="240"> |
| stargaze | 별 구경 | <img src="motions/stargaze.gif" width="240"> |

## 팔·손 (12)

| 모션 | 설명 | 모습 |
|---|---|---|
| hatTouch | 모자 만지기 | <img src="motions/hatTouch.gif" width="240"> |
| armSwing | 팔 스윙 크게 | <img src="motions/armSwing.gif" width="240"> |
| armSwingBig | 팔 스윙 아주 크게 | <img src="motions/armSwingBig.gif" width="240"> |
| fistPump | 주먹 불끈 | <img src="motions/fistPump.gif" width="240"> |
| fistPumpDouble | 주먹 두 번 | <img src="motions/fistPumpDouble.gif" width="240"> |
| wave | 손 흔들기 — 관객 인사 | <img src="motions/wave.gif" width="240"> |
| waveBig | 크게 흔들기 | <img src="motions/waveBig.gif" width="240"> |
| airDrum | 에어 드럼 | <img src="motions/airDrum.gif" width="240"> |
| scratchHead | 머리 긁적 | <img src="motions/scratchHead.gif" width="240"> |
| pointAhead | 손가락 지목 | <img src="motions/pointAhead.gif" width="240"> |
| shadowBox | 섀도복싱 | <img src="motions/shadowBox.gif" width="240"> |
| palmCheck | 손금 보기 | <img src="motions/palmCheck.gif" width="240"> |

## 상체·자세 (14)

| 모션 | 설명 | 모습 |
|---|---|---|
| shrug | 으쓱 | <img src="motions/shrug.gif" width="240"> |
| slump | 축 처짐 | <img src="motions/slump.gif" width="240"> |
| stretch | 기지개 | <img src="motions/stretch.gif" width="240"> |
| chestPuff | 가슴 활짝 — 으스대기 | <img src="motions/chestPuff.gif" width="240"> |
| leanBack | 뒤로 젖히기 | <img src="motions/leanBack.gif" width="240"> |
| leanForward | 앞으로 기울기 | <img src="motions/leanForward.gif" width="240"> |
| bowSlight | 목례 | <img src="motions/bowSlight.gif" width="240"> |
| squatDip | 살짝 스쿼트 | <img src="motions/squatDip.gif" width="240"> |
| squatDeep | 깊은 스쿼트 | <img src="motions/squatDeep.gif" width="240"> |
| torsoTwist | 몸통 비틀기 | <img src="motions/torsoTwist.gif" width="240"> |
| shoulderRoll | 어깨 돌리기 | <img src="motions/shoulderRoll.gif" width="240"> |
| neckStretch | 목 스트레칭 | <img src="motions/neckStretch.gif" width="240"> |
| backArch | 허리 젖혀 기지개 | <img src="motions/backArch.gif" width="240"> |
| wiggle | 옴찔옴찔 | <img src="motions/wiggle.gif" width="240"> |

## 리듬·스텝 (16)

| 모션 | 설명 | 모습 |
|---|---|---|
| skip | 폴짝 | <img src="motions/skip.gif" width="240"> |
| skipJoy | 신나는 폴짝 | <img src="motions/skipJoy.gif" width="240"> |
| hipSway | 힙 흔들기 | <img src="motions/hipSway.gif" width="240"> |
| bounce | 통통 바운스 | <img src="motions/bounce.gif" width="240"> |
| moonBounce | 달 위를 걷듯 느린 큰 바운스 | <img src="motions/moonBounce.gif" width="240"> |
| strut | 으스대는 걸음 | <img src="motions/strut.gif" width="240"> |
| shimmy | 어깨 셔플 | <img src="motions/shimmy.gif" width="240"> |
| grooveNod | 그루브 타기 | <img src="motions/grooveNod.gif" width="240"> |
| hopSmall | 짧은 홉 | <img src="motions/hopSmall.gif" width="240"> |
| doubleHop | 두 번 홉 | <img src="motions/doubleHop.gif" width="240"> |
| danceStep | 댄스 스텝 | <img src="motions/danceStep.gif" width="240"> |
| waddle | 뒤뚱뒤뚱 | <img src="motions/waddle.gif" width="240"> |
| springStep | 스프링 스텝 | <img src="motions/springStep.gif" width="240"> |
| tipToe | 발끝 살금살금 | <img src="motions/tipToe.gif" width="240"> |
| marchStep | 행진 | <img src="motions/marchStep.gif" width="240"> |
| slideGlide | 미끄러지듯 여유롭게 | <img src="motions/slideGlide.gif" width="240"> |

## 감정 표현 (14)

| 모션 | 설명 | 모습 |
|---|---|---|
| cheer | 환호 | <img src="motions/cheer.gif" width="240"> |
| celebrate | 자축 세리머니 | <img src="motions/celebrate.gif" width="240"> |
| facepalm | 아이고… | <img src="motions/facepalm.gif" width="240"> |
| dejected | 낙담 | <img src="motions/dejected.gif" width="240"> |
| determined | 각오 다지기 | <img src="motions/determined.gif" width="240"> |
| nervous | 안절부절 두리번 | <img src="motions/nervous.gif" width="240"> |
| whistle | 휘파람 스텝 | <img src="motions/whistle.gif" width="240"> |
| yawn | 하품 | <img src="motions/yawn.gif" width="240"> |
| laugh | 어깨 들썩 웃음 | <img src="motions/laugh.gif" width="240"> |
| grumble | 구시렁 | <img src="motions/grumble.gif" width="240"> |
| psyched | 신남 폭발 | <img src="motions/psyched.gif" width="240"> |
| zen | 깊은 호흡 | <img src="motions/zen.gif" width="240"> |
| sneeze | 에취 | <img src="motions/sneeze.gif" width="240"> |
| hiccup | 딸꾹질 | <img src="motions/hiccup.gif" width="240"> |

## 관찰·잡동사니 (12)

| 모션 | 설명 | 모습 |
|---|---|---|
| butterflyWatch | 나비 쫓는 시선 | <img src="motions/butterflyWatch.gif" width="240"> |
| windCheck | 풀잎 던져 바람 읽기 | <img src="motions/windCheck.gif" width="240"> |
| distanceScan | 손차양으로 먼 곳 살피기 | <img src="motions/distanceScan.gif" width="240"> |
| watchAdjust | 손목시계 확인 | <img src="motions/watchAdjust.gif" width="240"> |
| kneeSlap | 무릎 탁! | <img src="motions/kneeSlap.gif" width="240"> |
| chinStroke | 턱 쓰다듬기 | <img src="motions/chinStroke.gif" width="240"> |
| pocketPat | 주머니 톡톡 (공 어디 갔지) | <img src="motions/pocketPat.gif" width="240"> |
| stumbleCatch | 살짝 비틀 — 아무 일 없었다는 듯 | <img src="motions/stumbleCatch.gif" width="240"> |
| skyPoint | 하늘 지목 — 저 새 봐라 | <img src="motions/skyPoint.gif" width="240"> |
| crowdWave | 갤러리 웨이브 | <img src="motions/crowdWave.gif" width="240"> |
| tada | 짜잔 — 양팔 펼치기 | <img src="motions/tada.gif" width="240"> |
| bowFinish | 정중한 인사 | <img src="motions/bowFinish.gif" width="240"> |
