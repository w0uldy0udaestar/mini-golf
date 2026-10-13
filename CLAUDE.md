# CLAUDE.md — mini-golf

## 1. 프로젝트와 현재 단계
macOS 메뉴바 앱. 데스크탑 맨 아래 투명 띠에서 스틱맨이 9홀 사이드뷰 골프를 친다(Swift·SPM, 외부 의존성 0, 공개 저장소 MIT).
현재: 공개 릴리스 v0.8.9(Makefile VERSION). M6 판정 완료, M7 2차 지형 장애물(메사·거대 사구·항아리 벙커) main 머지 → **사용자 플레이 판정 대기 → v0.9.0 릴리스(사용자 확인 필수)**. 상세는 HANDOFF.md·PLAN.md.

## 2. 빌드·실행·테스트
- `swift build` 디버그 빌드 · `swift test` 전체 테스트(GolfCoreTests + MiniGolfTests) · 일부만: `swift test --filter <이름>`
- 계측 표: `swift test --filter GimmickProbe` → `$TMPDIR/gimmick-probe.txt` · `swift test --filter CourseBalanceProbe`(밸런스 봇 표)
- `swift test`는 실패한 프로세스의 stdout을 버린다 → 표·계측은 파일로 남긴다. 검증 명령에 파이프(`| tail`)를 붙이지 않는다(종료 코드가 가려진다)
- 스타일: swiftformat은 PostToolUse 훅이 .swift 편집 때 자동 실행 → **수동 실행 불필요**. CI(`.github/workflows/ci.yml`)는 `swift build` → `swiftformat --lint .`(0.62.1 고정) → `swift test`
- Makefile: `make release`(유니버설 릴리스 빌드) · `make app` → `dist/MiniGolf.app` · `make zip` → `dist/MiniGolf-$(VERSION).zip` + SHA-256 · `make clean`
- 앱 실행: `open dist/MiniGolf.app` (장치 골라 보기 `--args --gimmick mesa|dune|potBunker|volcano`). 종료는 Esc 또는 메뉴바 ⛳️ 우클릭 → 종료
- 개발 실행: `swift build && .build/debug/MiniGolf [플래그]`. 관찰 플래그(`--demo*`·`--seed N`·`--screen N` 등)는 `Sources/MiniGolf/DemoOptions.swift` 한 곳
- 개발 인스턴스 종료: `pkill -f "\.build/debug/MiniGolf"` — 경로를 꼭 지정(`pkill -f MiniGolf`는 사용자가 켜 둔 앱도 죽인다)
- 릴리스: immutable releases + 태그 룰셋이라 게시 후 수정·태그 이동 불가. 순서(VERSION → `make zip` → 산출물 확인 → CHANGELOG·노트 → `gh release create` → homebrew tap cask 갱신)는 HANDOFF.md "v0.9.0 릴리스 절차"
- 광고 렌더: `ads/<폴더>/scripts/render.sh`(HyperFrames, 폴더마다 인자 다름 — 각 파일 2~3행 주석), 미리보기 `scripts/preview.sh`, 30초판 최종 `ads/mini-golf-30s/scripts/final.sh`(2회 렌더 MD5 비교). `node_modules`가 없으면 폴더마다 `npm ci`로 복구

## 3. 구조 지도
- `Sources/GolfCore/` 순수 로직(UI 의존 0, 결정론적): 탄도(Ballistics)·클럽 표·코스 생성·지형 장치(Gimmick)·미션·날씨·IK·걷기 프로파일
- `Sources/MiniGolf/` 앱·렌더(AppKit 오버레이 + SpriteKit): GameScene·스틱맨(Poses·Skeleton·WalkFlavors)·HUD·사운드·서프라이즈·기록·PlayLog
- `Sources/MiniGolfSpike/` M0 리스크 스파이크(투명 오버레이·클릭 통과 검증용)
- `Tests/GolfCoreTests/` 물리·코스 불변식 + `*Probe` 계측 · `Tests/MiniGolfTests/` 포즈·플래그·기록·현지화
- `refs/` 로컬 전용 참조(gitignore, `refs/video/`만 추적): `refs/mocap/` CMU 모캡 원본·도구, `refs/video/` 프로 스윙 영상 키포인트 추출 도구
- `ads/` 광고 영상 소스(HyperFrames+GSAP, SwiftFormat 린트 제외) · `dist/` 빌드·렌더·캡처 산출물(gitignore, 커밋 금지)
- `docs/` 모션 카탈로그·QA 보고서·리서치 노트 · `docs/handoff-archive/` 옛 HANDOFF 이력 · `scripts/` 개발용 캡처·아이콘 도구(앱에 미포함)

