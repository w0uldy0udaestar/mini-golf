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
    private enum Mode { case aim, swinging, motion, walking, holed, end }
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
    private var stickX = CourseGenerator.teeX
    private var trailPoints: [CGPoint] = []

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

        // HUD는 지면 아래 스트립(0~96px 빈 띠) — 시선이 플레이 지점을 떠나지 않는다 (2026-08-14 사용자 결정)
        scoreTitle.position = CGPoint(x: size.width - 24, y: 66)
        scoreSub.position = CGPoint(x: size.width - 24, y: 40)
        clubTitle.position = CGPoint(x: 24, y: 66)
        clubSub.position = CGPoint(x: 24, y: 40)
        hintLabel.position = CGPoint(x: size.width / 2, y: 60)
        hintLabel.setText("←→ 클럽 · ↑↓ 백스윙 · Space 스윙 · R 새 라운드 · Esc 종료")
        pauseLabel.position = CGPoint(x: size.width / 2, y: size.height - 46) // 일시정지 배너만 상단(⛳️ 버튼 곁)
        pauseLabel.setText("일시정지 — 메뉴바 ⛳️ 클릭으로 재개")
        pauseLabel.isHidden = true
        toastTitle.position = CGPoint(x: size.width / 2, y: size.height * 0.64)
        toastSub.position = CGPoint(x: size.width / 2, y: size.height * 0.64 - 42)
        toastTitle.alpha = 0
        toastSub.alpha = 0
        scorecard.position = CGPoint(x: size.width / 2, y: size.height / 2)
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
        if demoCardPreview { // 스코어카드 레이아웃 검증용 고정 샘플 (이글·버디·파·보기·더블·기권 포함)
            let sample: [(par: Int, strokes: Int, gaveUp: Bool)] = [
                (4, 4, false), (3, 2, false), (4, 5, false), (5, 3, false), (4, 4, false),
                (3, 6, false), (4, 12, true), (5, 5, false), (4, 3, false),
            ]
            scorecard.show(results: sample, title: "라운드 종료", footer: "합계 +7 · 흐린 숫자 = 기권  —  R로 새 라운드")
        }
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
        enterAim()
    }

    private func enterAim() {
        mode = .aim
        aimTime = 0
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
        // 완전 여유로운 걸음 — 실제 골퍼처럼 서두르지 않는다
        var anim = WalkAnim(fromX: from, toX: to, dur: min(12.0, max(1.2, dist / 10)))
        // 랜덤 잉여 동작: 긴 이동은 어깨 캐리 + 20종 모션을 겹치지 않게 흩뿌린다
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
            anim.flavorEvents.append(WalkFlavorEvent(kind: kind, t0: t, dur: dur))
            t += dur + Double.random(in: 0.8 ... 2.2)
        }
        if demoMode, !anim.flavorEvents.isEmpty { // 프레임 캡처와 대조할 모션 계측 (관찰용)
            let list = anim.flavorEvents
                .map { "\($0.kind)@\(String(format: "%.1f", $0.t0))" }
                .joined(separator: " ")
            print("FLAVOR \(list)")
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
        toast(
            scoreName(strokes: strokes, par: hole.par),
            sub: "\(strokes)타 · 파 \(hole.par) · \(Int(hole.dist))m",
            overFlag: true
        )
        run(.sequence([.wait(forDuration: 1.7), .run { [weak self] in self?.advanceHole() }]))
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
        toast("기권", sub: "\(Phys.maxStrokes)타 초과")
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
        }
    }

    /// 토스트 — 기본은 화면 중앙, overFlag는 깃발 위 (홀인 스코어는 사건 지점에서 읽힌다 —
    /// 2026-08-15 사용자 요청 3번). 깃발이 화면 끝이면 잘리지 않게 안쪽으로 당긴다
    private func toast(_ main: String, sub: String? = nil, overFlag: Bool = false) {
        if overFlag {
            let x = min(size.width - 150, max(150, px(hole.holeX)))
            let baseY = groundY(hole.holeX) + 62 // 깃대 끝
            toastTitle.position = CGPoint(x: x, y: baseY + 64)
            toastSub.position = CGPoint(x: x, y: baseY + 26)
        } else {
            toastTitle.position = CGPoint(x: size.width / 2, y: size.height * 0.64)
            toastSub.position = CGPoint(x: size.width / 2, y: size.height * 0.64 - 42)
        }
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
        clubSub.setText(club.cat == .wood ? "우드" : club.cat == .iron ? "아이언" : club.cat == .wedge ? "웨지" : "퍼터")
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
                if demoWait > 1.2 {
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
            let tw = w.t - w.relax
            if tw >= 0 {
                let u = min(1, tw / w.dur)
                stickX = w.fromX + (w.toX - w.fromX) * smoothstep(u)
                let vInst = abs(w.toX - w.fromX) * 6 * u * (1 - u) / w.dur
                w.vPx = vInst * Double(pxPerM)
                // 게이트 갱신: 보폭·듀티는 속도 함수, 접지점은 리프트오프 순간 래치 (노슬립)
                w.stepL = 22 * min(1, max(0.5, (w.vPx / 30).squareRoot()))
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
            var lipped = false
            while acc >= Phys.dt {
                acc -= Phys.dt
                let event = Ballistics.step(&ball, hole: hole)
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
                e.kind.apply(u: u, into: &flavor)
            }
            // 발 위치: 접지발 = 래치된 접지점 그대로, 스윙발 = 고정된 목표로 보간 (노슬립)
            let dPx = abs(stickX - w.fromX) * Double(pxPerM)
            let vAmp = min(1, w.vPx / 30)
            func footPose(_ i: Int) -> (x: Double, lift: Double) {
                let f = (w.gaitPhase + (i == 1 ? 0.5 : 0)).truncatingRemainder(dividingBy: 1)
                let g = w.feet[i]
                if !g.inSwing {
                    return (g.plant - dPx, 0)
                }
                let sw = max(0, (f - w.duty) / (1 - w.duty))
                // sin² 프로파일: 이륙·착지 모두 속도 0 (발 '찍기' 제거)
                let lift = sin(.pi * sw) * sin(.pi * sw) * (3 + 5 * vAmp + 6 * flavor.skip)
                return (mix(g.swingFrom, g.swingTo, smoothstep(sw)) - dPx, lift)
            }
            targetRig = RigBuilder.walking(
                f1: footPose(0), f2: footPose(1), gaitPhase: w.gaitPhase,
                vPx: w.vPx, clubLen: renderLen, flavor: flavor
            ) { dx in
                let xm = self.stickX + dx / Double(self.pxPerM)
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
            // 진입 직후엔 느리게 → 연속 램프로 기민해진다 (계단식 속도 전환 = 가속 킥 = 움찔의 원인)
            rigRate = 5 + 8 * smoothstep(min(1, aimTime / 1.1))
        } else if mode == .walking { // 피니시 여운 (relax) — 직립으로 느긋하게
            targetRig = RigBuilder.fromPose(Poses.upright, ballFwd: renderBallFwd, clubLen: renderLen)
            rigRate = 5
        } else {
            targetRig = RigBuilder.fromPose(lastFinishPose ?? Poses.p10, ballFwd: renderBallFwd, clubLen: renderLen)
            applySlopeStance(&targetRig) // 피니시 홀드 중에도 발은 경사를 딛는다 (리뷰 지적)
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

        if mode != .holed { // 홀인 드롭 연출 중에는 SKAction이 공 위치를 갖는다
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
