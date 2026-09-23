import AppKit
import GolfCore
import SpriteKit

/// 게임 씬 — GolfCore 상태를 렌더하고 키보드 입력을 처리한다 (물리는 GolfCore)
/// 디자인: "조용한 계기판" — 상자 없는 타이포 HUD, 균일한 헤어라인 지형, 포인트 컬러는 깃발 하나
final class GameScene: SKScene {
    // 게임 상태
    private var course: [Hole] = []
    private var holeIdx = 0
    var ball = BallState(x: CourseGenerator.teeX, y: 0)
    var strokes = 0
    private var clubIdx = 0
    var heightPct = 0.6
    private var results: [(par: Int, strokes: Int, gaveUp: Bool)] = []
    enum Mode { case aim, swinging, motion, walking, holed, end, surprise, ritual } // Surprises.swift 확장이 읽는다
    var mode = Mode.aim
    var dir = 1.0
    private var heldKeys = Set<UInt16>()
    var lastTime: TimeInterval = 0
    private var acc = 0.0
    private let timeScale = 2.5
    var isGamePaused = false
    var demoMode = false // --demo: 조준에서 자동 스윙 반복 — 모션 관찰용 (디버그 전용)
    var demoWallForce = false // --demo-wall: 매 홀을 벽 옆에서 시작 — 벽 스탠스 관찰용
    var demoCardPreview = false // --demo-card: 스코어카드 레이아웃 즉시 표시 (디버그 전용)
    var demoNoClamp = false // --no-wall-clamp: 벽 경성 클램프 끄기 — 침범 재현·검증 전용
    var demoSeed: UInt32? // --seed N: 코스 시드 고정 — 특정 지형·장애물 시각 검증용 (디버그 전용)
    var demoTripForce = false // --demo-trip: 긴 걸음마다 넘어지기 강제 — 모션 관찰용 (디버그 전용)
    var demoIdleForce = false // --demo-idle: 조준을 25s 유지 — 아이들 잔동작 관찰용 (디버그 전용)
    var demoSetbackForce = false // --demo-setback: 모든 샷을 좌절 계열로 — 좌절 반응 관찰용
    var demoGreetForce = false // --demo-greet: 조준 3s 뒤 일시정지→1s 뒤 재개, 인사 임계 0 — 포커스 복귀 인사 관찰용
    var demoGreeted = false
    var demoMotionShowcase = false // --demo-motions: 모션 37종 순서 시연 — 카탈로그 캡처용 (디버그 전용)
    var demoShowpieceForce = false // --demo-memes: 걷기마다 쇼피스 1개, 12종 순환 (카탈로그 캡처용)
    var demoSurpriseForce = false // --demo-surprise: 샷마다 서프라이즈 (관찰용)
    var demoPickupForce = false // --demo-pickup: 컵 앞 시작 — 공 줍기 의식 관찰
    var demoSettleForce = false // --demo-settle: 첫 샷을 홀 쪽 라이저 상단(러프, |경사| > 0.42)에 떨어뜨려 정착 굴림 관찰
    var demoPower: Double? // --demo-power P: 봇 파워 고정 (실플레이 풀파워 조건 재현용) — 조준 프리뷰에도 적용
    var demoStartHole = 1 // --demo-hole N: 새 라운드를 N번 홀부터 (미러 홀·특정 아키타입 관찰)
    var demoBallX: Double? // --demo-ball X: 홀 시작 공 위치(m) — 특정 라이·거리의 조준 자세 관찰
    var demoTurnForce = false // --demo-turn: 첫 샷을 뒤로 22m 떨어뜨려 걷기 방향 반전(제자리 돌기) 관찰
    var demoReplanForce = false // --demo-replan: 걷는 도중 공을 옮긴다 (1차 12m 앞 → 연속 재계획, 2차 25m 뒤 → 도착 후 재출발+턴)
    private var demoReplanCount = 0
    var demoGIRForce = false // --demo-gir: 파4·5에서 그린 위 정지면 무조건 원온/투온 연출 (관찰용)
    // 공 줍기 의식 (2026-09-17 사용자 요청 "공이 튀어오르지 말고 손에 들게"): 공이 트레일 손을 따라간다
    var ballHeld = false
    var pickupVariant = 0 // 0 = 툭 던져 받기 · 1 = 주머니에 넣기
    var pickupCatchPlayed = false
    var demoTrademarkForce = false // --demo-trademark: 풀샷마다 굿샷 판정(트월 강제) + 리그 덤프 로그 — 트레이드마크 관찰용
    var demoClubId: String? // --club ID: 홀 시작 클럽 지정(DR·7I·SW·PT…) — 클럽별 어드레스 관찰용
    var demoBackdrop = false // --demo-bg: 불투명 배경 (캡처 판독용)
    // ── 서프라이즈 상태 (Surprises.swift) ──
    var demoSurpriseKind: SurpriseKind? // --surprise KIND: 해당 훅마다 그 종류 강제 (관찰용)
    var surpriseCounts: [SurpriseKind: Int] = [:] // 라운드당 종류별 발동 수 (등급 상한)
    var preShot = (x: CourseGenerator.teeX, strokes: 0, remain: 0.0) // 멀리건용 직전 샷 스냅샷
    var gustWind: Double? // 돌풍 중 바람 덮어쓰기 (m/s) — Ballistics.step에 전달
    var gustUntil: TimeInterval = 0
    var napping = false // 낮잠 중 — 키 입력은 깨우기로 소비
    var napIdle = Double.infinity // 마지막 입력 뒤 이만큼 방치하면 낮잠 (초, 조준당 1회)
    var lastInputAim = 0.0 // 조준 중 마지막 키 입력 시각 (aimTime)
    var demoRestartIn: Double? // --demo-restart-in T: 서프라이즈 시작 T초 뒤 새 라운드 (인터럽트 정리 관찰)
    var demoRestartAfterHoled: Double? // --demo-restart-after-holed T: 첫 홀아웃 T초 뒤 새 라운드 (홀 전환 타이머 인터럽트 관찰)
    private var demoRestartedAfterHoled = false
    var napStart = 0.0
    var napNode: SKNode?
    var catState: CatState?
    var surpriseCursor = 0
    // ── 서프라이즈 2차 (Surprises2.swift) ──
    var ballKind = BallKind.standard // 공 바꿔치기: 다음 한 샷만 (샷이 끝나면 표준으로)
    var tunnelArmed = false // 창 터널: 이 샷의 첫 범퍼 진입을 반사 대신 터널로
    var tunnelTransit: TunnelTransit? // 창 속을 지나는 중 — 비행 물리 정지
    /// 급경사 정착(`Ballistics.settleOffSteepSlope`)의 스냅을 렌더에서 굴림으로 — 물리 위치는 즉시 확정, 그림만 from→to
    /// (프로브 실측 2026-09-23: 샷의 1.2%, 최대 18.5m·평균 5.4m — 한 프레임 점프는 순간이동으로 보인다)
    var settleRoll: (from: Double, to: Double, t: Double, dur: Double)?
    var galleryState: GalleryState?
    var demoBumperFracs: [[Double]] = [] // --demo-bumpers: 창이 없는 관찰 환경용 합성 범퍼 (화면 비율 x,y,w,h)
    var motionCursor = 0 // --demo-motions 시연 커서 (--motion-cursor N으로 중간부터)
    private var showpieceCursor = 0
    private var demoWait = 0.0

    /// 연출 상태
    private struct SwingAnim { var t = 0.0; var launched = false; let prof: SwingProfile; let fromPose: Pose }
    /// 발 하나의 게이트 상태 — 접지점은 월드(진행축) 좌표로 래치되어 절대 밀리지 않는다
    private struct FootGait {
        var plant = 0.0 // 접지점 (진행축 px, 래치)
        var swingFrom = 0.0
        var swingTo = 0.0 // 리프트오프 순간 고정되는 다음 착지점
        var inSwing = false
    }

    private struct WalkAnim {
        let fromX, toX, dur: Double
        let profile: WalkProfile // 램프·등속·램프 속도 프로파일 — 위치와 vInst의 단일 출처 (GolfCore)
        var t = 0.0
        var relax = 0.8 // 피니시 여운 — 서두르지 않는다 (방향 반전이면 제자리 돌기만큼 길어진다)
        /// 제자리 돌기 (2026-09-23, docs/research-turn-in-place.md): 예고(머리 선행) → 구 뒷발이 새 방향으로 짧게 내딛기 →
        /// 가장 좁은 실루엣에서 반전(미러·발 정체 교환) → 구 앞발 반 보폭 → 정착. 끝난 스탠스 = 걷기 시작 스탠스(−11·+16)라 미끄러짐 0
        struct TurnPlan {
            let start: Double // walk 시계 기준 시작
            let dur: Double
            let newDir: Double
            var atBody = false // 도착 턴: 원점이 몸(걷기 좌표) — 출발 턴은 공 원점이라 몸이 ∓(ballFwd+5)에 선다
            var flipped = false
            var started = false
        }

        var turn: TurnPlan?
        var arrivalTurn: TurnPlan? // 도착 턴 — 걸어온 방향과 조준 방향이 반대일 때 (공이 뒤에 있던 경우)
        var mood = WalkMood.neutral // 무드 워크 채널 오버레이 (속도·보폭·자세)
        var replanFired = false // --demo-replan: 이 걷기에서 공을 이미 옮겼나
        var arrivalDir = 1.0
        var vPx = 0.0
        // 게이트 상태 (리서치 반영: stride warping + 접지점 래치)
        var gaitPhase = 0.0 // 보행 위상 (1 = 두 걸음)
        var stepL = 22.0 // 현재 보폭 — 속도에 비례해 줄어든다 (walk ratio)
        var duty = 0.66 // 접지 비율 — 느릴수록 커진다 (double support 증가)
        var feet = [FootGait(), FootGait()]
        var gaitReady = false
        // 랜덤 잉여 동작 (생명감): 어깨 캐리 구간 + 짧은 모션 이벤트들 (walk 시작 기준 초)
        var shoulderRange: ClosedRange<Double>?
        var flavorEvents: [WalkFlavorEvent] = []
        // 아주 가끔 넘어지기 (2026-08-15 사용자 요청 — 재미): t0는 walk 시계(초), 총 2.2s
        var tripAt: Double?
        var tripFxDone = false
        // 쇼피스 밈 모션 (2026-08-20): 걷기를 멈추고 크게 추는 희귀 이벤트 — 걷기당 최대 1개
        var showAt: Double?
        var showKind: ShowpieceKind?
        var pausedTime = 0.0 // 넘어져 있는 동안 전진이 멈춘 시간 — 걸음 시계에서 빼서 위치를 동결
        var stepFxParity = false // 스텝 먼지는 한 걸음 걸러 — 과하지 않게
        var relaxShift = 0.0 // 여운 포즈의 로컬 x 보정 (방향 반전 시 몸 자리에 앵커)

        /// 정지 발자국 계획 (2026-09-14 전환 개편): 남은 거리가 stopPlanRange 이하가 된 착지 순간부터
        /// 위상 대신 '남은 거리 비율 p'가 발을 움직인다 — 뒷발이 먼저 어드레스 뒷발 자리(-11)에,
        /// 앞발이 마지막에 앞발 자리(+16)에 내려앉아 몸이 멈추는 순간 스탠스가 완성된다.
        /// 미끄러짐 대신 보폭 차이로 오차를 흡수한다 (UE distance matching·footstep planning 번안)
        struct StopPlan {
            let dStart, dStop, rearFrom, frontFrom: Double
            static let rearOffset = -11.0, frontOffset = 16.0 // 어드레스 포즈 foot1/foot2 − hip
            func progress(_ dNow: Double) -> Double {
                min(1, max(0, (dNow - dStart) / max(1e-6, dStop - dStart)))
            }
        }

        static let stopPlanRange = 42.0 // 마지막 두 걸음 보폭 0.5~1.0배 — 50은 다리 45에서 보폭 극단에 힙이 7px 내려앉았다
        var stopPlan: StopPlan?
        var planPhase0 = 0.0

        /// 두 발 모두 접지한 순간에만 호출 — 뒤에 있는 발을 feet[0](포즈 foot1 = 뒷발)로 정렬.
        /// 반환 true면 정체를 교환했으니 호출측은 렌더 리그의 foot/knee도 함께 교환해야 한다
        /// (타깃만 바꾸면 스무딩(footRate 60)이 두 발을 2~3프레임 가운데로 모았다 벌린다 — 리뷰 2026-09-14)
        mutating func beginStopPlan(dNow: Double, dStop: Double) -> Bool {
            let swapped = feet[1].plant < feet[0].plant
            if swapped {
                feet.swapAt(0, 1) // 두 다리는 같은 획이라 교환 자체는 화면에 보이지 않는다
            }
            stopPlan = StopPlan(dStart: dNow, dStop: dStop, rearFrom: feet[0].plant, frontFrom: feet[1].plant)
            planPhase0 = gaitPhase
            return swapped
        }
    }

    /// 골프 의식 (2026-08-29 CMU 모캡 이식): 티 꽂기·공 줍기 — 타이밍·자세 비율은
    /// refs/mocap 64_17/64_20(스쿼트 0.68, 21/60/19)·64_28/64_29(허리 힌지, 33/33/33) 실측
    fileprivate struct RitualAnim {
        enum Kind { case teePlace, ballPickup }
        let kind: Kind
        var t = 0.0
        var touchFired = false
        var cupDx = 16.0 // pickup: 컵의 로컬 x (facing 기준)
        static let pickupGrab = 1.15 // 줍기(허리 힌지) 구간 — 뒤에 들고 보기·던져 받기/주머니 1.35s가 붙는다
        var dur: Double {
            kind == .teePlace ? 1.35 : Self.pickupGrab + 1.35
        }
    }

    fileprivate var ritualAnim: RitualAnim?
    private var swingAnim: SwingAnim?
    private var walkAnim: WalkAnim?
    private var lastFinishPose: Pose?
    private var renderRig = RigBuilder.fromPose(Poses.p1, ballFwd: 24, clubLen: 31)
    // 클럽 변경 시 즉시 점프하는 값들은 전부 스무딩을 탄다 (길이·스탠스·백스윙 폭)
    private var renderLen = 31.0
    private var renderBallFwd = 24.0
    private var renderTop = 1.0
    private var renderLoft = 10.5 // 헤드 기하(크기·틸트·굵기)도 이 값으로 구동 — 모양 점프 방지
    // 헤드 '종류'(우드/블레이드/퍼터) 전환은 캡슐 기하 morph — 이전 종류에서 새 종류로 0.3s 변형
    private var prevHeadClub = ClubTable.all[0]
    private var lastClub = ClubTable.all[0]
    private var headMorph = 1.0
    var aimTime = 0.0 // 조준 진입 후 경과 — 진입 직후엔 천천히 가라앉는다
    private var renderWallT = 0.0 // 벽 스탠스 근접도 (스무딩) — 뒷발 벽 딛기 자세 블렌드
    private var renderTreeT = 0.0 // 나무 캐노피 근접도 (스무딩) — 웅크린 펀치 자세 블렌드
    private var finishAt: TimeInterval = 0 // 피니시 도달 시각 — 무빙 홀드 감쇠 진동 기준
    /// 홀아웃 직후 스틱맨의 스코어 반응 (QA·Whimsy 리뷰 — 결과에 감정을 싣는다)
    enum ReactionKind { case none, rejoice, fistPump, nod, slump, dejected, startled, shoo, laugh } // 뒤 셋은 서프라이즈 반응
    /// 무드 워크 (2026-09-23, docs/research-mocap-index.md 적용안): 홀아웃·온그린·워터·좌절의 감정이 다음 걷기 전체에 남는다
    enum WalkMood: String { case neutral, elated, sad }
    var reactionKind = ReactionKind.none
    var reactionAt: TimeInterval = 0
    /// 이번 샷의 스트라이크 품질 — 타이거 트월 트리거. 결과(낙하 지점)가 아니라 발사 순간의 '느낌'(미스힛·파워)으로 판단
    var lastShotGood = false
    private var rigDumpLast: TimeInterval = 0
    private var jumpLogged = false // 계측: 임팩트 점프 로그 스윙당 1회
    private var twirlLogged = false // 계측: 트월 로그 스윙당 1회
    /// 조준 방치 시 잔동작 (아이들) — 곁눈질했을 때도 스틱맨이 살아 있다
    private var idleNextAt = 6.0
    private var idleKind = 0
    private var idleStart = 0.0
    var stickX = CourseGenerator.teeX
    var trailPoints: [CGPoint] = [] // Surprises2(창 터널)가 진입점에서 끊는다
    private var didSetUp = false // didMove 완료 전 didChangeSize 가드 (모니터 전환)
    var shotBumpers: [Bumper] = [] // 창 범퍼 — 샷 순간 스냅샷, 비행 동안 고정 (Surprises2 창 터널이 읽는다)
    private var shotHitBumper = false // 이 샷에서 범퍼를 맞았나 — 뱅크샷 홀인 배지 판정
    var roundHadWater = false // 무입수 라운드 배지 판정
    // QA P1 재미 3 (2026-09-16): 좌절 반응·버디 스트릭·포커스 복귀 인사
    var setbackStreak = 0 // 워터·벙커·립아웃 연속 횟수 — 2회째에 좌절 반응
    var lastShotLie = Surface.tee // 직전 샷을 친 라이 — 벙커 탈출 실패(벙커에서 쳐서 벙커에 남음) 판정
    var bunkerHintShown = false // 벙커 탈출 힌트는 홀당 한 번 (QA 2026-08-15 "탈출 실패 루프")
    var walkMood = WalkMood.neutral // 무드 워크: 다음 걷기의 감정
    var walkMoodLeft = 0 // 남은 걷기 횟수 (버디·더블보기·기권 2, 온그린·워터·좌절 1)
    var demoMood: WalkMood? // --demo-mood M: 모든 걷기에 무드 강제 (관찰)
    var shotLipped = false // 이번 샷에 립아웃이 있었나 (정지 시 좌절 판정)
    var birdieStreak = 0 // 연속 버디 이상 — 2회부터 홀아웃 토스트에 표시
    var pausedAt: Date? // 5분 이상 비웠다 돌아오면 손 흔들기

    var hole: Hole {
        course[holeIdx]
    }

    private var club: Club {
        ClubTable.all[clubIdx]
    }

    /// 스윙 스타일 (⛳️ 메뉴 선택, UserDefaults 기억) — 키프레임·템포만 바뀌고 물리는 동일
    var swingStyle = SwingStyle.saved

    private var profile: SwingProfile {
        SwingProfile.profile(for: club.cat, style: swingStyle)
    }

    func setSwingStyle(_ style: SwingStyle) {
        swingStyle = style
        UserDefaults.standard.set(style.rawValue, forKey: SwingStyle.prefKey)
        toast("스윙 스타일 · \(style.title)", sub: nil)
    }

    var pxPerM: CGFloat {
        size.width / hole.worldW
    }

    private var groundBase: CGFloat = 96 // 홀 최저 표고에 맞춰 rebuildTerrain에서 보정 (HUD 침범 방지)
    /// 경사 라이: 스탠스 기울기 = 로프트 전달 비율 — 단일 출처는 Phys (리뷰 S-6)
    private let slopeTiltRatio = Phys.stanceSlopeRatio
    private var renderSlopeTilt = 0.0 // 경사 스탠스 기울기 (스무딩)

    // 노드
    private let terrainNode = SKNode()
    let stickman = StickmanNode()
    let ballNode = SKShapeNode(circleOfRadius: 5.5)
    let shadowNode = SKShapeNode(ellipseOf: CGSize(width: 15, height: 4.5))
    let trailNode = SKShapeNode()
    let trailUnderNode = SKShapeNode() // 궤적 언더스트로크 (밝은 배경 대비)
    let flagNode = SKNode()
    private let scoreTitle = GlassLabel(font: HUDFont.medium, size: 17, align: .right, kern: 1.0)
    private let scoreSub = GlassLabel(font: HUDFont.regular, size: 12, alpha: 0.8, align: .right)
    private let clubTitle = GlassLabel(font: HUDFont.medium, size: 17, align: .left, kern: 1.0)
    private let clubSub = GlassLabel(font: HUDFont.regular, size: 11.5, alpha: 0.7, align: .left, kern: 1.4)
    private let hintLabel = GlassLabel(font: HUDFont.regular, size: 11.5, alpha: 0.66)
    private let pauseLabel = GlassLabel(font: HUDFont.medium, size: 14)
    private let toastTitle = GlassLabel(font: HUDFont.light, size: 34, kern: 2.0)
    private let toastSub = GlassLabel(font: HUDFont.regular, size: 13, alpha: 0.8)
    private let powerLabel = GlassLabel(font: HUDFont.medium, size: 11, alpha: 0.85)
    private let scorecard = ScorecardNode()

    func px(_ m: Double) -> CGFloat {
        CGFloat(m) * pxPerM
    }

    func py(_ elev: Double) -> CGFloat {
        groundBase + CGFloat(elev) * pxPerM
    }

    func groundY(_ xm: Double) -> CGFloat {
        py(hole.ground(at: xm))
    }

