# 리서치 — MOCAP Motion Index 전수 확인 (2026-08-28)

## 범위와 방법

- 대상: https://motion-index-phi.vercel.app/ — CMU Graphics Lab Motion Capture Database의
  클립을 종이풍 루프로 보여주는 카탈로그 (사용자 제보)
- 방법: 사이트의 `data/catalog.json`을 직접 받아 **1,456클립 전량**을 스크립트 스캔,
  고유 제목 **1,107건 전부**를 수작업 판독. 골프·후보군은 상세 설명(desc)까지 확인
- 라이선스: CMU 공개 데이터 — 연구·상업 자유 사용, **데이터 재판매만 금지** (NSF EIA-0196217).
  게임 레퍼런스·이식 사용에 제약 없음. 출처 표기 문구를 README에 넣는 것이 관례

## 결론 먼저

1,107종 중 게임에 **직접 적용 가치가 있는 것은 약 230종**, 그중 즉시 효과가 큰 것은
**골프 직결 8클립**과 **성격 걷기 ~40종**이다. 우리 애니메이션은 절차식(채널 엔벨로프)이라
모캡을 그대로 재생하지 않는다 — 적용 방식은 ① 레퍼런스 삼아 새 레시피 작성(즉시 가능)
② CMU 원본 BVH를 2D 투영해 키포즈 자동 추출 → 레시피 초안 생성(파이프라인 구축, 반나절)

## A. 골프 직결 — 8클립 (최우선, 게임에 없는 의식들)

| 클립 | 내용 | 게임 적용 |
|---|---|---|
| 63_01 / 64_10 | 골프 스윙 (짧은/긴 테이크) | P-System 스윙과 대조 검증 — 체중 이동·어깨/골반 시차 회전 레퍼런스 |
| 64_17 / 64_20 | **티 꽂기** | 홀 시작 의식 신규: 몸 굽혀 티 꽂고 일어서기 → 어드레스. 현재 게임은 공이 그냥 나타남 |
| 64_23 / 64_24 | **공 놓기** | 드롭(워터·새 도둑 후) 연출 — 공을 '놓는' 동작 |
| 64_28 / 64_29 | **공 줍기** | 홀아웃 후 컵에서 공 줍기 의식 — 현재는 공이 사라지기만 함 |

## B. 성격 걷기 (locomotion 133종 중 스타일 ~40종) — 최대 발견

Bouncy·Cool·TooCool·Macho·Lavish·Attitude·Elated·Joy·Excited / Depressed·Sad·Scared·
Shy·achey·Mope / Sneaky·Creeping·Silent / March·Stern·Rushed / Clumsy·Spastic·Stumble /
Drunk·Zombie·Mummy·Frankenstein·Gorilla·Penguin·Pigeon-toed·Duck-footed·까치발·팔자 등.

**적용안 — "무드 워크" 시스템**: 스코어 상태를 걷기 스타일에 연동
(버디 직후 Elated/Bouncy로 걷고, 더블보기 후 Depressed/Mope, 워터 후 achey…).
현 걷기 게이트(속도·보폭·듀티) 위에 채널 오버레이만 얹으면 되는 구조라 이식 부담이 낮고,
감정 반응(홀아웃 순간)을 다음 걷기 전체로 연장해 생명감이 크게 늘어난다.

## C. 아이들 확장 (Wait 12종 + posture)

Cat/Old Man/Strong Man/Graceful Lady/Gangly Teen/Drunk/Chicken/Dinosaur Wait,
wait for bus, Pacing(서성이기), Shifting Weight(무게중심 옮기기), thinker(생각에 잠기기),
Looking around, Stretch and Yawn. → 조준 방치 아이들 잔동작의 캐릭터 버전.

## D. 쇼피스 후보 (dance 56 + acro 71 + odd 57)

- 댄스: 마카레나·치킨댄스·찰스턴·린디합·살사·람바다·러시안댄스·트위스트·문워크·브레이크댄스
- 곡예: cartwheel(옆돌기)·backflip·핸드스프링·헬리콥터·사방치기(hopscotch)
- 흉내: 닭·공룡(T-rex)·고릴라·펭귄·좀비·미라·유령·슈퍼히어로·개미·곰·티팟 율동
- 현 쇼피스 12종과 중복 없음 — 시즌 확장 소재로 사실상 무한

