import Foundation
import GolfCore

/// 관찰·디버그 실행 인자 한 묶음 (2026-09-28 — GameScene에 흩어져 있던 플래그 저장 프로퍼티 27개와 main.swift의 파싱을 여기로).
/// 실플레이는 인자가 없으니 전부 기본값이고, 게임 로직은 `demo.xxx`로만 읽는다. 런타임에 변하는 관찰 상태(demoWait·motionCursor 등)는
/// 씬에 남긴다 — 여기는 "실행 시 정해진 설정"만.
struct DemoOptions: Equatable {
    // ── 모드·환경 ──
    var active = false // --demo 계열 아무 플래그: 조준 1.2s 뒤 자동 스윙 반복, 사운드 끔, PlayLog는 stdout
    var screenIndex: Int? // --screen N: 실행 시 모니터 지정 (0부터, 저장 안 함)
    var seed: UInt32? // --seed N: 코스 시드 고정 (특정 지형·장애물 시각 검증)
    var backdrop = false // --demo-bg: 불투명 배경 (캡처 판독용)
    var noWallClamp = false // --no-wall-clamp: 벽 경성 클램프 끄기 (침범 재현·검증)
    var cardPreview = false // --demo-card: 스코어카드 레이아웃 즉시 표시
    var recordsCard = false // --demo-records: 2s 뒤 기록 카드 (레이아웃 검증)
    var switchAfter: Double? // --demo-switch T: T초 뒤 다음 모니터로 (런타임 전환 관찰)
    // ── 시나리오 강제 ──
    var wallForce = false // --demo-wall: 매 홀을 벽 옆에서 시작 (벽 스탠스 관찰)
    var tripForce = false // --demo-trip: 긴 걸음마다 넘어지기 강제
    var slipForce = false // --demo-slip: 경사(|경사| > 0.03) 풀샷마다 피니시 넘어지기 강제 (경사 넘어지기 관찰)
    var idleForce = false // --demo-idle: 조준을 25s 유지 (아이들 잔동작 관찰)
    var setbackForce = false // --demo-setback: 모든 샷을 좌절 계열로
    var greetForce = false // --demo-greet: 조준 3s 뒤 일시정지→1s 뒤 재개, 인사 임계 0 (--demo-idle과 함께)
    var pickupForce = false // --demo-pickup: 컵 앞 시작 (공 줍기 의식 관찰)
    var settleForce = false // --demo-settle: 첫 샷을 홀 쪽 라이저 상단에 떨어뜨려 정착 굴림 관찰 (협곡 시드)
    var turnForce = false // --demo-turn: 첫 샷을 뒤로 22m 떨어뜨려 걷기 방향 반전(제자리 돌기) 관찰
    var replanForce = false // --demo-replan: 걷는 도중 공을 옮긴다 (1차 12m 앞 → 재계획, 2차 25m 뒤 → 재출발+턴)
    var girForce = false // --demo-gir: 파4·5에서 그린 위 정지면 무조건 원온/투온 연출
    var hotkeyUI = false // --demo-hotkey-ui: 단축키 기록 대화상자를 1.5s 뒤 띄우고 견본 조합을 넣어 본다 (키 입력 없이)
    var rangeStart = false // --demo-range: 연습장으로 시작, 샷마다 클럽을 돌려 친다 (눈금·표식·HUD 관찰)
    var noticeForce = false // --demo-notice: 홀아웃마다 견본 배지 알림을 대기열에 (알림 타이밍 관찰 — 다음 홀 조준 뒤에 뜨는가)
    var trademarkForce = false // --demo-trademark: 풀샷마다 굿샷 판정(트월 강제) + 리그 덤프 로그
    var motionShowcase = false // --demo-motions: 모션 42종 순서 시연 (카탈로그 캡처)
    var motionCursorStart = 0 // --motion-cursor N: 시연을 N번째 모션부터 (부분 재캡처)
    var showpieceForce = false // --demo-memes: 걷기마다 쇼피스 1개, 12종 순환
    var surpriseForce = false // --demo-surprise: 샷마다 서프라이즈 (훅별 순환)
    var surpriseKind: SurpriseKind? // --surprise KIND: 해당 훅마다 그 종류 강제
    // ── 값 ──
    var power: Double? // --demo-power P: 봇 파워 고정 (0.05~1 클램프) — 조준 프리뷰에도 적용
    var mood: GameScene.WalkMood? // --demo-mood elated|sad|neutral: 모든 걷기에 무드 강제
    var ballX: Double? // --demo-ball X: 홀 시작 공 위치(m) — 특정 라이·거리의 조준 자세 관찰
    var startHole = 1 // --demo-hole N: 새 라운드를 N번 홀부터 (미러 홀·특정 아키타입 관찰)
    var restartAfterHoled: Double? // --demo-restart-after-holed T: 첫 홀아웃 T초 뒤 새 라운드 (홀 전환 타이머 인터럽트 관찰)
    var restartIn: Double? // --demo-restart-in T: 서프라이즈 시작 T초 뒤 새 라운드 (인터럽트 정리 관찰)
    var hour: Int? // --demo-hour H: 뻐꾸기 시각 고정, 0~23로 정규화 (밤 20~05시 반딧불 대체 관찰)
    var clubId: String? // --club ID: 홀 시작 클럽 지정 (DR·7I·SW·PT… — 클럽별 어드레스 관찰)
    var shape: ShotShape? // --demo-shape punch|lob: 매 샷 종류 강제 (탄도·폼 관찰, Tab 없이)
    var swingStyle: SwingStyle? // --style: 스윙 스타일 지정 (관찰·캡처용, 저장 안 함)
    var hat: Hat? // --hat: 모자 시각 검증 (저장 안 함)
    var lang: Lang? // --lang ko|en: 표시 언어 지정 (저장 안 함 — 영어 화면 관찰)
    var weather: Weather? // --weather clear|rain|gale: 9홀 전부 그 날씨로 강제 (M6 — 실플레이에서도 듣는다: 날씨만 고르고 치는 용도)
    var mission: MissionKind? // --mission KIND: 모든 홀에 그 미션 (M6 관찰)
    var gimmick: GimmickKind? // --gimmick volcano|funnel|mesa|dune|potBunker: 들어가는 홀 전부에 그 장치 (M7 — 날씨처럼 실플레이에서도 듣는다)

