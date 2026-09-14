# 스틱맨 절차적 리그: 검증된 기법 리서치

조사일 2026-09-14 · 대상: Swift + SpriteKit 사이드뷰 2D, 60fps, 관절 점 좌표 직접 구동

---

## 0. 결론 먼저

- **(A) 팔다리 늘어남** → Ryan Juckett의 해석적 2-bone IK(2008, 코사인법칙) 그대로 이식. 사이드뷰에서는 pole 벡터가 필요 없고 **관절당 굽힘 부호를 상수로 고정**하면 끝난다(무릎 = 진행방향 앞, 팔꿈치 = 뒤). 도달 불가 시 cos 클램프만 쓰면 "쫙 펴진 다리"로 스냅되므로, **타깃을 (L1+L2)×0.98로 먼저 클램프 + 잔여분은 골반 하강(root 보상)으로 흡수**하는 하이브리드를 권장.
- **(B) 느릿하다 가속** → 생체역학상 보행 개시는 **앞으로 몰린(front-loaded) 램프**다. 정상 속도의 대부분을 1걸음, 실질적 정상 상태를 2~3걸음(≈1.0~1.6초)에 도달. 포물선을 버리고 **임계감쇠 스프링(halflife 0.30~0.35s)** 으로 목표 속도를 추종. 동시에 **보폭·케이던스를 둘 다 √v에 비례**시켜야 한다(walk ratio 상수성에서 유도) — 첫 걸음이 짧고 둘째부터 정상인 실제 패턴이 공짜로 나온다.
- **(C) 발 미끄러짐·끊김** → 포즈 블렌딩을 다시 시도하지 말 것. 원인은 "두 포즈의 평균 발 위치는 어느 쪽 접지점도 아니다"라는 구조적 문제다. 해법 3층: ① **거리 구동 위상(distance matching)** — 사이클 위상을 시간이 아니라 이동 거리로 진행시키면 미끄러짐이 정의상 0 ② **접지 래치(foot plant latch)** — 접지 순간 월드 x를 동결 ③ **정지 지점 예측 + 마지막 1~2걸음 보폭 조정**으로 어드레스 발 위치에 정확히 착지. 상체 등 비접촉 부위만 **inertialization**(크로스페이드가 아니라 오프셋 감쇠)으로 0.2~0.4초 처리.

---

## 1. 범위와 방법

- 조사 항목 5종(2-bone IK / 보행 개시·종료 생체역학 / 절차적 걷기 구현 / 전환 기법 / 스틱피겨 원칙).
- 방법: 웹 검색 + 원문 페치. 1차 자료(논문 초록·공식 엔진 문서·원저자 블로그) 우선, 접근 차단된 논문(ScienceDirect 403, PubMed/Springer/Nature 리다이렉트)은 검색 스니펫·2차 요약으로 대체하고 **본문에 그 사실을 표시**했다.
- PDF 2건(Game AI Pro Ch.25, Bollo GDC 2018 슬라이드)은 로컬 렌더러(poppler) 부재로 본문 추출 실패 → **미확인**으로 표기.
- 사용 출처 약 25종. 핵심 수식은 원문 표기를 그대로 인용.

---

## 2. 항목별 발견

### 2-1. 2-bone IK (2D) — 신뢰도 높음, 1차 자료 2종 교차 확인

**Ryan Juckett, "Analytic Two-Bone IK in 2D"** (ryanjuckett.com, 2008-12-29 게시 / 2020-11-29 갱신). 원문 수식:

- 도달 가능 영역(환형): 최소 `|d₁ - d₂|`, 최대 `d₁ + d₂`, 타깃 거리 `√(x² + y²)`
- 코사인법칙: `h² = d₁² + d₂² - 2d₁d₂ cos β`, 단 `β = π - θ₂`
- 두 번째 관절각:
  `cos θ₂ = (x² + y² - d₁² - d₂²) / (2 d₁ d₂)`
  `θ₂ = arccos((x² + y² - d₁² - d₂²) / (2 d₁ d₂))`
- 첫 번째 관절각:
  `θ₁ = atan2( y(d₁ + d₂ cos θ₂) - x(d₂ sin θ₂),  x(d₁ + d₂ cos θ₂) + y(d₂ sin θ₂) )`
