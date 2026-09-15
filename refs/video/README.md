# refs/video — 프로 스윙 영상 키포인트 추출 도구

face-on(정면) 골프 스윙 영상에서 MediaPipe Pose로 관절 키포인트를 뽑아 스틱맨 P-System 키프레임
파라미터(hipDx·tilt·handA·handD·clubA·heel·headDx)와 템포로 변환한다. 2026-09-15 로리 매킬로이 아이언
스윙(YouTube "Rory Mcilroy Pure Iron Swing with Slow Motion", Visual Golf, 2023-08-28)에 적용해
`Sources/MiniGolf/Poses.swift`를 갱신했다. 결과·판단은 `docs/research-swing-keypoints.md`.

**영상·키포인트 JSON은 저장소에 넣지 않는다** (영상 저작권). 작업 폴더는 `SWING_WORK` 환경변수(기본 `~/swing-work`).

## 절차

```bash
uv venv --python 3.12 .venv && . .venv/bin/activate
uv pip install "mediapipe==0.10.21" opencv-python numpy   # 1.0.x는 macOS에서 graph service 오류 — 0.10 레거시 API 사용
uvx yt-dlp --js-runtimes node --remote-components ejs:github -f "bv*[ext=mp4][height<=1080]/b" -o rory.mp4 "<URL>"
# pose_extract.py: segments 딕셔너리에 (t0, t1, x0, x1) — 정면 구간과 크롭(2분할 영상은 정면 패널만)
python tools/pose_extract.py            # → pose_<name>.json (33 랜드마크 px·가시성)
python tools/analyze.py slow            # → 이벤트(address·takeaway·top·impact·follow·finish)·파라미터 표·overlay_<name>.png
python tools/shaft.py slow              # → 손목 주변 직선 검출로 샤프트 각 (톱·팔로·피니시는 잘 잡히고 어드레스·임팩트는 수동 확인)
```

이벤트 검출 원리: 손목 중점 높이의 봉우리 두 개(톱·피니시)와 그 사이 타깃 쪽 최대 뻗음(팔로)으로 스윙을
찾고, 타깃 방향은 팔로의 부호로 자동 판정한다. 어드레스는 톱 이전 손이 바닥에 머문 마지막 프레임.
파라미터는 몸통 길이(힙→어깨)를 스틱맨 25px, 팔 최대 신전을 35px로 정규화한다.

## 2단계 도구 (2026-09-15, 웨지·퍼터)

```bash
python tools/thumbs.py <video.mp4> thumbs.png 8            # 등간격 썸네일 시트 — 각도(face-on)·슬로모션 구간·장면 전환 확인
python tools/extract.py <name> <video> [x0 x1] [step] [t0 t1]   # 시간 창 추가 (긴 영상의 일부만, 예: 흑백 분석 영상의 단일 패널 41~80s)
HAND_PEAK=-0.3 EXT_MIN=0.35 DEBUG=1 python tools/analyze.py <name> [t0 t1]   # 웨지: 봉우리 손 높이·팔로 뻗음 임계 완화, 짝짓기 스킵 사유 출력
PICK=0 python tools/analyze_putt.py <name> [t0 t1]         # 퍼팅 전용 검출(손목 수평 변위) — PICK으로 n번째 유효 스트로크 강제
python tools/gen_table2.py                                  # events_<style>_{wg|pt}.json → SwingKeyframes 웨지 3 + PutterKeyframes 3 (EX=2.5)
```

이벤트 파일 이름 규약: `events_<style>_wg.json`(웨지)·`events_<style>_pt.json`(퍼터) — analyze 출력(`events_<name>.json`)을 복사해 맞춘다.
퍼터 생성기는 어드레스·임팩트 손 각을 "헤드가 공 뒤 5px"가 되도록 이분법으로 풀고(ballFwd 표준 6·암록 16), 백스트로크 폭은 표준
−32° 공용, 팔로스루 길이만 1.5배 과장한다. 배경 이유는 `docs/research-swing-styles.md` §2단계.