    override func didMove(to _: SKView) {
        backgroundColor = .clear // ⚠️ skView.backgroundColor는 설정 금지
        if demoBackdrop { // 관찰 전용: 데스크탑 위 겹침 없이 캡처하기 위한 불투명 배경 (실플레이 경로 아님)
            let bg = SKShapeNode(rect: CGRect(x: -100, y: -100, width: size.width + 200, height: size.height + 200))
            bg.fillColor = NSColor(white: 0.16, alpha: 1)
            bg.strokeColor = .clear
            bg.zPosition = -100
            addChild(bg)
        }

        ballNode.fillColor = .white
        ballNode.lineWidth = 1.2
        shadowNode.fillColor = NSColor(white: 0, alpha: 0.28)
        shadowNode.strokeColor = .clear
        trailNode.strokeColor = NSColor(white: 1, alpha: 0.28)
        trailNode.lineWidth = 1
        trailUnderNode.strokeColor = NSColor(white: 0, alpha: 0.3)
        trailUnderNode.lineWidth = 2.8
        trailUnderNode.lineCap = .round

        layoutHUD()
        hintLabel.setText("←→ 클럽 · ↑↓ 백스윙 · Space 스윙 · R 새 라운드 · Esc 종료")
        pauseLabel.setText("일시정지 — 메뉴바 ⛳️ 클릭으로 재개")
        pauseLabel.isHidden = true
        toastTitle.alpha = 0
        toastSub.alpha = 0
        scorecard.hide()

        for n in [terrainNode, trailUnderNode, trailNode, stickman, shadowNode, ballNode, flagNode] as [SKNode] {
            addChild(n)
        }
        for n in [
            scoreTitle,
            scoreSub,
            clubTitle,
            clubSub,
            hintLabel,
            pauseLabel,
            toastTitle,
            toastSub,
            powerLabel,
            scorecard,
        ] as [SKNode] {
            addChild(n)
        }

        // 힌트는 잠시 후 조용히 사라진다 (화면을 어지르지 않기)
        hintLabel.run(.sequence([.wait(forDuration: 8), .fadeOut(withDuration: 1.2)]))

        applyContrastMode()
        newRound()
        didSetUp = true
        if demoCardPreview { // 스코어카드 레이아웃 검증용 고정 샘플 (이글·버디·파·보기·더블·기권 포함)
            let sample: [(par: Int, strokes: Int, gaveUp: Bool)] = [
                (4, 4, false), (3, 2, false), (4, 5, false), (5, 3, false), (4, 4, false),
                (3, 6, false), (4, 12, true), (5, 5, false), (4, 3, false),
            ]
            scorecard.show(results: sample, title: "라운드 종료", footer: "합계 +7 · 흐린 숫자 = 기권  —  R로 새 라운드")
        }
    }

    /// HUD는 지면 아래 스트립(0~96px 빈 띠) — 시선이 플레이 지점을 떠나지 않는다 (2026-08-14 사용자 결정)
    private func layoutHUD() {
        scoreTitle.position = CGPoint(x: size.width - 24, y: 66)
        scoreSub.position = CGPoint(x: size.width - 24, y: 40)
        clubTitle.position = CGPoint(x: 24, y: 66)
        clubSub.position = CGPoint(x: 24, y: 40)
        hintLabel.position = CGPoint(x: size.width / 2, y: 60)
        pauseLabel.position = CGPoint(x: size.width / 2, y: size.height - 46) // 일시정지 배너만 상단(⛳️ 버튼 곁)
        toastTitle.position = CGPoint(x: size.width / 2, y: size.height * 0.64)
        toastSub.position = CGPoint(x: size.width / 2, y: size.height * 0.64 - 42)
        scorecard.position = CGPoint(x: size.width / 2, y: size.height / 2)
    }

