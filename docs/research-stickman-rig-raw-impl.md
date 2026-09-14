# 스틱맨 절차적 리그 — 재사용 가능한 구현체·에셋 조사

## 결론 (먼저)

**"우리 리그를 그대로 대체할 Swift/SpriteKit 2D 절차적 스틱맨 구현체는 존재하지 않는다."** 이 영역은 직접 구현이 전제다. 대신 **문제별로 검증된 알고리즘·데이터를 가져오면** 구현 비용이 크게 줄어든다.

- **고무팔 (P1)** → Ryan Juckett의 해석적 2-bone IK(2D 전용, 굽힘 방향 부호 파라미터 포함). Swift 이식 난이도 **하**. 라이선스 무해.
- **발 미끄러짐 전환 (P2)** → 에셋이 아니라 **아키텍처 교체**가 답이다. "포즈 보간"을 버리고 "발 타깃 궤적(plant/swing phase) + IK"로 간다. 이 구조를 쓰는 공개 구현 2개 확인(spine_anim_mcp, Moynilr 2D-procedural-walk).
- **걷기 가속 곡선 (P3)** → Nature *Scientific Data* 보행 데이터셋(CC BY 4.0). 0.7–2.0 m/s 속도별 엉덩이·무릎·발목 관절각 실측치. 추측 대신 실측 곡선을 쓸 수 있다.
- **모션 다양성 (P4)** → Quaternius **Universal Animation Library (CC0, 120+종)**. 라이선스 리스크 0. 사지털 평면 사영으로 2D 관절각 추출.
- **SpriteKit 내장 IK는 채택하지 말 것.** API는 실존하고 macOS 10.10+에서 살아 있으나(비deprecated), 액션 기반 + 실제 SKNode 계층 필수 + 폴 벡터 없음 — 우리 구조(관절 좌표 → 단일 SKShapeNode path)와 근본적으로 안 맞는다.

---

## ① 범위와 방법

- **기간**: 2026-09-14 조사. **도구**: 웹 검색 + 1차 자료 직접 페치.
- **검색어**: `SpriteKit SKReachConstraints / SKAction.reach`, `2D procedural walk cycle stick figure IK github`, `two bone IK analytic 2D pole vector`, `foot lock no sliding procedural walk`, `Rive iOS runtime bone transform`, `spine-ios license`, `DragonBones Swift runtime`, `CC0 humanoid animation library`, `free BVH permissive license`, `walking speed stride length biomechanics`.
- **둘러본 곳**: Apple Developer Documentation(JSON 데이터 엔드포인트로 직접 추출 — 일반 URL은 JS 렌더링이라 본문이 안 나옴), GitHub(REST API로 license/stars/pushed_at 검증), ryanjuckett.com, guillaumeblanc.github.io(ozz-animation), quaternius.com, esotericsoftware.com, help.rive.app, nature.com/PMC, OpenGameArt, itch.io, GDC/archive.org, littlepolygon.com.
- **검증 방식**: 저장소는 `api.github.com/repos/...`로 라이선스 SPDX·스타·마지막 푸시일을 직접 확인. 라이선스 파일이 없으면 **"미확인"**으로 표기하고 사용 금지를 권고.

---

## ② 후보 목록 (문제별)

### P1. 고무팔 = 뼈 길이 고정 + 2-bone IK

#### ★ Ryan Juckett — "Analytic Two-Bone IK in 2D"
- URL: https://www.ryanjuckett.com/analytic-two-bone-ik-in-2d/
- **라이선스**: zlib 스타일 퍼미시브 — "상업적 용도 포함 어떤 목적으로도 사용·자유 재배포 허용"
- **언어/플랫폼**: 데모 `RJ_Demo_IK`는 C#, 수식 자체는 언어 무관
- **발행일**: 2008-12-29 게시 / **2020-11-29 갱신** (수식은 노후화 대상 아님)
- **재사용 범위**: 알고리즘 + 코드 거의 그대로
- **이식 난이도**: **하** — `acos`/`atan2` 기반, Swift로 60줄 내외
- **해결하는 문제**: **P1 직결.** 뼈 길이가 입력 상수이므로 고무팔이 구조적으로 불가능해진다. `solvePosAngSign` 파라미터로 **무릎/팔꿈치 굽힘 방향**을 지정(해가 2개일 때 어느 쪽으로 굽힐지). 타깃이 사거리 밖이면 최대 신장 상태로 타깃 방향을 향함 — 스냅 없이 자연스러운 폴백.
- **판단**: 우리 문제에 가장 정확히 대응하는 단일 자료. 2D 전용이라 3D 라이브러리에서 축약할 필요도 없다.

