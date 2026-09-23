# HANDOFF.md

## 현재 상태 (2026-09-23 — v0.8.1 릴리스 뒤 백로그 4종 + 서프라이즈 3차 리뷰 반영(1c56c86) main 머지. v0.8.2 미배포 — 판정·릴리스 확인 대기)

v0.6.0 릴리스 뒤 **서프라이즈 2차**(사용자 선택 "계열별 1종, 5종")를 `feature/surprises-2`에 구현하고 Code Reviewer(critical 0·major 1·
minor 6·nit 5) 반영 후 main에 머지했다. 창 터널(데스크탑·epic)·핀 이동(규칙·rare)·공 바꿔치기(물리·rare)·갤러리(스틱맨·common)·
거위 떼(생물·common). 종류는 12개가 됐지만 라운드 상한 5는 그대로. 검증: build 경고 0·lint·test 56(신규 4) + `--demo --surprise KIND`
강제 발동 프레임 캡처 5종 + `--demo-restart-in` 인터럽트 3종. `make app`으로 dist/MiniGolf.app 재빌드됨(미서명 로컬용).
이해도 확인 페이지(1차 설계 아티팩트, 5절이 서프라이즈): https://claude.ai/code/artifact/a235d28e-bc9c-47e9-9c22-111744b4ff2a

- [x] ③ 관절 뼈대 — `GolfCore/TwoBoneIK`(Juckett 해석해+pole+tanh 소프트닝) + `MiniGolf/Skeleton`
      (점 리그 유지, 렌더 직전 뼈 길이 강제: 몸통 25·팔 17.5+17.5·다리 23.25+23.25). 의식 2종 재작성
- [x] ② 걷기 속도 — `GolfCore/WalkProfile` 램프 0.9s·등속·램프 1.1s. 실측 정점/평균 1.04~1.09(구 1.5)
- [x] ① 전환 — 원점 통일(걷기 출발·도착 = 몸 자리) + StopPlan(마지막 두 걸음 발자국 계획) +
      setFacing(방향 반전 미러 보정). 실측 출발 힙 1.3px/frame·발 0.5(구 40px), 도착 힙 0.4·발 0.0(구 25px)
- [x] ①②③ Code Reviewer 반영 후 **main 머지 완료**(b25a10e) + 핫픽스 58d72da(발 교환 배타성 크래시)
- [x] ④ 모션 37종 재설계 — `feature/motion-redesign` (WalkFlavors 전면 교체: 극좌표 손 목표·샤프트 각·
      jump/heelLift·gait 보폭/정지 수정자·가중치 랜덤). `--demo-motions` 37종 전부 시연·시트 확인, 크래시 0.
      카탈로그 docs/motions.md(GIF 재캡처 예정), README·CHANGELOG(v0.5.0 미배포) 갱신. 리뷰 위임 중
- [x] ④ 리뷰 반영·main 머지(cd315d2). 사용자 플레이 판정 "90대 할아버지 자세" → 교정(722b750: 스윙 팔 원근 호 복귀·
      다리 45·진자 팔·클럽 옆 들기) → "스윙 때 뒤로 쏠림" → 교정(aab3dd3: 투영 모드 힙 하강 금지) → 프로 실측 반영(0313eb6)
- [x] **프로 스윙 키포인트**(사용자 제안): 로리 매킬로이 아이언 face-on 영상 → MediaPipe → P-System 키프레임·템포
      갱신. 도구 refs/video/tools, 문서 docs/research-swing-keypoints.md. 핵심: 톱에서 몸이 뒤로 흔들리지 않음, 임팩트
      머리 공 뒤, 팔로 척추 타깃 반대 유지, 피니시 손 머리 뒤
- [x] **선수별 스윙 스타일 3종 1단계**(f96f675): 로리·타이거·브라이슨 × 드라이버/아이언 6편 실측 → SwingKeyframes 6세트,
      ⛳️ 메뉴 "스윙 스타일"(UserDefaults `swingStyle`), --style 플래그. 편차 1.3배 과장. 문서 docs/research-swing-styles.md
- [x] 사용자 판정 "3개 차이를 모르겠다" → 과장 2.5배 + 템포 과장 + 타이거 톱 홀드(SwingKeyframes.topHold) 적용
- [x] **선수 트레이드마크 연출** (`feature/swing-trademarks` 4470f6b, 리서치 docs/research-swing-styles.md §트레이드마크):
      타이거 — 굿샷(미스힛<0.12·파워≥45%, `lastShotGood`) 뒤 리코일→그립 축 트월(`trademarkTwirl`, clubRate 40)·
      버디 이상 어퍼컷(코킹→펀치, 이글 이상 두 번, `uppercutActive`면 rigRate 16) · 브라이슨 — 팔 직선 렌더
      (`Skeleton.solve(straightArms:)`)·드라이버 테이크어웨이 힌지 19°·암록 퍼터(`PutterKeyframes.armLock` 길이 43·
      `Rig.butt` 10·샤프트=전완) · 로리 — 임팩트 점프 8px(`applyImpactJump`)·피니시 리코일(`applyFinishRecoil`).
      부수 수정: 탭인 홀아웃 반응이 퍼터 스윙 애니 상한(0.83s) 때문에 0.3s 늦던 문제(전 스타일). "브라이슨 긴 톱 홀드"는
      출처가 없어 제외
