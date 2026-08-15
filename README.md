<div align="center">

<br>

# ⛳ mini-golf

**데스크탑이 코스다**

스틱맨이 여러분의 창 위를 걸어다니며 골프를 칩니다.<br>
공은 실제 물리를 따라 데스크탑을 가로질러 날아갑니다.

<br>

<img src="docs/demo.gif" alt="데스크탑 위에서 드라이버 티샷이 날아간다" width="820">

<br>

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-111?logo=apple&logoColor=fff)
![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=fff)
![MIT License](https://img.shields.io/badge/license-MIT-blue)

<br>

</div>

## 빌드 · 실행

```sh
git clone https://github.com/w0uldy0udaestar/mini-golf.git
cd mini-golf
swift build -c release
.build/release/MiniGolf
```

메뉴바에 ⛳️ 아이콘이 나타나면 준비 완료.

> **서명되지 않은 바이너리** — macOS가 실행을 막으면 `xattr -cr .build/release/MiniGolf` 후 다시 실행하세요.

---

## 이런 게임입니다

<table>
<tr>
<td width="50%" valign="top">

**9홀 랜덤 코스**<br>
<sub>홀마다 성격이 다른 지형 — 능선, 분지, 플래토, 솟은 그린.<br>
워터 · 벙커 · 나무 장애물. 좌우 미러 홀. 매번 다른 코스.</sub>

**클럽 13종**<br>
<sub>드라이버부터 퍼터까지. 클럽별 로프트 · 스핀 물리.<br>
파3는 아이언, 그린에선 퍼터 — 상황별 자동 추천.</sub>

**진짜 물리**<br>
<sub>마그누스 양력 · 백스핀 백업 · 경사 라이 · 립아웃.<br>
풀파워 미스샷 리스크. 퍼터는 순수 지면 롤.</sub>

</td>
<td width="50%" valign="top">

**조용한 계기판**<br>
<sub>상자 없는 타이포 HUD, 헤어라인 지형선.<br>
포인트 컬러는 깃발 레드 하나. 배경은 여러분의 데스크탑.</sub>

**합성 사운드**<br>
<sub>외부 샘플 없이 전부 실시간 합성.<br>
클럽별 타구음 · 바운스 · 홀인 · 립아웃 · 워터.</sub>

**마우스 통과**<br>
<sub>마우스 클릭은 아래 앱으로 그대로 통과.<br>
다른 앱을 쓰는 동안에도 라운드는 계속 흐릅니다.</sub>

</td>
</tr>
</table>

---

## 100가지 모션

스틱맨은 그냥 걷지 않습니다.

<div align="center">

<img src="docs/motions.gif" alt="랜덤 걷기 모션 — 클럽 트월, 에어 스윙, 나비 쫓기" width="820">

<sub>클럽 트월 · 에어 스윙 · 나비 쫓기 · 오케스트라 지휘 · 그리고 아주 가끔, 철푸덕 넘어지기</sub>

</div>

<br>

걷기 중 랜덤으로 발동하는 [100종의 잔동작](docs/motions.md). 걸음당 최대 5개가 겹치지 않게 스케줄됩니다. 경사면에선 발이 지형에 맞춰 기울고, 벙커에서는 느릿느릿, 러프에서는 뻣뻣하게 — 지형마다 걸음이 다릅니다.

---

## 조작

| 입력 | 동작 |
|:---:|---|
| <kbd>←</kbd> <kbd>→</kbd> | 클럽 변경 &nbsp; <sub>→ = 드라이버 쪽 = 멀리</sub> |
| <kbd>↑</kbd> <kbd>↓</kbd> | 백스윙 높이 (파워) |
| <kbd>Space</kbd> | 스윙 |
| <kbd>R</kbd> | 새 라운드 |
| <kbd>Esc</kbd> | 종료 |

메뉴바 ⛳️ **좌클릭** = 재개 / 일시정지 · **우클릭** = 메뉴 (사운드 · 고대비 모드 · 새 라운드 · 종료)

> **밝은 배경 팁** — 흰 창 위에선 헤어라인이 잘 안 보입니다. 우클릭 → **고대비 모드**.

---

## 구조

```
Sources/GolfCore/    물리 · 코스 생성 (UI 무관, 결정론 — 테스트 대상)
Sources/MiniGolf/    앱 · 렌더 (AppKit + SpriteKit, 스틱맨 · HUD · 사운드)
Tests/               XCTest 32종 (탄도 불변식 · 립아웃 · 코스 통계 · 회귀)
```

```sh
swift test        # 전체 테스트
swift build       # 디버그 빌드
```

<details>
<summary><b>데모 · 디버그 플래그</b></summary>

<br>

| 플래그 | 용도 |
|---|---|
| `--demo` | 자동 플레이 (모션 관찰, 사운드 꺼짐) |
| `--seed N` | 코스 시드 고정 |
| `--demo-wall` | 벽 반사 스탠스 관찰 |
| `--demo-trip` | 넘어지기 강제 |
| `--demo-idle` | 조준 유지 (아이들 잔동작 관찰) |
| `--demo-motions` | 모션 100종 순서 시연 |
| `--no-wall-clamp` | 렌더 경계 클램프 해제 |

</details>

---

## 요구 사항

- macOS 13 (Ventura) 이상 — Apple Silicon / Intel
- Swift 5.9+ (Xcode 15+)
- 별도 접근성 권한 불필요

---

<div align="center">
<sub>MIT License · made with SpriteKit, real ballistics, and too many walk animations</sub>
</div>
