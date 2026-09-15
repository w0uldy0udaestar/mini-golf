# HANDOFF.md

## 현재 상태 (2026-09-14 — 스틱맨 리그 개편 1·2·3 구현 완료, 사용자 플레이 판정 대기)

사용자 피드백 5건(2026-09-14: ①전환 탁탁 ②걷기 느리다 가속 ③고무팔 ④모션 100종 획일 ⑤서프라이즈
밋밋) 중 **①②③을 `feature/stickman-joints`(origin 푸시됨, main 미머지)에 구현**했다.
리서치 게이트를 먼저 통과했고(docs/research-stickman-rig.md — 사용자 지시 "기존 구현체·에셋 먼저 찾아봐"),
각 단계는 build·lint·test(52) + `--demo` 프레임 캡처·계측 로그로 검증했다. 이해도 확인 페이지(아티팩트):
https://claude.ai/code/artifact/a235d28e-bc9c-47e9-9c22-111744b4ff2a

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
- [ ] **사용자 플레이 판정 대기** (`dist/MiniGolf.app` 실행 중 = main 최신) → 버전 범프 0.5.0·릴리스·GIF 카탈로그 재캡처
- [ ] 후속 후보: 드라이버·웨지·퍼터 face-on 영상으로 클럽별 키프레임 분리, 어드레스·임팩트 샤프트 각 검출(현재 미검출)
- [ ] ⑤ 서프라이즈 — 사용자 선택: 데스크탑 연동(권장)·물리·규칙·스틱맨/생물 전부. 아이디어 15개는
      아티팩트 5절. 원칙: 결과 종류 다양화 · 예고→사건→반응 3박자 · 희귀 등급

### 재개 지점

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
플래그: `--demo` `--demo-motions` `--demo-memes` `--demo-surprise` `--demo-pickup` `--demo-trip` `--demo-idle`
`--screen N` `--seed N` `--hat` `--demo-records`

### ⚠️ 핫픽스 절차 교훈 (2026-09-15 실측)

브랜치에 미커밋 작업이 있는 상태에서 `git stash` → main 체크아웃 → `stash pop` → 파일 단위 커밋을 하면
**브랜치 변경이 main 커밋에 섞인다**(GameScene에 재설계 hunk가 들어가 main 빌드가 깨졌고, 되돌리기 후
브랜치 머지가 그 hunk를 다시 지웠다). 핫픽스는 ① 브랜치 작업을 먼저 커밋(WIP 가능) ② main에서 해당 hunk만
적용 ③ **커밋 전 `git diff --cached`로 hunk 확인** ④ 가능하면 `git worktree`로 main을 따로 체크아웃.
검증 명령은 파이프로 exit 코드를 가리지 말 것(`git revert -q`는 잘못된 옵션이라 실패했는데 파이프에 가려졌다).

## 주의사항

- 합성 키 전송 금지 · 검증 명령에 파이프 금지(`$?` 가림 — swiftformat --lint | tail 로 한 번 놓쳤다) ·
  캡처는 화면 잠금 시 실패 · SourceKit 진단은 상시 뒤처짐(컴파일러만 신뢰) · main = 항상 동작 상태