## 4. 검증 관례
- 순서: `swift build` → `swift test` → (해당 시) 계측 Probe·play.log 확인 → 캡처 → **사용자 플레이 판정**
- **게임 변경은 사용자가 직접 한 라운드 쳐 봐야 끝난다**(체감 게이트, PLAN.md). 로그·캡처는 "구현됐다"의 증명일 뿐 "재밌다/느껴진다"의 증명이 아니다
- 켜 주기 전에 새로 보이는 것을 한 줄씩 소개한다(HANDOFF "사용자에게 보여 줄 것")
- Claude가 먼저 돌릴 자동 검증:
  - 단위·불변식 테스트, `*Probe` 표(GimmickProbe·CourseBalanceProbe 등)로 수치 전후 비교
  - 플레이 로그 `~/Library/Logs/MiniGolf/play.log`의 ROUND·HOLE·SHOT·REST(lie·strokes·label) 줄로 노출·판정 근거 확인
  - `--demo*` 플래그 + 계측 로그(STICK·BONES·WALKV·MOVE)로 모션 재현
  - 창 단위 캡처 `scripts/capture-window.py` + `scripts/flatten.swift`(불투명 픽셀 1% 미만이면 게임 창만 찍힘). 화면 전체 캡처 스크립트는 빈 화면에서만
  - `make app` 뒤 산출물 확인: `strings dist/MiniGolf.app/Contents/MacOS/MiniGolf | grep "<영문 문구>"`(한글은 strings에 안 잡힌다)
  - 광고: 컨택트 시트·프레임 diff(최대 ≤12, 135×240 축소)·세이프존·2회 렌더 MD5 일치(`ads/*/qa/`)
- 합성 키 이벤트를 게임에 보내지 않는다(사용자 타이핑과 충돌). 캡처물은 스크래치패드·`dist/cap/`에만, 저장소 커밋 금지

## 5. 용어 (사용자에게 설명할 때)
- **오버레이**: 다른 창 위에 투명하게 겹쳐 뜨는 게임 창. 마우스 클릭은 아래 앱으로 그대로 통과한다
- **라이(lie)**: 공이 멈춘 자리의 땅 종류(그린·에이프런·페어웨이·러프·벙커). 라이마다 굴림·타격 페널티가 다르다
- **240Hz 탄도 시뮬**: 공의 비행을 1/240초 단위로 계산(항력·백스핀 양력·스핀 감쇠). 프레임 속도와 무관하게 같은 결과
- **펀치샷**: 낮게 깔아 치는 샷. 나무 캐노피 밑으로 보내 넘어갈 수 있다
- **장치(gimmick) 홀**: 화산·메사·거대 사구·항아리 벙커처럼 특별 지형을 덧씌운 홀(라운드당 세 홀)
- **서프라이즈**: 라운드 중 가끔 일어나는 깜짝 이벤트(거위 떼·핀 이동 등)
- **모캡 AMC**: CMU 모션캡처 데이터 형식. 관절 각도를 초당 120번 기록한 파일(ASF는 뼈대 정의). 스틱맨 동작 연구용, 저장소 미포함
- **P-System 키프레임**: 스윙을 단계별 자세로 나눈 골프 표준 분할. 프로 스윙 영상에서 뽑아 스틱맨 포즈에 반영
- **프로브(Probe)**: 봇·시뮬을 돌려 수치 표를 뽑는 계측용 테스트(일부는 허용 범위 단언도 포함)
- **판정**: 사용자가 실제로 쳐 보고 유지·조정·삭제를 정하는 것

## 6. 작업 규칙
- 브랜치: `feature/<기능>`에서 작업 → 테스트·린트 통과 → Code Reviewer 리뷰 반영 → `git merge --no-ff`로 main. 커밋은 `feat|fix|docs|chore: 한국어 요약`, 머지는 `merge: …`
- **공개 저장소**: 절대 경로·개인 이메일·타 프로젝트명·내부 메모를 커밋하지 않는다. 커밋 전 개인 정보 문자열 `git grep` 확인(명령은 HANDOFF "주의 (10-01 추가)")
- HANDOFF.md와 `docs/handoff-archive/`는 로컬 전용(.gitignore, 원격 백업 없음). 옛 세션 이력은 archive 파일에 원문 그대로 둔다
- 리뷰 산출물: 코드 리뷰 소견은 HANDOFF.md에 요약, 실측·변경 내역은 CHANGELOG.md, 종합 QA는 `docs/qa-report-*.md`, 광고 QA는 `ads/*/qa/`
- 계획 밖 아이디어는 IDEAS.md, 마일스톤·판정 기록은 PLAN.md
- 프로젝트 에이전트 `.claude/agents/motion-ad-director.md`(Motion Ad Director): 광고 영상(HyperFrames+GSAP) 제작·수정 전용. `ads/`·`dist/ads/`·`dist/cap/` 안에서만 작업, 게임 소스 수정·커밋·push 금지(메인 세션이 검토·커밋)
- 설정 저장소 주의: .app 번들의 UserDefaults 도메인과 개발 바이너리(`.build`)의 도메인이 다르다 — 설정 복구·검증은 번들 도메인 기준
