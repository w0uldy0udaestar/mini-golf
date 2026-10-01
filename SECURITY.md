# 보안 정책

## 취약점 제보

GitHub 저장소의 **Security → Report a vulnerability**(비공개 제보)로 알려 주세요. 재현 방법은 공개 이슈에 올리지 말아 주세요.
지원 대상은 최신 릴리스입니다.

## 이 앱이 하는 일과 하지 않는 일

- 네트워크 통신이 없습니다.
- 손쉬운 사용·화면 기록·입력 모니터링 같은 권한을 요청하지 않습니다.
- 키 입력을 기록하지 않습니다. 게임 조작 키는 게임 창이 활성일 때만 받습니다.
- Mac에 남기는 파일은 두 가지입니다: 설정·기록(UserDefaults `io.github.w0uldy0udaestar.mini-golf`)과
  플레이 로그(`~/Library/Logs/MiniGolf/play.log` — 홀·샷·정지 시각). 둘 다 지워도 됩니다.

## 배포물 확인

- 릴리스 앱은 서명·공증되지 않은 ad-hoc 빌드입니다. 받은 zip은 릴리스 노트의 SHA-256과 대조하세요:
  `shasum -a 256 MiniGolf-x.y.z.zip`
- 직접 빌드할 수도 있습니다: `make app` (README 설치 C).

## 개발용 도구

`scripts/capture-*`와 `ads/*/capture/`는 개발·광고 제작용 화면 캡처 도구이며 앱에는 포함되지 않습니다.