- [x] Code Reviewer 반영(e1955b8: 트월 고속 추적 스핀 창 한정·암록 연장부 .surprise/.end 유지·어퍼컷 종료 페이드) → main 머지 → `make app`.
      보류: 기권·워터 경로의 리코일 포즈 잔존(해제 시 클럽 재감기 스냅이 더 나쁨), 칩인 시 트월+어퍼컷 동시(의도), UPPER 로그 60Hz
- [x] 사용자 플레이 판정 1차(2026-09-15): "드라이버 외 어드레스가 뒤로 기울고 걸을 때도" → 백스윙 머리 클램프(≥+1)·척추 후방 휨
      2.5→0.8px(eccf119, `--club ID` 관찰 플래그). 원인: 조준 화면은 heightPct(기본 0.6, 리셋 안 됨)의 백스윙 프리뷰라 타이거 아이언
      톱 머리 −5.2가 뒤로 기운 어깨 위에 얹혔고, 척추 휨+무릎 전방 굽힘(힙 42~43.5·다리 45 → 6~8px)이 걷기까지 뒤로 기운 실루엣을 만들었다.
      사용자 "좋아" 판정. 남은 조정 후보: 아이언·웨지 백스윙 tilt 자체 축소(드라이버 유지)
- [x] **트레이드마크·2.5배 판정** (2026-09-23): "읽히긴 하는데 차이가 많이 나 보이지 않음" → 사용자 선택 트레이드마크 강화(e2c2afa):
      로리 점프 8→12(로그 lift 9.6), 타이거 트월 파워 문턱 0.45→0.3, 브라이슨 암록 butt 10→14. **타이거 아이언·웨지 tilt**: "세컨샷부터
      어프로치샷이 과도하게 몸 자체가 기울어져 부자연" → tilt 채널만 과장 2.5→1.0(기본 대비 편차 ×0.4, 임팩트 −31.5→−24.0), 드라이버 유지.
      PosesTests 대역 통과·`--club 7I` 프레임 확인. 교훈: 과장은 채널별 — 척추 기울기는 짧은 클럽에서 작게(메모리 갱신)
- [x] **2단계 웨지·퍼터 실측** (`feature/swing-stage2`): 퍼터 3인 실측(PutterKeyframes rory/tiger/bryson + ballFwd 6/6/16, 손 각은
      헤드=공 뒤 5px 수치 해), 웨지 로리·타이거 실측 + 브라이슨 유도(brysonWedge). wedge 프로파일 topScale·finishScale 0.72→1.0.
      브라이슨 정면 풀웨지 영상은 6편 탐색 모두 불가(TV 줌·후방 뷰·칩샷). 문서 docs/research-swing-styles.md §2단계, 도구 refs/video/README
      리뷰(Code Reviewer, minor 3·nit 5, 블로커 0) 반영: startHole renderBallFwd 스냅·armLockPutter 플래그 제거·도구 방어 코드.
      수용한 잔여: 걷기 도착 중 ⛳️ 스타일 전환 시 퍼터 스탠스 차(최대 10px)가 스무딩으로만 흡수됨. 후속 제안이던 포즈 불변식 테스트는
      2026-09-16 `Tests/MiniGolfTests/PosesTests.swift`로 구현(아래 품질 부채 항목)
- [x] **v0.5.0 릴리스** (2026-09-15): 066f399 버전 범프 → `make zip` → gh release v0.5.0(zip 639,625B, SHA 181bb4cd…) → 공개 에셋 SHA 재검증
      일치 → homebrew-tap b1cfaca(version·sha256) push. README 모션 GIF 표(구 100종 이름)는 두 번째 디스플레이가 없어 재캡처 못 함
- [x] **README 모션 GIF 재캡처** (c9b2810): `--demo-bg` 덕에 주 화면에서 캡처. 스크래치패드 capture_motions.py(MOTION/SHOWPIECE 시작
      로그 → `screencapture -R` 연사 → STICK 보간 크롭 → 배경 평탄화·32색·프레임 절반 GIF 350×280). 49종(37+12) docs/motions,
      구 100종 GIF 73개 삭제(fc4a406). 교훈: 캡처 영역이 화면 밖으로 잘리면 폭 가정이 깨져 크롭이 어긋난다(클램프 필수)