    init() {}

    /// `ProcessInfo.processInfo.arguments` 그대로. 값 플래그는 바로 다음 인자를 읽고, 없거나 형식이 틀리면 기본값
    init(arguments args: [String]) {
        func flag(_ name: String) -> Bool {
            args.contains(name)
        }
        func value(_ name: String) -> String? {
            guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        active = args.contains { $0.hasPrefix("--demo") } // 하위 플래그(--demo-pickup 등)만 줘도 관찰 모드
        screenIndex = value("--screen").flatMap { Int($0) }
        seed = value("--seed").flatMap { UInt32($0) }
        backdrop = flag("--demo-bg")
        noWallClamp = flag("--no-wall-clamp")
        cardPreview = flag("--demo-card")
        recordsCard = flag("--demo-records")
        switchAfter = value("--demo-switch").flatMap { Double($0) }
        wallForce = flag("--demo-wall")
        tripForce = flag("--demo-trip")
        slipForce = flag("--demo-slip")
        idleForce = flag("--demo-idle")
        setbackForce = flag("--demo-setback")
        greetForce = flag("--demo-greet")
        pickupForce = flag("--demo-pickup")
        settleForce = flag("--demo-settle")
        turnForce = flag("--demo-turn")
        replanForce = flag("--demo-replan")
        girForce = flag("--demo-gir")
        noticeForce = flag("--demo-notice")
        rangeStart = flag("--demo-range")
        hotkeyUI = flag("--demo-hotkey-ui")
        trademarkForce = flag("--demo-trademark")
        motionShowcase = flag("--demo-motions")
        motionCursorStart = value("--motion-cursor").flatMap { Int($0) }.map { max(0, $0) } ?? 0 // 음수 방어
        showpieceForce = flag("--demo-memes")
        surpriseForce = flag("--demo-surprise")
        surpriseKind = value("--surprise").flatMap(SurpriseKind.init(rawValue:))
        power = value("--demo-power").flatMap { Double($0) }.map { min(1, max(0.05, $0)) }
        mood = value("--demo-mood").flatMap(GameScene.WalkMood.init(rawValue:))
        ballX = value("--demo-ball").flatMap { Double($0) }
        startHole = value("--demo-hole").flatMap { Int($0) } ?? 1
        restartAfterHoled = value("--demo-restart-after-holed").flatMap { Double($0) }
        restartIn = value("--demo-restart-in").flatMap { Double($0) }
        hour = value("--demo-hour").flatMap { Int($0) }.map { ($0 % 24 + 24) % 24 }
        clubId = value("--club")
        shape = value("--demo-shape").flatMap(ShotShape.init(rawValue:))
        swingStyle = value("--style").flatMap(SwingStyle.init(rawValue:))
        hat = value("--hat").flatMap(Hat.init(rawValue:))
        lang = value("--lang").flatMap(Lang.init(rawValue:))
        weather = value("--weather").flatMap(Weather.init(rawValue:))
        mission = value("--mission").flatMap(MissionKind.init(rawValue:))
        gimmick = value("--gimmick")
            .flatMap { v in
                GimmickKind.allCases.first { $0.rawValue.lowercased() == v.lowercased() }
            } // potbunker도 통한다
    }
}