    /// 모니터 전환(2026-08-20): 월드는 미터 단위라 홀 진행은 그대로 — px 파생물만 재계산
    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard didSetUp, oldSize != size else { return }
        layoutHUD()
        trailPoints = [] // px 캐시 — 화면 폭이 바뀌면 무효
        rebuildTerrain()
        updateHUD()
    }

    /// ── 고대비 모드 (밝은 배경 opt-in) ──
    func setHighContrast(_ on: Bool) {
        Theme.highContrast = on
        applyContrastMode()
        rebuildTerrain() // 지형 언더스트로크·깃대 테두리는 재생성으로 반영
    }

    private func applyContrastMode() {
        ballNode.strokeColor = Theme.highContrast ? NSColor(white: 0, alpha: 0.4) : .clear
        trailUnderNode.isHidden = !Theme.highContrast
        stickman.applyContrast()
        scorecard.applyContrast()
        for l in [
            scoreTitle, scoreSub, clubTitle, clubSub, hintLabel,
            pauseLabel, toastTitle, toastSub, powerLabel,
        ] {
            l.applyContrast()
        }
    }

    func newRound() {
        course = CourseGenerator.makeCourse(
            seed: demoSeed
                ?? UInt32(Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 2_000_000_000))
        )
        holeIdx = demoMode ? min(8, max(0, demoStartHole - 1)) : 0
        results = []
        roundHadWater = false
        setbackStreak = 0
        bunkerHintShown = false
        walkMoodLeft = 0
        birdieStreak = 0
        surpriseCounts = [:]
        scorecard.hide()
        startHole()
    }

    private func startHole() {
        cancelSurprises() // R 새 라운드·홀 전환 중 진행 중이던 서프라이즈 정리 (리뷰 M2)
        cancelHoleFlow() // 홀아웃·기권 뒤 '줍기/다음 홀' 타이머 — R이 끼어들면 새 라운드의 1번 홀을 건너뛰었다 (2026-09-23 재현)
        strokes = 0
        // 티샷 기본 클럽: 파4·5 드라이버, 파3 7번 아이언 (관례 — 2026-08-15 사용자 요청. ←→ 변경 자유)
        let teeClub = hole.par == 3 ? "7I" : "DR"
        clubIdx = ClubTable.all.firstIndex { $0.id == teeClub } ?? 0
        if let id = demoClubId, let i = ClubTable.all.firstIndex(where: { $0.id == id }) {
            clubIdx = i // 관찰용 클럽 고정
        }
        renderBallFwd = profile.ballFwd // 홀 시작 클럽의 스탠스로 즉시 — 퍼터(6)→드라이버(20) 활강이 티 의식 발 기준점을 미끄러뜨린다 (리뷰)
        ball = BallState(x: hole.teeX, y: hole.ground(at: hole.teeX)) // 미러 홀은 오른쪽 티에서 시작
        if demoPickupForce { // 공 줍기 의식 관찰: 컵 앞 그린에서 시작 — 탭인 → 홀인 → 줍기
            let x = hole.holeX - 1.2 * (hole.holeX >= hole.teeX ? 1 : -1)
            ball = BallState(x: x, y: hole.ground(at: x))
        }
        if let x = demoBallX { // 공 위치 고정 관찰 (라이·거리별 조준 자세)
            let cx = min(max(x, 1), hole.worldW - 1)
            ball = BallState(x: cx, y: hole.ground(at: cx))
        }
        if demoWallForce { // 벽 스탠스 관찰: 릴리프 하한(46px) 직후의 최소 이격 케이스로 시작
            let m = 48 / Double(pxPerM)
            let x = hole.holeX > hole.teeX ? m : hole.worldW - m
            ball = BallState(x: x, y: hole.ground(at: x))
        }
        trailPoints = []
        swingAnim = nil
        walkAnim = nil
        ballHeld = false
        settleRoll = nil
        ballNode.removeAllActions() // 홀인 드롭 연출 복구
        ballNode.alpha = 1
        ballNode.setScale(1)
        rebuildTerrain()
        PlayLog.note(
            "HOLE \(holeIdx + 1) par \(hole.par) \(hole.signature?.rawValue ?? "plain") tee \(Int(hole.teeX)) cup \(Int(hole.holeX)) "
                + "green \(Int(hole.greenStart))-\(Int(hole.greenEnd))"
        )
        if demoMode, let sig = hole.signature { // 캡처 대조용 계측 (관찰용)
            print("SIGNATURE \(sig.rawValue)")
            fflush(stdout)
        }
        // 티 꽂기 의식 — 모션 카탈로그 캡처 모드에선 생략 (걷기 관찰이 목적)
        if !demoMotionShowcase, !demoCardPreview {
            startRitual(.teePlace)
        } else {
            enterAim()
        }
    }

    /// 홀 전환 타이머(홀아웃 → 줍기/다음 홀, 기권 → 다음 홀)는 씬에 직접 run하지 않고 이 노드에 건다 — `startHole`이 지운다.
    /// 씬 직접 run은 R 새 라운드를 넘어 살아남아 새 라운드 1번 홀에 이전 홀의 줍기 의식이 끼어들고 `advanceHole`로 스코어 없이
    /// 2번 홀로 넘어갔다 (Code Reviewer 범위 밖 관찰 → `--demo-pickup --demo-restart-after-holed 0.5`로 재현, 2026-09-23)
    static let holeFlowNodeName = "holeFlowTimer"
    private func afterHoleFlow(_ delay: Double, _ block: @escaping () -> Void) {
        let timer = SKNode()
        timer.name = Self.holeFlowNodeName
        addChild(timer)
        timer.run(.sequence([.wait(forDuration: delay), .run(block), .removeFromParent()]))
    }

    private func cancelHoleFlow() {
        enumerateChildNodes(withName: Self.holeFlowNodeName) { node, _ in node.removeFromParent() }
    }

    /// 걷는 도중 공이 같은 방향 앞으로 옮겨졌을 때 — 새 프로파일의 등속 구간에서 이어받아 속도·게이트(발자국)를 유지한다.
    /// 새 출발점은 지금 자리보다 램프인 거리만큼 뒤로 잡아 position(rampIn) = 지금 자리가 되게 한다 (위치·속도 연속)
    private func replanAhead(_ w: inout WalkAnim, to: Double) {
        let sgn: Double = w.toX >= w.fromX ? 1 : -1
        let dNowPx = abs(stickX - w.fromX) * Double(pxPerM)
        let moodSpeed = w.mood == .elated ? 0.85 : w.mood == .sad ? 1.45 : 1.0
        var xIn = 6.0 // 램프인 거리(m) 초기 추정 → 프로파일에서 다시 읽는다
        var prof = WalkProfile(dist: abs(to - stickX) + xIn, dur: 1)
        for _ in 0 ..< 2 {
            let dist = abs(to - stickX) + xIn
            let dur = min(14.0, max(1.2, dist / 10 * moodSpeed))
            prof = WalkProfile(dist: dist, dur: dur)
            xIn = prof.position(at: prof.rampIn)
        }
        var n = WalkAnim(fromX: stickX - sgn * xIn, toX: to, dur: prof.dur, profile: prof)
        n.relax = 0
        n.t = prof.rampIn // 등속 구간 첫 프레임 = 지금 자리
        n.gaitReady = true
        n.gaitPhase = w.gaitPhase
        n.stepL = w.stepL
        n.duty = w.duty
        n.vPx = w.vPx
        n.mood = w.mood
        n.stepFxParity = w.stepFxParity
        n.replanFired = w.replanFired
        let shift = xIn * Double(pxPerM) - dNowPx // 진행축 원점 fromX → 새 fromX
        n.feet = w.feet.map { f in
            var g = f
            g.plant += shift
            g.swingFrom += shift
            g.swingTo += shift
            return g
        }
        if demoMode {
            print(String(format: "REPLAN ahead to %.1f (남은 %.1fm)", to, abs(to - stickX)))
            fflush(stdout)
        }
        w = n
    }

    /// --demo-replan: 걷기 1.5s 지점에서 공을 옮긴다 — 1차 12m 앞(연속 재계획), 2차 25m 뒤(도착 후 재출발·제자리 돌기)
    private func demoReplanTick(_ w: inout WalkAnim) {
        guard demoReplanForce, !w.replanFired, demoReplanCount < 2, w.t - w.relax - w.pausedTime > 1.5 else { return }
        w.replanFired = true
        let sgn: Double = w.toX >= w.fromX ? 1 : -1
        let ahead = demoReplanCount == 0
        demoReplanCount += 1
        let nx = min(max(ahead ? ball.x + sgn * 12 : stickX - sgn * 25, 2), hole.worldW - 2) // 2차는 걷는 사람 뒤로
        ball = BallState(x: nx, y: hole.ground(at: nx))
        print(String(format: "DEMO-REPLAN %@ ball → %.1f", ahead ? "ahead" : "behind", nx))
        fflush(stdout)
    }

    /// 무드 워크 채널 (docs/research-mocap-index.md — CMU 걷기 스타일 차분의 실루엣 요약, 70px용 과장):
    /// 들뜸(elated) = 폴짝 바운스·팔 크게·머리 들고 가슴 폄 · 처짐(sad) = 힙·어깨 내려앉고 머리 숙임·어깨 앞으로·팔 죽음·보폭 0.8.
    /// 출발 0.6s 램프인, 도착 0.9s 램프아웃 — 정지 발자국 계획이 완성되는 스탠스는 중립이어야 조준 전환이 튀지 않는다
    private func moodEnvelope(tw: Double, dur: Double) -> Double {
        smoothstep(min(1, max(0, tw / 0.6))) * smoothstep(min(1, max(0, (dur - tw) / 0.9)))
    }

    private func applyMood(_ f: inout WalkFlavor, mood: WalkMood, tw: Double, dur: Double) {
        let e = moodEnvelope(tw: tw, dur: dur)
        guard e > 0, mood != .neutral else { return }
        // 1차 값(힙 −2.5·머리 −3·폴짝 0.35)은 프레임 시트에서 거의 안 읽혔다 → 2배 과장 (2026-09-23)
        if mood == .elated {
            f.skip += 0.6 * e
            f.armAmpBoost += 0.8 * e
            f.headDyOff += 3.0 * e
            f.shoulderYOff += 2.0 * e
            f.gripLift += 0.6 * e
        } else {
            f.hipYOff -= 5.0 * e
            f.shoulderYOff -= 3.0 * e
            f.shoulderXOff += 4.0 * e
            f.headDyOff -= 5.0 * e
            f.headDxOff += 3.0 * e
            f.armAmpBoost -= 0.7 * e
        }
    }

    private func moodStride(_ mood: WalkMood, e: Double) -> Double {
        mood == .elated ? 1 + 0.1 * e : mood == .sad ? 1 - 0.3 * e : 1
    }

    /// 제자리 돌기 리그 — 걷기 리그 공간(몸 원점)에서 만들어 몸이 서 있는 자리(공 원점 기준 ∓(ballFwd+5))로 옮긴다.
    /// 반전 전(구 facing): 앞발(+16)을 축으로 두고 뒷발(−11)을 새 방향으로 5px 내딛는다 → 미러 후 그 발이 새 앞발(+16)이 된다.
    /// 반전 후(새 facing): 축발(이제 뒷발, −16)이 −11로 반 걸음 → 걷기 시작 스탠스와 일치. 머리는 예고 구간부터 새 방향, 힙은
    /// 반전 즈음 2px 내려앉는다(무릎 거의 폄 → IK 방향 뒤집힘이 안 튄다). 수치는 리서치 권고(0.65s, 15/30/10/30/15%)의 2.5배 과장
    private func turnRig(_ tp: WalkAnim.TurnPlan, t: Double) -> Rig {
        let u = min(1, max(0, (t - tp.start) / tp.dur))
        let step1 = smoothstep(min(1, max(0, (u - 0.15) / 0.30))) // 구 뒷발
        let step2 = smoothstep(min(1, max(0, (u - 0.55) / 0.30))) // 구 앞발(축발)
        let lift1 = sin(.pi * min(1, max(0, (u - 0.15) / 0.30)))
        let lift2 = sin(.pi * min(1, max(0, (u - 0.55) / 0.30)))
        var flavor = WalkFlavor()
        flavor.hipYOff = -2 * sin(.pi * min(1, max(0, (u - 0.3) / 0.4))) // 반전 즈음 무게 싣기
        let hipLocal = tp.atBody ? 0 : (tp.flipped ? 1.0 : -1.0) * (renderBallFwd + 5)
        var f1: (x: Double, lift: Double)
        var f2: (x: Double, lift: Double)
        if !tp.flipped { // 구 facing: foot1 = 뒷발(내딛는 발), foot2 = 앞발(축)
            f1 = (mix(-11, -16, step1), 6 * lift1 * lift1)
            f2 = (16, 0)
            flavor.hipXOff = 3 * smoothstep(min(1, u / 0.15)) // 축발 쪽으로 체중
            flavor.headDxOff = -6 * smoothstep(min(1, u / 0.15)) // 머리가 먼저 새 방향을 본다 (예고)
        } else { // 새 facing (미러·발 교환 뒤): foot1 = 축발(이제 뒷발), foot2 = 내딛은 발(이제 앞발)
            f1 = (mix(-16, -11, step2), 6 * lift2 * lift2)
            f2 = (16, 0)
            flavor.hipXOff = 3 * (1 - step2)
        }
        var r = RigBuilder.walking(f1: f1, f2: f2, gaitPhase: 0, vPx: 0, clubLen: renderLen, flavor: flavor) { dx in
            let xm = self.stickX + (dx + hipLocal) * self.dir / Double(self.pxPerM)
            return Double(self.groundY(xm) - self.groundY(self.stickX))
        }
        r.shiftX(hipLocal)
        return r
    }

    /// --demo-settle: 홀에서 티 쪽으로 훑어 처음 만나는 러프 급경사(|경사| > 0.42 — 러프 마찰 4.5가 중력 3.5를 이겨 서는 자리).
    /// 협곡이면 홀 쪽 라이저 상단이라 정착이 라이저 전체를 내려간다 (프로브 최대 18.5m 사례). 없으면 nil (일반 홀)
    private func demoSteepRimSpot() -> Double? {
        let toward = hole.teeX >= hole.holeX ? 1.0 : -1.0
        var x = hole.holeX
        while (hole.teeX - x) * toward > 0 {
            if abs(hole.slope(at: x)) > 0.42, hole.surface(at: x) == .rough {
                return x
            }
            x += toward * 0.5
        }
        return nil
    }

    /// 핀 이동 서프라이즈 — 홀을 사본으로 교체하고 지형·컵·깃발을 다시 그린다 (Surprises2)
    func replaceHole(_ h: Hole) {
        course[holeIdx] = h
        rebuildTerrain()
    }

    /// 방향 전환 — 렌더 리그를 로컬 미러하고 두 발의 정체를 교환해 화면 위치를 보존한다.
    /// 구현 전(2026-09-14)에는 facing이 바뀌는 프레임에 스틱맨 전체가 원점 기준으로 뒤집혔다 (발 27~32px 점프).
    /// 미러 후 타깃을 쫓아가면 머리·팔·클럽이 몸을 가로질러 반대편으로 '돌아서는' 연속 동작이 된다
    private func setFacing(_ newDir: Double) {
        guard newDir != dir else { return }
        renderRig.mirrorX()
        swapRenderFeet()
        dir = newDir
    }

    /// 두 발의 정체 교환을 렌더 리그에도 적용 — 타깃과 렌더가 같은 발을 가리켜야 스무딩이 발을 움직이지 않는다
    private func swapRenderFeet() {
        // swap(&a.x, &a.y)는 같은 프로퍼티(renderRig)에 대한 중첩 inout 접근이라 런타임 배타성 위반으로 크래시한다
        // (2026-09-15 시연 중 "Fatal access conflict" 실측) — 임시 변수로 교환
        let f = renderRig.foot1
        renderRig.foot1 = renderRig.foot2
        renderRig.foot2 = f
        let k = renderRig.knee1
        renderRig.knee1 = renderRig.knee2
        renderRig.knee2 = k
    }

    private func enterAim() {
        mode = .aim
        aimTime = 0
        if demoMode, let p = demoPower {
            heightPct = p // 관찰: 조준 프리뷰(백스윙 높이)도 고정 파워로
        }
        reactionKind = .none
        napping = false
        napNode?.removeFromParent()
        napNode = nil
        lastInputAim = 0
        napIdle = demoSurpriseKind == .nap || demoSurpriseForce ? 0.8 : Double
            .random(in: 12 ... 20) // 롤은 발동 시점에 (tickNap)
        idleKind = 0
        idleNextAt = Double.random(in: 5 ... 9)
        walkAnim = nil
        setFacing(hole.holeX >= ball.x ? 1 : -1)
        // 원점 전환: 걷기(몸 원점) → 조준(공 원점). 렌더 리그를 반대로 옮겨 화면 위치 보존
        renderRig.shiftX(dir * Double(px(stickX) - px(ball.x)))
        stickX = ball.x
        // 그린에 올라오면 퍼터로 자동 전환 (관례 — 이후 ←→로 자유 변경 가능)
        if strokes > 0 || demoPickupForce, hole.surface(at: ball.x) == .green, !club.isPutter { // 관찰 모드는 첫 샷도 퍼터
            clubIdx = ClubTable.all.firstIndex { $0.isPutter } ?? clubIdx
        }
        renderBallFwd = profile.ballFwd // 걷기 도착 자리가 이 클럽의 스탠스로 계획됐으므로 스무딩 없이 맞춘다
        presetPutterHeight()
        updateHUD()
        if demoMode { // 프레임 캡처와 대조할 스탠스 계측 (관찰용): 경사·라이·근처 장애물
            let s = hole.slope(at: ball.x)
            print(String(
                format: "AIM x %.1f lie %@ slope %+.3f tilt %+.1f° obs %d",
                ball.x, hole.surface(at: ball.x).label,
                s, slopeTiltRatio * atan(s) * 180 / .pi, hole.obstacles.count
            ))
            fflush(stdout)
        }
    }

    /// 퍼터를 잡으면 남은 거리에 맞는 백스윙에서 시작한다 — 평지 기준 계산이라
    /// 그린 경사 읽기는 여전히 플레이어의 몫 (어시스트가 아니라 합리적 시작점)
    private func presetPutterHeight() {
        guard club.isPutter, mode == .aim else { return }
        let d = abs(hole.holeX - ball.x)
        let v0 = min(13.0, (2 * 1.1 * d + 4).squareRoot()) // 도착 속도 ~2m/s 목표
        heightPct = min(0.92, max(0.03, (v0 / 13.0 - Phys.putterMinRatio) / (1 - Phys.putterMinRatio)))
    }

    /// ── 벽 스탠스: 화면 끝 = 벽. 몸 뒤 공간이 좁으면 백스윙이 제한되고(펀치샷),
    /// 실제 골퍼처럼 뒷발을 벽에 딛는 자세로 선다 (2026-08-14 사용자 요청 + 리서치 Q5) ──
    private var wallBehindPx: Double {
        dir > 0 ? Double(px(stickX)) : Double(size.width - px(stickX))
    }

    /// 펀치 정도 [0,1] — 벽이 가까울수록 낮은 탄도·적은 스핀. 파워 제한이 아니다:
    /// 사용자 의도(2026-08-14)는 '샷강도 제약'이 아니라 '극복하는 자세' — 폼만 컴팩트해진다
    private var wallPunch: Double {
        club.isPutter ? 0 : min(1, max(0, 1 - (wallBehindPx - 28) / 45))
    }

    /// 나무 캐노피가 샷 방향에 드리우면 1 — 웅크린 펀치로 빠져나가는 극복 자세 (요청 2·4번 연동)
    private var treePunchT: Double {
        guard !club.isPutter else { return 0 }
        var t = 0.0
        for ob in hole.obstacles where ob.kind == .tree {
            let ahead = (ob.x - ball.x) * dir // 샷 방향 거리(m)
            if ahead > -ob.size, ahead < ob.size + 14 {
                t = max(t, 1 - max(0, ahead - ob.size) / 14)
            }
        }
        return t
    }

    /// 벽·나무 근접 시 백스윙 '폼'만 압축 — 짧은 백스윙으로 풀파워를 내는 극복 자세.
    /// 팔·클럽이 화면(벽)이나 캐노피를 뚫지 않는 폭으로 제한한다
    private var wallTopScale: Double {
        renderTop * min(1, max(0.18, (wallBehindPx - 36) / 45)) * (1 - 0.45 * renderTreeT)
    }

    /// 벽이 스탠스 폭보다 가까우면 몸을 벽 안쪽으로 압축 — 공이 스탠스 뒤쪽에 놓인다
    /// (릴리프 46px 이후엔 거의 발동하지 않는 안전망. renderWallT로 스무딩 — 리뷰 S-2)
    private var wallBallFwd: Double {
        guard !club.isPutter else { return renderBallFwd }
        return mix(renderBallFwd, min(renderBallFwd, max(2, wallBehindPx - 10)), renderWallT)
    }

    /// ── 벽 경성 클램프: 리그의 어떤 점(클럽 팁·머리 반지름 포함)도 화면 밖에 그려질 수 없다.
    /// 컴팩트 폼(wallTopScale)이 미적 1차 방어라면 이것은 기하학적 최종 보증 —
    /// 렌더 사본에만 적용되어 추적 상태에는 영향이 없다 (2026-08-15 사용자 재현 신고 대응) ──
    /// 벽 경성 클램프의 로컬 x 경계 (facing 좌표)
    private func wallBounds() -> (lo: Double, hi: Double) {
        let sx = Double(px(stickX))
        let margin = 8.0
        let a = (margin - sx) / dir
        let b = (Double(size.width) - margin - sx) / dir
        return (min(a, b), max(a, b))
    }

    /// IK가 만든 무릎·팔꿈치는 현(chord) 밖으로 최대 ~8px 나온다 — 리그 점 클램프 뒤에 관절도 같은 경계로
    /// (벽 옆에서 관절 획이 화면 밖으로 잘리지 않게 — 리뷰 2026-09-14). 경계에서만 뼈 길이가 미세하게 깨진다
    private func clampJointsToWalls(_ j: inout Skeleton.Joints) {
        let (lo, hi) = wallBounds()
        func cl(_ p: inout CGPoint) {
            p.x = CGFloat(min(hi, max(lo, Double(p.x))))
        }
        cl(&j.knee1)
        cl(&j.knee2)
        cl(&j.elbowLead)
        cl(&j.elbowTrail)
    }

    private func clampRigToWalls(_ rig: inout Rig) {
        let (lo, hi) = wallBounds()
        func cl(_ p: inout CGPoint) {
            p.x = CGFloat(min(hi, max(lo, Double(p.x))))
        }
        cl(&rig.hip)
        cl(&rig.shoulder)
        cl(&rig.foot1)
        cl(&rig.foot2)
        cl(&rig.knee1)
        cl(&rig.knee2)
        cl(&rig.grip)
        cl(&rig.handTrail)
        // 머리 (반지름 ~11)
        let headX = Double(rig.shoulder.x) + rig.headDx
        if headX < lo + 11 {
            rig.headDx += lo + 11 - headX
        } else if headX > hi - 11 {
            rig.headDx -= headX - (hi - 11)
        }
        // 클럽 팁: 길이를 보존한 채 샤프트를 세워서 안으로 (위/아래 반구는 유지 —
        // 벽에 클럽이 '기대어 서는' 자연스러운 제한 백스윙으로 읽힌다)
        let tipX = Double(rig.grip.x) + rig.clubLen * sin(rig.clubPhi)
        if tipX < lo || tipX > hi {
            let s = (min(hi, max(lo, tipX)) - Double(rig.grip.x)) / rig.clubLen
            let t = asin(min(1, max(-1, s)))
            let phiN = rig.clubPhi.remainder(dividingBy: 2 * .pi)
            rig.clubPhi = cos(phiN) >= 0 ? t : .pi - t
        }
    }

    /// 데모 전용 경계 감시 — 렌더 리그가 화면을 벗어나면 즉시 stdout으로 보고 (검증 계기판)
    private var boundsWorst = 0.0
    private var boundsCount = 0
    private var boundsLastLog: TimeInterval = 0
    /// 뼈대 계측 (관찰용): 힙 하강·손 클램프·다리 잔여 신장의 구간 최대치를 0.5초마다 찍는다.
    /// 프레임 캡처와 대조해 "늘어남 0"을 증거로 확인하기 위한 로거 (추정 금지 원칙)
    private var bonesLastLog: TimeInterval = 0
    private var bonesMax = Skeleton.Joints()
    private func logBones(_ j: Skeleton.Joints, currentTime: TimeInterval) {
        bonesMax.hipDrop = max(bonesMax.hipDrop, j.hipDrop)
        bonesMax.clampLead = max(bonesMax.clampLead, j.clampLead)
        bonesMax.clampTrail = max(bonesMax.clampTrail, j.clampTrail)
        bonesMax.legStretch = max(bonesMax.legStretch, j.legStretch)
        guard currentTime - bonesLastLog > 0.5 else { return }
        bonesLastLog = currentTime
        // 캡처 크롭용 위치 (벽시계 타임스탬프): 씬 좌표 x, 지면 y, 씬 높이 — 스크린샷은 좌상단 원점
        print(String(
            format: "STICK[%.2f] %d %d %d %@",
            Date().timeIntervalSince1970, Int(px(stickX)), Int(groundY(stickX)), Int(size.height),
            String(describing: mode)
        ))
        let notable = bonesMax.hipDrop > 0.05 || bonesMax.clampLead > 0.05
            || bonesMax.clampTrail > 0.05 || bonesMax.legStretch > 0
        if notable {
            print(String(
                format: "BONES[%.2f] drop %.1f clampLead %.1f clampTrail %.1f legStretch %.1f mode %@",
                currentTime, bonesMax.hipDrop, bonesMax.clampLead, bonesMax.clampTrail, bonesMax.legStretch,
                String(describing: mode)
            ))
            fflush(stdout)
        }
        bonesMax = Skeleton.Joints()
    }

    /// 전환 점프 계측 (관찰용): 힙·발·그립의 화면 x가 한 프레임에 움직인 최대량을 0.5초 창으로 찍는다.
    /// 걷기 출발·도착의 '탁'은 여기서 수십 px/frame으로 드러난다 (정상 걷기 스윙발은 ≤ 6px/frame)
    private var jumpPrev: (hip: Double, f1: Double, f2: Double, grip: Double)?
    private var jumpMax = (hip: 0.0, f1: 0.0, f2: 0.0, grip: 0.0)
    private var jumpLastLog: TimeInterval = 0
    private var jumpModes = Set<String>()
    private func logJumps(_ rig: Rig, currentTime: TimeInterval) {
        let sx = Double(px(stickX))
        let cur = (
            hip: sx + Double(rig.hip.x) * dir, f1: sx + Double(rig.foot1.x) * dir,
            f2: sx + Double(rig.foot2.x) * dir, grip: sx + Double(rig.grip.x) * dir
        )
        jumpModes.insert(String(describing: mode))
        if let p = jumpPrev {
            jumpMax.hip = max(jumpMax.hip, abs(cur.hip - p.hip))
            // 두 발은 같은 획이라 정체 교환(정지 계획·방향 전환)은 보이지 않는다 — 짝짓기 중 작은 쪽을 잰다
            let direct = max(abs(cur.f1 - p.f1), abs(cur.f2 - p.f2))
            let swapped = max(abs(cur.f1 - p.f2), abs(cur.f2 - p.f1))
            let feet = min(direct, swapped)
            jumpMax.f1 = max(jumpMax.f1, feet)
            jumpMax.f2 = max(jumpMax.f2, feet)
            jumpMax.grip = max(jumpMax.grip, abs(cur.grip - p.grip))
        }
        jumpPrev = cur
        guard currentTime - jumpLastLog > 0.5 else { return }
        jumpLastLog = currentTime
        print(String(
            format: "MOVE[%.2f] hip %.1f f1 %.1f f2 %.1f grip %.1f %@",
            Date().timeIntervalSince1970, jumpMax.hip, jumpMax.f1, jumpMax.f2, jumpMax.grip,
            jumpModes.sorted().joined(separator: ">")
        ))
        jumpMax = (0, 0, 0, 0)
        jumpModes = []
    }

    /// 리그 전체 덤프 (60Hz, --demo-trademark): 오프라인 플롯으로 트레이드마크 연출을 프레임 단위로 검증한다.
    /// 좌표는 facing 로컬(px, 지면 0) — 렌더는 x·headDx·clubPhi에 dir을 곱한다
    private func logRigDump(_ r: Rig, joints j: Skeleton.Joints, currentTime: TimeInterval) {
        // 60Hz — 30Hz는 프레임 교번 진동(무릎 떨림 의심)을 에일리어싱으로 놓친다 (2026-09-23)
        guard currentTime - rigDumpLast >= 1.0 / 60 - 0.002 else { return }
        rigDumpLast = currentTime
        let pts: [CGPoint] = [
            r.hip,
            r.shoulder,
            r.foot1,
            r.foot2,
            r.knee1,
            r.knee2,
            r.grip,
            r.handTrail,
            j.elbowLead,
            j.elbowTrail,
        ]
        let xy = pts.map { String(format: "%.1f,%.1f", Double($0.x), Double($0.y)) }.joined(separator: " ")
        print(String(
            format: "RIG[%.3f] %@ %@ head %.1f,%.1f phi %.3f len %.1f butt %.1f curved %d dir %d",
            currentTime, String(describing: mode), xy, r.headDx, r.headDy, r.clubPhi, r.clubLen, r.butt,
            j.armsCurved ? 1 : 0, Int(dir)
        ))
        fflush(stdout)
    }

    private func logRigBounds(_ rig: Rig, currentTime: TimeInterval) {
        let sx = Double(px(stickX))
        func scr(_ x: Double) -> Double {
            sx + x * dir
        }
        var xs: [Double] = [scr(Double(rig.grip.x) + rig.clubLen * sin(rig.clubPhi))]
        for p in [rig.hip, rig.shoulder, rig.foot1, rig.foot2, rig.knee1, rig.knee2, rig.grip, rig.handTrail] {
            xs.append(scr(Double(p.x)))
        }
        let headX = scr(Double(rig.shoulder.x) + rig.headDx)
        xs.append(headX - 11)
        xs.append(headX + 11)
        let over = max(0 - xs.min()!, xs.max()! - Double(size.width))
        if over > 0.5 {
            boundsCount += 1
            boundsWorst = max(boundsWorst, over)
            if currentTime - boundsLastLog > 0.5 {
                boundsLastLog = currentTime
                print(String(
                    format: "OUTBOUND over %.1fpx (count %d, worst %.1f) mode %@",
                    over, boundsCount, boundsWorst, String(describing: mode)
                ))
                fflush(stdout)
            }
        }
    }

    /// 라이별 어드레스 자세 — 벙커는 발을 파묻는 와이드 스탠스·웅크림·초크다운, 러프는 살짝
    /// 웅크림 (2026-08-15 사용자 요청 2번). 타깃에만 적용 — 라이 전환은 기존 추적 스무딩이 처리
    private func applyLieStance(_ rig: inout Rig) {
        let lie = strokes == 0 ? Surface.tee : hole.surface(at: ball.x)
        switch lie {
        case .bunker:
            rig.foot1.x -= 3 // 와이드 스탠스
            rig.foot2.x += 3
            rig.foot1.y -= 1.5 // 모래에 파묻힌 발
            rig.foot2.y -= 1.5
            rig.knee1.y -= 2
            rig.knee2.y -= 2
            rig.hip.y -= 2.5 // 무릎을 굽혀 낮게
            rig.shoulder.y -= 2.5
            rig.clubLen *= 0.93 // 초크다운
        case .rough:
            rig.hip.y -= 1.2 // 풀을 누르며 살짝 웅크린다
            rig.shoulder.y -= 1.5
        default:
            break
        }
        // 나무 캐노피가 머리 위에 드리우면 웅크린다 (극복 자세)
        if renderTreeT > 0.001 {
            rig.hip.y -= 2.5 * renderTreeT
            rig.shoulder.y -= 3.5 * renderTreeT
        }
    }

    /// 경사 라이 스탠스 — 발·무릎이 실제 지면 높이를 정확히 딛고(zRotation 잔차 보정),
    /// 체중이 내리막 발로 흘러 오르막/내리막 라이가 실루엣으로 읽힌다 (2026-08-15 사용자 요청 3번).
    /// zRotation(경사×0.7)은 몸 전체 기울기만 담당 — 여기서 발 접지·체중 배분을 더한다.
    /// 벽 스탠스와는 상충(벽 클램프가 무회전 평면 가정)이라 renderWallT만큼 약해진다
    private func applySlopeStance(_ rig: inout Rig) {
        let strength = 1 - renderWallT
        guard strength > 0.001 else { return }
        let sinT = sin(renderSlopeTilt)
        /// 회전이 만든 발 높이와 실제 지형 높이의 잔차 — 벙커 턱·경사 꼭대기에서도 발이 뜨지 않는다
        func groundResidual(_ localX: Double) -> Double {
            let screenDx = localX * dir
            let xm = stickX + screenDx / Double(pxPerM)
            let delta = Double(groundY(xm) - groundY(stickX))
            return (delta - screenDx * sinT) * strength
        }
        let r1 = groundResidual(Double(rig.foot1.x))
        let r2 = groundResidual(Double(rig.foot2.x))
        rig.foot1.y += r1
        rig.foot2.y += r2
        rig.knee1.y += r1 * 0.55
        rig.knee2.y += r2 * 0.55
        // 체중 배분: 오르막 라이 = 뒷발(내리막 쪽), 내리막 라이 = 앞발 (실제 골프 셋업 관례)
        let slopeFacing = atan(hole.slope(at: stickX)) * dir // + = 타깃 쪽 오르막
        let shift = min(1, max(-1, slopeFacing / 0.18)) * strength
        rig.hip.x -= 5 * shift
        rig.shoulder.x -= 2.5 * shift
        rig.knee1.x -= 3 * shift
        rig.knee2.x -= 3 * shift
    }

    // ── 선수 트레이드마크 연출 (2026-09-15, docs/research-swing-styles.md §트레이드마크) ──
    // 키프레임 밖 연출: 정면 2D 키포인트가 못 잡는 특징이 진짜 구분점이라 스타일 분기를 여기에 둔다. 물리는 동일

    /// 타이거 트월 (굿샷 한정): 피니시 도달 뒤 0.1~0.45s 감긴 클럽을 앞으로 풀어 내려 리코일 자세,
    /// 0.45~0.9s 그립을 축으로 한 바퀴(오른손 엄지). 반환 회전은 타깃 clubPhi에 더해지며 렌더 추적이 최단 각도라 되감기 없음
    private func trademarkTwirl(ft: Double) -> (recoil: Pose, blend: Double, spin: Double)? {
        guard swingStyle.clubTwirl, lastShotGood, ft > 0.1 else { return nil } // 상한 없음 — 리코일 자세는 걷기 전까지 유지
        let base = lastFinishPose ?? profile.keys.p10
        let recoil = Pose(
            hipDx: base.hipDx, tilt: base.tilt + 4, handA: 32, handD: 27, clubA: 28, heel: base.heel,
            headDx: base.headDx + 2
        )
        let blend = smoothstep(min(1, max(0, (ft - 0.1) / 0.35)))
        let spin = 2 * Double.pi * smoothstep(min(1, max(0, (ft - 0.45) / 0.45)))
        if demoMode, ft >= 0.45, !twirlLogged { // 스윙당 한 번
            twirlLogged = true
            print(String(format: "TRADEMARK twirl ft %.2f", ft))
            fflush(stdout)
        }
        return (recoil, blend, spin)
    }

    /// 타이거 어퍼컷이 진행 중인가 — 이 동안 리그 추적을 16으로 (5는 펀치의 반도 못 따라간다)
    private var uppercutActive: Bool {
        mode == .holed && swingStyle.uppercut && (reactionKind == .rejoice || reactionKind == .fistPump)
    }

    /// 로리 임팩트 점프: 다운스윙 끝~팔로 초입에 지면 반력으로 몸 전체가 뜬다 (양발 이륙, 파워 비례). 무릎은 뼈대 IK가 따라온다
    private func applyImpactJump(_ rig: inout Rig, t: Double, prof: SwingProfile) {
        let h = swingStyle.impactJump
        guard h > 0, !prof.isPutter else { return }
        let u = (t - (prof.down - 0.03)) / 0.26
        guard u > 0, u < 1 else { return }
        let lift = h * sin(.pi * u) * max(0.4, heightPct)
        rig.hip.y += lift
        rig.shoulder.y += lift
        rig.foot1.y += lift
        rig.foot2.y += lift
        rig.knee1.y += lift
        rig.knee2.y += lift
        if demoMode, u >= 0.5, !jumpLogged { // 스윙당 한 번 (프레임 간격 0.064가 좁은 창을 건너뛴다)
            jumpLogged = true
            print(String(format: "TRADEMARK jump lift %.1f", lift))
            fflush(stdout)
        }
    }

    /// 로리 피니시 리코일: 피니시에 도달한 상체가 리드 다리 위로 탄력 있게 올라앉으며 잦아드는 반동 (감쇠 진동 0.8s).
    /// 렌더 추적(5)이 진동을 절반쯤 깎으므로 진폭은 그만큼 크게 준다
    private func applyFinishRecoil(_ rig: inout Rig, ft: Double) {
        guard swingStyle.finishRecoil, !club.isPutter, ft > 0, ft < 0.8 else { return }
        let osc = sin(2 * .pi * 1.4 * ft) * exp(-3.5 * ft)
        rig.shoulder.x += 6 * osc
        rig.hip.y += 1.5 * osc
        rig.headDx += 2 * osc
    }

    /// 홀아웃 스코어 반응 — 피니시 홀드 위에 얹는 짧은 감정 표현 (0.15~1.5s).
    /// 공이 컵에 들어가는 걸 '본 다음' 반응한다 (인과 — 드롭 연출 0.24s 이후 시작)
    private func applyScoreReaction(_ rig: inout Rig, t: Double) {
        guard t > 0.15, t < 1.5 else { return }
        let u = (t - 0.15) / 1.35
        let bell = smoothstep(min(1, min(u, 1 - u) / 0.25))
        switch reactionKind {
        case .rejoice where swingStyle.uppercut, .fistPump where swingStyle.uppercut:
            // 타이거 어퍼컷 (트레이드마크): 트레일 손이 클럽을 놓고 뒤·아래로 당겼다가(코킹 0.15s) 앞·위로 꽂히고(0.08s)
            // 몸이 타깃 쪽으로 실린다. 이글 이상은 두 번(코킹은 한 번). 리그 추적은 이 동안 16 (5는 펀치를 반도 못 따라간다)
            let n = reactionKind == .rejoice ? 2.0 : 1.0
            let c = (u * n).truncatingRemainder(dividingBy: 1) // u < 1이라 마지막 사이클도 1에 닿지 않는다
            let fade = smoothstep(min(1, (1 - u) / 0.15)) // 끝에는 손이 클럽으로, 몸도 같이 복귀 (리뷰: 몸만 0.2s 잔류)
            let cock = smoothstep(min(1, u * n / 0.22)) * fade
            let punch = fade * (c < 0.22 ? 0 : c < 0.34 ? smoothstep((c - 0.22) / 0.12) : c < 0.75 ? 1 : 1 -
                smoothstep((c - 0.75) / 0.25))
            let hx = mix(rig.shoulder.x - 7, rig.shoulder.x + 9, punch)
            let hy = mix(rig.shoulder.y - 12, rig.shoulder.y + 13, punch)
            rig.handTrail = CGPoint(x: mix(rig.handTrail.x, hx, cock), y: mix(rig.handTrail.y, hy, cock))
            rig.shoulder.x += 4 * punch
            rig.hip.y -= 2 * punch // 무릎을 굽히며
            rig.headDx += 3 * punch
            rig.headDy -= 1.5 * punch
            if demoTrademarkForce { // 계측: 어퍼컷 위상 (30Hz 덤프와 대조)
                print(String(format: "UPPER t %.2f u %.2f c %.2f cock %.2f punch %.2f n %.0f", t, u, c, cock, punch, n))
                fflush(stdout)
            }
        case .rejoice: // 홀인원·이글: 만세 + 두 번 폴짝
            let hop = abs(sin(2 * .pi * 2 * u)) * bell * 5
            rig.hip.y += hop
            rig.shoulder.y += hop + 2 * bell
            rig.handTrail.x = mix(rig.handTrail.x, rig.shoulder.x + 6, bell)
            rig.handTrail.y = mix(rig.handTrail.y, rig.shoulder.y + 18, bell)
            rig.headDy += 2 * bell
        case .fistPump: // 버디: 주먹 불끈
            rig.handTrail.x += 4 * bell
            rig.handTrail.y += 18 * bell
            rig.shoulder.y += 1.5 * bell
        case .nod: // 파: 만족의 끄덕
            rig.headDy -= 1.5 * abs(sin(2 * .pi * 1.5 * u)) * bell
        case .slump: // 보기 이상: 어깨가 살짝 처진다
            rig.shoulder.y -= 3 * bell
            rig.headDy -= 3 * bell
        case .dejected: // 기권: 고개 푹
            rig.shoulder.y -= 4 * bell
            rig.headDy -= 4.5 * bell
        case .startled: // 화들짝: 뒤로 움찔, 양팔·클럽 번쩍, 고개 뒤로 — 0.12s 스냅 후 서서히 풀린다
            let snap = min(1, u / 0.12) * (1 - smoothstep(min(1, max(0, (u - 0.45) / 0.55))))
            rig.hip.x -= 4 * snap
            rig.shoulder.x -= 6 * snap
            rig.shoulder.y += 2 * snap
            rig.handTrail = CGPoint(
                x: mix(rig.handTrail.x, rig.shoulder.x - 6, snap),
                y: mix(rig.handTrail.y, rig.shoulder.y + 16, snap)
            )
            rig.grip = CGPoint(
                x: mix(rig.grip.x, rig.shoulder.x + 9, snap),
                y: mix(rig.grip.y, rig.shoulder.y + 14, snap)
            )
            rig.headDx -= 4 * snap
            rig.headDy += 1.5 * snap
        case .shoo: // 훠이훠이: 트레일 팔을 앞으로 뻗어 흔든다
            let wave = sin(2 * .pi * 3 * u)
            rig.handTrail = CGPoint(
                x: mix(rig.handTrail.x, rig.shoulder.x + 15 + 3 * wave, bell),
                y: mix(rig.handTrail.y, rig.shoulder.y + 5 + 8 * abs(wave), bell)
            )
            rig.headDx += 2 * bell
        case .laugh: // 낄낄: 어깨 들썩 + 고개 뒤로
            let shake = abs(sin(2 * .pi * 4 * u)) * bell
            rig.shoulder.y += 2.5 * shake
            rig.headDx -= 3 * bell
            rig.headDy += 2 * bell
        case .none:
            break
        }
    }

    /// 조준 방치 잔동작: 상시 미세 호흡 + 5~9초마다 두리번·클럽 툭툭·발끝 까딱 중 하나.
    /// 오버레이 게임의 '곁눈질' 순간에도 스틱맨이 살아 있게 (QA·Whimsy 리뷰)
    private func applyIdleFidget(_ rig: inout Rig) {
        rig.shoulder.y += 0.6 * sin(2 * .pi * 0.25 * aimTime) // 호흡
        if idleKind == 0, aimTime > idleNextAt {
            idleKind = Int.random(in: 1 ... 4)
            idleStart = aimTime
        }
        guard idleKind > 0 else { return }
        let u = (aimTime - idleStart) / 1.6
        if u >= 1 {
            idleKind = 0
            idleNextAt = aimTime + Double.random(in: 5 ... 9)
            return
        }
        let bell = smoothstep(min(1, min(u, 1 - u) / 0.3))
        switch idleKind {
        case 1: rig.headDx += 4 * bell // 홀 쪽 응시
        case 2: // 두리번
            rig.headDx -= 3 * bell
            rig.headDy += bell
        case 3: // 클럽 헤드 툭툭 — 그립 들썩 + 샤프트 까딱
            rig.grip.y += 1.5 * abs(sin(3 * .pi * u)) * bell
            rig.clubPhi += 0.06 * sin(3 * .pi * u) * bell
        default: // 앞발 토탭
            rig.foot2.y += 1.2 * abs(sin(2 * .pi * u)) * bell
        }
    }

    /// 벽 스탠스 자세 보정 — 뒷발을 벽에 올리고(가까울수록 높이), 체중은 앞발로,
    /// 그립은 초크다운. t: 벽 근접도 0~1 (renderWallT로 스무딩되어 들어온다)
    private func applyWallStance(_ rig: inout Rig, t: Double) {
        guard t > 0.001 else { return }
        let wallX = -wallBehindPx // 로컬(공 원점, facing 기준) 벽 위치
        rig.foot1 = CGPoint(
            x: mix(rig.foot1.x, wallX + 1.5, t),
            y: mix(rig.foot1.y, 7 + 9 * t, t)
        )
        rig.knee1 = CGPoint(
            x: (rig.hip.x + rig.foot1.x) / 2 + 2,
            y: (rig.hip.y + rig.foot1.y) / 2 + 4
        )
        rig.hip.x += 4 * t // 체중 앞발 (펀치 자세 — 리서치: 체중 65% 앞발)
        rig.shoulder.x += 3 * t
        rig.clubLen *= 1 - 0.10 * t // 초크다운
    }

    /// 걷기 도착 자리와 조준 방향 — 공 위치·도착 클럽 스탠스에서. startWalk와 걷는 도중 재계획(공이 옮겨졌을 때)이 공유
    /// (도착 클럽은 enterAim의 자동 퍼터 전환과 같은 조건으로 미리 안다 — 도착 자리를 그 스탠스로)
    private func walkTarget() -> (to: Double, dir: Double) {
        let arrivalDir: Double = hole.holeX >= ball.x ? 1 : -1
        let willPutt = (strokes > 0 || demoPickupForce) && hole.surface(at: ball.x) == .green
        let arrivalFwd = willPutt ? SwingProfile.profile(for: .putter, style: swingStyle).ballFwd : profile
            .ballFwd // 스타일별 퍼터 스탠스
        return (ball.x - arrivalDir * (arrivalFwd + 5) / Double(pxPerM), arrivalDir)
    }

    /// fromBody: 걷기 도착 자리(몸 원점)에서 다시 출발 — 걷는 동안 공이 옮겨져 도착해 보니 공이 없을 때 (2026-09-23 재계획)
    func startWalk(fromBody: Bool = false) {
        endShotTrail()
        // 원점 통일 (2026-09-14 전환 개편): 포즈 리그는 공이 원점이고 몸(힙)은 공 뒤 ballFwd+5px에 선다.
        // 걷기 리그는 몸이 원점이므로, 걷기의 출발·도착을 '몸이 서는 자리'로 잡아야 전환 순간 좌표 점프가 0이다
        // (구: 출발 stickX·도착 ball.x → 출발 때 몸이 25px 앞으로 튀고, 도착 때 25px 뒤로 미끄러졌다).
        let from = fromBody ? stickX : stickX - dir * (renderBallFwd + 5) / Double(pxPerM)
        let (to, arrivalDir) = walkTarget()
        let dist = abs(to - from)
        mode = .walking
        let newDir: Double = to >= from ? 1 : -1
        let reversing = dist > 0.5 && newDir != dir // 아주 짧은 이동은 방향 유지 (제자리 반걸음)
        // 완전 여유로운 걸음 — 실제 골퍼처럼 서두르지 않는다.
        // 험한 길(경사·러프·벙커)은 더 오래 걸린다 (지형 적응 — 2026-08-15 사용자 요청)
        var hardness = 0.0
        if dist > 1 {
            let n = 12
            for k in 0 ... n {
                let xm = from + (to - from) * Double(k) / Double(n)
                let s = hole.surface(at: xm)
                hardness += min(1, abs(hole.slope(at: xm)) / 0.3) * 0.5
                    + (s == .rough || s == .bunker ? 0.5 : 0)
            }
            hardness /= Double(n + 1)
        }
        // 무드 워크: 들뜬 걸음은 조금 빠르고, 처진 걸음은 터덜터덜 (거리 무관 배율)
        let mood = demoMood ?? (walkMoodLeft > 0 ? walkMood : .neutral)
        if walkMoodLeft > 0 {
            walkMoodLeft -= 1
        }
        let moodSpeed = mood == .elated ? 0.85 : mood == .sad ? 1.45 : 1.0
        let dur = min(14.0, max(1.2, dist / 10 * (1 + 0.4 * hardness) * moodSpeed))
        var anim = WalkAnim(
            fromX: from, toX: to, dur: dur,
            // 한두 걸음에 제속도 → 등속 → 마지막 한두 걸음에 정지 (구 전구간 포물선은 "느릿하다 가속")
            profile: WalkProfile(dist: dist, dur: dur)
        )
        if reversing { // 제자리 돌기: 피니시 애니가 끝나는 0.55s 뒤 0.65s 턴 + 정착 — 반전은 턴 중간에 (setFacing은 update에서)
            // (0.3s 시작은 스윙 피니시 타깃이 아직 리그를 쥐고 있어 예고·1걸음이 잘렸다 — 2026-09-23 RIG 덤프)
            let start = fromBody ? 0.1 : 0.55 // 몸 원점 재출발은 피니시가 없다
            anim.turn = WalkAnim.TurnPlan(start: start, dur: 0.65, newDir: newDir, atBody: fromBody)
            anim.relax = start + 0.65 + 0.15
        } else if fromBody {
            anim.relax = 0.25 // 재출발: 잠깐 멈칫만
        }
        if fromBody {
            anim.relaxShift = renderBallFwd + 5 // 여운(직립) 포즈를 몸 원점에 (공 원점 포즈는 −(ballFwd+5)에 선다)
        }
        anim.mood = mood
        if demoMode, mood != .neutral {
            print("MOOD \(mood.rawValue) dur \(String(format: "%.1f", dur))")
            fflush(stdout)
        }
        // 아주 가끔 넘어진다 (재미): 기본 1%, 험한 길 2% — 라운드에 한 번 볼까 말까
        // (초기 3~6%는 실플레이에서 "너무 자주"로 판정 — 2026-08-15)
        if anim.dur > 5.0,
           demoTripForce || Double.random(in: 0 ..< 1) < 0.01 + 0.01 * min(1, hardness * 2) {
            anim.tripAt = anim.relax + Double.random(in: 1.0 ... (anim.dur - 3.5))
        }
        // 쇼피스 밈 모션 (2026-08-20): 걷기가 넉넉할 때 8% — 트립과 겹치지 않게 (개그 과밀 방지)
        if anim.tripAt == nil, anim.dur > 6.0,
           demoShowpieceForce || Double.random(in: 0 ..< 1) < 0.08 {
            let kind = demoShowpieceForce
                ? ShowpieceKind.allCases[showpieceCursor % ShowpieceKind.allCases.count]
                : ShowpieceKind.allCases.randomElement()!
            if demoShowpieceForce {
                showpieceCursor += 1
            }
            let latest = anim.relax + anim.dur - kind.duration - 1.2
            if latest > anim.relax + 1.2 {
                anim.showKind = kind
                anim.showAt = anim.relax + Double.random(in: 1.2 ... latest)
            }
        }
        // 랜덤 잉여 동작: 긴 이동은 어깨 캐리 + 37종 모션을 겹치지 않게 흩뿌린다 (무드 관찰 --demo-mood에서는 끈다 — 계측 오염)
        if demoMood == nil, anim.dur > 4.5, Double.random(in: 0 ..< 1) < 0.5 {
            anim.shoulderRange = (anim.relax + 0.8) ... (anim.relax + anim.dur * 0.72)
        }
        var t = anim.relax + 0.7
        while demoMood == nil, t < anim.relax + anim.dur - 1.2, anim.flavorEvents.count < 5 {
            guard Double.random(in: 0 ..< 1) < 0.5 else {
                t += 1.1
                continue
            }
            let kind = WalkFlavorKind.weightedRandom() // 멈추는 모션은 드물게
            let dur = kind.duration
            // 어깨에 클럽을 걸친 동안엔 클럽 손짓 불가 (클럽이 손에 없다)
            if kind.needsClub, let r = anim.shoulderRange, r.overlaps(t ... (t + dur)) {
                t += 1.0
                continue
            }
            // 넘어지는 동안엔 다른 모션 금지 (트월하며 넘어지면 코미디가 아니라 버그로 보인다)
            if let tr = anim.tripAt, ((tr - 0.3) ... (tr + 2.9)).overlaps(t ... (t + dur)) {
                t = tr + 3.0
                continue
            }
            // 쇼피스 무대는 비워둔다 — 잔동작이 겹치면 큰 동작이 묻힌다
            if let sa = anim.showAt, let sk = anim.showKind,
               ((sa - 0.4) ... (sa + sk.duration + 0.5)).overlaps(t ... (t + dur)) {
                t = sa + sk.duration + 0.6
                continue
            }
            anim.flavorEvents.append(WalkFlavorEvent(kind: kind, t0: t, dur: dur))
            t += dur + Double.random(in: 0.8 ... 2.2)
        }
        if demoMotionShowcase { // 카탈로그 캡처: 랜덤 대신 37종을 커서 순서로, 트립·어깨 캐리 없이
            anim.flavorEvents = []
            anim.shoulderRange = nil
            anim.tripAt = nil
            anim.showAt = nil // 쇼피스가 카탈로그 위에 겹치면 캡처가 오염된다 (리뷰)
            anim.showKind = nil
            var st = anim.relax + 0.8
            while st < anim.relax + anim.dur - 1.5, motionCursor < WalkFlavorKind.allCases.count {
                let kind = WalkFlavorKind.allCases[motionCursor]
                anim.flavorEvents.append(WalkFlavorEvent(kind: kind, t0: st, dur: kind.duration))
                motionCursor += 1
                st += kind.duration + 1.3
            }
            if motionCursor >= WalkFlavorKind.allCases.count, anim.flavorEvents.isEmpty {
                print("MOTIONS DONE")
                fflush(stdout)
            }
        }
        if demoMode, !anim.flavorEvents.isEmpty || anim.tripAt != nil { // 캡처 대조용 계측 (관찰용)
            let list = anim.flavorEvents
                .map { "\($0.kind)@\(String(format: "%.1f", $0.t0))" }
                .joined(separator: " ")
            let trip = anim.tripAt.map { String(format: " TRIP@%.1f", $0) } ?? ""
            let show = anim.showAt.map { String(format: " SHOW:%@@%.1f", anim.showKind!.rawValue, $0) } ?? ""
            print(String(format: "FLAVOR[%.2f] ", Date().timeIntervalSince1970) + list + trip + show)
            fflush(stdout)
        }
        anim.arrivalDir = arrivalDir
        walkAnim = anim
        updateHUD()
    }

    private func startSwing() {
        mode = .swinging
        jumpLogged = false
        twirlLogged = false
        swingAnim = SwingAnim(
            prof: profile,
            fromPose: backswingPose(heightPct: heightPct, profile: profile, topScale: wallTopScale)
        )
        if !club.isPutter {
            SoundKit.shared.whoosh(power: heightPct, dur: profile.down + 0.05)
        }
    }

    private func launchBall() {
        let lie = strokes == 0 ? Surface.tee : hole.surface(at: ball.x)
        lastShotLie = lie
        // 풀파워 리스크: 모든 샷에 베이스 분산(±1°) + 80% 초과분^1.6의 리스크, 정규분포 근사
        // (uniform 3개 평균 ≈ 가우시안 — 큰 미스는 드물고 작은 흔들림이 대부분, 리서치 E)
        let overdrive = max(0, (heightPct - 0.8) / 0.2)
        let risk = 0.25 + 0.75 * pow(overdrive, 1.6)
        let gauss = (Double.random(in: -1 ... 1) + Double.random(in: -1 ... 1) + Double.random(in: -1 ... 1)) / 3
        let mishit = club.isPutter ? 0 : risk * gauss
        // 굿샷 판정 (타이거 트월): 실제처럼 공이 뜨자마자 스트라이크 품질로 — 미스힛 작고 반 이상 파워. 퍼터 제외
        // 파워 문턱 0.45 → 0.3: 트월이 세컨샷·어프로치에서도 나오게 (2026-09-23 플레이 판정 "차이가 많이 나 보이지 않음")
        lastShotGood = !club.isPutter && (demoTrademarkForce || (heightPct >= 0.3 && abs(mishit) < 0.12))
        // 벽·나무 근접 = 펀치샷: 파워는 그대로, 낮은 탄도·적은 스핀으로 (컴팩트 폼의 물리적 귀결)
        // 경사 라이는 스탠스 기울기와 같은 비율(0.7)만 로프트로 전달 — 물리·애니메이션 정합
        let slope = club.isPutter ? 0 : hole.slope(at: ball.x) * slopeTiltRatio
        settleRoll = nil // 직전 정착 굴림이 남아 있으면 발사 순간 공이 뒤로 보인다
        Ballistics.launch(
            &ball, club: club, heightPct: heightPct, lie: lie, dir: dir,
            mishit: mishit, punch: max(wallPunch, treePunchT * 0.85), slope: slope,
            kind: ballKind // 공 바꿔치기 (Surprises2)
        )
        shotHitBumper = false
        shotLipped = false
        // 창 범퍼 모드: 샷 순간의 창 배치를 스냅샷 — 이 샷의 비행 동안 고정 범퍼
        if Theme.windowBumpers, let screen = view?.window?.screen {
            shotBumpers = WindowBumpers.snapshot(
                screen: screen, pxPerM: Double(pxPerM), groundBase: Double(groundBase)
            )
            if demoMode, !shotBumpers.isEmpty { // 좌표 대조용 계측 (관찰용, 미터)
                let list = shotBumpers
                    .map { String(format: "(%.0f,%.0f %.0fx%.0f)", $0.x, $0.y, $0.w, $0.h) }
                    .joined(separator: " ")
                print("BUMPERS \(shotBumpers.count) \(list)")
                fflush(stdout)
            }
        } else {
            shotBumpers = []
        }
        if demoMode, !demoBumperFracs.isEmpty { // --demo-bumpers: 합성 범퍼 (창 터널 관찰용, 실플레이 경로 아님)
            shotBumpers = syntheticBumpers()
            drawSyntheticBumpers()
        }
        preShot = (x: ball.x, strokes: strokes, remain: abs(hole.holeX - ball.x)) // 멀리건·갤러리 스냅샷
        strokes += 1
        PlayLog.note(String(
            format: "SHOT %d %@ h%.2f from %.1f lie %@",
            strokes,
            club.id,
            heightPct,
            preShot.x,
            "\(lie)"
        ))
        if !club.isPutter { // 임팩트 타격감: 공 신장 + 헤드 스미어 (퍼터는 조용히)
            // 히트스톱은 실플레이에서 '렉'으로 읽혀 제거 (2026-08-14 사용자 판정 —
            // 골프처럼 한 번의 연속 동작에선 정지가 타격감이 아니라 프레임 드랍으로 보인다)
            ballNode.zRotation = CGFloat(atan2(ball.vy, ball.vx))
            let ks = ballKind.renderScale // 바꿔치기된 공(볼링 1.75·고무 1.15)의 크기를 스쿼시가 1로 덮지 않게 (리뷰 m2)
            ballNode.xScale = 1.4 * ks
            ballNode.yScale = 0.72 * ks
            ballNode.run(.sequence([
                .group([.scaleX(to: ks, duration: 0.14), .scaleY(to: ks, duration: 0.14)]),
                .run { [weak self] in self?.ballNode.zRotation = 0 },
            ]))
            stickman.impactSmear()
        }
        trailPoints = []
        for t in [trailNode, trailUnderNode] {
            t.removeAllActions()
            t.alpha = 1
        }
        mode = .motion
        if demoTurnForce, strokes == 1 { // 제자리 돌기 관찰: 공이 뒤로 떨어졌다
            let x = min(max(stickX - dir * 22, 2), hole.worldW - 2)
            ball = BallState(x: x, y: hole.ground(at: x))
            ball.phase = .roll
        }
        if demoSettleForce, strokes == 1, let x = demoSteepRimSpot() { // 정착 굴림 관찰: 마찰로 설 수 있는 급경사에 '떨어진' 공
            ball = BallState(x: x, y: hole.ground(at: x))
            ball.phase = .roll // 다음 스텝에 정지 판정 → settleOffSteepSlope → SETTLE 로그·굴림
        }
        SoundKit.shared.impact(cat: club.cat, lie: lie, power: heightPct)
        if !club.isPutter, heightPct >= 0.4, let kind = rollSurprise(hook: .inFlight) { // 돌풍 (비행 훅)
            playSurprise(kind)
        }
        if lie == .rough || lie == .bunker { // 러프 풀잎·벙커 모래가 튄다
            FX.dust(
                on: self,
                at: CGPoint(x: px(ball.x), y: groundY(ball.x)),
                surface: lie,
                intensity: 0.4 + 0.6 * heightPct
            )
        }
        updateHUD()
    }

    /// 샷이 끝나면 궤적은 잠시 여운을 남기고 사라진다
    func endShotTrail() {
        guard !trailPoints.isEmpty else { return }
        trailUnderNode.removeAllActions()
        trailUnderNode.run(.fadeAlpha(to: 0, duration: 1.1))
        trailNode.removeAllActions()
        trailNode.run(.sequence([
            .fadeAlpha(to: 0, duration: 1.1),
            .run { [weak self] in
                guard let self else { return }
                trailPoints.removeAll()
                // 알파 복원 전에 경로부터 비운다 — 액션 블록은 update 이후에 돌아서,
                // 경로가 남은 채 알파만 1이 되면 그 프레임에 궤적이 번쩍 나타난다 (사용자 재현)
                trailNode.path = nil
                trailUnderNode.path = nil
                trailNode.alpha = 1
                trailUnderNode.alpha = 1
            },
        ]))
    }

    /// ── 홀 이벤트 ──
    private func onHoled() {
        PlayLog.note("HOLED strokes \(strokes)")
        mode = .holed
        results.append((hole.par, strokes, false))
        endShotTrail()
        SoundKit.shared.holeIn()
        dropBallIntoCup()
        // 스코어 감정 계층 (QA·Whimsy 리뷰): 좋은 결과일수록 토스트가 크고, 스틱맨이 반응한다
        let diff = strokes == 1 ? -3 : strokes - hole.par // 홀인원은 최상급 취급
        reactionKind = diff <= -2 ? .rejoice : diff == -1 ? .fistPump : diff == 0 ? .nod : .slump
        walkMood = diff <= -1 ? .elated : diff >= 2 ? .sad : .neutral // 다음 홀의 첫 두 걷기까지 감정이 남는다 (무드 워크)
        walkMoodLeft = walkMood == .neutral ? 0 : 2
        birdieStreak = diff <= -1 ? birdieStreak + 1 : 0 // 연속 버디 이상 (QA P1 재미 3)
        setbackStreak = 0
        reactionAt = lastTime
        if diff <= -2 { // 이글·홀인원: 홀인음 뒤에 상승 차임이 얹힌다
            run(.sequence([.wait(forDuration: 0.35), .run { SoundKit.shared.chime() }]))
        }
        if demoMode {
            print("HOLED diff \(diff)")
            fflush(stdout)
            if let t = demoRestartAfterHoled, !demoRestartedAfterHoled { // 홀 전환 타이머 위에 R을 얹는다 (관찰)
                demoRestartedAfterHoled = true
                let n = SKNode()
                addChild(n)
                n.run(.sequence([.wait(forDuration: t), .run { [weak self] in
                    print("DEMO-R")
                    fflush(stdout)
                    self?.newRound()
                }, .removeFromParent()]))
            }
        }
        toast(
            scoreName(strokes: strokes, par: hole.par),
            sub: "\(strokes)타 · 파 \(hole.par) · \(Int(hole.dist))m" +
                (birdieStreak >= 2 ? " · 버디 스트릭 ×\(birdieStreak)" : ""),
            overFlag: true,
            titleScale: diff <= -2 ? 1.3 : diff == -1 ? 1.12 : diff <= 0 ? 1.0 : 0.88
        )
        recordHoleOut(diff: diff)
        // 컵 근처(퍼팅·짧은 어프로치 홀인)면 스코어 리액션 후 공 줍기 의식 — 멀면 기존 흐름
        // 미터 기준 (픽셀은 홀 전장에 따라 스케일이 달라 긴 홀에서 오판 — 2026-08-29 실측)
        let nearCup = abs(stickX - hole.holeX) < 9 || demoPickupForce
        if nearCup {
            afterHoleFlow(1.3) { [weak self] in self?.startRitual(.ballPickup) }
        } else {
            afterHoleFlow(1.7) { [weak self] in self?.advanceHole() }
        }
    }

    // ── 기록·배지 (2026-08-21 재미 확장 2번) ──

    /// 새 배지는 홀 토스트가 걷힌 뒤에 알린다 (연출 겹침 방지)
    private func announceBadges(_ earned: [Badge]) {
        guard !earned.isEmpty else { return }
        let names = earned.map(\.title).joined(separator: " · ")
        run(.sequence([.wait(forDuration: 2.2), .run { [weak self] in
            guard let self else { return }
            toast("배지 획득", sub: names, titleScale: 1.1)
            SoundKit.shared.chime()
            let hats = Records.shared.unlockedHats
            if let newest = hats.last, newest != .none, Records.shared.hat == .none {
                // 첫 해금은 자동 착용 — 메뉴를 몰라도 보상이 눈에 보인다
                Records.shared.hat = newest
                Records.shared.save()
                stickman.setHat(newest)
            }
        }]))
    }

    private func recordHoleOut(diff: Int) {
        guard !demoMode else { return } // 기록은 실플레이 전용
        var r = Records.shared
        var earned: [Badge] = []
        r.holesPlayed += 1
        r.totalStrokes += strokes
        if strokes == 1 {
            r.holeInOnes += 1
            if r.award(.holeInOne) {
                earned.append(.holeInOne)
            }
        }
        if diff <= -2 {
            r.eagles += 1
            if r.award(.firstEagle) {
                earned.append(.firstEagle)
            }
        } else if diff == -1 {
            r.birdies += 1
            if r.award(.firstBirdie) {
                earned.append(.firstBirdie)
            }
        }
        if diff <= 0, let sig = hole.signature {
            if sig == .canyon, r.award(.canyonTamer) {
                earned.append(.canyonTamer)
            }
            if sig == .summitGreen, r.award(.summiteer) {
                earned.append(.summiteer)
            }
        }
        if shotHitBumper, r.award(.bumperBank) {
            earned.append(.bumperBank)
        }
        if r.holesPlayed >= 100, r.award(.century) {
            earned.append(.century)
        }
        Records.shared = r
        r.save()
        announceBadges(earned)
    }

    private func recordRoundEnd(total: Int) {
        guard !demoMode else { return } // 기록은 실플레이 전용
        var r = Records.shared
        var earned: [Badge] = []
        r.roundsCompleted += 1
        if r.bestRound.map({ total < $0 }) ?? true {
            r.bestRound = total
        }
        if r.award(.firstRound) {
            earned.append(.firstRound)
        }
        if total < 0, r.award(.underPar) {
            earned.append(.underPar)
        }
        if !roundHadWater, !results.contains(where: \.gaveUp), r.award(.dryRound) {
            earned.append(.dryRound)
        }
        if r.roundsCompleted >= 10, r.award(.marathoner) {
            earned.append(.marathoner)
        }
        Records.shared = r
        r.save()
        announceBadges(earned)
    }

    /// 모자 착용 (메뉴 선택·해금 자동 착용 공용)
    func applyHat(_ hat: Hat) {
        stickman.setHat(hat)
    }

    /// 메뉴 → 기록: 조용한 계기판 스타일 텍스트 카드
    func showRecordsCard() {
        let r = Records.shared
        scorecard.hide()
        toastTitle.removeAllActions()
        toastSub.removeAllActions()
        toastTitle.position = CGPoint(x: size.width / 2, y: size.height * 0.72)
        toastSub.position = CGPoint(x: size.width / 2, y: size.height * 0.72 - 46)
        toastTitle.setScale(1.1)
        toastTitle.setText("기록")
        toastSub.setText(r.summaryLines.joined(separator: "\n"))
        for node in [toastTitle, toastSub] as [SKNode] {
            node.run(.sequence([.fadeIn(withDuration: 0.18), .wait(forDuration: 6), .fadeOut(withDuration: 0.6)]))
        }
    }

    /// 공이 컵 속으로 굴러떨어지는 연출 — 렌더 루프는 .holed 동안 공 위치를 덮지 않는다
    private func dropBallIntoCup() {
        let cup = CGPoint(x: px(hole.holeX), y: groundY(hole.holeX))
        shadowNode.isHidden = true
        ballNode.removeAllActions()
        let slide = SKAction.move(to: CGPoint(x: cup.x, y: cup.y + 4), duration: 0.1)
        let sink = SKAction.move(to: CGPoint(x: cup.x, y: cup.y - 6), duration: 0.14)
        sink.timingMode = .easeIn
        ballNode.run(.sequence([
            slide,
            .group([sink, .scale(to: 0.72, duration: 0.14)]),
            .fadeOut(withDuration: 0.1), // 컵 안 어둠 속으로
        ]))
        // 공이 바닥에 닿은 뒤에야 점이 튀고 깃발이 흔들린다
        run(.sequence([.wait(forDuration: 0.24), .run { [weak self] in
            guard let self else { return }
            FX.holePop(on: self, at: cup)
            FX.flagWave(flagNode)
        }]))
    }

    private func onWater() {
        strokes += 1
        PlayLog.note("WATER strokes \(strokes)")
        walkMood = .sad // 드롭까지 터덜터덜
        walkMoodLeft = 1
        roundHadWater = true
        if !demoMode {
            Records.shared.waterBalls += 1
            Records.shared.save()
        }
        endShotTrail()
        SoundKit.shared.splash()
        FX.ripple(on: self, at: CGPoint(x: px(ball.x), y: groundY(ball.x)))
        let wr = hole.waterRange ?? (ball.x - 3) ... (ball.x + 3)
        let dropX = dir > 0 ? wr.lowerBound - 2.5 : wr.upperBound + 2.5
        ball = BallState(x: dropX, y: hole.ground(at: dropX))
        toast("워터 해저드", sub: "+1 벌타 · 드롭")
        if strokes >= Phys.maxStrokes {
            giveUp()
        } else if noteSetback(true) {
            playFrustration(reason: nil) // 워터 토스트는 그대로 두고 고개만 푹
        } else {
            startWalk()
        }
    }

    /// 좌절 계열(워터·벙커·립아웃) 연속 카운트 — 2회째면 true(좌절 반응 차례)이고 카운트는 리셋된다.
    /// 홀인·정상 정지는 카운트를 0으로 (QA P1 재미 3, 2026-08-15 Whimsy 리뷰)
    func noteSetback(_ hit: Bool) -> Bool {
        guard hit else {
            setbackStreak = 0
            return false
        }
        setbackStreak += 1
        guard setbackStreak >= 2 else { return false }
        setbackStreak = 0
        return true
    }

    /// 파4 원온·파5 투온만 — 원래 어려운 것이라 값이 있다 (파3 원온은 당연해서 제외, 2026-09-17 사용자 결정)
    func greenChanceLabel() -> String? {
        guard hole.surface(at: ball.x) == .green, hole.par >= 4 else { return nil }
        if demoGIRForce {
            return hole.par == 4 ? "원온!" : "투온!"
        }
        if hole.par == 4, strokes == 1 {
            return "원온!"
        }
        if hole.par == 5, strokes == 2 {
            return "투온!"
        }
        return nil
    }

    /// 온그린 연출: 씬을 1.8s 점유 — 만세·폴짝(rejoice) + 차임·환호 + 공 주위 고리와 반짝임, 그 뒤 걷기
    func playGreenCelebration(_ label: String) {
        mode = .surprise
        react(.rejoice)
        SoundKit.shared.chime()
        walkMood = .elated // 그린까지 들뜬 걸음
        walkMoodLeft = 1
        afterSurprise(0.2) { SoundKit.shared.cheer() }
        toast(label, sub: "이글 찬스", titleScale: 1.3)
        let at = CGPoint(x: px(ball.x), y: groundY(ball.x) + 5.5)
        for i in 0 ..< 3 {
            afterSurprise(Double(i) * 0.22) { [weak self] in
                guard let self else { return }
                FX.holePop(on: self, at: at)
                let ring = SKShapeNode(circleOfRadius: 8)
                ring.strokeColor = NSColor(white: 1, alpha: 0.85)
                ring.lineWidth = 1.4
                ring.fillColor = .clear
                ring.position = at
                ring.setScale(0.4)
                ring.zPosition = 7
                ring.name = Self.surpriseNodeName
                addChild(ring)
                ring.run(.sequence([
                    .group([.scale(to: 2.6, duration: 0.7), .fadeOut(withDuration: 0.7)]),
                    .removeFromParent(),
                ]))
            }
        }
        afterSurprise(1.8) { [weak self] in self?.finishSurprise() }
        if demoMode {
            print("GIR \(label) par \(hole.par) strokes \(strokes)")
            fflush(stdout)
        }
    }

    /// 좌절: 씬을 1.6s 점유하고 한숨과 함께 고개를 푹 떨군다(dejected 재활용) — 그 뒤 걷기
    func playFrustration(reason: String?) {
        mode = .surprise
        react(.dejected)
        SoundKit.shared.sigh()
        walkMood = .sad
        walkMoodLeft = 1
        if let reason {
            toast("휴…", sub: reason)
        }
        afterSurprise(1.6) { [weak self] in self?.finishSurprise() }
        if demoMode {
            print("FRUSTRATION \(reason ?? "water")")
            fflush(stdout)
        }
    }

    private func giveUp() {
        mode = .holed
        results.append((hole.par, Phys.maxStrokes, true))
        endShotTrail()
        reactionKind = .dejected
        reactionAt = lastTime
        walkMood = .sad
        walkMoodLeft = 2
        toast("기권", sub: "\(Phys.maxStrokes)타 초과", titleScale: 0.88)
        afterHoleFlow(1.4) { [weak self] in self?.advanceHole() }
    }

    private func advanceHole() {
        if holeIdx < 8 {
            holeIdx += 1
            startHole()
        } else {
            mode = .end
            let total = results.reduce(0) { $0 + ($1.strokes - $1.par) }
            let totalStr = total > 0 ? "+\(total)" : total == 0 ? "이븐 파" : "\(total)"
            let footer = results.contains(where: \.gaveUp)
                ? "합계 \(totalStr) · 흐린 숫자 = 기권  —  R로 새 라운드"
                : "합계 \(totalStr)  —  R로 새 라운드"
            scorecard.show(results: results, title: "라운드 종료", footer: footer)
            SoundKit.shared.chime()
            recordRoundEnd(total: total)
        }
    }

    /// 토스트 — 기본은 화면 중앙, overFlag는 깃발 위 (홀인 스코어는 사건 지점에서 읽힌다 —
    /// 2026-08-15 사용자 요청 3번). 깃발이 화면 끝이면 잘리지 않게 안쪽으로 당긴다
    func toast(
        _ main: String, sub: String? = nil, overFlag: Bool = false, titleScale: CGFloat = 1
    ) {
        if overFlag {
            let x = min(size.width - 150, max(150, px(hole.holeX)))
            let baseY = groundY(hole.holeX) + 62 // 깃대 끝
            toastTitle.position = CGPoint(x: x, y: baseY + 64)
            toastSub.position = CGPoint(x: x, y: baseY + 26)
        } else {
            toastTitle.position = CGPoint(x: size.width / 2, y: size.height * 0.64)
            toastSub.position = CGPoint(x: size.width / 2, y: size.height * 0.64 - 42)
        }
        toastTitle.setScale(titleScale) // 스코어 무게 = 크기 (이글 1.3 ~ 보기 0.88)
        toastTitle.setText(main)
        toastSub.setText(sub ?? "")
        for node in [toastTitle, toastSub] as [SKNode] {
            node.removeAllActions()
            node.run(.sequence([.fadeIn(withDuration: 0.18), .wait(forDuration: 1.4), .fadeOut(withDuration: 0.45)]))
        }
    }

    /// ── 일시정지 ──
    func setGamePaused(_ paused: Bool) {
        isGamePaused = paused
        pauseLabel.isHidden = !paused
        if paused {
            heldKeys.removeAll()
            pausedAt = Date()
        } else if let t = pausedAt { // 포커스 복귀 인사: 오래 비웠다 돌아오면 손을 흔든다 (QA P1 재미 3). 조준 중에만 — 반응이 그려지는 모드
            pausedAt = nil
            let away = Date().timeIntervalSince(t)
            if mode == .aim, away >= (demoGreetForce ? 0 : 300) {
                react(.shoo)
                toast("어서 와", sub: nil)
                if demoMode {
                    print(String(format: "GREET away %.0fs", away))
                    fflush(stdout)
                }
            }
        }
    }

    /// 포커스 상실 시 홀드만 해제 — 게임은 계속 흐른다 (일시정지는 ⛳️ 수동 토글만)
    func releaseHeldInput() {
        heldKeys.removeAll()
    }

    /// ── 지형: 균일한 헤어라인 + 라이별 미세 질감 ──
    private func rebuildTerrain() {
        terrainNode.removeAllChildren()
        // 깊은 계곡·워터가 하단 HUD 스트립을 침범하지 않게 바닥선을 홀 최저 표고 기준으로 (리뷰 S-3)
        let minElev = hole.elevation.min() ?? 0
        groundBase = max(96, 84 - CGFloat(minElev) * pxPerM)
        let cupHalfM = max(Phys.cupHalfWidth, 4.5 / Double(pxPerM))
        let cupL = hole.holeX - cupHalfM
        let cupR = hole.holeX + cupHalfM

        func linePath(from: Double, to: Double) -> CGMutablePath {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: px(from), y: groundY(from)))
            var x = from + 1
            while x < to {
                path.addLine(to: CGPoint(x: px(x), y: groundY(x)))
                x += 1
            }
            path.addLine(to: CGPoint(x: px(to), y: groundY(to)))
            return path
        }

        func addGround(from: Double, to: Double, surface: Surface) {
            guard to - from > 0.1 else { return }
            let node = SKShapeNode()
            let base = linePath(from: from, to: to)
            switch surface {
            case .water: // 대시 수면 + 수면 아래 은은한 면 채움 — 해저드가 멀리서도 '물'로 읽힌다
                node.path = base.copy(dashingWithPhase: 0, lengths: [5, 4])
                node.strokeColor = Palette.waterBlue.withAlphaComponent(0.9)
                node.lineWidth = 1.8
                let depth: CGFloat = 12
                let fill = CGMutablePath()
                fill.move(to: CGPoint(x: px(from), y: groundY(from)))
                fill.addLine(to: CGPoint(x: px(to), y: groundY(to))) // 수면은 평평 (생성기가 보장)
                fill.addLine(to: CGPoint(x: px(to), y: groundY(to) - depth))
                fill.addLine(to: CGPoint(x: px(from), y: groundY(from) - depth))
                fill.closeSubpath()
                let fillNode = SKShapeNode(path: fill)
                fillNode.fillColor = Palette.waterBlue.withAlphaComponent(0.2)
                fillNode.strokeColor = .clear
                terrainNode.addChild(fillNode)
            case .green: // 살짝 도드라진 순백
                node.path = base
                node.strokeColor = NSColor(white: 1, alpha: 0.95)
                node.lineWidth = 2.6
            case .rough: // 어둡게 가라앉힘 + 길고 촘촘한 잔디 틱 (좌우 교차로 '풀숲' 질감)
                node.path = base
                node.strokeColor = Palette.roughGray.withAlphaComponent(0.5)
                node.lineWidth = 1.8
                let grass = CGMutablePath()
                var gx = from + 0.9
                var lean = false
                while gx < to - 0.5 {
                    let gy = groundY(gx)
                    grass.move(to: CGPoint(x: px(gx), y: gy))
                    grass.addLine(to: CGPoint(x: px(gx) + (lean ? -0.8 : 0.9), y: gy + (lean ? 4.2 : 5.4)))
                    lean.toggle()
                    gx += 1.5
                }
                let grassNode = SKShapeNode(path: grass)
                grassNode.strokeColor = Palette.roughGray.withAlphaComponent(0.45)
                grassNode.lineWidth = 1
                terrainNode.addChild(grassNode)
            case .bunker: // 모래 웅덩이 면 채움 + 스티플 — 파인 단면이 통째로 모래색
                node.path = base
                node.strokeColor = Palette.bunkerSand.withAlphaComponent(0.9)
                node.lineWidth = 2.0
                let fill = CGMutablePath() // 지면선 아래 6px 모래 밴드 — 딥(≈3px)보다 안정적인 두께
                fill.move(to: CGPoint(x: px(from), y: groundY(from)))
                var fx = from + 1
                while fx < to {
                    fill.addLine(to: CGPoint(x: px(fx), y: groundY(fx)))
                    fx += 1
                }
                fill.addLine(to: CGPoint(x: px(to), y: groundY(to)))
                fill.addLine(to: CGPoint(x: px(to), y: groundY(to) - 6))
                var rx = to - 1
                while rx > from {
                    fill.addLine(to: CGPoint(x: px(rx), y: groundY(rx) - 6))
                    rx -= 1
                }
                fill.addLine(to: CGPoint(x: px(from), y: groundY(from) - 6))
                fill.closeSubpath()
                let fillNode = SKShapeNode(path: fill)
                fillNode.fillColor = Palette.bunkerSand.withAlphaComponent(0.3)
                fillNode.strokeColor = .clear
                terrainNode.addChild(fillNode)
                let dots = CGMutablePath()
                var bx = from + 0.8
                while bx < to - 0.5 {
                    let cy = groundY(bx) - 3.2
                    dots.addEllipse(in: CGRect(x: px(bx) - 0.7, y: cy - 0.7, width: 1.4, height: 1.4))
                    bx += 1.2
                }
                let dotNode = SKShapeNode(path: dots)
                dotNode.fillColor = Palette.bunkerSand.withAlphaComponent(0.55)
                dotNode.strokeColor = .clear
                terrainNode.addChild(dotNode)
            default: // 티·페어웨이·에이프런: 조용한 헤어라인
                node.path = base
                node.strokeColor = Palette.hairline.withAlphaComponent(0.75)
                node.lineWidth = 1.8
            }
            node.lineCap = .round
            if Theme.highContrast { // 언더스트로크: 밝은 배경에서 헤어라인이 사라지지 않게 (opt-in)
                let under = SKShapeNode(path: node.path ?? base)
                under.strokeColor = NSColor(white: 0, alpha: 0.32)
                under.lineWidth = node.lineWidth + 2.2
                under.lineCap = .round
                terrainNode.addChild(under)
            }
            terrainNode.addChild(node)
        }

        for seg in hole.segments {
            if seg.to <= cupL || seg.from >= cupR {
                addGround(from: seg.from, to: seg.to, surface: seg.type)
            } else {
                addGround(from: seg.from, to: max(seg.from, cupL), surface: seg.type)
                addGround(from: min(seg.to, cupR), to: seg.to, surface: seg.type)
            }
        }

        // 컵: 지면 아래 조용한 홈
        let cupY = groundY(hole.holeX)
        let cup = SKShapeNode(rect: CGRect(x: px(hole.holeX) - 5, y: cupY - 9, width: 10, height: 9))
        cup.fillColor = NSColor(white: 0.05, alpha: 0.85)
        cup.strokeColor = .clear
        terrainNode.addChild(cup)

        // 깃발: 유일한 포인트 컬러
        flagNode.removeAllChildren()
        flagNode.zRotation = 0 // flagWave가 중간에 끊겨도 잔여 회전이 남지 않게
        let pole = SKShapeNode(rect: CGRect(x: -0.6, y: 0, width: 1.2, height: 62))
        pole.fillColor = NSColor(white: 0.95, alpha: 0.85)
        pole.strokeColor = Theme.highContrast ? NSColor(white: 0, alpha: 0.35) : .clear
        pole.lineWidth = 1
        let flag = SKShapeNode(path: {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 0, y: 62))
            p.addLine(to: CGPoint(x: 21, y: 55.5))
            p.addLine(to: CGPoint(x: 0, y: 49))
            p.closeSubpath()
            return p
        }())
        flag.fillColor = Palette.flagRed
        flag.strokeColor = .clear
        // 바람 시각화 (2026-08-21): 깃발이 바람 부는 쪽을 향하고, 세기 비례로 펄럭인다
        let w = hole.wind
        if abs(w) > 0.3 {
            flag.xScale = w < 0 ? -1 : 1 // 폴 기준 미러 (경로 원점이 폴)
            let mag = min(1, abs(w) / 7)
            let period = 0.5 - 0.3 * mag // 강할수록 빠르게
            flag.run(.repeatForever(.sequence([
                .scaleX(to: flag.xScale * (0.55 + 0.15 * (1 - mag)), duration: period),
                .scaleX(to: flag.xScale, duration: period),
            ])))
        }
        flagNode.addChild(pole)
        flagNode.addChild(flag)
        flagNode.position = CGPoint(x: px(hole.holeX), y: cupY)

        // 장애물 — 조용한 헤어라인: 나무는 줄기+캐노피 윤곽, 바위는 반원 둔덕
        for ob in hole.obstacles {
            let gx = px(ob.x)
            let gy = groundY(ob.x)
            switch ob.kind {
            case .tree:
                // 초심플 귀여운 나무 (2026-08-15 사용자 요청): 통통한 트렁크 + 뭉게구름 캐노피.
                // 퍼프 3원을 한 경로에 담으면 nonzero winding으로 겹침 없이 한 덩어리로 채워지고,
                // 스트로크의 안쪽 교차 호는 잎 뭉치 스캘럽으로 읽힌다. 충돌은 여전히 반지름 r 원 하나
                let r = CGFloat(ob.size) * pxPerM
                // above: 0 = 지면 기준 오프셋만 취한다 (gy에 이미 표고 포함 — 리뷰 S-5)
                let cy = gy + CGFloat(ob.canopyCenterY(above: 0)) * pxPerM
                let trunkPath = CGMutablePath()
                trunkPath.move(to: CGPoint(x: gx, y: gy + 1))
                trunkPath.addLine(to: CGPoint(x: gx, y: cy - r * 0.3)) // 캐노피 속까지 — 틈 없음
                let trunk = SKShapeNode(path: trunkPath)
                trunk.strokeColor = Palette.hairline.withAlphaComponent(0.75)
                trunk.lineWidth = 4.5
                trunk.lineCap = .round
                // 캐노피 = 6스캘럽 뭉게구름 윤곽 하나: 링 위 여섯 원의 바깥 호만 이어붙인다.
                // half(1.199rad)는 이웃 원과의 교점 반각 — 호 끝점이 정확히 만나 틈이 없다.
                // 실루엣 0.89r~1.08r로 충돌원(r)과 거의 일치
                let puffs = CGMutablePath()
                let ringR = 0.6 * r
                let bumpR = 0.48 * r
                let half = 1.199
                for k in 0 ..< 6 {
                    let phi = Double.pi / 2 - Double(k) * .pi / 3
                    let c = CGPoint(x: gx + ringR * cos(phi), y: cy + ringR * sin(phi))
                    puffs.addArc(
                        center: c, radius: bumpR,
                        startAngle: phi + half, endAngle: phi - half, clockwise: true
                    )
                }
                puffs.closeSubpath()
                let canopy = SKShapeNode(path: puffs)
                canopy.strokeColor = Palette.hairline.withAlphaComponent(0.8)
                canopy.lineWidth = 2.0
                canopy.lineJoin = .round
                canopy.fillColor = NSColor(white: 1, alpha: 0.16)
                if Theme.highContrast {
                    let under = SKShapeNode(path: puffs)
                    under.strokeColor = NSColor(white: 0, alpha: 0.32)
                    under.lineWidth = 4
                    under.fillColor = .clear
                    terrainNode.addChild(under)
                }
                terrainNode.addChild(trunk)
                terrainNode.addChild(canopy)
            case .rock:
                // 귀여운 조약돌 무더기: 납작 둥근 큰 돌 + 곁의 아기 돌 (충돌은 큰 돌만).
                // 공(순백 원)과 헷갈리지 않게 납작한 돔 + 진한 채움으로 '돌덩이'로 읽힌다
                let r = CGFloat(ob.size) * pxPerM
                func pebbleDome(cxPx: CGFloat, baseY: CGFloat, radius: CGFloat) -> CGPath {
                    let tf = CGAffineTransform(translationX: cxPx, y: baseY + radius * 0.22)
                        .scaledBy(x: 1, y: 0.74)
                    let p = CGMutablePath()
                    p.addArc(
                        center: .zero, radius: radius,
                        startAngle: -0.31, endAngle: .pi + 0.31, clockwise: false,
                        transform: tf
                    )
                    return p
                }
                let rock = SKShapeNode(path: pebbleDome(cxPx: gx, baseY: gy, radius: r))
                rock.strokeColor = Palette.hairline.withAlphaComponent(0.85)
                rock.fillColor = NSColor(white: 1, alpha: 0.28)
                rock.lineWidth = 2.0
                rock.lineCap = .round
                let babyXm = ob.x - ob.size * 1.5 // 아기 돌은 왼쪽 곁에 (시각 전용, 비충돌)
                let baby = SKShapeNode(
                    path: pebbleDome(cxPx: px(babyXm), baseY: groundY(babyXm), radius: r * 0.45)
                )
                baby.strokeColor = Palette.hairline.withAlphaComponent(0.65)
                baby.fillColor = NSColor(white: 1, alpha: 0.2)
                baby.lineWidth = 1.5
                baby.lineCap = .round
                if Theme.highContrast {
                    for path in [rock.path!, baby.path!] {
                        let under = SKShapeNode(path: path)
                        under.strokeColor = NSColor(white: 0, alpha: 0.32)
                        under.lineWidth = 4
                        under.lineCap = .round
                        terrainNode.addChild(under)
                    }
                }
                terrainNode.addChild(rock)
                terrainNode.addChild(baby)
            }
        }
    }

    func updateHUD() {
        let total = results.reduce(0) { $0 + ($1.strokes - $1.par) }
        let totalStr = total > 0 ? "+\(total)" : total == 0 ? "E" : "\(total)"
        let remain = abs(hole.holeX - ball.x)
        let lie = strokes == 0 ? Surface.tee : hole.surface(at: ball.x)
        // 표고차: 공→홀컵 (↑ = 오르막). 봇 실측에서 표고 지식 가치 ≈1.7타/홀인데 게임이 안 알려줬다 (QA 2026-08-15 밸런스 신호).
        // 거리와 같은 급의 정보라 탄도 어시스트가 아니다. 1m 미만은 생략
        let dz = hole.ground(at: hole.holeX) - hole.ground(at: ball.x)
        let elevStr = abs(dz) < 1 ? "" : " \(dz > 0 ? "↑" : "↓")\(Int(abs(dz).rounded()))m"
        scoreTitle.setText("\(holeIdx + 1)번 홀 · 파 \(hole.par)")
        scoreSub.setText("타수 \(strokes) · 합계 \(totalStr) · \(lie.label) · \(Int(remain))m" + elevStr)
        clubTitle.setText(club.name)
        let cat = club.cat == .wood ? "우드" : club.cat == .iron ? "아이언" : club.cat == .wedge ? "웨지" : "퍼터"
        // 바람: 화살표는 부는 방향 (→ = 오른쪽으로 밀어줌), 0.5m/s 미만은 무풍 취급
        let w = hole.wind
        let windStr = abs(w) < 0.5 ? "" : " · 바람 \(w > 0 ? "→" : "←") \(Int(abs(w).rounded()))m/s"
        clubSub.setText(cat + windStr)
    }

    /// ── 입력 ──
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: NSApp.terminate(nil) // Esc
        case 15: newRound(); return // R
        default: break
        }
        if napping, mode == .aim { // 낮잠: 아무 키나 깨우기로 소비
            wakeUp()
            return
        }
        guard mode == .aim, !isGamePaused else { return }
        lastInputAim = aimTime // 방치 판정 기준 (리뷰 m1: 조준 경과가 아니라 입력 없는 시간)
        switch event.keyCode {
        case 126, 125: heldKeys.insert(event.keyCode) // ↑↓
        // → = 드라이버(긴 클럽) 쪽, ← = 퍼터 쪽 (2026-08-15 사용자 요청 — 오른쪽 = 멀리)
        case 123: clubIdx = min(ClubTable.all.count - 1, clubIdx + 1); presetPutterHeight(); updateHUD() // ←
        case 124: clubIdx = max(0, clubIdx - 1); presetPutterHeight(); updateHUD() // →
        case 49: startSwing() // Space
        default: break
        }
    }

    override func keyUp(with event: NSEvent) {
        heldKeys.remove(event.keyCode)
        if mode == .aim {
            lastInputAim = aimTime
        }
    }

    /// ── 메인 루프 ──
    override func update(_ currentTime: TimeInterval) {
        let dt = lastTime == 0 ? 0 : min(currentTime - lastTime, 0.1)
        lastTime = currentTime
        guard !isGamePaused else { return }

        if demoMode { // 자동 플레이: 조준 1.2s 후 스윙, 라운드 끝나면 새 라운드
            if mode == .aim {
                if demoWallForce {
                    heightPct = 0.95 // 벽 관찰: 조준 내내 풀 백스윙 프리뷰 유지 (최악 케이스 상시 노출)
                }
                demoWait += dt
                if !napping, demoWait > (demoIdleForce ? 25 : 1.2) { // 아이들 관찰 모드는 조준을 길게 유지
                    demoWait = 0
                    // 벽 관찰 모드는 최악 케이스(풀 백스윙)로
                    if let p = demoPower {
                        heightPct = p // 관찰용 파워 고정
                    } else if demoWallForce {
                        heightPct = Double.random(in: 0.9 ... 1.0)
                    } else if !(demoPickupForce && club.isPutter) { // 줍기 관찰: 거리 프리셋 퍼팅 그대로 (탭인)
                        heightPct = Double.random(in: 0.5 ... 0.85)
                    }
                    startSwing()
                }
            } else if mode == .end {
                demoWait += dt
                if demoWait > 3 {
                    demoWait = 0
                    newRound()
                }
            } else {
                demoWait = 0
            }
        }

        if mode == .aim, !napping {
            let rate = club.isPutter ? 0.4 : 0.85
            if heldKeys.contains(126) {
                heightPct = min(1, heightPct + rate * dt)
            }
            if heldKeys.contains(125) {
                heightPct = max(0, heightPct - rate * dt)
            }
        }

        if var anim = swingAnim {
            anim.t += dt
            if !anim.launched, anim.t >= anim.prof.down {
                anim.launched = true
                swingAnim = anim
                launchBall()
            }
            if anim.t >= SwingTiming.total {
                lastFinishPose = finishPose(profile: anim.prof)
                finishAt = currentTime
                swingAnim = nil
            } else {
                swingAnim = anim
            }
        }

        if mode == .ritual {
            stepRitual(dt: dt)
        }

        if mode == .walking, var w = walkAnim {
            w.t += dt
            if var tp = w.turn, w.t >= tp.start {
                if !tp.started {
                    tp.started = true
                    if demoMode {
                        print(String(format: "TURN start x %.0f dir %d", Double(px(stickX)), Int(dir)))
                        fflush(stdout)
                    }
                }
                if !tp.flipped, w.t >= tp.start + tp.dur * 0.5 { // 가장 좁은 실루엣·무릎 거의 폄 — 여기서 미러·발 교환
                    tp.flipped = true
                    setFacing(tp.newDir)
                    if demoMode {
                        print("TURN flip")
                        fflush(stdout)
                    }
                }
                w.turn = tp
            }
            // 걷는 도중 공이 옮겨졌나 (서프라이즈·관찰 --demo-replan): 같은 방향 앞이면 속도를 유지한 채 목표만 교체,
            // 뒤거나 가까우면 도착한 뒤 그 자리에서 재출발한다 (아래 도착 처리 — 반대 방향이면 제자리 돌기 포함)
            if w.gaitReady, w.stopPlan == nil, w.arrivalTurn == nil, w.t >= w.relax {
                demoReplanTick(&w)
                let tgt = walkTarget()
                let sgn: Double = w.toX >= w.fromX ? 1 : -1
                if abs(tgt.to - w.toX) > 0.3, (tgt.to - stickX) * sgn > 0,
                   abs(tgt.to - stickX) * Double(pxPerM) > WalkAnim.stopPlanRange + 30 {
                    replanAhead(&w, to: tgt.to)
                }
            }
            // 넘어짐: 전진 동결을 연속 램프로 — 쓰러지며(0.3~0.6) 멈추고, 일어난 만큼(1.5~2.2)
            // 다시 가속한다. 이진 동결은 엎어진 채 슬라이드(리뷰 S1)와 duty 점프 스냅(S3)을 만든다
            var freeze = 0.0
            if let tr = w.tripAt {
                let te = w.t - tr
                if te > 0.25, te < 2.4 { // 걸림(0.25)→철푸덕(0.5)→홀드→일어나기(1.6~2.4)
                    let fall = smoothstep(min(1, (te - 0.25) / 0.25))
                    let rise = smoothstep(min(1, max(0, (te - 1.6) / 0.8)))
                    freeze = fall * (1 - rise * rise)
                }
                if !w.tripFxDone, te > 0.5 { // 철푸덕 — 소리·먼지는 한 번만, 지물에 맞는 이펙트로
                    w.tripFxDone = true
                    SoundKit.shared.bounce(speed: 5, surface: .rough)
                    let at = CGPoint(x: px(stickX), y: groundY(stickX))
                    let s = hole.surface(at: stickX)
                    if s == .water {
                        FX.ripple(on: self, at: at)
                    } else {
                        FX.dust(on: self, at: at, surface: s == .bunker ? .bunker : .rough, intensity: 0.7)
                    }
                }
            }
            // 쇼피스: 트립과 같은 연속 램프 — 서서히 멈춰 서서 추고, 끝나면 다시 걷는다
            if let sa = w.showAt, let sk = w.showKind {
                let te = w.t - sa
                if te > 0, te < sk.duration {
                    let inR = smoothstep(min(1, te / 0.35))
                    let outR = smoothstep(min(1, max(0, (te - (sk.duration - 0.5)) / 0.5)))
                    freeze = max(freeze, inR * (1 - outR * outR))
                }
            }
            // 잔동작 중 걸음을 멈추는 것(bow·airSwing 등)과 보폭 배율 — 쇼피스와 같은 동결 램프 (WalkFlavorKind.gait)
            var strideScale = 1.0
            for e in w.flavorEvents {
                let g = e.kind.gait(u: (w.t - e.t0) / e.dur)
                strideScale *= g.stride
                freeze = max(freeze, g.stop)
            }
            strideScale *= moodStride(w.mood, e: moodEnvelope(tw: w.t - w.relax - w.pausedTime, dur: w.dur))
            if freeze > 0 {
                w.pausedTime += dt * freeze // 걸음 시계는 동결 비율만큼만 멈춘다
            }
            let tw = w.t - w.relax - w.pausedTime
            if tw >= 0 {
                let u = min(1, tw / w.dur)
                let sgn: Double = w.toX >= w.fromX ? 1 : -1
                let prevStickX = stickX
                stickX = w.fromX + sgn * w.profile.position(at: tw)
                // 유효 속도 = 프로파일의 해석 도함수 × (1 - freeze) — 위치와 게이트가 같은 비율로 감속·재가속
                let vInst = (1 - freeze) * w.profile.velocity(at: tw)
                w.vPx = vInst * Double(pxPerM)
                if demoMode, Int(tw * 10) != Int((tw - dt) * 10) { // 속도 프로파일 계측 (0.1초 간격)
                    print(String(format: "WALKV %.1f %.1f %.1f", tw, abs(stickX - w.fromX) * Double(pxPerM), w.vPx))
                }
                // 게이트 갱신: 보폭·듀티는 속도 함수, 접지점은 리프트오프 순간 래치 (노슬립)
                w.stepL = 22 * min(1, max(0.5, (w.vPx / 30).squareRoot())) * strideScale
                // 지형 적응 (2026-08-15 요청): 경사에선 보폭을 줄이고, 러프·벙커는 무거운 걸음
                let walkSurf = hole.surface(at: stickX)
                w.stepL *= 1 - 0.3 * min(1, abs(atan(hole.slope(at: stickX))) / 0.35)
                if walkSurf == .rough {
                    w.stepL *= 0.85
                } else if walkSurf == .bunker {
                    w.stepL *= 0.75
                }
                w.duty = 0.68 - 0.08 * min(1, w.vPx / 30)
                let dNow = abs(stickX - w.fromX) * Double(pxPerM)
                let dStop = abs(w.toX - w.fromX) * Double(pxPerM)
                if !w.gaitReady {
                    w.gaitReady = true
                    // 어드레스 스탠스 그 자리에서 시작 (foot1 = 뒷발 -11, foot2 = 앞발 +16 — 점프 0).
                    // 위상 0.5: 뒷발(feet[0])이 먼저 나간다 (보행 개시 — 첫 걸음은 짧다)
                    w.feet[0].plant = dNow + WalkAnim.StopPlan.rearOffset
                    w.feet[1].plant = dNow + WalkAnim.StopPlan.frontOffset
                    w.gaitPhase = 0.5
                    // 원점 전환: 조준(공 원점) → 걷기(몸 원점). 렌더 리그를 반대로 옮겨 화면 위치 보존
                    renderRig.shiftX(dir * Double(px(prevStickX) - px(stickX)))
                    if dStop <= WalkAnim.stopPlanRange, w.beginStopPlan(dNow: dNow, dStop: dStop) {
                        swapRenderFeet() // 두 걸음 거리 — 처음부터 발자국 계획
                    }
                }
                if let plan = w.stopPlan {
                    w.gaitPhase = w.planPhase0 + plan.progress(dNow) // 바운스·팔 위상만 이어간다
                } else {
                    w.gaitPhase += w.vPx * dt / (2 * w.stepL)
                    var landedNearStop = false
                    for i in 0 ..< 2 {
                        let f = (w.gaitPhase + (i == 1 ? 0.5 : 0)).truncatingRemainder(dividingBy: 1)
                        if f < w.duty {
                            if w.feet[i].inSwing { // 착지 — 목표점에 래치
                                w.feet[i].inSwing = false
                                w.feet[i].plant = w.feet[i].swingTo
                                if dStop - dNow <= WalkAnim.stopPlanRange {
                                    landedNearStop = true // 두 발 접지 — 여기서 정지 발자국 계획 시작
                                }
                                // 지물 반응 (재미): 러프·벙커 스텝 먼지, 물 위는 파문 — 한 걸음 걸러
                                w.stepFxParity.toggle()
                                if w.stepFxParity, w.vPx > 8 {
                                    let sgn: Double = w.toX >= w.fromX ? 1 : -1
                                    let footXm = w.fromX + sgn * w.feet[i].plant / Double(pxPerM)
                                    let fs = hole.surface(at: footXm)
                                    let at = CGPoint(x: px(footXm), y: groundY(footXm))
                                    if fs == .rough || fs == .bunker {
                                        FX.dust(on: self, at: at, surface: fs, intensity: 0.18)
                                    } else if fs == .water {
                                        FX.ripple(on: self, at: at)
                                    }
                                }
                            }
                        } else if !w.feet[i].inSwing { // 리프트오프 — 다음 착지점을 지금 고정
                            w.feet[i].inSwing = true
                            w.feet[i].swingFrom = w.feet[i].plant
                            w.feet[i].swingTo = dNow + 2 * w.stepL * (1 - w.duty) + w.duty * w.stepL
                        }
                    }
                    if landedNearStop, w.beginStopPlan(dNow: dNow, dStop: dStop) {
                        swapRenderFeet()
                    }
                }
                var rewalk = false
                if u >= 1, w.arrivalTurn == nil {
                    let tgt = walkTarget() // 저장값 대신 지금 값 — 핀 이동·공 이동(서프라이즈) 뒤에도 맞는 방향·자리로
                    if abs(tgt.to - stickX) > 0.5 { // 도착해 보니 공이 없다 — 이 자리에서 다시 걷는다
                        rewalk = true
                        if demoMode {
                            print(String(format: "REWALK from %.1f to %.1f", stickX, tgt.to))
                            fflush(stdout)
                        }
                    } else if tgt.dir != dir { // 도착 턴: 조준 방향으로 제자리 돌기 뒤 조준
                        w.arrivalTurn = WalkAnim.TurnPlan(start: w.t, dur: 0.65, newDir: tgt.dir, atBody: true)
                        if demoMode {
                            print(String(format: "TURN arrival x %.0f dir %d", Double(px(stickX)), Int(dir)))
                            fflush(stdout)
                        }
                    }
                }
                if rewalk {
                    walkAnim = w
                    startWalk(fromBody: true)
                } else if var tp = w.arrivalTurn {
                    if !tp.flipped, w.t >= tp.start + tp.dur * 0.5 {
                        tp.flipped = true
                        setFacing(tp.newDir)
                        if demoMode {
                            print("TURN arrival flip")
                            fflush(stdout)
                        }
                    }
                    w.arrivalTurn = tp
                    walkAnim = w
                    if w.t >= tp.start + tp.dur + 0.15 {
                        enterAim()
                    }
                } else {
                    walkAnim = w
                    if u >= 1 {
                        enterAim()
                    }
                }
            } else {
                walkAnim = w
            }
        }

        if mode == .motion, tunnelTransit == nil { // 창 터널 통과 중엔 비행 물리 정지 (Surprises2)
            acc += dt * timeScale
            var terminal = StepEvent.none
            var landing: (speed: Double, surface: Surface, x: Double)?
            var wallHit: (speed: Double, x: Double)?
            var bumperHit: (speed: Double, x: Double, y: Double)?
            var lipped = false
            var settledFrom: Double? // 정착 스냅이 일어난 프레임 — 궤적 잔상은 정지 지점까지만
            while acc >= Phys.dt {
                acc -= Phys.dt
                let prevX = ball.x, prevY = ball.y
                let event = Ballistics.step(
                    &ball, hole: hole, bumpers: tunnelArmed ? [] : shotBumpers, // 터널 무장 중엔 반사 대신 진입 판정 (아래)
                    wind: gustWind, kind: ballKind // 돌풍 덮어쓰기 · 공 바꿔치기
                )
                switch event {
                case .holed, .water:
                    terminal = event
                case let .bounce(speed, surface): // 프레임당 가장 강한 착지 하나만 연출
                    if speed > (landing?.speed ?? 0) {
                        landing = (speed, surface, ball.x)
                    }
                case let .wall(speed):
                    if speed > (wallHit?.speed ?? 0) {
                        wallHit = (speed, ball.x)
                    }
                case let .bumper(speed):
                    if speed > (bumperHit?.speed ?? 0) {
                        bumperHit = (speed, ball.x, ball.y)
                    }
                case .lipOut:
                    lipped = true
                case .none:
                    break
                }
                if terminal == .none, ball.phase == .rest, abs(ball.x - prevX) > 0.6 { // 스텝당 이동 ≤ 0.32m — 초과는 정착 스냅
                    let d = abs(ball.x - prevX)
                    settledFrom = prevX
                    settleRoll = (prevX, ball.x, 0, min(0.8, 0.2 + 0.035 * d))
                    if demoMode {
                        print(String(format: "SETTLE %.1f→%.1f %.1fm", prevX, ball.x, d))
                        fflush(stdout)
                    }
                }
                if terminal != .none {
                    break
                }
                if tunnelArmed,
                   enterTunnelIfInside(prevX: prevX, prevY: prevY) { // 종결(홀인·입수) 뒤에만 — 같은 스텝의 홀인을 삼키지 않게 (리뷰 M1)
                    break
                }
            }
            if let l = landing, l.speed > 1.4 {
                if ballKind == .bowling { // 볼링공은 둔탁하게 (Surprises2)
                    SoundKit.shared.thump()
                } else {
                    SoundKit.shared.bounce(speed: l.speed, surface: l.surface)
                }
                FX.dust(
                    on: self,
                    at: CGPoint(x: px(l.x), y: groundY(l.x)),
                    surface: l.surface,
                    intensity: min(1, l.speed / 12)
                )
            }
            if let w = wallHit, w.speed > 0.8 {
                SoundKit.shared.wall(speed: w.speed)
            }
            if let bh = bumperHit, bh.speed > 0.8 { // 창 범퍼 — 벽 반사음 + 임팩트 링
                shotHitBumper = true
                if !demoMode {
                    Records.shared.bumperHits += 1
                    Records.shared.save()
                }
                SoundKit.shared.wall(speed: bh.speed)
                FX.ripple(on: self, at: CGPoint(x: px(bh.x), y: py(bh.y)))
                if demoMode {
                    print(String(format: "BUMPER-HIT %.1f @(%.0f, %.0f)", bh.speed, bh.x, bh.y))
                    fflush(stdout)
                }
            }
            if lipped {
                SoundKit.shared.lipOut()
                shotLipped = true
            }
            let trailX = settledFrom ?? ball.x
            trailPoints.append(CGPoint(x: px(trailX), y: py(hole.ground(at: trailX)) + 5.5))
            if trailPoints.count > 400 {
                trailPoints.removeFirst()
            }
            if terminal != .none || ball.phase == .rest { // 샷 종료 한 번 — 갤러리 판정·공 바꿔치기 복귀 (Surprises2)
                onShotEnded(terminal: terminal)
            }
            switch terminal {
            case .holed: onHoled()
            case .water:
                if let kind = rollSurprise(hook: .water) { // 개구리 구조 (워터 훅)
                    playSurprise(kind)
                } else {
                    onWater()
                }
            default:
                if ball.phase == .rest {
                    // 벽 릴리프 (장애물 무벌타 구제 격): 스탠스·컴팩트 백스윙이 화면 안에
                    // 온전히 서는 최소 이격(46px)을 보장 — 스틱맨은 절대 화면 밖에 서지 않는다
                    let reliefM = 46 / Double(pxPerM)
                    let relieved = min(max(ball.x, reliefM), hole.worldW - reliefM)
                    if relieved != ball.x {
                        ball.x = relieved
                        ball.y = hole.ground(at: ball.x)
                    }
                    let inBunker = hole.surface(at: ball.x) == .bunker
                    let frustrated = noteSetback(demoSetbackForce || inBunker || shotLipped)
                    PlayLog.note(String(
                        format: "REST strokes %d x %.1f lie %@ label %@", strokes, ball.x,
                        "\(hole.surface(at: ball.x))",
                        greenChanceLabel() ?? "-"
                    ))
                    if strokes >= Phys.maxStrokes {
                        giveUp()
                    } else if let label = greenChanceLabel() {
                        playGreenCelebration(label) // 파4 원온·파5 투온 — 이글 찬스 (2026-09-17 사용자 요청)
                    } else if galleryWantsScene() {
                        galleryReact() // 갤러리가 지켜본 샷 — 스틱맨 반응이 끝나면 걷기 (Surprises2)
                    } else if frustrated {
                        var reason = inBunker ? "또 벙커…" : shotLipped ? "또 립아웃…" : "또…"
                        if inBunker, lastShotLie == .bunker, !bunkerHintShown { // 탈출 실패 — 힌트는 홀당 한 번
                            bunkerHintShown = true
                            reason += " 웨지로 백스윙 절반 이상"
                        }
                        playFrustration(reason: reason)
                    } else if inBunker, lastShotLie == .bunker, !bunkerHintShown { // 좌절 반응 없이 실패한 경우도 힌트
                        bunkerHintShown = true
                        toast("벙커 탈출", sub: "웨지로 백스윙 절반 이상 — 벙커는 파워가 반으로 준다")
                        startWalk()
                    } else if let kind = rollSurprise(hook: .ballRest) {
                        playSurprise(kind)
                        if !kind.ownsScene { // 갤러리처럼 다음 샷 위에 얹히는 종류는 바로 걷는다
                            startWalk()
                        }
                    } else {
                        startWalk()
                    }
                }
            }
            updateHUD()
        }

        // ── 통합 리그: 모든 상태가 같은 파라미터 공간의 '타깃'만 바꾼다 → 전환이 자동으로 이어진다 ──
        // 클럽 변경으로 점프하는 값 전부 스무딩 (길이·스탠스·백스윙 폭 — 카테고리 경계 움찔 방지)
        let clubK = 1 - exp(-8 * dt)
        renderLen += ((club.isPutter ? profile.putt.len : club.renderLength) - renderLen) * clubK // 암록 퍼터는 43
        renderBallFwd += (profile.ballFwd - renderBallFwd) * clubK
        renderTop += (profile.topScale - renderTop) * clubK
        /// 헤드 '종류'가 바뀌면 morph 시작 (캡슐 기하 변형 — 몸 동작 없이 헤드만 변한다)
        func headKind(_ c: Club) -> Int {
            c.cat == .wood ? 0 : c.cat == .putter ? 2 : 1
        }
        if headKind(club) != headKind(lastClub) {
            prevHeadClub = lastClub
            headMorph = 0
        }
        lastClub = club
        headMorph = min(1, headMorph + dt / 0.3)
        renderLoft += (club.loft - renderLoft) * clubK
        if mode == .aim {
            aimTime += dt
            tickNap() // 낮잠 (조준 방치 훅)
        }
        updateSurprises(dt: dt, currentTime: currentTime)
        if demoGreetForce, !demoGreeted, mode == .aim, aimTime > 3 { // 관찰: 일시정지 1s 뒤 재개 → 인사
            demoGreeted = true
            setGamePaused(true)
            afterSurprise(1.0) { [weak self] in self?.setGamePaused(false) }
        }
        // 벽 근접도 (0~1) — 조준·스윙 중에만 켜지고, 스무딩으로 자세가 툭 바뀌지 않는다
        let wallTarget = (mode == .aim || swingAnim != nil) && !club.isPutter
            ? smoothstep(min(1, max(0, (80 - wallBehindPx) / 36)))
            : 0
        renderWallT += (wallTarget - renderWallT) * (1 - exp(-6 * dt))
        let treeTarget = mode == .aim || swingAnim != nil ? treePunchT : 0
        renderTreeT += (treeTarget - renderTreeT) * (1 - exp(-6 * dt))
        var targetRig: Rig
        let rigRate: Double
        var rigClubRate: Double? = nil // 팔로스루 오버랩 — 클럽만 느린 추적
        if let anim = swingAnim {
            targetRig = RigBuilder.fromPose(
                swingPose(t: anim.t, fromPose: anim.fromPose, profile: anim.prof, heightPct: heightPct),
                ballFwd: wallBallFwd, clubLen: renderLen
            )
            // 다운스윙은 초고속 추적(220) — 스무딩 지연(≈31°)이 '클럽이 공에 닿는 프레임'을
            // 지우고 있었다 (리서치 P1). 임팩트 후는 45로 복귀 (그 시점 오차 ≈1°라 킥 없음)
            rigRate = anim.t < anim.prof.down ? 220 : 45
            if anim.t >= anim.prof.down { // 팔로스루: 클럽만 늦게 멈추는 오버랩 (리서치 P6)
                rigClubRate = 22
            }
            // 임팩트까지는 벽 스탠스 유지, 팔로스루에서 0.25s에 걸쳐 발을 내린다
            let wallSwingT = anim.t < anim.prof.down
                ? renderWallT
                : renderWallT * max(0, 1 - (anim.t - anim.prof.down) / 0.25)
            applySlopeStance(&targetRig)
            applyWallStance(&targetRig, t: wallSwingT)
            applyLieStance(&targetRig)
            applyImpactJump(&targetRig, t: anim.t, prof: anim.prof) // 로리 트레이드마크
            // 탭인은 스윙 애니메이션(스타일 상한 0.83s)이 끝나기 전에 홀아웃된다 — 반응을 늦추지 않고 피니시 위에 바로 얹는다
            if mode == .holed, reactionKind != .none, anim.t >= anim.prof.down {
                applyScoreReaction(&targetRig, t: currentTime - reactionAt)
            }
        } else if mode == .walking, let w = walkAnim, let tp = w.arrivalTurn { // 도착 턴 (몸 원점)
            targetRig = turnRig(tp, t: w.t)
            rigRate = 9
        } else if mode == .walking, let w = walkAnim, w.t >= w.relax {
            var flavor = WalkFlavor()
            applyMood(&flavor, mood: w.mood, tw: w.t - w.relax - w.pausedTime, dur: w.dur) // 무드 오버레이 (이벤트가 위에 합산)
            if let r = w.shoulderRange { // 0.6초에 걸쳐 어깨에 올렸다 내린다
                let up = min(1, max(0, (w.t - r.lowerBound) / 0.6))
                let down = min(1, max(0, (r.upperBound - w.t) / 0.6))
                flavor.shoulder = smoothstep(min(up, down))
            }
            // 모션 레시피는 WalkFlavorKind.apply(37종 — WalkFlavors.swift)가 채널에 합산한다
            for e in w.flavorEvents {
                let u = (w.t - e.t0) / e.dur
                guard u > 0 else { continue }
                if demoMotionShowcase, w.t - dt < e.t0 { // 시작 프레임 — 캡처 워처에 위치 통지
                    let info = "\(e.kind) \(Int(px(stickX))) \(Int(groundY(stickX))) \(String(format: "%.1f", e.dur))"
                    try? info.write(toFile: "/tmp/minigolf-motion.txt", atomically: true, encoding: .utf8)
                    print(String(format: "MOTION[%.2f] ", Date().timeIntervalSince1970) + info)
                    fflush(stdout)
                }
                e.kind.apply(u: u, into: &flavor)
            }
            // (구 1.7× 진폭 부스트는 제거 — 37종은 관절 사거리 안에서 최종 크기로 직접 작성됐다, 2026-09-15)
            // 쇼피스 밈 모션 — 동결된 무대 위에 크게 얹는다 (WalkFlavors.swift ShowpieceKind)
            if let sa = w.showAt, let sk = w.showKind {
                let su = (w.t - sa) / sk.duration
                if su > 0, su < 1 {
                    if w.t - dt < sa { // 시작 프레임
                        if !demoMode { // 기록은 실플레이 전용
                            Records.shared.showpiecesSeen += 1
                            if Records.shared.showpiecesSeen >= 10 {
                                Records.shared.award(.memeWitness) // 연출은 기록 카드에서
                            }
                            Records.shared.save()
                        }
                        if demoMode { // 캡처 워처에 위치 통지
                            let info =
                                "\(sk.rawValue) \(Int(px(stickX))) \(Int(groundY(stickX))) \(String(format: "%.1f", sk.duration))" // 캡처
                            // 길이용 duration
                            try? info.write(toFile: "/tmp/minigolf-motion.txt", atomically: true, encoding: .utf8)
                            print("SHOWPIECE \(info)")
                            fflush(stdout)
                        }
                    }
                    sk.apply(u: su, into: &flavor)
                }
            }
            // 지형 적응 자세 (2026-08-15 요청): 오르막은 상체를 앞으로(등산),
            // 내리막은 뒤로 젖히고 무릎을 굽혀 조심조심 — 보폭 축소는 게이트 쪽에서
            let sFace = atan(hole.slope(at: stickX)) * dir
            let leanT = min(1, abs(sFace) / 0.3)
            if sFace > 0 {
                flavor.shoulderXOff += 3.5 * leanT
                flavor.headDyOff -= 0.5 * leanT
            } else {
                flavor.shoulderXOff -= 3.0 * leanT
                flavor.hipYOff -= 1.5 * leanT
            }
            if hole.surface(at: stickX) == .bunker { // 모래에 발이 잠긴 무거운 걸음
                flavor.hipYOff -= 1.2
                flavor.shoulderXOff += 1.0
            }
            // 넘어지기 연출: 발이 걸려(lurch) 앞으로 쏠리다 몸이 쭉 뻗어 철푸덕 엎어진다(프론).
            // 웅크림이 아니라 배로 엎어지는 슬랩스틱 (2026-08-15 사용자 재판정).
            // 전진 동결은 게이트 쪽 pausedTime이 담당 — 여기는 몸짓만
            if let tr = w.tripAt {
                let te = w.t - tr
                if te > 0, te < 2.4 {
                    let lurch = smoothstep(min(1, max(0, te / 0.25)))
                    let fall = smoothstep(min(1, max(0, (te - 0.25) / 0.25)))
                    let rise = smoothstep(min(1, max(0, (te - 1.6) / 0.8)))
                    let down = min(fall, 1 - rise)
                    // 걸림: 상체가 급히 앞으로 → 엎어짐: 힙·어깨가 지면 높이로, 어깨는 훨씬 앞에
                    flavor.shoulderXOff += 8 * lurch * (1 - rise) + 12 * down
                    flavor.hipXOff += 3 * lurch * (1 - rise) + 3 * down
                    flavor.hipYOff -= 34 * down // 몸통이 바닥에 (어깨 68.5-34-25 ≈ 힙 43.5-34)
                    flavor.shoulderYOff -= 25 * down
                    flavor.headDxOff += 5 * down // 얼굴이 앞바닥을 향한다
                    flavor.headDyOff -= 8 * down
                    flavor.freeHandXOff += 18 * down // 팔이 앞으로 뻗은 채
                    flavor.freeHandYOff -= 6 * down
                    flavor.armAmpBoost -= down
                }
            }
            // 발 위치: 접지발 = 래치된 접지점 그대로, 스윙발 = 고정된 목표로 보간 (노슬립)
            let dPx = abs(stickX - w.fromX) * Double(pxPerM)
            let vAmp = min(1, w.vPx / 30)
            // 지물 적응: 러프는 풀을 넘는 하이스텝, 벙커는 발이 모래에 잠긴다
            let surfHere = hole.surface(at: stickX)
            let liftBoost = surfHere == .rough ? 1.5 : 1.0
            func footPose(_ i: Int) -> (x: Double, lift: Double) {
                if let plan = w.stopPlan { // 정지 발자국 계획: 뒷발 p∈[0,0.5] → 앞발 p∈[0.45,1] (거리 구동 — 정지하면 발도 멈춘다)
                    let p = plan.progress(dPx)
                    let s = i == 0 ? min(1, p / 0.5) : min(1, max(0, (p - 0.45) / 0.55))
                    let from = i == 0 ? plan.rearFrom : plan.frontFrom
                    let to = plan.dStop + (i == 0 ? WalkAnim.StopPlan.rearOffset : WalkAnim.StopPlan.frontOffset)
                    let lift = sin(.pi * s) * sin(.pi * s) * (4 + 3 * vAmp) * liftBoost
                    return (mix(from, to, smoothstep(s)) - dPx, lift)
                }
                let f = (w.gaitPhase + (i == 1 ? 0.5 : 0)).truncatingRemainder(dividingBy: 1)
                let g = w.feet[i]
                if !g.inSwing {
                    let xm = stickX + (g.plant - dPx) * dir / Double(pxPerM)
                    return (g.plant - dPx, hole.surface(at: xm) == .bunker ? -1.8 : 0)
                }
                let sw = max(0, (f - w.duty) / (1 - w.duty))
                // sin² 프로파일: 이륙·착지 모두 속도 0 (발 '찍기' 제거)
                let lift = sin(.pi * sw) * sin(.pi * sw) * (3 + 5 * vAmp + 6 * flavor.skip) * liftBoost
                return (mix(g.swingFrom, g.swingTo, smoothstep(sw)) - dPx, lift)
            }
            targetRig = RigBuilder.walking(
                f1: footPose(0), f2: footPose(1), gaitPhase: w.gaitPhase,
                vPx: w.vPx, clubLen: renderLen, flavor: flavor
            ) { dx in
                // dx는 facing 로컬(px) — 렌더가 dir로 미러하므로 지면 샘플도 dir을 곱해야
                // 미러 홀에서 앞뒤 발 높이가 뒤바뀌지 않는다 (2026-08-15 수정)
                let xm = self.stickX + dx * self.dir / Double(self.pxPerM)
                return Double(self.groundY(xm) - self.groundY(self.stickX))
            }
            rigRate = 14 // 상체는 부드럽게 — 발·무릎은 아래 footRate로 고속 추적
        } else if mode == .aim {
            targetRig = RigBuilder.fromPose(
                backswingPose(heightPct: heightPct, profile: profile, topScale: wallTopScale),
                ballFwd: wallBallFwd, clubLen: renderLen
            )
            applySlopeStance(&targetRig)
            applyWallStance(&targetRig, t: renderWallT)
            applyLieStance(&targetRig)
            applyIdleFidget(&targetRig)
            if napping {
                applyNap(&targetRig)
            }
            if reactionKind != .none { // 낮잠에서 깬 화들짝 (조준 진입 시 리셋되므로 그 외엔 none)
                applyScoreReaction(&targetRig, t: currentTime - reactionAt)
            }
            // 진입 직후엔 느리게 → 연속 램프로 기민해진다 (계단식 속도 전환 = 가속 킥 = 움찔의 원인)
            rigRate = 5 + 8 * smoothstep(min(1, aimTime / 1.1))
        } else if mode == .ritual, let anim = ritualAnim {
            targetRig = ritualRig(anim)
            applySlopeStance(&targetRig) // 의식 중에도 발은 경사를 딛는다
            rigRate = 10
        } else if mode == .walking, let w = walkAnim, let tp = w.turn, w.t >= tp.start { // 제자리 돌기 (여운 중)
            targetRig = turnRig(tp, t: w.t)
            rigRate = 9
        } else if mode == .walking { // 피니시 여운 (relax) — 직립으로 느긋하게
            targetRig = RigBuilder.fromPose(Poses.upright, ballFwd: renderBallFwd, clubLen: renderLen)
            targetRig.shiftX(walkAnim?.relaxShift ?? 0) // 방향 반전 시 몸이 있는 자리에
            rigRate = 5
        } else {
            let ft = currentTime - finishAt
            var pose = lastFinishPose ?? profile.keys.p10
            let twirl = trademarkTwirl(ft: ft) // 타이거: 굿샷 뒤 리코일 → 트월
            if let tw = twirl {
                pose = Pose.lerp(pose, tw.recoil, tw.blend)
            }
            targetRig = RigBuilder.fromPose(pose, ballFwd: renderBallFwd, clubLen: renderLen)
            if let tw = twirl {
                targetRig.clubPhi += tw.spin
                if ft < 1.0 { // 스핀 창(0.45~0.9)만 고속 추적 — 느린 추적(5)은 회전에 π 넘게 뒤처져 되감긴다.
                    rigClubRate = 40 // 이후는 5로 복귀: 무빙 홀드 흔들림(0.18)이 rate 5 필터 전제라 40이면 2.4배 커진다 (리뷰)
                }
            }
            applySlopeStance(&targetRig) // 피니시 홀드 중에도 발은 경사를 딛는다 (리뷰 지적)
            applyFinishRecoil(&targetRig, ft: ft) // 로리 트레이드마크
            if mode == .holed || mode == .surprise || mode == .motion, reactionKind != .none { // 홀아웃·서프라이즈 반응
                applyScoreReaction(&targetRig, t: currentTime - reactionAt)
            }
            rigRate = uppercutActive ? 16 : twirl != nil ? 9 : 5
        }
        // 피니시 무빙 홀드: 완전 정지 대신 클럽이 관성으로 미세하게 흔들리다 잦아든다 (리서치 P6)
        if swingAnim == nil, mode == .motion || mode == .holed {
            let ft = currentTime - finishAt
            if ft > 0, ft < 3 {
                let osc: Double = sin(2 * Double.pi * 1.8 * ft)
                let decay: Double = exp(-ft * 2.2)
                targetRig.clubPhi += 0.18 * osc * decay
            }
        }
        // 걷기 중 발·무릎은 고속 추적 — 접지점이 스무딩에 밀려 미끄러져 보이는 것을 방지
        let footRate: Double? = mode == .walking && (walkAnim.map { $0.t >= $0.relax } ?? false) ? 60 : nil
        // 암록 퍼터: 퍼터를 쥐고 서 있는 동안(조준·스트로크·피니시 홀드·서프라이즈·라운드 끝) 그립 위로 샤프트가
        // 전완을 따라 올라간다. 걷기·의식만 0 (리뷰: 포함 목록 방식은 .surprise/.end에서 연장부가 스르륵 사라졌다)
        let holdsPutter = mode != .walking && mode != .ritual
        targetRig.butt = club.isPutter && holdsPutter ? profile.putt.butt : 0
        renderRig.chase(targetRig, rate: rigRate, footRate: footRate, clubRate: rigClubRate, dt: dt)

        // 경사 라이: 걷기 외에는 스탠스가 지면 경사를 따라 기운다 (물리와 동일 비율 — 3eccc4f 복원).
        // 벽 근처에선 억제 — 벽 경성 클램프가 무회전 평면을 가정하기 때문
        let tiltTarget = mode == .walking ? 0 : slopeTiltRatio * atan(hole.slope(at: stickX)) * (1 - renderWallT)
        renderSlopeTilt += (tiltTarget - renderSlopeTilt) * (1 - exp(-6 * dt))
        stickman.zRotation = CGFloat(renderSlopeTilt)
        // 렌더 반영 — 렌더 사본에 벽 경성 클램프 (스틱맨·클럽은 어떤 상태에서도 화면 밖에 그려지지 않는다)
        stickman.position = CGPoint(x: px(stickX), y: groundY(stickX))
        var drawRig = renderRig
        if !demoNoClamp {
            clampRigToWalls(&drawRig)
        }
        if demoMode {
            logRigBounds(drawRig, currentTime: currentTime)
        }
        // 뼈대 후처리: 뼈 길이 고정 + 무릎·팔꿈치 IK (발은 불변, 손은 사거리 안으로) — Skeleton.swift
        // 스윙·어드레스·피니시는 팔이 공(카메라) 쪽으로 향해 원근 단축되는 자세 — 팔꿈치 대신 호로 (Skeleton 주석)
        let projected = mode != .walking && mode != .ritual
        var joints = Skeleton.solve(
            &drawRig, curvedArms: projected, straightArms: swingStyle.straightArms, projected: projected
        )
        if !demoNoClamp {
            clampJointsToWalls(&joints)
        }
        if demoMode {
            logBones(joints, currentTime: currentTime)
            logJumps(drawRig, currentTime: currentTime)
            if demoTrademarkForce {
                logRigDump(drawRig, joints: joints, currentTime: currentTime)
            }
        }
        stickman.render(
            rig: drawRig, joints: joints, club: club, prevClub: prevHeadClub,
            headMorph: headMorph, visualLoft: renderLoft, dir: dir
        )

        // 홀인 드롭·서프라이즈·공 줍기 연출 중에는 SKAction이 공 위치를 갖는다
        let pickupOwns = mode == .ritual && ritualAnim?.kind == .ballPickup
        if pickupOwns, ballHeld, let anim = ritualAnim { // 공은 트레일 손에 — 던져 받기는 손 위로 포물선 (뼈대 처리 뒤 좌표라 사거리 클램프도 반영)
            let hand = CGPoint(
                x: stickman.position.x + drawRig.handTrail.x * CGFloat(dir),
                y: stickman.position.y + drawRig.handTrail.y
            )
            let s = max(0, (anim.t - RitualAnim.pickupGrab) / 1.35)
            let tossLift: CGFloat = pickupVariant == 0 ? 26 * CGFloat(sin(.pi * min(1, max(0, (s - 0.3) / 0.4)))) : 0
            ballNode.position = CGPoint(x: hand.x + CGFloat(dir) * 2, y: hand.y + 4 + tossLift)
            shadowNode.isHidden = true
        }
        if mode != .holed, mode != .surprise, !pickupOwns, tunnelTransit == nil { // 창 속 통과 중엔 공·그림자 숨김 유지
            var bx = ball.x, by = ball.y
            if var r = settleRoll { // 정착 굴림 — smoothstep으로 from→to, 지면을 따라
                r.t += dt
                let u = min(1, r.t / r.dur)
                bx = r.from + (r.to - r.from) * (u * u * (3 - 2 * u))
                by = hole.ground(at: bx)
                settleRoll = u >= 1 ? nil : r
            }
            ballNode.position = CGPoint(x: px(bx), y: py(by) + 5.5)
            let heightAbove = by - hole.ground(at: bx)
            shadowNode.isHidden = heightAbove <= 0.2
            shadowNode.position = CGPoint(x: px(bx), y: groundY(bx) - 1)
        }

        if trailPoints.count > 1 {
            let path = CGMutablePath()
            path.move(to: trailPoints[0])
            for p in trailPoints.dropFirst() {
                path.addLine(to: p)
            }
            trailNode.path = path
            trailUnderNode.path = path
        } else {
            trailNode.path = nil
            trailUnderNode.path = nil
        }

        // 조준 중 캐릭터 위: 클럽 약어 + 파워 (좌상단까지 시선 왕복 제거 — 2026-08-14 사용자 요청)
        powerLabel.setText("\(club.id) · \(Int(heightPct * 100))")
        powerLabel.isHidden = mode != .aim
        powerLabel.position = CGPoint(
            x: min(size.width - 54, max(54, px(stickX) - CGFloat(dir) * 20)), // 벽 옆에서도 잘리지 않게
            y: groundY(stickX) + 112
        )
    }
}