- [x] **v0.6.0 릴리스** (2026-09-16): gh release v0.6.0(zip 702,619B, SHA dc924fca…) 공개 SHA 일치 → homebrew-tap 0.6.0 push → brew fetch 검증
- [ ] 후속 후보: 어드레스·임팩트 샤프트 각 자동 검출(현재 미검출, 기존 기하 유지) · 선수 추가 시 gen_table.py 평균 재계산 주의
- [x] **⑤ 서프라이즈 1차** (`feature/surprises`, 사용자 선택 "계열별 대표 5개"): 프레임워크(등급 common/rare/epic·라운드 상한·훅 4종·
      예고→사건→반응) + 돌풍(물리)·멀리건(규칙)·낮잠(스틱맨)·커서 고양이(데스크탑, epic)·개구리 구조(생물·규칙) + 새·두더지 예고·반응.
      반응 3종(startled·shoo·laugh), 효과음 7종, `Ballistics.step(wind:)`. 카탈로그 docs/surprises.md. 관찰 `--surprise KIND`·`--demo-bg`.
      7종 강제 발동 캡처로 확인(스크래치패드 sur2-*-wide.png). 남은 아이디어 10개는 docs/surprises.md 끝
      리뷰(Code Reviewer: critical 1·major 2·minor 5) 반영 — 낮잠 기상 후 재수면 소프트락(조준당 1회), 낮잠 롤을 발동 시점으로(카운트
      선소모 제거), `cancelSurprises()`를 startHole에(R 인터럽트 잔존 정리), 방치 판정을 마지막 입력 기준으로, 개구리 통계·기권 정합,
      두더지·고양이 물 클램프, 돌풍 화들짝은 트월과 안 겹칠 때만. 검증: `--demo-idle --surprise nap`(재수면 0), `--demo-restart-in`
      (고양이·새·멀리건 도중 새 라운드 → 티에서 정상 시작·CAT 중단), 무강제 170s 라운드 14샷에 돌풍 1회·OUTBOUND 0
- [ ] ⑤ 사용자 플레이 판정 대기 — 확률(공 정지 8%·비행 6%·워터 40%·방치 60%)과 등급 상한은 실플레이 감으로 조정.
      미검증 경로: 실제 키 입력 기상(합성 키 금지 — 사용자 플레이로만), 일시정지 중 SKAction 기반 서프라이즈는 계속 재생(기존 패턴)
- [x] **⑥ 서프라이즈 2차** (`feature/surprises-2` 643fd1a + 리뷰 반영 0dc7ec3 → 머지 9cf5572, 카탈로그 docs/surprises.md, 코드
      `Sources/MiniGolf/Surprises2.swift`): 창 터널(무장 샷의 첫 창 진입을 반사 대신 삼켜 진행 방향 가장 먼 창 반대편에서 같은 속도로
      재출발, 통과 중 물리 정지·궤적 잔상) · 핀 이동(깃발이 다리 내고 그린 끝까지 걸어가 `Hole.movingPin` 사본 + `replaceHole`→지형
      재빌드) · 공 바꿔치기(`BallKind` 고무/볼링 — launch/step 배율, 다음 샷 종료 시 `onShotEnded`에서 복귀) · 갤러리(관중 4명이 다음 샷을
      보고 환호/박수/야유, 공 정지 샷이면 씬 1.7s 점유) · 거위 떼(홀 쪽에서 줄지어 와 둘째가 공 위에 앉고 흩어지며 알 잔류).
      공통: `onShotEnded(terminal:)`·`afterSurprise(delay)` 타이머 노드(씬에 직접 run 금지 — 1차 M2 함정)·`cancelSurprises2()`.
      효과음 9종. 리뷰 반영: 터널 진입을 종결 이벤트 뒤로(M1)·예고 깃발 흔들림 대상·스쿼시가 kind 스케일 유지·갤러리 퇴장/도착 전 스냅·
      퍼터 launchScale 면제·잔상 언더스트로크 제외·무산 터널 카운트 반환·그린 안착 환호 우선.
      **교훈**: 클럽 파워가 항력 전제로 튜닝돼 있어 볼링공 '안 뜸'을 공기력 제거로 만들면 오히려 351m > 306m — 발사 속도(0.5)로 만든다.
      수용한 잔여: 일시정지 중 터널 통과 타이머 벽시계 만료(돌풍과 같은 패턴, 0.3~1.3s) · 볼링공 퍼팅은 굴림 ×1.6만 적용
