# HANDOFF.md

## 현재 상태 (2026-09-16 — 서프라이즈 2차 main 머지 완료(9cf5572). v0.7.0 미배포, 플레이 판정 대기)

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
- [ ] **트레이드마크·2.5배 세부 판정 대기** — 2.5배 과장과 트레이드마크를 한 번에. 약하면: 점프 8→10, 트월 트리거 완화
      (heightPct 0.45→0.3), 암록 butt 10→14. ⛳️ 메뉴 → 스윙 스타일로 전환하며 비교, 타이거 어퍼컷은 버디 이상 홀아웃에서만
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
- [ ] ⑥ 사용자 플레이 판정 대기 — 2차 5종의 강도·빈도(터널은 창 범퍼 켜짐+창 존재 시 라운드 1회, 핀은 그린 폭만큼, 공 바꿔치기는
      >30m에서만). 실제 창으로 터널을 보려면 화면에 중간 크기 창을 둔 채 풀샷. 판정 뒤 v0.7.0 릴리스(Makefile VERSION 0.6.0→0.7.0 ·
      CHANGELOG v0.7.0(미배포) 확정 · `make zip` · gh release · tap)

### 서프라이즈 관찰 도구 (2026-09-16)

`--demo --demo-bg --surprise KIND [--seed N] [--demo-bumpers "fx,fy,fw,fh;…"] [--demo-restart-in T]`. 로그 `SURPRISE kind`·`TUNNEL armed/in/out`·
`PIN old → new`·`BALLKIND kind`·`GALLERY verdict gain/before surface`·`GEESE scatter`. 캡처는 스크래치패드 `capture_surprise.py`(세션 한정 —
데모 stdout의 트리거 prefix마다 `screencapture -x -C` 연사 → `sips -Z 1600`, pid로 종료). **⚠️ 화면에 실제 앱 창이 있으면 창 범퍼가
데모 샷을 되받아쳐(BUMPER-HIT) 관찰이 오염된다** — 터널 외 관찰은 `--demo-bumpers "0.995,0.995,0.003,0.003"`(구석의 티끌 범퍼)로 실제
창 스냅샷을 대체할 것. 터널 관찰은 `"0.3,0.28,0.1,0.3;0.6,0.33,0.08,0.28"`(공 궤적이 지나는 높이).

### 트레이드마크 관찰 도구 (2026-09-15)

`--demo-trademark [--style tiger|rory|bryson] [--demo-pickup]` — 풀샷마다 굿샷 판정(트월 강제) + `RIG[t] mode 10점 head phi len
butt curved dir` 30Hz 덤프 + `TRADEMARK twirl/jump`·`UPPER`(어퍼컷 위상) 로그. 덤프는 스크래치패드 `plot_rig.py`(matplotlib,
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

### 재개 지점 (기존)

1. 사용자 판정 수집 → 미세 조정 후보: 다리 길이(46.5 — 서 있을 때 무릎 7.5px 굽음, 줄이면 보폭 극단에서
   힙 하강 증가), 정지 계획 범위(50px), 램프 시간(0.9/1.1s), 방향 반전 시 상체가 몸을 가로질러 도는 연출
2. 리뷰 반영 후 `git merge --no-ff feature/stickman-joints` → main
3. ④ 착수 시: WalkFlavor 채널(오프셋)을 관절 각도 채널(어깨·팔꿈치·무릎·허리·목)로 확장하는 설계부터.
   IK 후처리가 있으므로 손·발 목표점 기반으로도 실루엣 설계 가능. 100종 → 묶음별 대표 30~40종 선정 필요

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
`--demo-idle` `--screen N` `--seed N` `--hat` `--demo-records`

### ⚠️ 핫픽스 절차 교훈 (2026-09-15 실측)

브랜치에 미커밋 작업이 있는 상태에서 `git stash` → main 체크아웃 → `stash pop` → 파일 단위 커밋을 하면
**브랜치 변경이 main 커밋에 섞인다**(GameScene에 재설계 hunk가 들어가 main 빌드가 깨졌고, 되돌리기 후
브랜치 머지가 그 hunk를 다시 지웠다). 핫픽스는 ① 브랜치 작업을 먼저 커밋(WIP 가능) ② main에서 해당 hunk만
적용 ③ **커밋 전 `git diff --cached`로 hunk 확인** ④ 가능하면 `git worktree`로 main을 따로 체크아웃.
검증 명령은 파이프로 exit 코드를 가리지 말 것(`git revert -q`는 잘못된 옵션이라 실패했는데 파이프에 가려졌다).

## 주의사항

- 합성 키 전송 금지 · 검증 명령에 파이프 금지(`$?` 가림 — swiftformat --lint | tail 로 한 번 놓쳤다) ·
  캡처는 화면 잠금 시 실패 · SourceKit 진단은 상시 뒤처짐(컴파일러만 신뢰) · main = 항상 동작 상태
