import AppKit
import GolfCore
import SpriteKit

/// 게임 씬 — GolfCore 상태를 렌더하고 키보드 입력을 처리한다 (물리는 GolfCore)
/// 디자인: "조용한 계기판" — 상자 없는 타이포 HUD, 균일한 헤어라인 지형, 포인트 컬러는 깃발 하나
final class GameScene: SKScene {
    // 게임 상태
    private var course: [Hole] = []
    private var holeIdx = 0
    private var ball = BallState(x: CourseGenerator.teeX, y: 0)
    private var strokes = 0
    private var clubIdx = 0
    private var heightPct = 0.6
    private var results: [(par: Int, strokes: Int, gaveUp: Bool)] = []
    private enum Mode { case aim, swinging, motion, walking, holed, end, surprise }
    private var mode = Mode.aim
    private var dir = 1.0
    private var heldKeys = Set<UInt16>()
    private var lastTime: TimeInterval = 0
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
    var demoMotionShowcase = false // --demo-motions: 모션 100종 순서 시연 — 카탈로그 캡처용 (디버그 전용)
    var demoShowpieceForce = false // --demo-memes: 걷기마다 쇼피스 1개, 12종 순환 (카탈로그 캡처용)
    var demoSurpriseForce = false // --demo-surprise: 샷마다 서프라이즈 (관찰용)
    var surpriseCursor = 0
    private var motionCursor = 0
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
        var t = 0.0
        let relax = 0.8 // 피니시 여운 — 서두르지 않는다
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
    }

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
    private var aimTime = 0.0 // 조준 진입 후 경과 — 진입 직후엔 천천히 가라앉는다
    private var renderWallT = 0.0 // 벽 스탠스 근접도 (스무딩) — 뒷발 벽 딛기 자세 블렌드
    private var renderTreeT = 0.0 // 나무 캐노피 근접도 (스무딩) — 웅크린 펀치 자세 블렌드
    private var finishAt: TimeInterval = 0 // 피니시 도달 시각 — 무빙 홀드 감쇠 진동 기준
    /// 홀아웃 직후 스틱맨의 스코어 반응 (QA·Whimsy 리뷰 — 결과에 감정을 싣는다)
    private enum ReactionKind { case none, rejoice, fistPump, nod, slump, dejected }
    private var reactionKind = ReactionKind.none
    private var reactionAt: TimeInterval = 0
    /// 조준 방치 시 잔동작 (아이들) — 곁눈질했을 때도 스틱맨이 살아 있다
    private var idleNextAt = 6.0
    private var idleKind = 0
    private var idleStart = 0.0
    private var stickX = CourseGenerator.teeX
    private var trailPoints: [CGPoint] = []
    private var didSetUp = false // didMove 완료 전 didChangeSize 가드 (모니터 전환)
    private var shotBumpers: [Bumper] = [] // 창 범퍼 — 샷 순간 스냅샷, 비행 동안 고정
    private var shotHitBumper = false // 이 샷에서 범퍼를 맞았나 — 뱅크샷 홀인 배지 판정
    private var roundHadWater = false // 무입수 라운드 배지 판정

    private var hole: Hole {
        course[holeIdx]
    }

    private var club: Club {
        ClubTable.all[clubIdx]
    }

    private var profile: SwingProfile {
        SwingProfile.profile(for: club.cat)
    }

    private var pxPerM: CGFloat {
        size.width / hole.worldW
    }

    private var groundBase: CGFloat = 96 // 홀 최저 표고에 맞춰 rebuildTerrain에서 보정 (HUD 침범 방지)
    /// 경사 라이: 스탠스 기울기 = 로프트 전달 비율 — 단일 출처는 Phys (리뷰 S-6)
    private let slopeTiltRatio = Phys.stanceSlopeRatio
    private var renderSlopeTilt = 0.0 // 경사 스탠스 기울기 (스무딩)

    // 노드
    private let terrainNode = SKNode()
    private let stickman = StickmanNode()
    private let ballNode = SKShapeNode(circleOfRadius: 5.5)
    private let shadowNode = SKShapeNode(ellipseOf: CGSize(width: 15, height: 4.5))
    private let trailNode = SKShapeNode()
    private let trailUnderNode = SKShapeNode() // 궤적 언더스트로크 (밝은 배경 대비)
    private let flagNode = SKNode()
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

    private func px(_ m: Double) -> CGFloat {
        CGFloat(m) * pxPerM
    }

    private func py(_ elev: Double) -> CGFloat {
        groundBase + CGFloat(elev) * pxPerM
    }

    private func groundY(_ xm: Double) -> CGFloat {
        py(hole.ground(at: xm))
    }

    override func didMove(to _: SKView) {
        backgroundColor = .clear // ⚠️ skView.backgroundColor는 설정 금지

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
        holeIdx = 0
        results = []
        roundHadWater = false
        scorecard.hide()
        startHole()
    }

    private func startHole() {
        strokes = 0
        // 티샷 기본 클럽: 파4·5 드라이버, 파3 7번 아이언 (관례 — 2026-08-15 사용자 요청. ←→ 변경 자유)
        let teeClub = hole.par == 3 ? "7I" : "DR"
        clubIdx = ClubTable.all.firstIndex { $0.id == teeClub } ?? 0
        ball = BallState(x: hole.teeX, y: hole.ground(at: hole.teeX)) // 미러 홀은 오른쪽 티에서 시작
        if demoWallForce { // 벽 스탠스 관찰: 릴리프 하한(46px) 직후의 최소 이격 케이스로 시작
            let m = 48 / Double(pxPerM)
            let x = hole.holeX > hole.teeX ? m : hole.worldW - m
            ball = BallState(x: x, y: hole.ground(at: x))
        }
        trailPoints = []
        swingAnim = nil
        walkAnim = nil
        ballNode.removeAllActions() // 홀인 드롭 연출 복구
        ballNode.alpha = 1
        ballNode.setScale(1)
        rebuildTerrain()
        if demoMode, let sig = hole.signature { // 캡처 대조용 계측 (관찰용)
            print("SIGNATURE \(sig.rawValue)")
            fflush(stdout)
        }
        enterAim()
    }

    private func enterAim() {
        mode = .aim
        aimTime = 0
        reactionKind = .none
        idleKind = 0
        idleNextAt = Double.random(in: 5 ... 9)
        walkAnim = nil
        stickX = ball.x
        dir = hole.holeX >= ball.x ? 1 : -1
        // 그린에 올라오면 퍼터로 자동 전환 (관례 — 이후 ←→로 자유 변경 가능)
        if strokes > 0, hole.surface(at: ball.x) == .green, !club.isPutter {
            clubIdx = ClubTable.all.firstIndex { $0.isPutter } ?? clubIdx
        }
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
    private func clampRigToWalls(_ rig: inout Rig) {
        let sx = Double(px(stickX))
        let margin = 8.0
        let a = (margin - sx) / dir
        let b = (Double(size.width) - margin - sx) / dir
        let lo = min(a, b), hi = max(a, b)
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

    /// 홀아웃 스코어 반응 — 피니시 홀드 위에 얹는 짧은 감정 표현 (0.15~1.5s).
    /// 공이 컵에 들어가는 걸 '본 다음' 반응한다 (인과 — 드롭 연출 0.24s 이후 시작)
    private func applyScoreReaction(_ rig: inout Rig, t: Double) {
        guard t > 0.15, t < 1.5 else { return }
        let u = (t - 0.15) / 1.35
        let bell = smoothstep(min(1, min(u, 1 - u) / 0.25))
        switch reactionKind {
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

    private func startWalk() {
        endShotTrail()
        let from = stickX, to = ball.x
        let dist = abs(to - from)
        mode = .walking
        if dist > 0.5 { // 아주 짧은 이동은 방향 유지 (제자리 반걸음)
            dir = to >= from ? 1 : -1
        }
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
        var anim = WalkAnim(
            fromX: from, toX: to,
            dur: min(14.0, max(1.2, dist / 10 * (1 + 0.4 * hardness)))
        )
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
        // 랜덤 잉여 동작: 긴 이동은 어깨 캐리 + 100종 모션을 겹치지 않게 흩뿌린다
        if anim.dur > 4.5, Double.random(in: 0 ..< 1) < 0.5 {
            anim.shoulderRange = (anim.relax + 0.8) ... (anim.relax + anim.dur * 0.72)
        }
        var t = anim.relax + 0.7
        while t < anim.relax + anim.dur - 1.2, anim.flavorEvents.count < 5 {
            guard Double.random(in: 0 ..< 1) < 0.5 else {
                t += 1.1
                continue
            }
            let kind = WalkFlavorKind.allCases.randomElement()!
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
        if demoMotionShowcase { // 카탈로그 캡처: 랜덤 대신 100종을 커서 순서로, 트립·어깨 캐리 없이
            anim.flavorEvents = []
            anim.shoulderRange = nil
            anim.tripAt = nil
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
        walkAnim = anim
        updateHUD()
    }

    private func startSwing() {
        mode = .swinging
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
        // 풀파워 리스크: 모든 샷에 베이스 분산(±1°) + 80% 초과분^1.6의 리스크, 정규분포 근사
        // (uniform 3개 평균 ≈ 가우시안 — 큰 미스는 드물고 작은 흔들림이 대부분, 리서치 E)
        let overdrive = max(0, (heightPct - 0.8) / 0.2)
        let risk = 0.25 + 0.75 * pow(overdrive, 1.6)
        let gauss = (Double.random(in: -1 ... 1) + Double.random(in: -1 ... 1) + Double.random(in: -1 ... 1)) / 3
        let mishit = club.isPutter ? 0 : risk * gauss
        // 벽·나무 근접 = 펀치샷: 파워는 그대로, 낮은 탄도·적은 스핀으로 (컴팩트 폼의 물리적 귀결)
        // 경사 라이는 스탠스 기울기와 같은 비율(0.7)만 로프트로 전달 — 물리·애니메이션 정합
        let slope = club.isPutter ? 0 : hole.slope(at: ball.x) * slopeTiltRatio
        Ballistics.launch(
            &ball, club: club, heightPct: heightPct, lie: lie, dir: dir,
            mishit: mishit, punch: max(wallPunch, treePunchT * 0.85), slope: slope
        )
        shotHitBumper = false
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
        strokes += 1
        if !club.isPutter { // 임팩트 타격감: 공 신장 + 헤드 스미어 (퍼터는 조용히)
            // 히트스톱은 실플레이에서 '렉'으로 읽혀 제거 (2026-08-14 사용자 판정 —
            // 골프처럼 한 번의 연속 동작에선 정지가 타격감이 아니라 프레임 드랍으로 보인다)
            ballNode.zRotation = CGFloat(atan2(ball.vy, ball.vx))
            ballNode.xScale = 1.4
            ballNode.yScale = 0.72
            ballNode.run(.sequence([
                .group([.scaleX(to: 1, duration: 0.14), .scaleY(to: 1, duration: 0.14)]),
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
        SoundKit.shared.impact(cat: club.cat, lie: lie, power: heightPct)
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
    private func endShotTrail() {
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
        mode = .holed
        results.append((hole.par, strokes, false))
        endShotTrail()
        SoundKit.shared.holeIn()
        dropBallIntoCup()
        // 스코어 감정 계층 (QA·Whimsy 리뷰): 좋은 결과일수록 토스트가 크고, 스틱맨이 반응한다
        let diff = strokes == 1 ? -3 : strokes - hole.par // 홀인원은 최상급 취급
        reactionKind = diff <= -2 ? .rejoice : diff == -1 ? .fistPump : diff == 0 ? .nod : .slump
        reactionAt = lastTime
        if diff <= -2 { // 이글·홀인원: 홀인음 뒤에 상승 차임이 얹힌다
            run(.sequence([.wait(forDuration: 0.35), .run { SoundKit.shared.chime() }]))
        }
        if demoMode {
            print("HOLED diff \(diff)")
            fflush(stdout)
        }
        toast(
            scoreName(strokes: strokes, par: hole.par),
            sub: "\(strokes)타 · 파 \(hole.par) · \(Int(hole.dist))m",
            overFlag: true,
            titleScale: diff <= -2 ? 1.3 : diff == -1 ? 1.12 : diff <= 0 ? 1.0 : 0.88
        )
        recordHoleOut(diff: diff)
        run(.sequence([.wait(forDuration: 1.7), .run { [weak self] in self?.advanceHole() }]))
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
        } else {
            startWalk()
        }
    }

    private func giveUp() {
        mode = .holed
        results.append((hole.par, Phys.maxStrokes, true))
        endShotTrail()
        reactionKind = .dejected
        reactionAt = lastTime
        toast("기권", sub: "\(Phys.maxStrokes)타 초과", titleScale: 0.88)
        run(.sequence([.wait(forDuration: 1.4), .run { [weak self] in self?.advanceHole() }]))
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
    private func toast(
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

    private func updateHUD() {
        let total = results.reduce(0) { $0 + ($1.strokes - $1.par) }
        let totalStr = total > 0 ? "+\(total)" : total == 0 ? "E" : "\(total)"
        let remain = abs(hole.holeX - ball.x)
        let lie = strokes == 0 ? Surface.tee : hole.surface(at: ball.x)
        scoreTitle.setText("\(holeIdx + 1)번 홀 · 파 \(hole.par)")
        scoreSub.setText("타수 \(strokes) · 합계 \(totalStr) · \(lie.label) · \(Int(remain))m")
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
        guard mode == .aim, !isGamePaused else { return }
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
                if demoWait > (demoIdleForce ? 25 : 1.2) { // 아이들 관찰 모드는 조준을 길게 유지
                    demoWait = 0
                    // 벽 관찰 모드는 최악 케이스(풀 백스윙)로
                    heightPct = demoWallForce ? Double.random(in: 0.9 ... 1.0) : Double.random(in: 0.5 ... 0.85)
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

        if mode == .aim {
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

        if mode == .walking, var w = walkAnim {
            w.t += dt
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
            if freeze > 0 {
                w.pausedTime += dt * freeze // 걸음 시계는 동결 비율만큼만 멈춘다
            }
            let tw = w.t - w.relax - w.pausedTime
            if tw >= 0 {
                let u = min(1, tw / w.dur)
                stickX = w.fromX + (w.toX - w.fromX) * smoothstep(u)
                // 유효 속도 = 해석 미분 × (1 - freeze) — 위치와 게이트가 같은 비율로 감속·재가속
                let vInst = (1 - freeze) * abs(w.toX - w.fromX) * 6 * u * (1 - u) / w.dur
                w.vPx = vInst * Double(pxPerM)
                // 게이트 갱신: 보폭·듀티는 속도 함수, 접지점은 리프트오프 순간 래치 (노슬립)
                w.stepL = 22 * min(1, max(0.5, (w.vPx / 30).squareRoot()))
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
                if !w.gaitReady {
                    w.gaitReady = true
                    w.feet[0].plant = dNow + 8 // 어드레스 발 위치 근처에서 시작
                    w.feet[1].plant = dNow - 10
                }
                w.gaitPhase += w.vPx * dt / (2 * w.stepL)
                for i in 0 ..< 2 {
                    let f = (w.gaitPhase + (i == 1 ? 0.5 : 0)).truncatingRemainder(dividingBy: 1)
                    if f < w.duty {
                        if w.feet[i].inSwing { // 착지 — 목표점에 래치
                            w.feet[i].inSwing = false
                            w.feet[i].plant = w.feet[i].swingTo
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
                walkAnim = w
                if u >= 1 {
                    enterAim()
                }
            } else {
                walkAnim = w
            }
        }

        if mode == .motion {
            acc += dt * timeScale
            var terminal = StepEvent.none
            var landing: (speed: Double, surface: Surface, x: Double)?
            var wallHit: (speed: Double, x: Double)?
            var bumperHit: (speed: Double, x: Double, y: Double)?
            var lipped = false
            while acc >= Phys.dt {
                acc -= Phys.dt
                let event = Ballistics.step(&ball, hole: hole, bumpers: shotBumpers)
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
                if terminal != .none {
                    break
                }
            }
            if let l = landing, l.speed > 1.4 {
                SoundKit.shared.bounce(speed: l.speed, surface: l.surface)
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
            }
            trailPoints.append(CGPoint(x: px(ball.x), y: py(ball.y) + 5.5))
            if trailPoints.count > 400 {
                trailPoints.removeFirst()
            }
            switch terminal {
            case .holed: onHoled()
            case .water: onWater()
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
                    if strokes >= Phys.maxStrokes {
                        giveUp()
                    } else if let kind = rollSurprise() {
                        playSurprise(kind)
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
        renderLen += (club.renderLength - renderLen) * clubK
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
        } else if mode == .walking, let w = walkAnim, w.t >= w.relax {
            var flavor = WalkFlavor()
            if let r = w.shoulderRange { // 0.6초에 걸쳐 어깨에 올렸다 내린다
                let up = min(1, max(0, (w.t - r.lowerBound) / 0.6))
                let down = min(1, max(0, (r.upperBound - w.t) / 0.6))
                flavor.shoulder = smoothstep(min(up, down))
            }
            // 모션 레시피는 WalkFlavorKind.apply(100종 — WalkFlavors.swift)가 채널에 합산한다
            for e in w.flavorEvents {
                let u = (w.t - e.t0) / e.dur
                guard u > 0 else { continue }
                if demoMotionShowcase, w.t - dt < e.t0 { // 시작 프레임 — 캡처 워처에 위치 통지
                    let info = "\(e.kind) \(Int(px(stickX))) \(Int(groundY(stickX)))"
                    try? info.write(toFile: "/tmp/minigolf-motion.txt", atomically: true, encoding: .utf8)
                    print("MOTION \(info)")
                    fflush(stdout)
                }
                e.kind.apply(u: u, into: &flavor)
            }
            // 잔동작 진폭 부스트 (2026-08-20 사용자: "동작이 완전 커야") — 잔동작만.
            // 쇼피스·트립·지형 적응은 이 뒤에 얹혀 원설계 크기 유지
            flavor.boostMotion(1.7)
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
                            let info = "\(sk.rawValue) \(Int(px(stickX))) \(Int(groundY(stickX)))"
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
            // 진입 직후엔 느리게 → 연속 램프로 기민해진다 (계단식 속도 전환 = 가속 킥 = 움찔의 원인)
            rigRate = 5 + 8 * smoothstep(min(1, aimTime / 1.1))
        } else if mode == .walking { // 피니시 여운 (relax) — 직립으로 느긋하게
            targetRig = RigBuilder.fromPose(Poses.upright, ballFwd: renderBallFwd, clubLen: renderLen)
            rigRate = 5
        } else {
            targetRig = RigBuilder.fromPose(lastFinishPose ?? Poses.p10, ballFwd: renderBallFwd, clubLen: renderLen)
            applySlopeStance(&targetRig) // 피니시 홀드 중에도 발은 경사를 딛는다 (리뷰 지적)
            if mode == .holed, reactionKind != .none {
                applyScoreReaction(&targetRig, t: currentTime - reactionAt)
            }
            rigRate = 5
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
        stickman.render(
            rig: drawRig, club: club, prevClub: prevHeadClub,
            headMorph: headMorph, visualLoft: renderLoft, dir: dir
        )

        if mode != .holed, mode != .surprise { // 홀인 드롭·서프라이즈 연출 중에는 SKAction이 공 위치를 갖는다
            ballNode.position = CGPoint(x: px(ball.x), y: py(ball.y) + 5.5)
            let heightAbove = ball.y - hole.ground(at: ball.x)
            shadowNode.isHidden = heightAbove <= 0.2
            shadowNode.position = CGPoint(x: px(ball.x), y: groundY(ball.x) - 1)
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

enum SurpriseKind: String, CaseIterable {
    case birdSteal // 새가 공을 물고 날아가 랜덤 지점에 드롭
    case moleNudge // 두더지가 쏙 나와 공을 톡 밀고 사라진다
}

extension GameScene {
    /// 샷 종료 시 호출 — 발동이면 종류 반환. 홀인 직전(그린 위)은 제외 (부당함 방지)
    func rollSurprise() -> SurpriseKind? {
        guard hole.surface(at: ball.x) != .green else { return nil }
        if demoSurpriseForce {
            surpriseCursor += 1
            return SurpriseKind.allCases[surpriseCursor % SurpriseKind.allCases.count]
        }
        guard Double.random(in: 0 ..< 1) < 0.025 else { return nil } // 라운드에 한 번 볼까 말까
        return SurpriseKind.allCases.randomElement()
    }

    func playSurprise(_ kind: SurpriseKind) {
        mode = .surprise
        if demoMode {
            print("SURPRISE \(kind.rawValue) @\(Int(ball.x))")
            fflush(stdout)
        }
        switch kind {
        case .birdSteal: playBirdSteal()
        case .moleNudge: playMoleNudge()
        }
    }

    /// ── 새 도둑: 유불리 랜덤 드롭 (골프 규칙 18-1 '외부 요인' — 놓인 자리에서 플레이) ──
    private func playBirdSteal() {
        let bird = makeBird()
        let ballPos = CGPoint(x: px(ball.x), y: groundY(ball.x) + 5.5)
        // 드롭 지점: 홀 방향 ±35m 랜덤 — 도움일 수도, 배신일 수도
        let delta = Double.random(in: -35 ... 35)
        var dropX = ball.x + delta
        dropX = min(max(dropX, 8), hole.worldW - 8)
        if hole.surface(at: dropX) == .water { // 물에는 안 떨어뜨린다 (벌타 사건은 과함)
            dropX = ball.x - delta.magnitude * 0.4
        }
        let dropPos = CGPoint(x: px(dropX), y: groundY(dropX) + 5.5)
        let entryY = size.height * 0.86
        bird.position = CGPoint(x: ballPos.x < size.width / 2 ? size.width + 40 : -40, y: entryY)
        addChild(bird)

        let swoopIn = SKAction.move(to: ballPos, duration: 0.9)
        swoopIn.timingMode = .easeInEaseOut
        let carry = SKAction.move(to: CGPoint(x: dropPos.x, y: dropPos.y + 130), duration: 1.1)
        carry.timingMode = .easeInEaseOut
        let exitX = bird.position.x // 들어온 쪽으로 되돌아 나간다
        let leave = SKAction.move(to: CGPoint(x: exitX, y: size.height * 0.95), duration: 0.9)
        leave.timingMode = .easeIn

        reactionKind = .dejected // 스틱맨: 아니 내 공…
        reactionAt = lastTime
        toast("새가 공을 물어갔다!", sub: nil)
        bird.run(.sequence([
            swoopIn,
            .run { [weak self] in // 낚아채기 — 공이 새를 따라간다
                guard let self else { return }
                SoundKit.shared.wall(speed: 3)
                ballNode.removeAllActions()
                ballNode.run(SKAction.customAction(withDuration: 2.0) { [weak self, weak bird] node, _ in
                    guard let bird else { return }
                    node.position = CGPoint(x: bird.position.x, y: bird.position.y - 9)
                    self?.shadowNode.isHidden = true
                })
            },
            carry,
            .run { [weak self] in // 드롭
                guard let self else { return }
                ball = BallState(x: dropX, y: hole.ground(at: dropX))
                ballNode.removeAllActions()
                let fall = SKAction.move(to: dropPos, duration: 0.42)
                fall.timingMode = .easeIn
                ballNode.run(.sequence([fall, .run { [weak self] in
                    guard let self else { return }
                    SoundKit.shared.bounce(speed: 3, surface: hole.surface(at: dropX))
                    FX.dust(on: self, at: dropPos, surface: hole.surface(at: dropX), intensity: 0.4)
                }]))
            },
            leave,
            .removeFromParent(),
            .run { [weak self] in self?.finishSurprise() },
        ]))
        // 날갯짓 — 위아래 파닥임
        bird.run(.repeatForever(.sequence([
            .scaleY(to: 0.55, duration: 0.12), .scaleY(to: 1.0, duration: 0.12),
        ])))
    }

    /// ── 두더지: 공을 1~3m 톡 — 사소한 참견 ──
    private func playMoleNudge() {
        let mole = makeMole()
        let side: Double = Bool.random() ? 1 : -1
        let moleX = ball.x - side * 1.2
        mole.position = CGPoint(x: px(moleX), y: groundY(moleX) - 14)
        mole.setScale(0.1)
        addChild(mole)
        let popUp = SKAction.group([
            SKAction.move(to: CGPoint(x: px(moleX), y: groundY(moleX) + 4), duration: 0.3),
            SKAction.scale(to: 1, duration: 0.3),
        ])
        popUp.timingMode = .easeOut
        let nudgeDist = side * Double.random(in: 1.2 ... 3.0)
        let newX = min(max(ball.x + nudgeDist, 6), hole.worldW - 6)
        let sink = SKAction.group([
            SKAction.move(to: CGPoint(x: px(moleX), y: groundY(moleX) - 14), duration: 0.25),
            SKAction.scale(to: 0.1, duration: 0.25),
        ])
        sink.timingMode = .easeIn

        toast("두더지!", sub: nil)
        mole.run(.sequence([
            popUp,
            .wait(forDuration: 0.35),
            .run { [weak self] in // 톡 — 공이 짧게 굴러간다
                guard let self else { return }
                SoundKit.shared.bounce(speed: 2, surface: hole.surface(at: ball.x))
                ball = BallState(x: newX, y: hole.ground(at: newX))
                let roll = SKAction.move(
                    to: CGPoint(x: px(newX), y: groundY(newX) + 5.5), duration: 0.5
                )
                roll.timingMode = .easeOut
                ballNode.run(roll)
            },
            .wait(forDuration: 0.5),
            sink,
            .removeFromParent(),
            .run { [weak self] in self?.finishSurprise() },
        ]))
    }

    private func finishSurprise() {
        guard mode == .surprise else { return } // 새 라운드 등으로 이미 전환됐으면 무시
        startWalk()
    }

    /// ── 생물 셰이프: 게임 회색 실루엣 문법 ──
    private func makeBird() -> SKNode {
        let bird = SKNode()
        let body = SKShapeNode(ellipseOf: CGSize(width: 16, height: 9))
        body.fillColor = NSColor(white: 0.82, alpha: 0.95)
        body.strokeColor = .clear
        let wing = SKShapeNode()
        let wp = CGMutablePath()
        wp.move(to: CGPoint(x: -10, y: 6))
        wp.addLine(to: CGPoint(x: -1, y: 1))
        wp.addLine(to: CGPoint(x: 8, y: 6))
        wing.path = wp
        wing.strokeColor = NSColor(white: 0.82, alpha: 0.95)
        wing.lineWidth = 2.4
        wing.lineCap = .round
        let beak = SKShapeNode()
        let bp = CGMutablePath()
        bp.move(to: CGPoint(x: 8, y: 1))
        bp.addLine(to: CGPoint(x: 13, y: -1))
        beak.path = bp
        beak.strokeColor = NSColor(white: 0.7, alpha: 0.95)
        beak.lineWidth = 2
        beak.lineCap = .round
        bird.addChild(body)
        bird.addChild(wing)
        bird.addChild(beak)
        bird.zPosition = 5
        return bird
    }

    private func makeMole() -> SKNode {
        let mole = SKNode()
        let head = SKShapeNode()
        let hp = CGMutablePath()
        hp.addArc(
            center: .zero, radius: 9,
            startAngle: 0, endAngle: .pi, clockwise: false
        )
        hp.closeSubpath()
        head.path = hp
        head.fillColor = NSColor(white: 0.55, alpha: 0.95)
        head.strokeColor = .clear
        let nose = SKShapeNode(circleOfRadius: 2.2)
        nose.position = CGPoint(x: 0, y: 8)
        nose.fillColor = NSColor(white: 0.35, alpha: 0.95)
        nose.strokeColor = .clear
        mole.addChild(head)
        mole.addChild(nose)
        mole.zPosition = 4
        return mole
    }
}
