# 리서치 요약 — 오버레이 기술 스택 & 레퍼런스 추적

작성일: 2026-08-13. 리서치 에이전트 2건(Trend Researcher, Tool Evaluator — 모두 Opus 4.6)의 결과를 메인 세션에서 교차 검증·종합한 기록. 원래 마우스 조작(선택적 클릭 통과) 전제로 평가했으며, 이후 **키보드 전용으로 설계가 바뀌어 클릭 통과 요구가 "창 전체 통과"로 완화**됨 — 결론(Swift/AppKit + SpriteKit)은 그대로 유효하고 오히려 더 단순해짐.

## 결론

**Swift/AppKit + SpriteKit 채택.** 근거:

1. 클릭 통과를 네이티브 API(`NSWindow.ignoresMouseEvents`, 필요 시 `hitTest` 오버라이드)로 정확 처리 — Apple이 공식 안내한 패턴 (Apple Developer Forums thread/812113, 2025)
2. 번들 <1MB, 추가 권한(Accessibility/Screen Recording) 불필요
3. 유사 장르 실증: Super Goose Desktop(AppKit+SpriteKit), BongoCat-mac(Swift/AppKit), Pet Therapy(SpriteKit, App Store 배포) 등 5개 이상이 동일 패턴
4. WebView 스택 대비 상시 렌더링 부담↓ — 투명 창 GPU 전력 ~8배 증가 측정치는 Tauri/WebKit 기준(#15471)이며 SpriteKit 직접 측정치는 없음(추정임을 명시)

## 후보별 요점

| 스택 | 가중 점수 | 핵심 결격/강점 |
|---|---|---|
| Swift/AppKit + SpriteKit | 8.35 | 강점: 클릭 통과 정확, 경량. 약점: 웹 개발자 기여 장벽(Xcode) |
| Godot 4.4+ | 7.30 | 2D 게임 제작 최편, 단 통과 API가 단일 폴리곤 제약 + 최신 macOS 회귀 영향 미검증 |
| Electron | 6.65 | 기여 장벽 최저(`npm start`), 단 캔버스 히트테스트 우회 필요·메모리 200~300MB·번들 150MB+ |
| Tauri v2 | 6.15 | `forward` 옵션 부재(5년째 미구현), 패키징 투명도 버그(#13415), 풀스크린 위 오버레이 불가 |
| Unity | 제외 | macOS 투명 창 공식 미지원, 서드파티 플러그인 제약이 요구사항과 충돌 |

## 구현 시 주의 (리서치가 지목한 함정)

- **SpriteKit 투명 배경**: `skView.allowsTransparency = true` + scene `backgroundColor = .clear`. 단 `skView.backgroundColor`를 어떤 값으로든 설정하면 투명이 깨짐 (thread/48085)
- **macOS Sonoma 회귀**: 투명 창에서 `setNeedsDisplay(true)` 반복 시 자동 클릭 통과가 깨진 사례 (thread/737584) — 명시적 `ignoresMouseEvents`/`hitTest` 사용으로 회피
- **풀스크린 앱 위 표시**: `collectionBehavior`에 `.fullScreenAuxiliary` 포함 (thread/26677)
- **좌표계**: AppKit 좌하단 원점 vs CoreGraphics 좌상단 원점
- **미서명 배포**: macOS 15.1+에서 마찰 증가 → 소스 빌드 안내 + `xattr -cr`, 추후 Homebrew cask

## 레퍼런스 추적 결과 (미해결)

Threads에서 화제가 된 "스틱맨 데스크탑 야구 타격" 오픈소스는 GitHub/웹/gh CLI 검색(검색어 60+회)으로 **찾지 못함**. 바이럴 후 비공개 전환 또는 비영어 README 소형 저장소일 가능성. 근접 사례(모두 야구 요소 없음):

- `chaymore/stickman` — macOS 스틱맨 컴패니언, Swift/AppKit
- `Whiterabbitnode/bonk-box` — 스틱맨 물리 토이, Tauri+Matter.js, Windows
- `coglabss/deskcat` — Electron 투명 오버레이 고양이 (아키텍처 참고용)

→ 원본 링크 확보 시 이 문서에 분석 추가.

## 한계

- GPU 오버헤드 수치는 WebKit 계열 측정치로부터의 추론 (SpriteKit 직접 측정 없음)
- Sonoma 회귀가 SpriteKit 내부 리드로 루프와 상호작용하는지 미확인 → M0 스파이크에서 실기 검증
- 레퍼런스 원본 미확인 → 컨셉은 사용자 설명 기반으로 재구성