private extension GameScene {
    // ═══════════════════════════════════════════════════════════════
    // 골프 의식 (2026-08-29): CMU 모캡 64번 골프 세션 실측 이식
    // 티 꽂기 = 무릎 스쿼트(힙이 손 하강의 0.68 동반), 공 줍기 = 허리 힌지 + 뒷다리 들기
    // ═══════════════════════════════════════════════════════════════

    func startRitual(_ kind: RitualAnim.Kind) {
        var anim = RitualAnim(kind: kind)
        if kind == .teePlace {
            stickX = ball.x
            dir = hole.holeX >= ball.x ? 1 : -1
            ballNode.alpha = 0 // 공은 '심는' 순간 나타난다
        } else {
            // 컵의 로컬 x (facing 기준) — 손이 닿는 범위로 클램프
            anim.cupDx = min(26, max(8, Double(px(hole.holeX) - px(stickX)) * dir))
        }
        ritualAnim = anim
        mode = .ritual
        if demoMode {
            print("RITUAL \(kind)")
            fflush(stdout)
        }
    }

    func stepRitual(dt: Double) {
        guard var anim = ritualAnim else { return }
        anim.t += dt
        // 터치 이벤트: 작업 구간 중앙 — 티 꽂기는 공 등장, 줍기는 공이 손에 들려 올라옴
        let touchT = anim.kind == .teePlace ? 0.42 * anim.dur : 0.5 * RitualAnim.pickupGrab
        if !anim.touchFired, anim.t >= touchT {
            anim.touchFired = true
            let at = CGPoint(x: px(ball.x), y: groundY(ball.x))
            if anim.kind == .teePlace {
                ball = BallState(x: ball.x, y: hole.ground(at: ball.x))
                ballNode.removeAllActions()
                ballNode.setScale(0.6)
                ballNode.alpha = 1
                ballNode.run(.scale(to: 1, duration: 0.18))
                FX.dust(on: self, at: at, surface: .tee, intensity: 0.25)
                SoundKit.shared.bounce(speed: 1.2, surface: .green)
            } else {
                // 컵에서 공을 꺼내 든다 — 이후 공은 트레일 손을 따라간다 (렌더 단계, ballHeld). 구 연출은 공이 혼자 34px 솟았다 사라졌다
                let cup = CGPoint(x: px(hole.holeX), y: groundY(hole.holeX))
                ballNode.removeAllActions()
                ballNode.position = CGPoint(x: cup.x, y: cup.y - 4)
                ballNode.setScale(0.72)
                ballNode.alpha = 1
                ballNode.run(.scale(to: 1, duration: 0.25))
                ballHeld = true
                pickupVariant = Int.random(in: 0 ... 9) < 6 ? 0 : 1
                pickupCatchPlayed = false
                if demoMode {
                    print("PICKUP hold variant \(pickupVariant)")
                    fflush(stdout)
                }
            }
        }
        if anim.kind == .ballPickup, ballHeld { // 들고 보기 구간의 사건: 던져 받기 소리 · 주머니에 넣기
            let s = (anim.t - RitualAnim.pickupGrab) / 1.35
            if pickupVariant == 0, !pickupCatchPlayed, s >= 0.7 {
                pickupCatchPlayed = true
                SoundKit.shared.pluck()
            }
            if pickupVariant == 1, !pickupCatchPlayed, s >= 0.75 {
                pickupCatchPlayed = true
                ballNode.run(.fadeOut(withDuration: 0.15))
            }
        }
        if anim.t >= anim.dur {
            let kind = anim.kind
            ritualAnim = nil
            if kind == .teePlace {
                enterAim()
            } else {
                ballHeld = false
                ballNode.alpha = 0 // 주머니에 — 다음 티에서 다시 꺼낸다 (teePlace 의식)
                advanceHole()
            }
            return
        }
        ritualAnim = anim
    }