- [x] **품질 부채 — 포즈 불변식 테스트** (`feature/pose-invariant-tests`): `MiniGolfTests` 타깃(실행 파일 타깃도 `@testable import` 가능,
      Package.swift). 리그 공간은 공이 원점, 헤드 팁 = 그립 + 길이×(sin φ, −cos φ), 페이스 = 팁 + 카테고리 헤드 길이(headParams 식:
      우드 4.5+0.5w·아이언 len·cos(0.9 로프트)+선폭/2). 실측 표(2026-09-16): 퍼터 어드레스 팁 x = −5.0(3인 동일)·임팩트 −2.5, 풀스윙 페이스
      x는 어드레스 0.4~5.2·임팩트 −1.6~7.7 — 대역 [−7, 7]/[−7, 11], 팁 높이 [−1.5, 6.5]. 백스윙·피니시 유한값 스모크 포함. 테스트 60개
- [x] **품질 부채 — QA P1 잔여** (`feature/qa-p1-fun`, 2026-08-15 리포트 점검): 해결됨 = P0 밝은 배경(고대비 opt-in 결정+README 팁)·
      스코어 감정 반응·아이들 모션·P2 문서/LICENSE. 이번에 구현(사용자 선택 3종) = HUD 표고차(`140m ↑6m`, 공→홀컵, 1m 미만 생략) ·
      좌절 반응(워터·벙커·립아웃 **연속 2회**에 씬 1.6s 점유 + dejected + 한숨 `sigh` + "휴… 또 벙커…", 갤러리가 씬을 점유하면 양보,
      홀인·정상 정지에 카운트 리셋) · 버디 스트릭(연속 버디 이상 2회부터 홀아웃 토스트 sub에 "버디 스트릭 ×N") · 복귀 인사(**일시정지**
      5분 이상 뒤 재개 시 조준 중이면 shoo 손 흔들기 + "어서 와" — 포커스 상실은 일시정지가 아니라 홀드 해제만이라 ⛳️ 수동 정지 기준).
      관찰 `--demo-setback`(모든 샷 좌절 계열)·`--demo-idle --demo-greet`(3s 뒤 정지→1s 재개)·`--demo-pickup`(홀마다 홀인원 → 스트릭).
      프레임 3종 확인. 남긴 것은 2026-09-23 47bcada에서 처리(벙커 탈출 힌트 구현, 파워 라벨–깃대 겹침 불가 확인)
- [x] **v0.8.1 릴리스** (2026-09-23, 065abcf): zip 825,127B SHA bc0e5a94… → gh release → 공개 SHA 일치 → tap → tap·fetch·untap 검증
- [x] **v0.8.0 릴리스** (2026-09-23, fa7a8a1): zip 815,772B SHA 936eb712… → gh release → 공개 SHA 일치 → tap 58e1cb8 → tap·fetch·untap 검증
- [x] **v0.7.0 릴리스** (2026-09-16, f3a7c8f 버전 범프): `make zip`(796,042B, SHA b6cd497e…) → gh release v0.7.0 → 공개 에셋 재다운로드 SHA 일치 →
      homebrew-tap 45a4431(version·sha256) push → `brew tap` → `brew fetch --cask` 통과(캐시 SHA 일치) → `brew untap`(이 머신엔 tap 미설치 상태가
      원래 상태라 복구). ⚠️ 이 머신은 tap이 설치돼 있지 않으니 검증 시 tap→fetch→untap 순서로