## E. 트립·낙상 변형 (현 1종 → 다양화)

BannanaPeelSlip(미끄러짐)·RugPullFall(발밑 빠짐)·fall on face(앞으로 철퍼덕)·
90TwistsFall(비틀려 넘어짐)·StumbleWalk(비틀거림)·stumble into(부딪혀 휘청).
지면별 트립 차등(벙커=미끄러짐, 러프=걸려 넘어짐)에 쓸 수 있다.

## F. 감정 제스처 확장 (gesture 19종)

laugh/crying/very happy/upset/scared/flexing(근육 자랑)/Shrug/Bow/Curtsey(무릎 인사).
스코어 반응 계층(현 4단)을 세분화: 이글=very happy+flexing, 기권=crying 등.

## G. 게임 맥락과 맞물리는 낱개 보석들

- **putting on a ball cap(모자 쓰기)** — 모자 해금 순간의 착용 연출로 정확히 들어맞음
- swatting at a fly/pesky bug — 나비(butterflyWatch)와 이어지는 벌레 쫓기
- whistle, walk jauntily — 휘파람 걸음 (기존 whistle 잔동작의 걷기 버전)
- fishing — 워터 해저드 앞 대기 개그
- digging(삽질) — 두더지 서프라이즈 후 반격 개그
- Underhand Toss — 공 던져 올리기 (홀아웃 후 공 줍기→토스 연결)
- balance object on forehead — 클럽 이마 균형(기존 clubBalance의 상위 버전)
- Singing in the rain jump — 버디 후 기쁨 점프

## 적용 불가 판정 (제외 근거)

- **duo 90종**: 2인 상호작용 — 스틱맨 1인 게임 (캐디/관중 신규 시스템을 만들면 재고)
- **climb 47종**: 사다리·계단·놀이기구 — 게임에 구조물 없음
- 수영 6종(워터=즉시 벌타), 농구 드리블·수비 ~30종, 무술 형(가라테 품새) ~20종,
  소품 의존 일상동작(운전·피아노·요리·바느질 등) ~60종, 이동 방향 변형(좌/우회전 등
  locomotion·run·climb의 절반) — 1D 사이드뷰라 방향 개념 없음
- 캘리브레이션·불량 데이터 표기 클립 소수

## 한계

- 사이트 미리보기(canvas 렌더)는 확인하지 않고 제목·설명 텍스트로 판정 — 개별 클립의
  실제 품질(지터·루프 절단)은 이식 시점에 CMU 원본으로 확인 필요
- CMU 클립 번호(id)는 사이트 자체 매핑 — 원본 subject/trial 대응은 각 카드의
  'CMU 원본 보기' 링크 기준으로 재확인 필요


## 이식 1차 결과 (2026-08-29)

- **파이프라인 구축**: `refs/mocap/tools/amc2d.py` — ASF/AMC 파싱 → FK → 손목 궤적 PCA
  기반 2D 사이드뷰 투영 → 게임 채널 시계열/스틱피겨 SVG. 골프 3클립 시각 검증 통과
- **실측 정답지** (`refs/mocap/tools/ritual_timing.json`, 테이크 2개 교차 일치):
  - 티 꽂기: 내려감 21% · 작업 60% · 복귀 19%, **스쿼트 비율 0.68** (무릎 주도)
  - 공 줍기: 33/33/33 균등, **스쿼트 비율 0.05** (순수 허리 힌지) + 뒷다리 들기
  - 스윙: 다운:팔로 = 1:2.2 — 게임 P-System(1:2.1)과 5% 이내 일치 → **수정 불필요 판정**
- **게임 이식**: RitualAnim(teePlace·ballPickup) — 티샷 전 공 심기 의식(공이 이때 등장),
  컵 근처 홀아웃 시 스코어 리액션 후 허리 힌지+뒷다리 들기로 공 줍기. 기권·원거리
  홀인은 생략. 모션 카탈로그 캡처 모드(--demo-motions)에선 생략
