# HANDOFF.md

## 현재 상태 (2026-09-14 세션 마무리)

**v0.4.1 배포·설치까지 완료.** main(=origin/main, bd8971e) 클린, 테스트 42개 통과.
사용자 Mac의 `/Applications/MiniGolf.app`에 v0.4.1이 설치·검증돼 있다 (구사본 휴지통 정리,
번들 도메인 설정 잔재 청소 완료 — 아래 함정 참조).

- [x] CMU 모캡 골프 의식 2종: 티 꽂기·공 줍기 (v0.4.0) — 스윙은 대조 검증만(일치, 수정 없음)
- [x] 주 디스플레이 폴백 버그 수정 — Sidecar 실종 (v0.4.1)
- [x] 릴리스 체인: GitHub Release + Homebrew tap + 공개 SHA·brew 실설치 검증 (v0.4.0/v0.4.1)
- [x] 사용자 Mac 재설치 + 설정 잔재 3종 삭제 (기록·고대비는 보존)
- [ ] **무드 워크** — 승인된 모캡 계획(①파서 ②의식 ③무드 워크)의 잔여분, 아래 재개 지점

### ⚠️ 다음 세션 재개 지점 — 무드 워크

스코어 상태 → 걷기 스타일 연동 (버디 후 Elated/Bouncy, 더블보기 후 Depressed/Mope…).

- 원료: `refs/mocap/` (157 AMC + 37 ASF, gitignore — manifest.json에 선정 목록.
  CMU 데이터는 재판매 금지라 저장소 커밋 금지)
- 도구: `refs/mocap/tools/amc2d.py` (ASF/AMC→FK→2D 투영→채널 추출, 검증 완료)
- 방법: 성격 걷기 클립과 표준 걷기(neutral)의 채널 차분 → WalkFlavor 오버레이 초안
  자동 생성 → 수동 다듬기. **발 접지(노슬립) 게이트는 절대 불변** — 상체 채널·보폭/듀티만
- 참고: docs/research-mocap-index.md '이식 1차 결과' 절, B절(대상 ~40종 목록)

### ⚠️ 설정 도메인 함정 (2026-08-31 실측 — "업데이트 적용 안 됨" 소동의 전말)

.app 번들의 UserDefaults 도메인은 `io.github.w0uldy0udaestar.mini-golf`, 개발 바이너리
(.build)는 `MiniGolf` — **서로 다른 저장소다**. 구버전 데모 사운드 버그의 잔재(soundEnabled=0)
와 Sidecar 모니터 선택(preferredDisplayID)·범퍼 꺼짐이 번들 도메인에 남아 v0.4.0이 체감 0이
됐었다. 교훈: 설정 복구·검증은 반드시 번들 도메인 기준으로.

### ⚠️ 공개 저장소 이력 (반드시 알 것)

- 저장소는 **public** (https://github.com/w0uldy0udaestar/mini-golf). 과거 캡처에 개인정보가
  찍혀 히스토리 재작성 후 **저장소를 재생성**해 정리된 히스토리만 올린 것이다.
- `mini-golf-archive-private`는 오염 캡처를 품은 보관용 — **절대 public 전환 금지**.
  재작성 전 전체 백업: `~/Project/mini-golf-backup-20260816-135637.bundle`.
- 교훈: 캡처물은 처음부터 검정 배경막(스크래치패드 backdrop 도구) 위에서 찍을 것.

## 백로그 (우선순위 낮음)

- 크로스플랫폼 배포 설계 논의 (사용자 지정 예약 주제 — GolfCore는 순수 Swift라 이식 가능,
  쟁점은 렌더·오버레이·사운드 대체와 Windows Swift 툴체인. 리서치 후 AskUserQuestion 권장)
- 모캡 후속: 공 놓기(64_23/24) 드롭 연출, 모자 쓰기 해금 연출, 아이들/트립/제스처 확장
- Apple 공증(연 $99) — 미서명 경고 제거 옵션
- QA 잔여 P1: 립아웃/워터 좌절 반응, 연속 버디 스트릭, 포커스 복귀 인사
- 릴리스 절차(확립됨): Makefile VERSION → `make zip` → `gh release create` →
  tap cask version·sha256 갱신 → 공개 SHA·brew 설치 검증

## 실행·관찰 도구

실행: `swift build && .build/debug/MiniGolf` (⛳️ 좌클릭 재개/일시정지 · 우클릭 메뉴)
플래그: `--demo` `--demo-motions` `--demo-memes` `--demo-surprise` `--demo-pickup`
`--demo-trip` `--demo-idle` `--screen N` `--seed N` `--hat` `--demo-records`
계측 로그: AIM·FLAVOR·MOTION·HOLED·SIGNATURE·RITUAL·BUMPERS·SHOWPIECE

## 주요 결정·교훈

- **코드리뷰는 fable 모델로** (사용자 지시, 메모리 저장됨) — 다른 위임은 opus
- 모션·시각 검증은 증거 루프: --demo 플래그 + 계측 로그 + 타임스탬프 캡처, 추정 금지
- **데모 캡처 전 반드시 `pkill -f MiniGolf`** — 사용자 인스턴스와 겹치면 이중 오버레이
- 넘어지기·쇼피스 동결은 이진 아닌 연속 램프(fall×(1-rise²)) — 슬라이드·듀티 스냅 방지
- 걷기 위치 곡선(smoothstep)과 vInst 도함수는 반드시 짝으로
- 조정 포인트: 잔동작 진폭 1.7(GameScene boostMotion 호출부) · 쇼피스/서프라이즈 8% ·
  시그니처 표고 예산 0.34×worldW(Course.swift)

## 주의사항

- 합성 키 전송 금지 · 검증 명령에 파이프 금지(`$?` 가림) · 캡처는 화면 잠금 시 실패
- SourceKit 진단은 상시 뒤처짐 — 컴파일러 결과만 신뢰
- main = 항상 동작 상태 · 시그니처 지형 변경 시 등반 가능성 회귀 테스트 필수