#### ozz-animation — `IKTwoBoneJob`
- URL: https://github.com/guillaumeblanc/ozz-animation / 샘플 https://guillaumeblanc.github.io/ozz-animation/samples/two_bone_ik/
- **라이선스**: **MIT** (소스 헤더에서 직접 확인. GitHub 자동 판정은 `NOASSERTION`이라 API만 믿으면 오판)
- **언어/활성도**: C++, **2,930 stars**, 마지막 푸시 **2026-08-01** — 활발
- **재사용 범위**: **알고리즘만** (3D 쿼터니언 기반)
- **이식 난이도**: **중** — 3D→2D는 오히려 단순화지만 API 설계를 읽어 개념만 옮기는 작업
- **가져올 가치**: `pole_vector`(굽힘 방향), `mid_axis`(중간 관절 회전축), **`soften`(타깃 도달 직전 점진 접근 — 팔 뻗을 때 "딱" 펴지는 스냅 제거)**, `weight`(IK 블렌딩 0~1 — 걷기↔서기 전환 시 IK를 페이드시킬 수 있음), `reached` 출력(도달 실패 플래그)
- **해결하는 문제**: P1 + **P2의 전환 구간**(`weight` 페이드로 IK를 끄고 켜는 블렌딩)
- **주의**: 문서상 "타깃과 폴 벡터가 정렬되면 체인 방향이 뒤집힌다" — 폴 벡터를 상수로 두지 말고 골반/어깨 기준 상대 방향으로 두어야 함

#### SKConstraint.distance(_:to:) (SpriteKit 내장)
- URL: https://developer.apple.com/documentation/spritekit/skconstraint
- **라이선스/플랫폼**: Apple 내장, macOS 10.10+ / iOS 8+
- **동작**: 노드 간 거리를 `SKRange`로 제한. 문서상 **"액션과 물리 처리가 끝난 뒤 매 프레임 적용"**
- **해결하는 문제**: 개념적으로 P1과 일치
- **판단**: **쓰지 말 것.** 실제 SKNode 계층이 존재해야만 동작한다. 우리는 관절 좌표 배열로 path를 그리므로, 이걸 쓰려면 보이지 않는 프록시 노드 계층을 만들고 매 프레임 좌표를 읽어와야 한다. 직접 벡터 clamp 한 줄이 더 싸다. (추정 — 벤치마크는 안 해봄)

---

### P2. 발 미끄러짐 = 포즈 보간 → 발 타깃 궤적 + IK

#### K-ulucay / spine_anim_mcp
- URL: https://github.com/K-ulucay/spine_anim_mcp
- **라이선스**: MIT / **언어**: Python 3.11+
- **활성도**: **커밋 2개, 스타 1** — 품질 검증 불가, 신뢰도 낮음
- **재사용 범위**: **알고리즘·파라미터 구조만**
- **내용**: 6종 절차적 생성기 — idle(sine breathing), walk(다리 역위상 + 팔 스윙), run(진폭 증폭 + 전방 기울기), jump(crouch→apex), attack(windup-strike-followthrough), hit(recoil-settle). walk/run은 **"2-bone 해석적 IK foot-lock"** — *발목을 plant/swing 경로 위에 놓고 다리를 역산해 도달시킨다.* **4-bone 스틱피겨와 18-bone 캐릭터 모두에서 동작**한다고 명시.
- **해결하는 문제**: **P2, P3, P4의 구조 설계 참고**
- **판단**: 코드를 가져오기엔 신뢰도가 부족하지만, **"발목 궤적을 먼저 정하고 다리를 IK로 푼다"**는 설계가 우리가 가야 할 방향임을 확인해 주는 독립 사례. Spine 4.2 JSON 출력에 강결합돼 있어 그대로 쓸 수는 없다.

