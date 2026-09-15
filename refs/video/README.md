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