- **굽힘 방향**: "negate the new θ₂" — 즉 θ₂의 부호를 뒤집으면 반대 방향 해. 3D의 pole 벡터가 2D에서는 **부호 하나**로 축약된다.
- **도달 불가 처리**: cos 값이 [-1,1]을 벗어나면(<-1 너무 가까움, >1 너무 멂) "clamps the value into the legal [-1,1] range" — 정확해가 없을 때 근사 최적해.
- 참조 구현(C#)에 0 길이 뼈 나눗셈 방지, `solvePosAngle2` 굽힘 방향 파라미터, 유효해 여부 반환값 포함.

**Alan Zucconi, "Inverse Kinematics in 2D — Part 1"** (2018-05-02) — 동일 코사인법칙을 삼각형 내각으로 표기:
`cos(α) = (b² + c² - a²)/(2bc)`, `cos(β) = (a² + c² - b²)/(2ac)`, `B = π - β`, `A = α + A'` (단 `A' = arctan((C_Y - A_Y)/(C_X - A_X))`). 해가 2개임을 명시. → Juckett과 수학적으로 동일, 교차 검증 성립.

**Godot 공식 문서 — `SkeletonModification2DTwoBoneIK`** (docs.godotengine.org, stable): 코사인법칙 기반임을 명시. 프로퍼티:
- `target_minimum_distance`: "If the target is closer than this distance, the modification will solve as if it's at this minimum distance."
- `target_maximum_distance`: 최대 거리 초과 시 최대 거리로 간주.
- `flip_bend_direction`: true면 "the bones in the modification will bend outward as opposed to inwards when contracting."
→ **프로덕션 엔진도 굽힘 방향을 불리언 1개, 도달 불가를 거리 클램프로 처리**한다는 확인.

**Max Kaufmann, Little Polygon Blog "Procedural Animation: Inverse Kinematics"** (2023-02-26): 도달 불가 시 `TargetOffset.GetClampedToMaxSize(MaxLength)`, 여기서 **MaxLength = 뼈 길이 합 − 1cm** — 수학적 경계 케이스(완전 신전 시 각도 미분 발산) 회피 목적. 개발자 블로그(2차)지만 실무 관용구로 널리 쓰임.

**관절 각 제한**: Daniel Holden(Epic Games Principal Animation Programmer), "Joint Limits" (theorangeduck.com, 2021-06-11)은 직사각/타원/K-DOP 투영, swing-twist 분해, 그리고 **`tanh` softening**("giving some leeway when the projection is from very far")을 제시. 하드 클램프의 팝을 없애는 용도로 2D에도 그대로 적용 가능.
※ 주의: 한 페치 도구가 theorangeduck 저자를 "Jonathan Blow"로 잘못 표기했다. about 페이지 재확인 결과 **Daniel Holden**이 맞다.

**보행 시 실제 관절 가동 범위(참고값, 2차 요약)**: 무릎 — 입각기 최대 약 20° 굴곡, 유각기 최대 60~70° 굴곡. 고관절 — 최대 신전 평균 7°, 유각기 말 최대 굴곡 평균 37°. 어깨 peak-to-peak 약 40~50°, 팔꿈치 약 90°(단 팔꿈치 90°는 단일 출처 PMC3106274 기반이며 과제 조건이 일반 보행과 다를 수 있음 — **교차 검증 실패, 낮은 신뢰도**).

---

### 2-2. 보행 개시·종료 생체역학 — 문헌 내 이견 존재, 명시함

**개시(gait initiation)**

- **Brenière Y., Do M.C., "When and how does steady state gait movement induced from upright posture begin?", J. Biomechanics 19 (1986) 1035–1040.** 결론: 보행 개시의 목적은 **첫 걸음 안에** 피험자를 정상 상태 보행에 놓는 것이며, 그 시간은 개인의 신체 분절 파라미터에만 의존하는 불변값이다. 첫 걸음 끝의 무게중심 전진 속도는 둘째 걸음의 평균 전진 속도와 유의차가 없다. (원문 유료 — 초록·인용 기반. **발행 40년 경과, 고전이지만 오래된 정보**)
- **반론/수정**: Miller & Verstraete (1996, 기계적 에너지 분석)는 3걸음 끝에 정상 상태 도달. 현재 보행 분석 실무 권고는 **측정 전후 최소 3걸음 확보**.
- **경사 보행 연구** (Gait & Posture, 2020/2021, "Analysis of sloped gait: How many steps are needed to reach steady-state walking speed after gait initiation?", PMID 33152612 — ScienceDirect 403으로 초록 원문 미확보, 검색 스니펫 인용): 모든 경사에서 **3번째 걸음에 정상 속도의 ≥90%(오르막) / ≥95%(내리막)** 도달. 수평 속도 상대 변화 기준으로는 **2번째 걸음** 후 이미 정상 상태.
- **2025년 연구** (PMID 40527299, 노화·파킨슨 비교): 필요한 걸음 수가 변수마다 다름 — **전진 속도·보폭·균형 지수는 2걸음, margin of stability는 1걸음**. (PubMed 접근 차단, 검색 스니펫 인용 — **단일 경로 확인**)

→ **종합 판단**: "1걸음" vs "3걸음"의 이견은 *측정 변수의 차이*로 설명된다. 속도만 보면 1~2걸음, 전신 안정화까지 보면 3걸음. 게임용으로는 **2~3걸음, 시각적으로는 첫 걸음에서 이미 거의 다 붙는 형태**가 두 진영 모두와 모순되지 않는다.

**종료(gait termination)**

- **Crenna P., Cuong D.M., Brenière Y., "Motor programmes for the termination of gait in humans: organisation and velocity-dependent adaptation", J. Physiol. 537(Pt 3):1059–1072, 2001-12-15** (PMC2279001, 원문 확인):
  - 느린 보행 → **1걸음(one-step) 정지**. 자연/빠른 속도 → **1스트라이드(one-stride, 짧은 추가 스텝 포함) 정지**가 필요하며, 빠른 속도에서는 **98%의 시도가 one stride로 정지**.
  - 타이밍: 정지 신호 후 **입각지 EMG 제동 개시 ≈150ms**, **후방 지면반력 증강 ≈230ms**, **유각지 제동 ≈330ms**.
  - 입각지는 원위→근위(soleus, hamstring 중심), 유각지는 근위→원위(슬관절 신근 중심). 속도가 빠를수록 soleus 의존이 줄고 hamstring/고관절 신근 의존이 커짐.
- 계획된 정지(PGT)는 **발목 주도 제동**, 비계획 정지(UGT)는 고관절·슬관절 주도 흡수 — Appl. Sci. 13:7323 (2023) 등 2차 확인.
- 상충 데이터: "교차로 접근 시 의도적 조기 정지는 평균 약 3초, 약 6걸음에 걸쳐 감속"이라는 서술도 있으나 이는 *여유 있는 자발적 조기 정지* 상황으로 문맥이 다르다. 신호 기반 즉시 정지는 1~2걸음이 맞다.

**속도–보폭–케이던스(walk ratio)**

- Walk ratio(WR) = 보폭 / 케이던스는 **속도 독립 상수**. 건강 성인에서 신장 정규화 시 **약 6.5 mm/(step/min)**, 비정규화 시 **약 0.006~0.007 m·step⁻¹·min**. (Sekiya & Nagasaki 계열 + Rota et al., Int J Rehabil Res, 2011-09 — 2개 경로 교차 확인)
- 정상 성인 참고값: 보행 속도 **1.35 ± 0.23 m/s**(41–50세 그룹), 케이던스 **약 101.8 steps/min(범위 80~120)**, 보폭은 신장에 비례(191–200cm군 0.91 ± 0.05 m).
- **유도(본 리서치의 추론, 원문 주장 아님)**: WR 상수성 `SL = WR · c` 와 `v = SL · c / 60` 을 결합하면
  `v ∝ c²` → **`c ∝ √v`, `SL ∝ √v`**.
  즉 속도가 1/4로 떨어지면 보폭과 케이던스가 각각 절반이 된다. 검산: WR=6.5, c=110 → SL=0.715 m, v=1.31 m/s (참고값과 일치).
- COM 수직 진폭: 최저 속도 **2.74 ± 0.52 cm** → 최고 속도 **4.83 ± 0.92 cm**, 사인 형태, **스트라이드당 2회**(2차 조화파). (Orendurff et al. 계열, 2004/2005 — 검색 스니펫 기반, 단일 경로)
- 팔–다리는 **역위상(antiphase)** 스윙. (복수 출처 일치)

---

### 2-3. 절차적 걷기 사이클 구현 기법

- **David Rosen (Wolfire), "Animation Bootcamp: An Indie Approach to Procedural Animation", GDC 2014** (GDC Vault / Internet Archive에 무료 공개). 요지: 아주 적은 키프레임으로 상호작용적·유연한 애니메이션 구현. 2차 서술에 따르면 **걷기·달리기 사이클이 각각 키프레임 4장**(좌/우의 pass 포즈 + reach 포즈)으로 구성되고, **IK 노드가 다리 관절을 회전시켜 발이 올바른 위치에 놓이게** 하며, 전체 철학은 "**anticipation/response와 squash-and-stretch 같은 전통 애니메이션 관행을 자동화**"하는 것. ※ 영상 본문을 직접 확인하지 못했으므로 **4키프레임 수치는 2차 출처(개발자 블로그) 기반**.
- **Rain World — Joar Jakobsson & James Therrien, "Rain World Animation Process", GDC 2016 Animation Bootcamp** (GDC Vault / GDC YouTube). 사지와 꼬리는 **베이스 모델 위에 덧그려지는 장식 레이어**이며 플레이어 입력에 따라 절차적으로 애니메이션된다. Jakobsson: "절차적 애니메이션을 하려고 시작한 게 아니라, slugcat의 팔다리를 움직여야 했고 게임에서 뭔가를 움직이는 방법이 코드였을 뿐".
- **전통 워크 사이클 4포즈**: contact / down / passing / up. Richard Williams, *The Animator's Survival Kit*(2001) 기준으로 한 스텝이 contact에서 시작해 contact로 끝나며 **한 사이클 총 8포즈**. contact 포즈가 가장 중요(여기서 틀리면 나중에 고치기 어려움). ※ 원서 미확인, 교육용 2차 출처 복수 일치.
- **Stride Warping** (Unreal Engine 5 공식 기능): 단일 걷기 사이클의 **발 배치 위치를 실시간으로 이동시켜 스트라이드 길이를 실제 이동 속도에 맞추는** 노드. 속도별 애니메이션을 따로 만들지 않고 미끄러짐을 제거.
- **Foot Locking**: 접지(plant) 구간을 감지해 **해당 발의 월드 위치를 IK로 고정**, lift-off까지 유지 → 속도 미세 불일치가 미끄러짐으로 보이지 않게 함.
- **발 궤적(lift profile)**: 보간 파라미터에 **사인 곡선 형태의 수직 아크**를 더하는 방식이 게임에서 일반적. 로보틱스에서는 **2차/3차 베지에**(제어점 좌표를 실제 속도·스윙/스탠스 지속시간·높이로 결정)나 **5차 다항식**(가속도 연속성 보장)을 사용. 좌우 발은 **위상 오프셋**.
- **몸 바운스·기울임** (Max Kaufmann, Little Polygon "Procedural Locomotion Part 1", 2023-04-29): 힙 오실레이션 `HipOffset.Z = HipMulti * (HipBiasZ + HipOffsetZ * Sin(HipPhase * 2π))`, **롤 회전은 절반 주파수**(케이던스용). 가속도 기반 린은 `Lean = UpVector ^ Accel`, 최대 45°로 클램프, 감쇠 스프링으로 평활화. 예시 파라미터: LeanMulti 0.64, HipPhaseSpeed 2.0, HipOffsetZ 20, HipBiasZ −17.

---

### 2-4. 전환 기법 — 여기가 문제 C의 핵심

**(a) Distance Matching — 정지 지점에 발을 정확히 내려놓기**

원출처: Laurent Delayen(Epic Games), Paragon 애니메이션 기술 발표, **nucl.ai 2016** (Distance Matching + Animation Warping). 현재는 Unreal Engine 공식 기능으로 문서화.

Unreal 공식 문서 요지:
- 문제: 시간 기반 재생은 **출발·정지·방향 전환에서 발 미끄러짐**을 만든다.
- 해법: **Distance Curve** — 애니메이션의 각 포즈를 시간이 아닌 **"관심 지점까지의 누적 거리"** 에 매핑. 문서 표현: "instead of the 9th keyframe transitioning to the 10th keyframe based on a unit-of-time threshold, the transition occurs based on a unit-of-distance threshold."
- **Predict Ground Movement Stop Location**: 추가 입력이 없을 때 캐릭터가 완전히 멈출 지점을 예측. 매 프레임 **남은 정지 거리에 해당하는 애니메이션 포즈를 선택**.
- 주요 노드: `Distance Match to Target`, `Advance Time by Distance Matching`, `Set Playrate to Match Speed`. Distance Curve Modifier 설정: Sample Rate(보통 30), Axis, Stop Speed Threshold.
→ **2D 절차적 리그로의 번역**: 사이클 위상 φ를 `dφ = (이동거리 Δs) / (현재 보폭)` 로 진행시키면 된다. 애니메이션 클립이 없으므로 커브 생성도 불필요 — 오히려 우리 쪽이 구현이 더 쉽다.

**(b) Inertialization — 크로스페이드를 대체하는 전환**

**David Bollo (Microsoft/The Coalition), "Inertialization: High-Performance Animation Transitions in Gears of War", GDC 2018** (GDC Vault, 슬라이드 PDF 공개 — 본문 추출 실패로 **수식은 미확인**, 개념은 복수 2차 출처 일치).
- 기존 블렌드 전환은 전환 중 **소스와 타깃 두 상태를 모두 평가**해야 해서 비용이 2배.
- Inertialization은 블렌드를 없애고 **전환을 후처리(post-process)** 로 처리: 전환 시점의 **소스 포즈와 타깃 포즈의 오프셋(위치·속도)** 을 기록하고, 이 오프셋을 **0으로 감쇠**시킨다. 평가되는 포즈는 **항상 1개(타깃)**.
- **5차 다항식**으로 감쇠하여 종점에서 위치·속도·가속도(및 저크) 0 보장, 유일 튜닝 파라미터는 전환 지속시간. 실무 권고: **0.4초 미만**.

구현 가능한 정확한 수식 — **Daniel Holden, "Inertialization Transition Cost" (theorangeduck.com, 2022-02-06)** 의 3차(cubic) inertializer, 원문 그대로:
```
d = x
c = v * blendtime
b = -3*d - 2*c
a =  2*d + c
offset(t) = a*t*t*t + b*t*t + c*t + d     (t = clip(dt / (blendtime + eps), 0, 1))
```
(x = 전환 순간의 포즈 차이, v = 그 차이의 변화율)

**임계감쇠 스프링** — Daniel Holden, "Spring-It-On: The Game Developer's Spring-Roll-Call" (2021-04-03), 원문 그대로:
```
damping = (4 * ln(2)) / (halflife + eps)
y  = damping / 2
j0 = x - x_goal
j1 = v + j0*y
eydt = exp(-y*dt)
x = eydt*(j0 + j1*dt) + x_goal
v = eydt*(v - j1*y*dt)
```
정확해: `x_t = j₀e^(-yt) + t·j₁e^(-yt) + c`, `v_t = -y·j₀e^(-yt) - y·t·j₁e^(-yt) + j₁e^(-yt)`.
Holden은 같은 글에서 inertialization을 "현재 재생 중인 애니메이션과 전환할 애니메이션 사이의 오프셋을 기록한 뒤 그 오프셋을 0으로 부드럽게 감쇠시키는 것"으로 설명한다.

**최신 비판(2026)**: Riccardo Lasagno(Sumo Digital), "Half Pound Filter for Real-Time Animation Blending", arXiv:2602.21702v1, 2026-02-25 — inertialization은 "유효한 고주파 동작에 적용하면 over-smoothing, 빠르게 변하는 모션에는 over-shooting"을 유발할 수 있다고 지적하며 1€ Filter 변형(HPF)을 제안. LaFAN1 데이터셋 기준 GB-HPF Auto가 MSE 0.0014 / NPSS 0.0438. → **참고만 권장**(preprint, 동료심사 미확인, 우리 규모에는 과함).

**(c) Footstep planning**

- **van Basten & Egges, "One step at a time: Animating virtual characters based on foot placement"** — 발 배치를 1차 제어 대상으로 삼는 접근(제목·요지만 확인, **본문 미확인**).
- **Aron Granberg, "Footstep planning (part 1/2)"** (2016-12 / 2017-02-11): 계층적 B-스플라인 + 반복 IK로 경로 전체의 발자국을 맞춤. 단, "약 200ms(전체 경로 처리)"로 **실시간 프레임 예산에는 부적합**하다고 저자 본인이 명시. → **우리에게는 과한 방법**.
- **Jarosław Ciupiński, "Animation-Driven Locomotion with Locomotion Planning", Game AI Pro (Ch.25)**: "정확한 지점에 올바른 방향으로 캐릭터를 위치시키는 액션"을 위해 위치와 방향을 모두 보정한다는 요지. **PDF 본문 추출 실패 — 미확인**.

**(d) 디즈니 12원칙의 전환 적용**

Rosen의 GDC 2014 발표가 명시적으로 "anticipation/response와 squash-and-stretch의 자동화"를 목표로 든 것이 가장 직접적인 사례(2차 확인). 흥미로운 수렴: 생체역학의 **정지 신호 후 150ms 제동 개시 지연**(Crenna et al. 2001)은 애니메이션 원칙의 **anticipation 구간과 사실상 같은 것**이다 — 즉 anticipation은 스타일이 아니라 실측 가능한 신경근 지연이다.

**(e) 골프 게임의 걷기→어드레스 전환 — 공개 자료 없음**

Golf Story, Everybody's Golf(Clap Hanz), 2D 골프 인디 모두 **전환 처리에 대한 공개 기술 설명을 찾지 못했다.** Clap Hanz 인터뷰(UploadVR, Ultimate Swing Golf)는 디자인 철학·물리 정확도만 다루고 애니메이션 전환은 언급하지 않는다. → **공백**.

---

### 2-5. 스틱피겨 애니메이션 실무 원칙

- Alan Becker의 튜토리얼 시리즈(AlanBeckerTutorials 채널: "Animating Walk Cycles", "Animating Run Cycles", "12 Principles of Animation" 플레이리스트, 그리고 Bloop Animation의 40강 "Stick Figure Animation Course")가 **존재함은 확인**했으나, **영상 내 발언 내용은 텍스트로 검증하지 못했다**. 따라서 "Alan Becker가 말한 원칙"으로 인용 가능한 것은 없다 — **미확인**.
- 대신 검증 가능한 등가 원칙: 워크 사이클 4포즈(contact/down/passing/up), contact 포즈 우선 확정, 전통 12원칙(anticipation, follow-through, overlapping action). 스틱맨은 실루엣이 선 하나뿐이라 **관절 굽힘 각도 자체가 유일한 가독성 수단**이라는 점은 논리적으로 자명하나, 이를 명시한 1차 출처는 확보하지 못했다(**의견/추정**).

---

## 3. 문제별 권장 접근

### (A) 2-bone IK — 권장: Juckett 해석해 + 부호 고정 + 하이브리드 도달 불가 처리

구현 순서:
1. 관절마다 `(L1, L2, bendSign)` 을 상수로 보유. 사이드뷰에서 **다리는 무릎이 진행방향 쪽(+facing), 팔은 팔꿈치가 반대쪽(−facing)** 으로 고정 → pole/hint 계산 자체가 불필요하고 캐릭터가 반전되어도 facing 부호만 곱하면 된다. **근거**: Juckett의 "negate θ₂", Godot의 `flip_bend_direction` 불리언 — 프로덕션 엔진도 2D에서는 부호 1개로 처리.
2. 타깃을 로컬 좌표로 변환 → 위 두 수식으로 θ₂, θ₁ 계산 → `bendSign`을 θ₂에 곱한다.
3. **도달 불가**: cos 클램프만 쓰지 말 것(완전 신전 시 다리가 작대기처럼 펴지고, 신전 근처에서 각도가 급변해 떨림이 생긴다). 권장 2단 처리:
   - `reach = min(|target - root|, 0.98 * (L1 + L2))` 로 타깃을 먼저 당긴다. **근거**: Little Polygon의 `MaxLength − 1cm`, Godot의 `target_maximum_distance` 둘 다 같은 관용구.
   - 남은 차이(target이 더 멀었던 만큼)는 **골반/root를 그 방향으로 끌어당겨** 흡수한다. halflife 0.1~0.15s 스프링으로. → "몸 보상"이 되고, 다리를 쭉 뻗는 대신 몸이 따라 기우는 사람다운 결과.
   - 최소 거리도 `max(reach, 1.05 * |L1 - L2|)` 로 클램프(완전 접힘 특이점 회피).
4. **관절 각 제한**: θ₂의 크기를 보행 실측 범위로 제한 — 무릎 0°~70°(유각기 최대 60~70° 실측), 필요 시 앉기용 150°까지 허용. 하드 클램프 대신 **tanh softening**(Holden 2021)으로 경계 근처를 부드럽게. 무릎은 반대 방향 굴곡이 물리적으로 불가하므로 **θ₂ ≥ 0 강제**가 "늘어남"과 "역굽힘" 둘 다를 한 번에 막는다.

### (B) 속도 프로파일 — 권장: 임계감쇠 스프링 + √v 보폭/케이던스 스케일링

**왜 현재 포물선이 틀렸나**: 구간 전체에 하나의 산 모양 곡선을 쓰면 가속·감속이 대칭이고 초반 기울기가 0이다. 실제 보행 개시는 **첫 걸음에서 속도의 대부분이 실린다**(Brenière & Do 1986: 첫 걸음 종료 시점의 전진 속도가 둘째 걸음 평균과 유의차 없음). 즉 프로파일이 **앞으로 몰려 있어야** 한다.

권장 수치(정상 보행 v_ss ≈ 1.3~1.4 m/s, 케이던스 ≈ 100~110 steps/min → **스텝 시간 ≈ 0.55~0.6초** 기준):

| 구간 | 권장값 | 근거 |
|---|---|---|
| 출발 램프 | 임계감쇠 스프링, **halflife 0.30~0.35s** | 3×halflife ≈ 0.9~1.05초에 목표의 약 92% 도달 = **약 2걸음**. 문헌의 "속도 기준 2걸음"과 일치 |
| 정상 상태 도달 체감 | **1.0~1.6초 / 2~3걸음** | 속도 변수 2걸음(2025 연구), 전신 안정 3걸음(관례 권고), 경사 연구 3번째 걸음에 ≥90% |
| 정지 반응 지연(anticipation) | **0.15초** 유지 후 감속 시작 | Crenna et al. 2001: 입각지 EMG 제동 개시 ≈150ms |
| 후방 반력 최대 | 신호 후 ≈0.23초 | 동, backward GRF 증강 230ms |
| 정지 소요 | **1스트라이드 = 2걸음 ≈ 1.0~1.2초** | 동: 자연/빠른 속도에서 98%가 one stride로 정지 |
| 감속 램프 | halflife **0.20~0.25s** (출발보다 짧게) | 정지가 출발보다 빠르다는 비대칭 = "탁 서는" 느낌의 근거 |

**함께 반드시 할 것 — 속도에 따른 보폭·케이던스 동시 스케일링**:
```
c_target(v)  = c_ss * sqrt(v / v_ss)      // 케이던스
SL_target(v) = SL_ss * sqrt(v / v_ss)     // 보폭
```
**근거**: walk ratio(보폭/케이던스)가 속도 독립 상수(≈6.5 mm/(step/min))라는 복수 출처 확인 + 여기서 유도한 `v ∝ c²`. **이 항목이 없으면** 램프 중에도 보폭이 고정되어 케이던스만 느려지고, 그게 바로 "느릿하다가 갑자기"의 시각적 정체다. 이 스케일링을 넣으면 **첫 걸음이 짧고 둘째부터 정상**이라는 실제 gait initiation 패턴이 자동으로 나온다.

부수 효과로 몸 바운스 진폭도 속도에 연동: COM 수직 진폭 **2.7cm(느림) → 4.8cm(빠름)**, 스트라이드당 2주기. 스틱맨 키를 175cm로 잡으면 화면 스케일로 환산해 쓰면 된다.

### (C) 전환 — 권장: 거리 구동 위상 + 접지 래치 + 정지 지점 발자국 계획 (+ 상체만 inertialization)

**이전 실패의 원인 진단**: "포즈 크로스페이드 + 원점 블렌드"가 더 어색해진 것은 튜닝 문제가 아니라 **구조적 문제**다. 접지 발은 월드 공간에 고정되어야 하는 **제약(constraint)** 인데, 두 포즈를 가중 평균하면 결과 발 위치가 **양쪽 어느 접지점도 아닌 제3의 점**이 된다. 그래서 반드시 미끄러진다. UE가 크로스페이드 대신 distance matching + foot lock을 쓰는 이유, Bollo가 블렌드 자체를 없애고 inertialization으로 간 이유가 정확히 이것이다. → **블렌딩 가중치를 다시 조정하는 방향은 전부 막다른 길**.

4층 레시피:

1. **위상을 거리로 구동** (문제의 90%가 여기서 해결)
   ```
   phase += deltaDistance / currentStrideLength      // 시간이 아니라 이동 거리
   ```
   속도가 0으로 떨어지면 위상 진행도 0이 된다 → 정지 중 발이 움직일 수 없다. **근거**: UE Distance Matching의 "unit-of-distance threshold" 원칙. 우리는 클립이 없으므로 distance curve를 만들 필요조차 없다.

2. **접지 래치 (foot plant latch)**
   위상이 contact 구간에 들어오면 해당 발의 **월드 x를 그 순간 값으로 동결**, lift-off 위상까지 유지. 발 IK 타깃은 동결된 월드 좌표를 매 프레임 로컬로 재변환. 골반은 그 위를 지나간다. **근거**: UE Foot Locking("detecting the plant phase and locking that foot's world-space position with IK until lift-off").
   유각 발의 궤적은 **사인 아크** 또는 **2차 베지에**(리프트오프·정점·착지 3점). 정점 높이는 속도에 비례.

3. **정지 지점 예측 + 마지막 1~2걸음 보폭 조정** ← 어드레스 전환의 핵심
   ```
   stopX = predictStopPosition(v, decelHalflife)       // (B)의 감속 프로파일로 적분
   targetStance = { frontFootX, backFootX }            // 골프 어드레스 발 위치 (stopX 기준 오프셋)
   remainingSteps = ceil(|targetFootX - currentFootX| / SL_normal)   // 1 또는 2
   각 잔여 스텝의 보폭을 조정해 마지막 착지가 targetStance에 정확히 떨어지게 한다
   ```
   보폭 조정 폭은 **±20~30% 이내**로 제한하고(벗어나면 어색), 부족하면 remainingSteps를 1 늘린다. 발이 미끄러지는 대신 **보폭이 조금 달라지는 것**으로 오차를 흡수 — 이게 footstep planning의 본질이다. 생체역학적으로도 정지는 1스트라이드(2걸음)이므로 **조정 대상은 마지막 2걸음이면 충분**하다.
   ※ 반대 방향(어드레스 → 걷기)도 동일: 어드레스 스탠스의 뒷발을 첫 스윙 발로 삼아 첫 걸음을 짧게 시작.

4. **비접촉 부위만 inertialization** (상체·팔·머리)
   전환 순간 각 관절의 **오프셋과 그 변화율**을 기록하고 0으로 감쇠. 위 Holden cubic 공식을 그대로 쓴다. **blendtime 0.2~0.35초** (Bollo 실무 권고 "0.4초 미만"). 중요한 점: **타깃 포즈는 즉시 100% 가중치로 재생**되고 오프셋만 얹히므로, 두 포즈의 평균이 나오는 크로스페이드의 물컹함이 없다. 접지 중인 발에는 적용하지 않는다(제약 우선).

5. **anticipation / follow-through**
   - 정지 명령 후 **0.15초** 동안은 속도를 유지하고 상체 무게중심만 살짝 앞으로 — 실측 EMG 지연(150ms)과 애니메이션 원칙이 일치하는 구간.
   - 마지막 발 착지 직후 상체·팔이 **약간 오버슛 후 정착**: halflife 0.12~0.20s 스프링. 팔은 다리보다 **1~2프레임 늦게**(overlapping action).
   - 어드레스 진입 시 골반 하강 2~3cm + 무릎 굴곡 증가를 같은 스프링으로.

---

## 4. 한계와 공백

1. **접근 차단으로 원문 미확보**: Brenière & Do 1986 원문, 경사 보행 논문(PMID 33152612) 초록, 2025 gait initiation 논문(PMID 40527299), van Basten & Egges 논문 본문 — ScienceDirect 403 / PubMed·Springer·Nature 리다이렉트. 해당 수치는 **검색 스니펫 및 2차 요약 기반**이며, "3번째 걸음에 ≥90%" 같은 구체 수치는 단일 경로 확인이다.
2. **PDF 본문 추출 실패**: Bollo GDC 2018 슬라이드(5차 다항식 계수), Game AI Pro Ch.25 — 로컬 poppler 미설치. **5차 계수는 인용하지 않았고**, 대신 검증된 Holden 3차 공식을 제시했다. 5차가 필요하면 UE 소스 `AnimNode_Inertialization.cpp`의 `CalcInertialFloat`를 직접 확인해야 한다(경계조건: t₁에서 위치·속도·가속도 모두 0).
3. **영상 발표 내용 미검증**: Rosen GDC 2014의 "4 키프레임", Rain World GDC 2016 세부, Alan Becker 튜토리얼 전부. 영상을 보지 않았으므로 **2차 서술 신뢰도**에 머문다. Rosen 발표는 무료 공개(Internet Archive `GDC2014Rosen`)이므로 직접 시청 권장.
4. **골프 게임 전환 처리는 공개 자료 자체가 없음** — Golf Story/Everybody's Golf/Clap Hanz 모두 기술 발표·포스트모템 미발견. 이 항목은 채울 수 없었다.
5. **팔꿈치 90° peak-to-peak**는 단일 출처이며 과제 조건이 일반 보행과 다를 가능성 — 사용 시 실측 대신 시각 튜닝 권장.
6. **`v ∝ c²`, `SL ∝ √v` 는 본 리서치의 유도**이며 원문의 직접 주장이 아니다. 전제(WR 상수성)는 복수 출처로 확인했고 참고값 검산도 맞지만, **매우 느린 속도에서는 WR 상수성이 깨진다**는 연구(PMID 28533617, "Estimated lower speed boundary at which the walk ratio constancy is broken")가 있으므로 출발 램프 극초반에는 하한을 두는 것이 안전하다.
7. **60fps 2D 스틱맨 전용 사례 연구는 없었다.** 위 기법들은 3D/클립 기반 시스템에서 검증된 것을 절차적 2D로 번역한 것이며, 번역 자체는 검증되지 않았다 — 특히 (3) 발자국 계획의 ±20~30% 보폭 조정 한계는 **실측이 아닌 제안값**이다.

---

## 참고 출처 (발행일)

**IK**
- Ryan Juckett, "Analytic Two-Bone IK in 2D", 2008-12-29 (upd. 2020-11-29) — https://www.ryanjuckett.com/analytic-two-bone-ik-in-2d/
- Alan Zucconi, "Inverse Kinematics in 2D – Part 1", 2018-05-02 — https://www.alanzucconi.com/2018/05/02/ik-2d-1/
- Godot Docs, `SkeletonModification2DTwoBoneIK` (stable) — https://docs.godotengine.org/en/stable/classes/class_skeletonmodification2dtwoboneik.html
- Max Kaufmann, "Procedural Animation: Inverse Kinematics", 2023-02-26 — https://blog.littlepolygon.com/posts/twobone/
- Daniel Holden, "Joint Limits", 2021-06-11 — https://theorangeduck.com/page/joint-limits

**생체역학**
- Brenière & Do, J. Biomechanics 19:1035–1040, 1986 — https://www.sciencedirect.com/science/article/abs/pii/002192908690120X (원문 미확보)
- Crenna, Cuong, Brenière, J. Physiol. 537(3):1059–1072, 2001-12-15 — https://pmc.ncbi.nlm.nih.gov/articles/PMC2279001/
- "Analysis of sloped gait: How many steps…", Gait & Posture, PMID 33152612 — https://pubmed.ncbi.nlm.nih.gov/33152612/ (스니펫)
- "How Many Steps to Reach Steady State…", PMID 40527299, 2025 — https://pubmed.ncbi.nlm.nih.gov/40527299/ (스니펫)
- Walk ratio (Rota et al., Int J Rehabil Res, 2011-09) — https://pubmed.ncbi.nlm.nih.gov/21629125/
- Walk ratio 상수성 하한 속도, PMID 28533617 — https://pubmed.ncbi.nlm.nih.gov/28533617/
- 정상 보행 규준치 — https://www.ncbi.nlm.nih.gov/pmc/articles/PMC11768510/
- COM 수직 변위 vs 속도 — https://pubmed.ncbi.nlm.nih.gov/15685471/
- 계획/비계획 정지 비교, Appl. Sci. 13:7323, 2023 — https://doi.org/10.3390/app13127323

**게임 기법**
- David Rosen, GDC 2014 "An Indie Approach to Procedural Animation" — https://archive.org/details/GDC2014Rosen / https://www.gdcvault.com/play/1020583/Animation-Bootcamp-An-Indie-Approach
- Jakobsson & Therrien, GDC 2016 "Rain World Animation Process" — https://www.gdcvault.com/play/1023475/Animation-Bootcamp-Rainworld-Animation
- UE Distance Matching 공식 문서 — https://dev.epicgames.com/documentation/en-us/unreal-engine/distance-matching-in-unreal-engine
- UE Stride Warping 공식 문서 — https://dev.epicgames.com/documentation/en-us/unreal-engine/stride-warping-in-unreal-engine
- David Bollo, GDC 2018 "Inertialization" — https://media.gdcvault.com/gdc2018/presentations/bollo_david_inertialization_high_performance.pdf (본문 미확보)
- Daniel Holden, "Spring-It-On", 2021-04-03 — https://theorangeduck.com/page/spring-roll-call
- Daniel Holden, "Inertialization Transition Cost", 2022-02-06 — https://theorangeduck.com/page/inertialization-transition-cost
- Max Kaufmann, "Procedural Locomotion (Part 1)", 2023-04-29 — https://blog.littlepolygon.com/posts/loco1/
- Aron Granberg, "Footstep planning (part 2)", 2017-02-11 — https://arongranberg.com/2017/02/footstep-planning-part-2/
- J. Ciupiński, Game AI Pro Ch.25 — https://www.gameaipro.com/GameAIPro/GameAIPro_Chapter25_Animation-Driven_Locomotion_with_Locomotion_Planning.pdf (본문 미확보)
- R. Lasagno, "Half Pound Filter for Real-Time Animation Blending", arXiv:2602.21702v1, 2026-02-25 — https://arxiv.org/html/2602.21702