#### Moynilr / 2D-procedural-walk (Godot 4)
- URL: https://github.com/Moynilr/2D-procedural-walk / 데모 https://moynilr.itch.io/2d-procedural-ik-walk-demo
- **라이선스**: **미확인** (SPDX 없음) → **코드 복사 금지, 구조만 참고**
- **언어**: GDScript, **스타 2**
- **내용**: 완전 절차적 버전과 IK 버전 2가지. 저자가 "IK 버전의 step solver가 훨씬 단순하고 견고하다"고 명시. 울퉁불퉁한 지형 대응 + 점프.
- **이식 난이도**: **상** — Souperior 애드온과 Godot 노드 구조에 강결합
- **해결하는 문제**: P2 (step solver 개념)

#### ZedManul / souperior-2d-skeleton-modifications (SoupIK)
- URL: https://github.com/ZedManul/souperior-2d-skeleton-modifications
- **라이선스**: **미확인** (GitHub API SPDX `null`) / GDScript / **72 stars**, 마지막 푸시 **2026-09-07** (매우 최신)
- **배경**: Godot 내장 `SkeletonModification2D`는 공식 문서에서 **"experimental — 향후 변경·제거 가능"**으로 표시돼 있어, 커뮤니티가 대체 애드온을 만든 상황
- **판단**: 활발하지만 라이선스 불명 → **읽고 배우는 용도만**

#### Little Polygon — "Procedural Animation: Locomotion (Part 1)"
- URL: https://blog.littlepolygon.com/posts/loco1/ / 코드 https://gist.github.com/maxattack/8369f4ec5f29729d2974aab0afed49ec
- **발행일**: 2023-04-29 / **언어**: C++ / **라이선스**: 명시 없음 (gist)
- **내용**: 가속도 기반 몸통 기울기, sine 파형 골반 운동, IK 발 배치. **"빠를 때 고주파, 느릴 때 저주파"** — 속도 정규화로 보행 주파수 변조.
- **한계**: **Part 1만 공개**. 실제 "발 내딛기(taking steps)"는 다음 편 예고로 끝남 — **후속편 미확인**. 발 미끄러짐·속도 곡선은 다루지 않음.
- **해결하는 문제**: P3 부분

---

### P3. 걷기 가속 곡선