    /// 의식 리그 — 모캡 키포즈를 게임 리그 공간으로 옮긴 보간 (u: 0~1)
    func ritualRig(_ anim: RitualAnim) -> Rig {
        let u = anim.t / anim.dur
        var r = RigBuilder.fromPose(Poses.upright, ballFwd: renderBallFwd, clubLen: renderLen)
        if anim.kind == .teePlace {
            // 구간 25 / 50 / 25 (모캡 21/60/19의 작업부 압축).
            // 뼈 길이 고정(Skeleton) 이후 재작성: 팔이 늘어나 공에 닿던 것을 — 깊은 스쿼트 + 체중을
            // 앞발로 옮기고(힙 전진, 발은 고정) 상체를 45° 숙여 어깨가 공 사거리(35px) 안에 들게 한다
            let down = smoothstep(min(1, u / 0.25)) * (1 - smoothstep(max(0, (u - 0.75) / 0.25)))
            let squat = down
            r.hip.y -= 28 * squat // 42 → 14: 허벅지가 거의 수평인 스쿼트
            r.hip.x += (renderBallFwd - 9) * squat // 체중 앞발 — 클럽(ballFwd)과 무관하게 힙이 x≈-14에 (무릎은 IK가 접는다)
            r
                .shoulder = mix(
                    r.shoulder,
                    CGPoint(x: r.hip.x + 20, y: r.hip.y + 15),
                    squat
                ) // 전방 숙임 — 어깨가 공 사거리 안 (계측: DR에서 손 3.8px 부족 → 보정)
            r.headDy = mix(12, 9, squat)
            r.headDx = mix(r.headDx, 9, squat) // 공을 내려다본다
            // 자유손: 공 자리(바닥)로 — 작업 중 '꽂는' 잔손질
            let work = smoothstep(min(1, max(0, (u - 0.2) / 0.15))) * (1 - smoothstep(max(0, (u - 0.72) / 0.18)))
            let jiggle = sin(u * 34) * 1.2 * (u > 0.3 && u < 0.65 ? 1 : 0)
            r.handTrail = mix(
                r.handTrail,
                CGPoint(x: renderBallFwd - 2, y: 2 + jiggle),
                work
            )
            // 클럽 든 손은 지팡이처럼 옆에 짚는다 — 헤드가 지면에 닿는 각도로 뒤로 기울인다
            // (수직(-0.06)이면 긴 클럽 헤드가 지면 아래로 뚫고 들어갔다)
            let caneY = 28.0
            r.grip = mix(r.grip, CGPoint(x: r.hip.x - 9, y: caneY), squat)
            r.clubPhi = mix(r.clubPhi, -acos(min(1, caneY / renderLen)), squat)
        } else {
            // 공 줍기: 33/33/33 균등 (모캡) — 힙 고정, 허리 힌지, 뒷다리 들기.
            // 힌지를 조금 더 깊게(어깨 y 36→33): 뼈 길이 고정 후 손이 컵에 정확히 닿도록 (사거리 35)
            let u = min(1, anim.t / RitualAnim.pickupGrab) // 줍기 구간만 0~1 — 뒤의 들고 보기는 아래 s
            let hinge = smoothstep(min(1, u / 0.33)) * (1 - smoothstep(max(0, (u - 0.67) / 0.33)))
            r.hip.y -= 3 * hinge
            // 컵이 멀면(cupDx > 12) 힙을 그만큼 앞발 쪽으로 옮긴다 — 몸통 25 + 팔 35 사거리 안에 컵이 들도록
            // (리뷰 2026-09-14: cupDx 26이면 손이 7.5px 못 닿았다). 앞발은 고정, 뒷다리는 힙 상대라 함께 간다
            r.hip.x += max(0, anim.cupDx - 12) * hinge
            r.shoulder = mix(r.shoulder, CGPoint(x: r.hip.x + 21, y: 33), hinge)
            r.headDy = mix(12, 7, hinge)
            r.headDx = mix(r.headDx, 10, hinge)
            // 뒷다리 들기 (모캡 시그니처) — 앞다리는 지지
            r.foot1 = mix(r.foot1, CGPoint(x: r.hip.x - 20, y: 13), hinge)
            r.knee1 = mix(r.knee1, CGPoint(x: r.hip.x - 12, y: 26), hinge)
            r.handTrail = mix(r.handTrail, CGPoint(x: anim.cupDx, y: 1), hinge)
            // 클럽 팔은 뒤로 뻗어 카운터밸런스 (사거리 35 안: 계측에서 (−16, 42)는 4.8px 클램프)
            r.grip = mix(r.grip, CGPoint(x: r.hip.x - 11, y: 40), hinge)
            r.clubPhi = mix(r.clubPhi, -1.35, hinge)
            // 들고 보기 (2026-09-17): 일어선 뒤 공을 가슴 앞으로 들어 올려 내려다본다 → 툭 던져 받거나 주머니에 넣는다
            let s = max(0, (anim.t - RitualAnim.pickupGrab) / 1.35)
            if s > 0 {
                let lift = smoothstep(min(1, s / 0.22)) * (1 - smoothstep(max(0, (s - 0.82) / 0.18)))
                r.handTrail = mix(r.handTrail, CGPoint(x: r.shoulder.x + 13, y: r.shoulder.y - 6), lift)
                r.headDx = mix(r.headDx, 8, lift)
                r.headDy = mix(r.headDy, 10.5, lift) // 고개를 살짝 숙여 공을 본다
                if pickupVariant == 0 { // 던져 받기: 던질 때 손이 살짝 밀고, 받을 때 살짝 받쳐 내린다
                    let toss = sin(.pi * min(1, max(0, (s - 0.3) / 0.4)))
                    r.handTrail.y += 3 * toss * lift
                    r.headDy += 2 * toss * lift // 공을 따라 시선이 올라간다
                } else { // 주머니: 손이 힙 옆으로 내려간다
                    let pocket = smoothstep(min(1, max(0, (s - 0.5) / 0.25)))
                    r.handTrail = mix(r.handTrail, CGPoint(x: r.hip.x - 5, y: r.hip.y + 3), pocket)
                    r.headDx = mix(r.headDx, 4, pocket)
                }
            }
        }
        return r
    }
}
