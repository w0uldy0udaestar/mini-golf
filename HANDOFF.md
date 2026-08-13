# HANDOFF.md

## 현재 상태 (2026-08-13)

프로젝트 킥오프 완료. 인터뷰 → 리서치(레퍼런스 추적 + 기술 비교) → 설계 결정 → PLAN.md 마스터플랜 확정까지 마침. 코드는 아직 없음.

## 완료

- [x] 프로젝트 정의 인터뷰 (컨셉·조작·범위·성공 기준)
- [x] 리서치 2건: 레퍼런스 야구 프로젝트 추적(미발견), 오버레이 기술 비교 → `docs/research-tech-stack.md`
- [x] 설계 확정: 사이드뷰 / 키보드 전용 / 풀 클럽 탄도·백스핀 물리 / Swift+SpriteKit / SPM 구조
- [x] PLAN.md · IDEAS.md · README.md 작성
- [x] git 커밋 + GitHub private 저장소 연결
- [x] HTML 게임필 프로토타입 (`prototype/mini-golf-prototype.html`) — 탄도·클럽 밸런스·9홀 흐름·스틱맨 스윙(백스윙=파워 게이지) 헤드리스 QA 통과. 물리 상수는 GolfCore로 이식 예정. 스틱맨 스윙 연출은 MVP 핵심 (사용자 교정)

## 다음 단계 (재개 지점)

**M0 리스크 스파이크부터 시작** — PLAN.md의 M0 체크리스트:
1. 투명 NSPanel + SpriteKit `.clear` 씬 렌더 (`skView.backgroundColor` 절대 설정 금지)
2. 창 전체 클릭 통과 + 키보드 캡처 (NSPanel nonactivating 방식), 아래 앱 키 유출 검증
3. 포커스 상실 시 일시정지

스파이크 통과 후 M1(SwiftFormat·XCTest 셋업 → GolfCore 탄도 엔진)으로.

## 주요 결정과 이유

- **키보드 전용** (사용자 결정): 오버레이 최대 난제였던 선택적 클릭 통과가 불필요해짐. 창 전체 통과 + 라운드 중 키 캡처만 하면 됨
- **자체 탄도 엔진**: 클럽별 로프트·백스핀·마그누스는 SpriteKit 내장 물리로 불가. GolfCore 순수 Swift 모듈로 분리해 XCTest로 검증
- **사이드뷰**: 탄도가 화면에 그대로 보이고 방향 조준이 필요 없어 키보드 전용과 정합

## 주의사항·리스크

- 사용자가 본 레퍼런스(스틱맨 야구 오버레이)는 끝내 못 찾음 — 링크를 받으면 `docs/`에 분석 추가
- macOS 최신 버전 오버레이 회귀 가능성 → M0에서 실기 검증이 최우선
- 저장소는 private. **public 전환은 M4에서 사용자 확인 게이트 필수**