#### ★ Nature *Scientific Data* — "A biomechanics dataset of healthy human walking at various speeds, step lengths and step widths"
- URL: https://www.nature.com/articles/s41597-022-01817-1 (본문은 PMC9669008에서 확인)
- **데이터 호스팅**: figshare — https://doi.org/10.6084/m9.figshare.c.5897423.v1
- **라이선스**: **CC BY 4.0** (출처 표기만 하면 상업 이용·개작 가능)
- **발행일**: **2022-11-16**
- **내용**: 건강한 젊은 성인 N=10. **속도 0.7–2.0 m/s, 보폭 0.5–1.1 m, 보간 0–0.4 m** 범위에서 **33가지 통제 조건**. 역동역학 계산으로 **하지(발목·무릎·엉덩이) 3D 관절 위치·각도·토크·파워** 제공. 사지털 평면 각도 포함. **큐레이션된 5-stride 세그먼트** 제공 — 사이클 루프에 바로 쓸 수 있는 형태.
- **부속 도구**: https://github.com/timvanderzee/human-walking-biomechanics
- **재사용 범위**: **데이터만**
- **이식 난이도**: **중** — MAT/C3D 파싱 후 사지털 각도만 추출해 속도별 룩업 테이블로 굽는 전처리 필요. 런타임 비용은 0.
- **해결하는 문제**: **P3 직결.** 속도가 바뀔 때 보폭·보행 주파수·관절각 진폭이 실제로 어떻게 변하는지 **실측 곡선**을 얻는다. 덤으로 **P2** — 한 보행 사이클 안에서 발이 언제 접지(stance)하고 언제 뜨는지(swing) 위상 비율을 데이터에서 직접 읽을 수 있다.
- **보조 근거(교차검증)**: 보행 속도 = 보폭 × 보행 주파수이며, 성인의 보폭-주파수-속도 관계는 **선형이 아니라 log-log 회귀가 더 잘 맞는다**는 결과(Grieve & Gear, *Ergonomics* 9(5), 1966 — https://www.tandfonline.com/doi/abs/10.1080/00140136608964399). 1966년 자료이나 이후 연구가 반복 확인한 고전이며, 위 Nature 데이터셋이 현대적 실측으로 뒷받침한다. → **속도-보폭을 선형으로 매핑하면 부자연스러워지는 이유가 여기 있다.**

#### David Rosen (Wolfire) — GDC 2014 "Animation Bootcamp: An Indie Approach to Procedural Animation"
- 무료 시청: https://archive.org/details/GDC2014Rosen / https://www.youtube.com/watch?v=LNidsMesxSE / GDC Vault https://www.gdcvault.com/play/1020583/Animation-Bootcamp-An-Indie-Approach
- **발행일**: 2014 (12년 전 — 하지만 방법론이라 노후화 영향 적음)
- **재사용 범위**: **방법론만** (공개 코드 없음)
- **핵심**: Overgrowth의 걷기·달리기는 **각각 키프레임 4개**(좌/우의 pass 포즈 + reach 포즈)로만 구성되고 나머지는 절차적으로 층을 쌓는다.
- **해결하는 문제**: P3, P4 — "포즈를 많이 만들지 말고 소수 키포즈 + 절차적 레이어" 전략의 원전. 우리 리그 철학과 정확히 일치.

---

### P4. 모션 다양성 (포즈·키프레임 에셋)

#### ★ Quaternius — Universal Animation Library
- URL: https://quaternius.com/packs/universalanimationlibrary.html / https://quaternius.itch.io/universal-animation-library / Godot Asset Store 등재
- **라이선스**: **CC0** — 개인·교육·상업 무제한, 귀속 표기조차 불필요
- **규모**: **120+ 애니메이션**, universal humanoid rig (UE/Godot/Unity 리타깃 전제)
- **포맷**: FBX, GLB (Blend는 상위 티어)
- **최종 업데이트**: **2025-03**
- **수록**: 8방향 locomotion, jog, sprint, push, crawl, swim, sit, death, combat/gun, **emotes**
- **재사용 범위**: **데이터만**
- **이식 난이도**: **중** — GLB에서 본 회전 키프레임을 읽어 **사지털 평면으로 사영**해 2D 관절각으로 변환하는 오프라인 컨버터가 필요. 런타임 의존성은 0.
- **해결하는 문제**: **P4 직결.** 라이선스 리스크가 완전히 0이라는 점이 결정적.
- **자매 팩**: Quaternius RPG Characters (CC0) — 캐릭터당 14종(Idle/Death/Attacking/Run/Roll/Walk/**Pick Up** 등). "줍기" 동작이 여기 있다.

#### Mixamo (Adobe)
- URL: https://www.mixamo.com
- **라이선스**: 무료 Adobe 계정으로 이용, **로열티프리 무제한 상업 이용**. 단 **원본 애니메이션/캐릭터 파일의 재배포·에셋팩 재판매 금지** (완성 제품에 포함하는 것은 허용).
- **재사용 범위**: 데이터만. waving / cheering / picking up 등 요청한 동작이 모두 있음
- **⚠ 신뢰도 주의**: "Adobe가 수년째 미업데이트, 2025-06 다목일 다운타임, 지원 중단 상태"라는 서술은 **2차 출처 1개(Cinevva 가이드)에서만 확인**했고 **Adobe 공식 발표는 찾지 못했다.** 서비스 자체는 2026-09 현재 종료 공지 없음. → **추정으로 취급. 의존한다면 자산을 미리 내려받아 보관할 것.**
- **해결하는 문제**: P4

#### Apple Vision — `VNDetectHumanBodyPoseRequest`
- URL: https://developer.apple.com/documentation/vision/vndetecthumanbodyposerequest
- **플랫폼**: **macOS 11.0+** / iOS 14+ (비deprecated. 일부 `...forRevision:` 메서드만 deprecated)
- **동작**: 이미지 기반 요청(`VNImageBasedRequest`) — **영상은 프레임별로 돌려야 함**. `VNHumanBodyPoseObservation`으로 관절 키포인트 + confidence 반환.
- **재사용 범위**: **도구** — 레퍼런스 영상에서 **2D 관절 좌표를 직접 추출**. 우리 리그의 입력 포맷(관절 점 좌표)과 **1:1로 맞는 유일한 후보**. 3D→2D 사영 변환이 아예 필요 없다.
- **이식 난이도**: **하** — macOS 내장, 외부 의존성·라이선스 이슈 0
- **해결하는 문제**: **P4**, 그리고 **P2/P3의 검증 수단**(실제 영상의 발 접지 타이밍과 우리 리그를 나란히 비교)
- **주의**: API는 무료지만 **입력 영상의 저작권은 별개**. 자체 촬영 또는 퍼미시브 라이선스 영상만 쓸 것.

#### CMU Motion Capture Database (이미 사용 중)
- 사용 시 권장: cgspeed의 Daz-friendly BVH 변환본(https://sites.google.com/a/cgspeed.com/cgspeed/motion-capture) — 원본 CMU BVH의 스켈레톤 이슈가 패치돼 있음. 재판매 금지 조건은 이미 인지하고 있는 대로.

#### Bandai Namco Research Motion Dataset — **제외 권고**
- BVH 대규모 라이브러리이나 **CC BY-NC-ND** (비상업·개작금지). 개작금지 조항 때문에 관절각 추출·변환 자체가 저촉될 소지가 크다.

#### rgsdev — "Animated Stick Figure Character 2D Free CC0"
- https://opengameart.org/content/animated-stick-figure-character-2d-free-cc0 / https://rgsdev.itch.io/animated-stick-figure-character-2d-free-cc0
- **CC0**, 512×512 스프라이트 시트. Idle/Walk/Run/Jump/Slide/Dash/Climb/Damage/Death/Attack Combo
- **재사용 범위**: **시각 레퍼런스만.** 관절 데이터가 아니라 픽셀이다. 포즈를 뽑으려면 수작업 로토스코핑 — 비용 대비 이득 없음. **다만 Vision 포즈 추정을 이 스프라이트에 돌려보는 건 시도해볼 만함** (검증 안 됨, 추정).

#### Rive Community 파일
- 라이선스: **CC BY** (Rive 문서·ToS 기준 — 커뮤니티 파일은 모두 CC BY로 공유, 귀속 표기 시 상업 이용 가능)
- 휴머노이드 벡터 리그가 있다면 본 구조 참고 가능. 단 `.riv` 파싱으로 데이터를 뽑아내는 경로는 **미확인**.

---

### ② -2. SpriteKit·Apple 내장 IK — 실존 여부와 한계 (요청 항목 2)

**실존 확인됨** (Apple 공식 문서, 2026-09-14 조회):

| API | 가용 플랫폼 | 상태 |
|---|---|---|
| `SKAction.reach(to:rootNode:duration:)` | macOS 10.10+, iOS 8+, tvOS 9+, visionOS 1+, watchOS | 비deprecated |
| `SKAction.reach(to:rootNode:velocity:)` | 동일 | 비deprecated |
| `SKNode.reachConstraints` | 동일 | 비deprecated |
| `SKReachConstraints(lowerAngleLimit:upperAngleLimit:)` | 동일 | 비deprecated |
| `SKConstraint.distance / positionX / positionY / orient / zRotation` | 동일 | 비deprecated |

**문서상 동작**: 대상 노드부터 `rootNode`까지의 조상 노드들의 회전값을 IK로 계산 → 각 노드를 anchor point 기준으로 회전 → 각 노드의 `reachConstraints`로 회전 제한 → 도달 불가 시 **best effort**로 최대한 근접. 역재생 불가(reverse는 자기 자신).

**우리 케이스에 부적합한 이유 (4가지, 모두 1차 문서 근거):**

1. **액션 기반 — 즉시 솔버가 아니다.** 두 오버로드 모두 `duration` 또는 `velocity`를 받는 **시간 애니메이션**이다. 매 프레임 해를 요구하는 60fps 절차적 리그에서는 프레임마다 SKAction을 생성·실행해야 하고, 이는 API 의도 밖이다.
2. **실제 SKNode 계층이 필수.** 솔버는 노드들의 `zRotation`을 바꾼다. 우리는 관절 좌표 배열로 **단일 SKShapeNode path**를 그리므로, 사용하려면 보이지 않는 프록시 노드 트리를 유지하고 매 프레임 좌표를 역으로 읽어와야 한다.
3. **폴 벡터가 없다.** 굽힘 방향은 `reachConstraints`의 각도 상·하한으로만 **간접 제어**된다. "무릎은 항상 앞으로, 팔꿈치는 항상 뒤로" 같은 명시적 지정이 불가능하다. Ryan Juckett의 `solvePosAngSign` 한 줄로 되는 일이다.
4. **솔버 알고리즘·성능이 비공개.** 2관절 해석해인지 반복 수렴인지 문서에 없다. 성능·수렴 특성에 대한 Apple의 언급도 없다.

**참고 자료의 노후화**: 가장 널리 인용되는 튜토리얼(Kodeco, https://www.kodeco.com/1158-spritekit-and-inverse-kinematics-with-swift)은 **2016-05-12 게시 / 2016-09-30 Swift 3·iOS 10 기준 갱신** — 10년 전 자료다. 이를 따라 만든 커뮤니티 저장소들(DragonZ/SKKinematics-Game-Tutorial, huydemi/IK-Ninja)도 "Swift·Xcode 변경으로 문제가 있어 우회 구현이 필요했다"고 기록하고 있다. **2020년 이후의 실사용 경험담은 찾지 못했다** — 이 기능이 사실상 쓰이지 않고 있다는 간접 신호로 해석한다(추정).

**결론**: SpriteKit IK를 우회하고 2-bone 해석해를 직접 작성하라. 코드량이 10배 적고 제어권은 훨씬 크다.

---

### ② -3. 2D 캐릭터 애니메이션 런타임 (요청 항목 4)

| 런타임 | 라이선스 | 언어/플랫폼 | 활성도 | 본 트랜스폼만 뽑아쓰기 | 판정 |
|---|---|---|---|---|---|
| **maxgribov/Spine** | **MIT** | **Swift + SpriteKit** (iOS/macOS/tvOS/watchOS) | 200★, 푸시 2024-09-28 | **가능 (설계상 최적)** | **조건부 채택 가능** |
| spine-ios (공식) | Spine Runtimes License | Swift(spine-c 래퍼), SwiftUI/UIKit/AppKit | 활발 | 가능 | 에디터 라이선스 필수 |
| rive-ios | **MIT** | Swift | 821★, 푸시 **2026-09-14** | GameKit에서 `worldTransform`(Mat2D) get/set — **preview** | 리스크 높음 |
| simonkim/spine-spritekit | BSD-3 | **Obj-C** | 99★, 푸시 **2014-01-25** | — | **제외 (12년 방치)** |
| DragonBones | — | Swift 런타임 **없음** | — | — | **제외** |

**maxgribov/Spine (가장 실용적인 도구 체인)**
- https://github.com/maxgribov/Spine — MIT, Swift, 200 stars, 마지막 푸시 2024-09-28
- Spine ESS 4.1+ JSON을 SpriteKit에 로드. 본 애니메이션, 스킨, 슬롯 애니메이션, 바운딩박스 기반 물리바디 지원. **메시·Pro 기능 없음** (우리는 스프라이트를 안 쓰므로 무관).
- **우리에게 맞는 이유**: Spine에서 스틱맨 리그를 만들어 애니메이션을 찍고, 런타임에서 **본의 위치·회전만 읽어** 우리 `SKShapeNode` path 생성기에 먹이면 된다. Spine JSON 파서 + 타임라인 보간 + 본 계층 해석이 **이미 Swift로 작성되어 있다.** → P4를 가장 빠르게 해결.
- **⚠ 라이선스 미해결 쟁점**: 코드는 MIT지만, Spine **에디터**는 유료다 — Essential **$69**, Professional **$379**, Enterprise $2,499+$379/user/년(연 매출 $500k 이상 기업 필수). 그리고 Esoteric의 Spine Runtimes License는 "런타임 통합은 무료지만 **소프트웨어 사용자가 각자 Spine 라이선스를 보유해야 한다**"고 규정한다. maxgribov 런타임은 Esoteric 코드를 쓰지 않은 독자 구현이므로 이 조항의 적용 대상인지 **불명확하다. 상업 배포 전 법무 확인 필요.** (미확인)

**rive-ios**
- MIT, 활발(2026-09-14 푸시), **벡터 네이티브**라 스틱맨과 궁합이 좋음. Rive GameKit에서 컴포넌트를 이름으로 조회해 `worldTransform`(Mat2D, 6요소) get/set 가능.
- **채택 반대 근거 3가지**: ① GameKit은 **technical preview, API 변경 예고됨** ② 지원 플랫폼이 **iOS/macOS(Apple Silicon)로 한정** ③ 무엇보다 **렌더링이 SpriteKit이 아니라 Rive 렌더러로 넘어간다** — 투명 데스크탑 오버레이 합성 파이프라인을 건드리게 되는데 이건 이 프로젝트에서 이미 가장 민감한 부분이다. "본 트랜스폼만 읽고 그리기는 우리가 한다"는 사용법이 문서화된 경로인지 **확인하지 못했다(추정: 가능하나 실험적)**.
- 에디터 가격: Free / Cadet $9/mo / Voyager $32/mo / Enterprise $120/mo. 커뮤니티 파일은 CC BY.

---

## ③ 추천 Top 3

### 1위. Ryan Juckett 해석적 2-bone IK → Swift 직접 이식
**근거**: (a) 우리 문제와 차원이 정확히 일치하는 유일한 자료 — 2D, 2관절, 굽힘 방향 부호 지정, 사거리 초과 폴백 내장. (b) 라이선스가 상업 이용·재배포 모두 허용이라 법적 검토가 불필요. (c) 이식 난이도 **하** — 외부 의존성 0, 60줄 내외. (d) **P1(고무팔)을 구조적으로 제거**한다: 뼈 길이가 입력 상수가 되므로 늘어날 방법이 없어진다.
**보강**: ozz-animation의 `soften`(도달 직전 스냅 제거)과 `weight`(IK 페이드) 개념을 함께 이식. 둘 다 MIT라 참고 자유.

### 2위. Nature/figshare 보행 바이오메카닉스 데이터셋 (CC BY 4.0)
**근거**: (a) **P3(걷기 가속 곡선)에 추측이 아닌 실측 데이터**를 넣을 수 있는 유일한 후보. 0.7–2.0 m/s × 33조건의 엉덩이·무릎·발목 각도. (b) 5-stride 큐레이션 세그먼트가 제공돼 루프 제작이 쉽다. (c) CC BY 4.0 — 귀속 표기만으로 상업 이용 가능. (d) **P2도 함께 해결**: 보행 사이클 내 stance/swing 위상 비율을 데이터에서 직접 읽어 발 접지 타이밍을 정할 수 있다. (e) 속도-보폭 관계가 log-log라는 고전 연구와 교차검증돼 있어, "선형 매핑이 왜 부자연스러운가"에 대한 답까지 나온다.

### 3위. Quaternius Universal Animation Library (CC0)
**근거**: (a) **라이선스 리스크가 완전히 0** — CC0는 귀속 표기도 불필요하다. Mixamo(재배포 금지 + 서비스 불확실성), Bandai Namco(NC-ND), CMU(재판매 제한) 어느 쪽보다 깨끗하다. (b) 120+ 동작 + universal humanoid rig로 리타깃 전제 설계. (c) 2025-03 갱신으로 최신. (d) **P4(모션 다양성) 직결.** 필요한 건 GLB→사지털 관절각 오프라인 컨버터 하나뿐이고, 런타임 의존성은 생기지 않는다.
**보강**: 특정 동작(줍기·손 흔들기)이 부족하면 **Apple Vision `VNDetectHumanBodyPoseRequest`로 자체 촬영 영상에서 2D 관절 좌표를 직접 추출**한다. macOS 11+ 내장, 우리 리그 입력 포맷과 1:1로 맞아 사영 변환조차 불필요하다.

**아키텍처 권고 (에셋으로는 못 푸는 것)**: **P2(발 미끄러짐)는 구현체를 가져온다고 해결되지 않는다.** "서기 포즈 ↔ 걷기 포즈 보간"을 버리고 **"발목 타깃을 plant/swing 궤적 위에 배치 → 다리를 2-bone IK로 역산"**으로 바꿔야 한다. 이 구조면 접지 중인 발의 월드 좌표를 고정할 수 있고, 전환은 IK weight 페이드로 처리된다. 독립 구현 2건(spine_anim_mcp, Moynilr)이 같은 구조를 채택했고, Overgrowth의 4-키프레임 방법론도 같은 철학이다.

---

## ④ 한계와 공백

**못 찾은 것**
1. **Swift/SpriteKit용 2D 절차적 스틱맨 리그를 그대로 쓸 수 있는 저장소는 없다.** 검색어를 여러 각도로 바꿔 봤으나(`spritekit procedural animation stickman`, `swift 2D IK library`, `skeleton rig bone length constraint`) 나온 것은 전부 Spine 런타임 아니면 튜토리얼 예제였다. **이 영역은 직접 구현이 전제**라고 결론 내린다.
2. **Swift 네이티브 2D IK 라이브러리 부재.** `bbeaumont/InverseKinematics`는 이름만 맞고 **ActionScript 3, 스타 3, 저자 본인이 "실용적인 내용은 별로 없다"고 README에 명시** — 제외했다.
3. **Little Polygon 로코모션 시리즈의 Part 2(실제 발 내딛기)를 찾지 못했다.** Part 1이 예고만 하고 끝난다.
4. **Rain World 절차적 애니메이션의 공식 공개 구현은 없다.** Merxon22의 Medium 재현 시리즈(Unity C#)가 있으나 2차 자료이고, 소프트바디 체인 중심이라 우리의 관절 리그와 접점이 적다. GDC Vault의 Rainworld 애니메이션 세션도 코드는 없다.

**라이선스 불명 (사용 금지 권고)**
- `ZedManul/souperior-2d-skeleton-modifications` — SPDX `null`, 라이선스 파일 404
- `Moynilr/2D-procedural-walk` — 라이선스 미기재
- `davepagurek/Axis` (스틱피겨 키프레임 애니메이터, 36★) — 라이선스 미기재 + 백엔드가 Perl + 포즈 데이터 포맷·내보내기 경로 확인 실패 → 제외
- Little Polygon gist — 라이선스 명시 없음

**신뢰도가 낮은 항목 (교차검증 실패 = 단일 출처)**
- **Mixamo 유지보수 상태**: "Adobe가 지원 중단으로 언급, 2025-06 다일간 다운타임" 주장은 2차 출처 1개(Cinevva 가이드, AI 생성 의심)에서만 확인. Adobe 공식 발표는 찾지 못했다. **서비스 종료 공지는 없음.** 의존한다면 자산을 선제적으로 내려받아 보관할 것.
- **spine_anim_mcp**: 커밋 2개 / 스타 1. README 설명은 우리 요구와 정확히 맞지만 **코드 품질은 검증 불가.** 알고리즘 구조 참고용으로만 취급했다.
- **ozz-animation 라이선스**: GitHub API는 `NOASSERTION`을 반환하지만 소스 헤더에서 MIT를 직접 확인했다. API만 신뢰하면 오판하는 사례.

**미확인 상태로 남긴 기술 질문**
- `maxgribov/Spine`(MIT, 독자 구현)을 상업 배포할 때 Esoteric의 "사용자별 Spine 라이선스 보유" 조항이 적용되는지 — **법무 확인 필요**
- Rive에서 "본 트랜스폼만 읽어 SpriteKit이 그리게 하기"의 실제 가능 여부 (GameKit `worldTransform` API는 존재 확인, 이 사용 패턴의 문서화는 확인 실패)
- SpriteKit `reach()` 솔버의 내부 알고리즘·프레임당 비용 (Apple 문서에 기재 없음)
- OpenGameArt 스틱피겨 스프라이트에 Vision 포즈 추정을 적용한 결과 (미시도)

**발행일 경과 표시**
- Ryan Juckett 2008 게시 / 2020 갱신 — 수식이라 노후화 영향 없음
- GDC 2014 Rosen — 12년 경과, 방법론이라 유효
- Grieve & Gear 1966 — 60년 경과. 고전으로 반복 인용되며 2022년 Nature 데이터셋이 현대 실측으로 뒷받침
- Kodeco SpriteKit IK 2016 — **10년 경과, 코드 그대로는 동작 안 할 가능성 높음**
- simonkim/spine-spritekit 2014 — **12년 방치, 제외**