- [x] **⑦ 코스 표고 재예산** (`feature/course-rebalance` bb6a446·98761ab → 머지 32ac3f1, 2026-09-17 사용자 판정 "오르막은 탄도가 안 나오고,
      협곡은 못 나오고, 내리막은 파5도 무조건 2온" → 선택 "탄도 기준 재예산"): 구 예산 0.34×worldW(파4 114~151m)가 풀샷 정점(42~67m)을
      넘던 것을 `plannedNetRise`(절벽 20~32·테라스 24~40·산정 20~36, 파3 절반)·`maxRiser` 14·`canyonDepthLimit`(러프 풀 PW 거리별 높이 표
      `pwRoughHeight`로 반대편 림을 2m 여유로 넘는 깊이 ≈10~17)로 교체. 수평 거리 = 유효거리(파 범위) − k·계획 낙차(오르막 1.0·내리막 1.5).
      **협곡 탈출 불가의 진짜 원인**은 라이저 꼬리에 공이 정지하고(저속 V자 가드·정상 정지) 그 자리 경사 스탠스가 로프트를 +30° 세워
      샷이 수직으로 뜨던 것 → `Ballistics.settleOffSteepSlope`(|경사| > 0.3이면 내리막 트레드로, 물이면 .water). 산정 백스톱 램프를 그린
      블렌드 뒤(climbEnd+48~62)로. 봇 실측(`Tests/GolfCoreTests/CourseBalanceProbe`, 40시드×9홀, 회귀 단언 포함): 아키타입별 순진 봇
      파 대비 −1.40~+1.01 → −0.47~−0.76(격차 2.41 → 0.29), 협곡 12타 고착 15% → 0%, 입수 0.99 → 0.08/홀, 급경사 정지 0. 테스트 63개.
      교훈: 낙차→거리 k≈1.0~1.2 실측(DR·7I ±20~40m), 라이저가 그 지점 탄도 높이를 넘으면 벽을 맞고 굴러 내려와 거리 자체가 붕괴.
      **리뷰 완료**(2026-09-23, Code Reviewer fable, 블로커·메이저 0·minor 3·nit 4 → 3661e19 반영): 산정 백스톱 램프 +52/+66(그린 뒤
      블렌드 최대 4m 겹침 제거, 봇 표 불변) · 정착 소진 가드 · pwRoughHeight 앞 외삽 금지 · 온그린 링 surpriseNodeName · 프로브 카운터
      리셋·회귀 대역 주석 실측(−0.47~−0.76, canyon 하한 −1.0까지 여유 0.24). **격상 발견**: 정착 스냅이 리뷰 추정(2~3m)이 아니라
      프로브 실측 샷의 1.2%·최대 18.5m·평균 5.4m(협곡 반대편 라이저 상단에 멈춘 공이 바닥까지) → GameScene `settleRoll`로 렌더만
      smoothstep 굴림(0.2~0.8s), 물리·밸런스 불변. `--demo-settle --seed 19` 프레임 캡처로 라이저 상단→중턱→바닥 4프레임 확인.
      범위 밖 관찰(onHoled/giveUp 씬 직접 run 타이머 → 홀아웃 직후 R에서 1번 홀 건너뛸 가능성, 미재현)은 IDEAS에 기록
- [x] **⑧ 홀컵 공 줍기 손에 들기 + 온그린 연출** (5c6c5e0): 줍기 1.15s 뒤 들고 보기 1.35s — 공이 Skeleton 처리 후 `drawRig.handTrail`을
      따라감(`ballHeld`), 60% 툭 던져 받기·40% 주머니. 온그린은 파4 원온·파5 투온만(사용자 선택, 파3 제외) — rejoice + 차임·환호 +
      고리·반짝임 + "원온!/투온! 이글 찬스", 갤러리·좌절보다 우선. 관찰 `--demo-pickup`·`--demo-gir`. 프레임 확인: 손에 든 공·가슴 앞 들기,
      투온 토스트·고리
- [x] ⑦⑧ 사용자 플레이 판정 1차 (2026-09-23): 지형 "괜찮" → 유지 · 실루엣 "뭔지 모르겠음" → 수직 과장 안 함 · 정착 굴림 "무슨 말인지
      모르겠음"(플레이 중 인지 안 됨) → 유지 · **온그린 "보이지 않음"** → 조건 코드 결함 미발견(프로브 봇 GIR 42~49%와 같은 판정), 사용자가
      실제 원온·투온을 달성했는지 확인 필요 · 파5 난도 언급 없음 → 클럽 리밸런스 보류 · **브라이슨 드라이버 피니시 "무릎 떨림"** → 60Hz 렌더
      리그 덤프(`--demo-trademark --style bryson [--demo-power 1.0] [--demo-settle]`)로 평지·풀파워·경사 0.29 등 5회 스윙 모두 프레임
      교번 진동 없음(재현 실패, 스크래치 knee.py) — 재현 조건(매번인지·특정 홀·파워·어느 다리) 사용자 확인 필요
- [ ] ⑥ 사용자 플레이 판정 대기 — 2차 5종의 강도·빈도(터널은 창 범퍼 켜짐+창 존재 시 라운드 1회, 핀은 그린 폭만큼, 공 바꿔치기는
      >30m에서만). 실제 창으로 터널을 보려면 화면에 중간 크기 창을 둔 채 풀샷. 설치 빌드: `brew upgrade --cask mini-golf` 또는 릴리스 zip

### 코스 밸런스 봇 (2026-09-17)

`swift test --filter CourseBalanceProbe` — `BOTBAL` 표(아키타입별 파 대비·고착·입수·순낙차, 파별, 고착 홀 샷 추적 `STUCK …`, 정착 이동량 `SETTLE n/max/mean`)와
`ELEVK`(낙차별 클럽 토탈). 봇 정책: 25m 안쪽 퍼터(텍사스 웨지)·벙커 SW·직전 샷 이동 < 3m면 PW 탈출·클럽은 토탈 ≥ 목표 중 최소.
지형·물리를 바꾸면 이 표부터 본다. 캡처 스크립트는 `scripts/capture-demo.py`로 저장소에 보존(2026-09-23 — 스크래치패드 유실로 두 번 재작성한 뒤):
`/usr/bin/python3 scripts/capture-demo.py OUTDIR MAXSEC --trigger "PREFIX:dur:gap:count" -- <MiniGolf 인자>`. 첫 1s는 합성 전 회색 화면이라 트리거를 늦게.

### 서프라이즈 관찰 도구 (2026-09-16)

`--demo --demo-bg --surprise KIND [--seed N] [--demo-bumpers "fx,fy,fw,fh;…"] [--demo-restart-in T]`. 로그 `SURPRISE kind`·`TUNNEL armed/in/out`·
`PIN old → new`·`BALLKIND kind`·`GALLERY verdict gain/before surface`·`GEESE scatter`. 캡처는 스크래치패드 `capture_surprise.py`(세션 한정 —
데모 stdout의 트리거 prefix마다 `screencapture -x -C` 연사 → `sips -Z 1600`, pid로 종료). **⚠️ 화면에 실제 앱 창이 있으면 창 범퍼가
데모 샷을 되받아쳐(BUMPER-HIT) 관찰이 오염된다** — 터널 외 관찰은 `--demo-bumpers "0.995,0.995,0.003,0.003"`(구석의 티끌 범퍼)로 실제
창 스냅샷을 대체할 것. 터널 관찰은 `"0.3,0.28,0.1,0.3;0.6,0.33,0.08,0.28"`(공 궤적이 지나는 높이).

### 트레이드마크 관찰 도구 (2026-09-15)

`--demo-trademark [--style tiger|rory|bryson] [--demo-pickup]` — 풀샷마다 굿샷 판정(트월 강제) + `RIG[t] mode 10점 head phi len
butt curved dir` 60Hz 덤프(구 30Hz — 프레임 교번 진동을 놓친다) + `TRADEMARK twirl/jump`·`UPPER`(어퍼컷 위상) 로그. 덤프는 스크래치패드 `plot_rig.py`(matplotlib,
`uv venv` + `uv pip install matplotlib`)로 프레임 시트를 그린다: `--from-mark twirl|jump|HOLED` 또는 `--from-mode swinging --nth N`.
실행은 사용자 앱을 죽이지 않도록 `--screen 1`로 띄우고 **pid로만** 종료(run_demos.sh 패턴). 퍼터 관찰은 `--demo-pickup`
(컵 앞 시작 → 탭인 → 홀인원 판정 → rejoice 반응).

### 재개 지점 (스윙 스타일 파이프라인)

2단계 작업 폴더 `~/swing-work`(venv .venv, 영상·pose_*.json·events_*_{wg,pt}.json·overlay_*.png). 재생성은
`gen_table2.py` → Poses.swift의 roryWedge/tigerWedge/roryPutt/tigerPutt/brysonPutt에 붙여 넣기. 퍼팅은 `analyze_putt.py`
(브라이슨은 `PICK=0`, 크롭 632~1066·41~80s), 웨지는 `HAND_PEAK=-0.3 EXT_MIN=0.35`. 브라이슨 웨지 실측 영상을 찾으면
`events_bryson_wg.json`만 추가하면 3인 평균 기준으로 재생성된다.

영상 → `refs/video/README.md` 절차. 작업 폴더(`SWING_WORK`)에 pose_<name>.json·events_<name>.json을 만들고
`gen_table.py`가 Swift 테이블을 출력하면 `Poses.swift`의 SwingKeyframes 세트에 붙여 넣는다. 유튜브 다운로드는
yt-dlp에 `--js-runtimes node --remote-components ejs:github`가 있어야 403이 안 난다. MediaPipe는 0.10.21(레거시 API).
장면 전환이 많은 영상은 analyze.py에 시간 창(t0 t1)을 주고, 오버레이 PNG로 관절 정합을 반드시 눈으로 확인.

### 재개 지점 (2026-09-23 — 다음 세션은 여기서)

main = 9935736(홀 전환 타이머 수정 머지), 작업 트리 클린, 원격 동기화됨. `dist/MiniGolf.app`은 9935736로 재빌드된 로컬 실행본(brew는 아직 0.7.0). 실플레이 로그 `~/Library/Logs/MiniGolf/play.log`.

1. **백로그 4종 완료** (2026-09-23 "전부 진행", 커밋 순): 클럽 리밸런스(5cf2825 — 우드 69/65/62, DR 306 → 286m, 봇 GIR 42~49 → 33~38%) ·
   무드 워크(03284e9 — `WalkMood`·`applyMood`, `--demo-mood`) · 걷기 중 방향 재계획(e943b62 — `walkTarget`·`replanAhead`·`startWalk(fromBody:)`,
   `--demo-replan`) · 서프라이즈 3차(faf48d2 — 서브에이전트 general-purpose(opus) 워크트리 구현, `Surprises3.swift`, 17종, `--demo-hour`).
   서프라이즈 3차 리뷰 완료·반영(1c56c86: critical·major 0·minor 2·nit 2 — 드롭 뒤 settleRoll 잔존(1차 종 4곳도 정리), 같은 프레임
   정리 가드 3곳, 바람 역전 0.6s·착지 뒤 문구, 문서 48px). **다음**: ① `dist/MiniGolf.app`(1c56c86) 사용자 판정(무드 워크 과장 폭, 턴·재계획 자연스러움,
   스프링클러 감쇠 강도(서브에이전트가 "꽤 강함" 지적), 캐디 빈도 7%, 강아지) ③ v0.8.2 릴리스(사용자 확인 뒤, v0.8.1 절차).
   교훈: 서브에이전트 워크트리(.claude/worktrees)를 `git add -A`가 gitlink로 잡았다 → .gitignore 처리(d526a5f). 데모 인자를 zsh 변수로
   넘기면 단어 분리가 안 돼 플래그가 무시된다 — 함수 인자("$1")나 직접 나열로
2. ~~온그린 추적~~ 해결(4번 항목). 참고: 데모 봇은 클럽 고정·파워 랜덤이라 GIR 관찰에 부적합(4분 데모 GIR 0·12타 기권) —
   자연 원온 재현은 `--seed 8 --demo-power 0.92`(파4 협곡 298m)
3. 파5가 쉽다는 판정이 나오면: 클럽 거리 리밸런스(IDEAS "클럽 거리 리밸런스 검토" — club.power 테이블, CourseStrategy 앵커는 자동 추종).
   봇 표(`swift test --filter CourseBalanceProbe`, GIR% 열 포함)로 전후 비교
4. ~~온그린 미발동 추적~~ **해결** (2026-09-23 play.log 증거): 4번 홀 파4 summitGreen 드라이버 h0.95 → `REST strokes 1 x 297.5 lie green
   label 원온!` 발동 확인. 앞선 "안 보임"은 조건 미달(파4 2타째 그린·파5 2타째 러프 — 라벨 `-`). 설계(파4 원온·파5 투온만)는 유지.
   (추적 경위) 사용자 확인 "파5 2타·파4 1타 만에 올렸는데도 안 나왔다". 데모에서는 자연 원온(seed 8 파4
   협곡 298m, `--demo-power 0.92`)으로 발동 확인(4회 중 2회 원온·2회 발동) → 정지 분기 로직 정상, 실플레이 전용 원인 미상. 코드 점검 완료:
   strokes 변이(발사·워터 +1·멀리건 복원), 정지 분기 순서(giveUp → 온그린 → 갤러리 → 좌절), 키 입력(조준 외 무시), toast 호출자.
   **PlayLog**(9fe8594, `Sources/MiniGolf/PlayLog.swift`) 추가 — `~/Library/Logs/MiniGolf/play.log`에 HOLE/SHOT/REST(lie·strokes·label)/
   HOLED/WATER. 사용자가 원온·투온을 만든 뒤 이 로그의 REST 줄(label이 `-`인데 lie가 green이고 strokes가 par−2면 버그, 아니면 조건 미달)을
   본다. 무릎 떨림은 "한 번 봤다/재현 안 됨" → 보류. 정착 굴림이 약하면 `settleRoll` dur 식(0.2 + 0.035·d, 상한 0.8s)만 조정
5. 남은 백로그: 서프라이즈 3차(스프링클러·바람 역전·캐디·정각 뻐꾸기·강아지, 라이벌 제외) · 걷기 방향 반전 제자리 돌기 · 무드 워크 ·
   벙커 탈출 힌트 · 파워 라벨–깃대 겹침 · Apple 공증 · 크로스플랫폼

### 재개 지점 (구 — 리그 개편 당시, 완료)

1. 사용자 판정 수집 → 미세 조정 후보: 다리 길이(46.5 — 서 있을 때 무릎 7.5px 굽음, 줄이면 보폭 극단에서
   힙 하강 증가), 정지 계획 범위(50px), 램프 시간(0.9/1.1s), 방향 반전 시 상체가 몸을 가로질러 도는 연출
2. 리뷰 반영 후 `git merge --no-ff feature/stickman-joints` → main (완료)
3. ④ 착수 시: WalkFlavor 채널(오프셋)을 관절 각도 채널(어깨·팔꿈치·무릎·허리·목)로 확장하는 설계부터 (완료)

### 관찰·계측 도구 (이번 세션 추가)

- `--demo` 로그: `STICK[벽시계] x groundY H mode`(0.5s, 캡처 크롭용) · `BONES`(힙 하강·손 클램프·다리 잔여) ·
  `WALKV tw x v`(0.1s 속도 프로파일) · `MOVE`(힙·발·그립 프레임당 최대 이동 — 전환 점프 검출)
- 캡처 워크플로(스크래치패드 도구 capture.sh·crop.py·walkv.py·jumps.py·transitions.py — 세션 한정):
  **사용자 인스턴스를 죽이지 않고** `--screen 1`로 두 번째 디스플레이에 띄운 뒤 `screencapture -D 2` 버스트,
  STICK 로그로 크롭. 종료는 `pkill -f "\.build/debug/MiniGolf"`(경로 지정 — `pkill -f MiniGolf`는 사용자 앱도 죽인다)
- `--demo-pickup`: 첫 샷도 퍼터·거리 프리셋 유지로 고쳐 탭인→홀인→줍기가 실제로 나온다

## 주요 결정·교훈 (누적)

- **애니메이션·리그는 기존 구현체·에셋 리서치 먼저** (2026-09-14 사용자 지시, 메모리 저장)
- **8-14 크로스페이드/원점 블렌드 기각의 구조적 원인**: 접지 발은 월드 제약인데 포즈 평균은 제3의 점 →
  반드시 미끄러짐. 블렌드 가중치 조정은 막다른 길 — 좌표계 정의를 맞추고 걸음을 계획한다
- SpriteKit 내장 IK(`SKReachConstraints`·`reach(to:)`)는 실존하지만 노드 트리·시간 액션 기반이라 기각
- 코드리뷰는 fable 모델(설치형 Code Reviewer frontmatter 고정, model 파라미터 생략) — 다른 위임은 opus
- 모션·시각 검증은 증거 루프: --demo 플래그 + 계측 로그 + 타임스탬프 캡처, 추정 금지
- 넘어지기·쇼피스 동결은 연속 램프(fall×(1-rise²)) · 걷기 위치 곡선과 vInst는 반드시 짝(WalkProfile이 단일 출처)
- 조정 포인트: 잔동작 진폭 1.7(boostMotion) · 쇼피스/서프라이즈 8% · 시그니처 표고 예산 0.34×worldW

### ⚠️ 설정 도메인 함정 (2026-08-31)

.app 번들 UserDefaults 도메인은 `io.github.w0uldy0udaestar.mini-golf`, 개발 바이너리(.build)는 `MiniGolf` —
서로 다른 저장소. 설정 복구·검증은 반드시 번들 도메인 기준으로.

### ⚠️ 공개 저장소 이력

- 저장소는 **public**. 과거 캡처 개인정보로 히스토리 재작성·저장소 재생성. `mini-golf-archive-private`는
  절대 public 전환 금지. 백업: `~/Project/mini-golf-backup-20260816-135637.bundle`
  (태그 `exp-transition-lab-20260814`에 8-14 스프링 실험실 보존 — 스크래치패드 복제본에서만 읽을 것)
- **캡처물은 저장소에 커밋 금지** (이번 세션 캡처는 전부 스크래치패드)

## 백로그 (우선순위 낮음)

- 무드 워크(스코어 상태→걷기 스타일, 모캡 차분) — ④와 합쳐 설계 권장 (`refs/mocap/`, amc2d.py)
- 걷기 방향 반전을 '제자리 돌기 2걸음'으로 (IDEAS) · 크로스플랫폼 배포 논의 · Apple 공증 · QA P1 잔여
- 릴리스 절차: Makefile VERSION → `make zip` → `gh release create` → tap cask 갱신 → 공개 SHA·brew 검증

## 실행·관찰

실행: `swift build && .build/debug/MiniGolf` (⛳️ 좌클릭 재개/일시정지 · 우클릭 메뉴)
플래그: `--demo` `--demo-motions` `--demo-memes` `--demo-surprise` `--surprise KIND` `--demo-bumpers` `--demo-pickup` `--demo-trip`
`--demo-idle` `--demo-setback` `--demo-greet` `--demo-gir` `--demo-settle` `--demo-power P` `--demo-restart-after-holed T` `--demo-hole N` `--demo-ball X` `--demo-turn` `--demo-mood M` `--demo-replan` `--demo-hour H` `--screen N` `--seed N` `--hat` `--demo-records`

### ⚠️ 핫픽스 절차 교훈 (2026-09-15 실측)

브랜치에 미커밋 작업이 있는 상태에서 `git stash` → main 체크아웃 → `stash pop` → 파일 단위 커밋을 하면
**브랜치 변경이 main 커밋에 섞인다**(GameScene에 재설계 hunk가 들어가 main 빌드가 깨졌고, 되돌리기 후
브랜치 머지가 그 hunk를 다시 지웠다). 핫픽스는 ① 브랜치 작업을 먼저 커밋(WIP 가능) ② main에서 해당 hunk만
적용 ③ **커밋 전 `git diff --cached`로 hunk 확인** ④ 가능하면 `git worktree`로 main을 따로 체크아웃.
검증 명령은 파이프로 exit 코드를 가리지 말 것(`git revert -q`는 잘못된 옵션이라 실패했는데 파이프에 가려졌다).

## 주의사항

- 합성 키 전송 금지 · 검증 명령에 파이프 금지(`$?` 가림 — swiftformat --lint | tail 로 한 번 놓쳤다) ·
  캡처는 화면 잠금 시 실패 · SourceKit 진단은 상시 뒤처짐(컴파일러만 신뢰) · main = 항상 동작 상태
