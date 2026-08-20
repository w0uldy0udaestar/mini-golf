# HANDOFF.md

## 현재 상태 (2026-08-19 세션 종료)

**저장소 PUBLIC 전환 완료** — https://github.com/w0uldy0udaestar/mini-golf (설명·토픽 10종 설정됨).
main 단일 브랜치(97커밋)·태그 `exp-transition-lab-20260814`(스프링 전환 실험 박제)·테스트 32개 통과.
README 전면 리뉴얼(SVG 배너 docs/banner.svg·물리 엔진 표·클럽 테이블·모션 그리드) +
모션 100종 GIF 카탈로그(docs/motions/*.gif, --demo-motions 캡처 → 스틱맨 추적 크롭) 완료.

### ⚠️ 공개 과정에서 있었던 일 (반드시 알 것)
- 과거 커밋의 데스크탑 캡처(motions/*.png 100장·구 demo.gif)에 로컬 경로·Claude 사용량/비용·
  Dock이 찍혀 있어 **히스토리를 재작성**(filter-branch, 5커밋)했다. 커밋 SHA가 전부 바뀜.
- force push 후에도 GitHub 서버가 구 객체를 회수하지 않아 구 SHA로 접근이 가능했음 →
  기존 저장소를 **`mini-golf-archive-private`로 이름 변경(private 보관)**하고 `mini-golf`를
  새 public 저장소로 재생성해 정리된 히스토리만 푸시. 구 SHA 404 검증 완료.
- 재작성 전 전체 백업: `~/Project/mini-golf-backup-20260816-135637.bundle` (무결성 검증됨).
  archive 저장소는 오염 캡처를 품고 있으니 **절대 public 전환 금지**. 필요 없으면 웹에서 삭제.
- 교훈: 캡처물은 처음부터 검정 배경막(스크래치패드 backdrop 도구) 위에서 찍을 것.

이전 상태: M3 + 폴리시 전부 main 머지, LICENSE(MIT)·CHANGELOG 완비. 사용자 실플레이
판정 완료: 사운드·라이 구분·경사 스탠스·장애물·클럽 디자인·넘어지기(1~2% 철푸덕)·모션
100종 모두 승인됨.

실행: `swift build && .build/debug/MiniGolf` (⛳️ 좌클릭 재개/일시정지 · 우클릭 메뉴)
관찰 도구: `--demo` `--demo-wall` `--demo-card` `--demo-trip` `--demo-idle`
`--demo-motions`(모션 100종 순서 시연 — 카탈로그 캡처용, /tmp/minigolf-motion.txt로 위치 통지)
`--seed N` `--no-wall-clamp` — 계측 로그: AIM·FLAVOR[epoch]·MOTION·HOLED·OUTBOUND

## ⚠️ 다음 세션 주제 (사용자 지정)

**크로스플랫폼 배포 설계: Windows·macOS·Linux 각각 어떻게 만들지 논의.**
논의 포인트 준비: 현재 구조는 GolfCore(순수 Swift, 플랫폼 무관)와
MiniGolf(AppKit+SpriteKit — macOS 전용 렌더·오버레이·사운드)로 분리되어 있음.
쟁점: ①렌더 대체(SDL/SFML/Godot 임베드 vs 각 플랫폼 네이티브) ②오버레이(투명 클릭스루
창)의 플랫폼별 지원(Win: WS_EX_LAYERED, Linux: X11/Wayland 편차 큼) ③사운드 합성 대체
④Swift 크로스컴파일 성숙도(Windows Swift 툴체인) vs 코어 포팅(C++/Rust) — 리서치 후
AskUserQuestion으로 방향 결정 권장.

## 남은 백로그 (우선순위 낮음, docs/qa-report-2026-08-15.md 참조)

- ~~GitHub public 전환~~ 완료 (2026-08-19)
- ~~배포~~ 완료 (2026-08-20): Release v0.1.0(유니버설 .app zip 440KB, `make zip`으로 조립) +
  Homebrew tap(`w0uldy0udaestar/homebrew-tap` 저장소, `brew install --cask w0uldy0udaestar/tap/mini-golf`
  실설치 검증 후 정리). 다음 릴리스 절차: Makefile VERSION 올리기 → `make zip` → `gh release create` →
  tap의 cask version·sha256 갱신. 남은 옵션: Apple 공증(연 $99, 경고 없는 실행)
- 밝은 배경 기본 가독성(사용자 결정: 현행 유지 — README에 고대비 안내로 갈음)
- HUD 표고차 표시·파3/파4 난이도 격차(사용자 결정: 현행 유지)
- QA 잔여 P1 일부: 립아웃/워터 좌절 반응, 연속 버디 스트릭, 포커스 복귀 인사

## 이번 세션 주요 작업 (시간순)

1. 1차 실플레이 4건: 라이 시각 구분·경사 스탠스(applySlopeStance)·포커스 상실 시 홀드만
   해제·장애물 가시성(+실측: 배치는 48% 홀에 이미 존재)
2. 2차 5건: 코스 다이나믹(성격 롤+능선/분지/플래토+솟은/낮은 그린, 낙차 평균 12.1m)·클럽
   키 반전(→=드라이버)·깃발 위 스코어·걷기 직립 교정·모션 100종(WalkFlavors.swift)
3. 장애물 재디자인(스캘럽 뭉게구름 나무·조약돌)·궤적 번쩍임 수정
4. 지형 적응 걷기+넘어지기, **종합 QA**(4관점 리뷰+소크 3,200샷+밸런스 봇 360홀 —
   docs/qa-report-2026-08-15.md): 비종결 굴림 치명 버그 발견·수정(lowSpeedTime 가드+회귀 테스트)
5. QA 처방 반영: 철푸덕 프론 넘어지기(1~2%)·스코어 감정 반응(만세/주먹/처짐+토스트 크기
   차등)·아이들 잔동작 / M4 문서·main 머지
6. 클럽 재디자인(볼 헤드·패들·미니 망치·그립 밴드) + 샤프트 실클럽 비례(DR 51~PT 34,
   상한은 어드레스 접지 기하)
7. 마무리: 모션 카탈로그(docs/motions.md + 실캡처 100장)·데모 GIF(docs/demo.gif,
   ImageIO 자체 조립) — README 연결

## 주요 결정·교훈

- **코드리뷰는 fable 모델로** (사용자 지시, 메모리 저장됨) — 다른 위임은 opus 유지
- 모션·시각 검증 표준 루프: --demo + epoch 계측 로그 + 타임스탬프 캡처 (운에 맡기지 말고
  로그로 프레임을 계산해서 잡을 것)
- **게임 인스턴스 중복 주의**: 데모 캡처 전 반드시 `pkill -f MiniGolf` — 사용자용 인스턴스와
  겹치면 오버레이가 이중으로 찍힌다 (이번 세션 2회 재발)
- 넘어지기 동결은 이진이 아니라 연속 램프(fall×(1-rise²))로 — 슬라이드·듀티 스냅 방지
- GIF는 ffmpeg 없이 ImageIO(CGImageDestination)로 조립 가능 (scratchpad giftool)
- 걷기 위치 곡선(smoothstep)과 vInst 도함수는 반드시 짝으로 — exp 브랜치 이식 금지 사항 유지

## 주의사항

- 합성 키 전송 금지 · 검증 명령에 파이프 금지(`$?` 가림) · 캡처는 화면 잠금 시 실패
- SourceKit 진단은 상시 뒤처짐 — 컴파일러 결과만 신뢰
- 저장소 private (public 전환은 사용자 확인 대기) · main = 최신 동작 상태
