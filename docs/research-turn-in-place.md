# 리서치 — 측면 2D 스틱맨의 제자리 돌기(turn in place) (2026-09-23)

## 결론

2~3걸음 걸리는 실제 사람의 180° 돌기를 게임용으로 압축해 **2걸음 스텝 턴, 총 0.6~0.75초**로 만든다. 근거는 Prince of Persia(1989)의
제자리 돌기가 **8프레임(12fps ≈ 0.67초)** 이라는 원본 소스 확인과, 건강한 성인의 180° 돌기가 **1.8~2.5초에 2~3걸음**이라는 보행 연구.
순서는 여러 출처가 같다: **머리·시선 → 몸통 → 골반 → 발**. 측면 전용 스틱맨(정면 뷰 없음)에서 중요한 두 조치(추정): ① 좌우 반전은
**실루엣이 가장 좁은 프레임**(팔이 몸통에 붙고 무릎이 거의 펴진 순간)에 ② IK 무릎 굽힘 방향도 그 프레임에서만 뒤집는다.

게임 반영(GameScene `WalkAnim.TurnPlan`·`turnRig`): 여운 0.3s 뒤 0.65s — 예고 15%(머리 선행·축발 쪽 체중) → 구 뒷발이 새 방향으로
5px 내딛기 30% → 반전(미러·발 정체 교환, 힙 2px 다운) → 구 앞발(축발) 반 걸음 30% → 정착 15%. 끝난 스탠스 = 걷기 시작 스탠스(−11·+16)라
게이트 진입 점프 0. 관찰 `--demo-turn`(첫 샷을 뒤로 22m) + `TURN start/flip` 로그.

## 범위와 방법

웹 리서치(general-purpose 서브에이전트, 최신 Opus로 해석됨; 검색 ~20회·페이지 ~15회). 1차 자료: PoP Apple II 원본 소스(Mechner GitHub),
SDLPoP 포트 소스, 보행 생체역학 논문. 2차: Game Anim·animotionx·Little Polygon·WeaverDev. 접속 실패(403)로 검색 요약에만 의존한 항목은
한계 절에 표시.

## 주요 주장별 출처

| 주장 | 근거 | 출처 | 신뢰도 |
|---|---|---|---|
| PoP 제자리 돌기 = 8프레임, 반전은 1프레임째, 마지막 3프레임 정착 | `SEQTABLE.S` `turn`: aboutface → 45~52 → stand | [jmechner/Prince-of-Persia-Apple-II](https://github.com/jmechner/Prince-of-Persia-Apple-II) (1989 코드, 2012 공개) · [SDLPoP seqtbl.c](https://github.com/NagyD/SDLPoP) | 확실(같은 계보 2출처) |
| 재생 12fps(전투 10fps) → 0.53~0.67초 | 역어셈블리 기반 커뮤니티 자료 | [TASVideos PoP](https://tasvideos.org/GameResources/DOS/PrinceOfPersia) · Mechner 일지 "15fps" 인용(단일) | 참고 |
| 실제 180° 돌기 1.8~2.5초, 2~3걸음 | 관성 센서·대조군 실측 | [PubMed 19964471](https://pubmed.ncbi.nlm.nih.gov/19964471/) (2009) · [Hollands 2010](https://doi.org/10.1177/1545968309348508) | 확실(2출처) |
| 머리 → 몸통 → 골반 → 발 순서, 눈이 접지 ~400ms 전 | 생체역학 3편 + 애니 튜토리얼 | [Sensors 2021](https://doi.org/10.3390/s21082827) · [Gait & Posture 2005](https://pubmed.ncbi.nlm.nih.gov/16139746/) · PMC7739666(2020) | 확실(3출처) |
| spin(피벗) vs step(반대발 내딛기) — step이 지지 기반 넓고 협응 부담 작음 | Hase & Stein 1999, Taylor 2005 | [J Neurophysiol 1999](https://journals.physiology.org/doi/full/10.1152/jn.1999.81.6.2914) · [PubMed 16129503](https://pubmed.ncbi.nlm.nih.gov/16129503/) | 확실(2출처) |
| 절차적 turn-in-place: 2~3걸음을 IK로 투영, 발이 home에서 벗어나면 스텝, 오버슈트 착지 | UE Fab 상품 설명·WeaverDev 튜토리얼 | 검색 요약만 | 참고 |

## 권고 (우리 조건: 70px 스틱맨·측면 전용·2-bone IK 다리·StopPlan)

- 총 0.65초(0.55~0.75). 단계 비율 예고 15% / 1걸음 30% / 반전 10% / 2걸음 30% / 정착 15%.
- 기본은 step turn. 교차 피벗은 '휙 도는' 연출에만(0.4~0.5초).
- 힙 순이동 ≤ ±3px, 반전 즈음 힙 2px 다운. 머리 선행 1~2px는 70px에서 안 읽히니 2.5배 과장(→ 6px 적용).
- 측면 전용 단서 우선순위: 무릎 굽힘 방향 뒤집힘(펴진 순간에만) > 머리 선행 > 중간 프레임 실루엣 폭 축소 > 팔 스윙 위상 리셋 > 첫 걸음이 새 방향.

## 한계와 공백

- PoP 45~52 프레임의 실제 모습(정면 통과 실루엣 여부)은 미확인. Flashback·Another World 프레임 수 미확인. 12fps는 커뮤니티 자료, 15fps는 단일 출처.
- "2~3걸음, 2초 미만"·3.2±0.7걸음은 검색 요약(PMC 원문 접속 실패). Animation Mentor·Hase & Stein 본문·Sensors 부위별 지연(ms)·Fab 설명은 403.
- 측면 2D 스틱맨의 절차적 제자리 돌기 공개 코드는 없음 — 단계·비율·px는 조합 추정이라 `--demo-turn` 프레임 캡처로 검증한다.
- 게임의 1/3 압축 비율 근거는 PoP 하나뿐.
