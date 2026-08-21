import GolfCore
import SpriteKit

/// 클럽별 렌더 속성 — 클럽만 보고도 무엇을 들었는지 알 수 있게 (물리와 무관, 연출 전용)
extension Club {
    /// 렌더 길이(px): 실클럽 비례 — 드라이버가 가장 길고 퍼터가 가장 짧다.
    /// 상한은 어드레스 기하(handD 하한 16에서 헤드가 지면에 닿는 길이 ≈ 51)가 결정
    /// (2026-08-15 사용자 판정: 전체가 짧고 클럽별 차이가 안 읽힘 → 길이·스프레드 확대)
    var renderLength: Double {
        switch id {
        case "DR": 51
        case "3W": 49
        case "5W": 47.5
        case "PT": 34
        default: 46 - (loft - 21) * 8 / 35 // 아이언·웨지: 로프트가 클수록 짧게 (3I 46 → SW 38)
        }
    }
}

/// 걷기 중 랜덤 잉여 동작 — 스틱맨의 생명감.
/// 100종의 모션(WalkFlavors.swift)은 전부 이 모듈레이션 채널들의 시간 엔벨로프 조합으로
/// 표현된다 (겹쳐도 안전). 발 접지 게이트는 채널이 아니다 — 노슬립 불변식 보호
struct WalkFlavor {
    var twirlAngle = 0.0 // 클럽 트월 누적 회전(rad) — 완료 후에도 유지 (되감기 없음)
    var shoulder = 0.0 // 어깨 캐리 블렌드
    var lookBack = 0.0 // 뒤돌아보기 블렌드
    var hatTouch = 0.0 // 모자 만지기 블렌드 (자유 팔이 머리로)
    var skip = 0.0 // 폴짝 (발 들기·바운스 부스트)
    var headDxOff = 0.0 // 머리 수평 오프셋 (응시·까딱)
    var headDyOff = 0.0 // 머리 수직 오프셋 (하늘 보기·갸웃)
    var shoulderYOff = 0.0 // 어깨 수직 오프셋 (으쓱·처짐·기지개)
    var shoulderXOff = 0.0 // 어깨 수평 오프셋 (뒤로 젖히기·숙이기·비틀기)
    var hipXOff = 0.0 // 힙 흔들기
    var hipYOff = 0.0 // 힙 수직 (스쿼트·바운스 — 어깨도 함께 내려간다)
    var armAmpBoost = 0.0 // 자유 팔 진폭 부스트 (음수 = 차분)
    var freeHandXOff = 0.0 // 자유 손 수평 오프셋 (지목·섀도복싱)
    var freeHandYOff = 0.0 // 자유 손 수직 오프셋 (주먹 불끈·손 흔들기)
    var phiWobble = 0.0 // 클럽 각 진동(rad)
    var gripLift = 0.0 // 클럽 살짝 들기 (0~1)
    var clubPointBlend = 0.0 // 클럽 전방 수평 지목 블렌드
    var clubUpBlend = 0.0 // 클럽 수직 세워 균형 블렌드

    /// 잔동작 진폭 부스트 (2026-08-20 사용자: "동작이 완전 커야") — 오프셋 채널만 스케일.
    /// twirlAngle은 회전수 의미(스케일하면 클럽이 거꾸로 선 채 끝남), shoulder는 기능 포즈라 제외.
    /// 팔 오프셋은 리그의 팔 길이에서 자연 포화 — 큰 값은 '팔을 끝까지 뻗음'이 된다.
    mutating func boostMotion(_ k: Double) {
        headDxOff *= k
        headDyOff *= k
        shoulderXOff *= k
        shoulderYOff *= k
        hipXOff *= k
        hipYOff *= k
        armAmpBoost *= k
        freeHandXOff *= k
        freeHandYOff *= k
        phiWobble *= k
        gripLift = min(1, gripLift * k)
        skip = min(1, skip * k)
        lookBack = min(1, lookBack * k)
        hatTouch = min(1, hatTouch * k)
        clubPointBlend = min(1, clubPointBlend * k)
        clubUpBlend = min(1, clubUpBlend * k)
    }
}

struct WalkFlavorEvent {
    let kind: WalkFlavorKind
    let t0: Double
    let dur: Double
}

func mix(_ a: CGPoint, _ b: CGPoint, _ u: Double) -> CGPoint {
    CGPoint(x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u)
}

func mix(_ a: Double, _ b: Double, _ u: Double) -> Double {
    a + (b - a) * u
}

/// ═══════════════════════════════════════════════════════════════
/// 통합 리그 — 스윙·걷기·전환이 전부 이 하나의 파라미터 공간을 지나간다.
/// 모드는 '타깃 리그'만 바꾸고, 렌더는 지수 감쇠로 타깃을 쫓는다.
/// 어떤 모드 전환도 같은 공간 안의 보간이므로 순간이동이 구조적으로 불가능하다.
/// 좌표는 facing 기준(+x = 바라보는 쪽), 렌더에서 dir로 미러링한다.
/// ═══════════════════════════════════════════════════════════════
struct Rig {
    var hip = CGPoint(x: -5, y: 42)
    var shoulder = CGPoint(x: 1, y: 66)
    var headDx = 7.0
    var foot1 = CGPoint(x: -16, y: 0) // 포즈에선 뒷발, 걷기에선 위상 +발
    var foot2 = CGPoint(x: 11, y: 0)
    var knee1 = CGPoint(x: -13, y: 22)
    var knee2 = CGPoint(x: 6, y: 21)
    var grip = CGPoint(x: 8, y: 33) // 리드 손 = 클럽 그립
    var handTrail = CGPoint(x: 10, y: 30) // 트레일 손 (스윙: 그립에 겹침 · 걷기: 자유 팔)
    var headDy = 12.0 // 어깨→머리 수직 거리
    var clubPhi = 0.2 // 샤프트 절대각 (0 = 수직 아래, + = 타겟 쪽)
    var clubLen = 31.0

    /// 지수 감쇠 추적 — clubPhi는 최단 각도 경로로 (트월 한 바퀴 후 되감기 방지)
    /// footRate: 걷기 중 발·무릎만 고속 추적 — 접지점이 스무딩에 밀리면 미끄러져 보인다
    /// clubRate: 팔로스루에서 클럽만 느리게 — 몸이 멈춘 뒤 클럽이 늦게 멈추는 오버랩
    mutating func chase(_ t: Rig, rate: Double, footRate: Double? = nil, clubRate: Double? = nil, dt: Double) {
        let k = 1 - exp(-rate * dt)
        let kf = footRate.map { 1 - exp(-$0 * dt) } ?? k
        let kc = clubRate.map { 1 - exp(-$0 * dt) } ?? k
        hip = mix(hip, t.hip, k)
        shoulder = mix(shoulder, t.shoulder, k)
        headDx = mix(headDx, t.headDx, k)
        headDy = mix(headDy, t.headDy, k)
        foot1 = mix(foot1, t.foot1, kf)
        foot2 = mix(foot2, t.foot2, kf)
        knee1 = mix(knee1, t.knee1, kf)
        knee2 = mix(knee2, t.knee2, kf)
        grip = mix(grip, t.grip, k)
        handTrail = mix(handTrail, t.handTrail, k)
        clubLen = mix(clubLen, t.clubLen, k)
        let dPhi = (t.clubPhi - clubPhi).remainder(dividingBy: 2 * .pi)
        clubPhi += dPhi * kc
    }
}

enum RigBuilder {
    /// P-System 포즈 → 리그 (스탠스는 공 원점 기준)
    static func fromPose(_ p: Pose, ballFwd: Double, clubLen: Double) -> Rig {
        let px = -ballFwd
        var r = Rig()
        r.hip = CGPoint(x: px + p.hipDx - 5, y: 42)
        r.shoulder = CGPoint(x: r.hip.x + 6 + 0.5 * p.tilt, y: 66)
        r.headDx = p.headDx
        let aH = p.handA * .pi / 180
        let aC = p.clubA * .pi / 180
        // 긴 클럽일수록 그립을 몸쪽으로 — 어드레스·임팩트에서 헤드가 지면에 닿는 기하 유지
        let handD = max(16, p.handD - (clubLen - 31))
        r.grip = CGPoint(x: r.shoulder.x + sin(aH) * handD, y: r.shoulder.y - cos(aH) * handD)
        r.handTrail = CGPoint(x: r.grip.x + sin(aC) * 4, y: r.grip.y - cos(aC) * 4) // 그립 아래쪽에 겹쳐 잡는다
        r.clubPhi = aC
        r.clubLen = clubLen
        // 뒷발꿈치 들림 = 발끝으로 서기 (발이 뜨지 않는다)
        r.foot1 = CGPoint(x: px - (16 - p.heel * 0.45), y: min(p.heel * 0.25, 3.5))
        r.foot2 = CGPoint(x: px + 11, y: 0)
        r.knee1 = CGPoint(x: px - 13 + p.hipDx * 0.5, y: 22)
        r.knee2 = CGPoint(x: px + 6 + p.hipDx * 0.5, y: 21)
        return r
    }

    /// 걷기 — 같은 Rig 공간. 발 위치는 호출측 게이트 상태(접지점 래치·stride warping)에서 온다.
    /// f1/f2: 발 로컬 x·들림 — 접지발은 월드 고정점이라 미끄러짐이 구조적으로 0
    static func walking(
        f1: (x: Double, lift: Double),
        f2: (x: Double, lift: Double),
        gaitPhase: Double,
        vPx: Double,
        clubLen: Double,
        flavor: WalkFlavor,
        groundDelta: (Double) -> Double
    ) -> Rig {
        let vAmp = min(1, vPx / 30)
        // 바디 밥: C1 연속(첨점 없음), 최저점 = 접지 순간
        let bob = (1.6 * vAmp + 2.5 * flavor.skip) * (1 - cos(4 * .pi * gaitPhase)) / 2

        var r = Rig()
        // 자세: 척추를 세우고 가슴을 편 당당한 걸음 — 전방 숙임(구 +2.5vAmp)이 '축 처짐'의
        // 주범이었다 (2026-08-15 사용자 판정). 속도에 따른 자연스러운 미세 기울임만 남긴다
        r.hip = CGPoint(x: flavor.hipXOff, y: 43.5 + bob + flavor.hipYOff)
        r.shoulder = CGPoint(
            x: 0.5 + 1.2 * vAmp + flavor.shoulderXOff,
            y: 68.5 + bob + flavor.hipYOff + flavor.shoulderYOff // 스쿼트 시 상체가 함께 내려간다
        )
        r.headDx = mix(1.5, -7, flavor.lookBack) + flavor.headDxOff // 뒤돌아보기·응시·까딱
        r.headDy = 13 + flavor.headDyOff // 머리를 들고 걷는다
        r.foot1 = CGPoint(x: f1.x, y: groundDelta(f1.x) + f1.lift)
        r.foot2 = CGPoint(x: f2.x, y: groundDelta(f2.x) + f2.lift)
        r.knee1 = CGPoint(
            x: (r.hip.x + f1.x) / 2 + 3,
            y: (r.hip.y + r.foot1.y) / 2 + 3 + f1.lift * 0.5
        )
        r.knee2 = CGPoint(
            x: (r.hip.x + f2.x) / 2 + 3,
            y: (r.hip.y + r.foot2.y) / 2 + 3 + f2.lift * 0.5
        )

        // 클럽 캐리: 기본은 옆에 살짝 들어(당당함) gripLift로 더 들 수 있고, 어깨 캐리 블렌드 시 어깨 위로.
        // hipYOff(스쿼트·넘어짐)를 따라 내려간다 — 몸만 떨어지고 클럽이 공중에 뜨지 않게
        let s = clubLen / 38
        var grip = CGPoint(x: -12, y: 48.5 + bob + flavor.hipYOff + 6 * flavor.gripLift)
        var tip = CGPoint(x: grip.x - 19 * s, y: grip.y - 33 * s)
        if flavor.shoulder > 0 {
            let sGrip = CGPoint(x: r.shoulder.x + 9, y: r.shoulder.y - 3)
            let sTip = CGPoint(x: r.shoulder.x - 26 * s, y: r.shoulder.y + 15 * s)
            grip = mix(grip, sGrip, flavor.shoulder)
            tip = mix(tip, sTip, flavor.shoulder)
        }
        // 클럽 제스처 블렌드: 전방 지목(수평) / 수직 세워 균형 — 스케줄러가 동시 발동을 막는다
        if flavor.clubPointBlend > 0 {
            grip = mix(grip, CGPoint(x: 6, y: 52 + bob), flavor.clubPointBlend)
        }
        if flavor.clubUpBlend > 0 {
            grip = mix(grip, CGPoint(x: 9, y: 49 + bob), flavor.clubUpBlend)
        }
        r.grip = grip
        var phi = atan2(tip.x - grip.x, grip.y - tip.y)
        phi = mix(phi, .pi / 2, flavor.clubPointBlend) // 팁이 타깃 쪽 수평
        phi = mix(phi, .pi - 0.05, flavor.clubUpBlend) // 팁이 하늘 (균형 잡기)
        r.clubPhi = phi + flavor.twirlAngle + flavor.phiWobble
        r.clubLen = clubLen

        // 자유 팔: 다리 반대 위상 스윙 — 느린 걸음에도 최소 진폭을 보장해 생기를 유지
        // (구 vAmp² 감쇠는 저속에서 팔이 완전히 죽어 '축 늘어짐'으로 읽혔다)
        let armAmp = (3 + 5 * vAmp) * max(0, 1 + flavor.armAmpBoost)
        let free = CGPoint(x: 5 - armAmp * sin(2 * .pi * gaitPhase), y: 48.5 + bob + flavor.hipYOff)
        let hat = CGPoint(x: r.shoulder.x + r.headDx + 3, y: r.shoulder.y + 9)
        r.handTrail = mix(free, hat, flavor.hatTouch)
        r.handTrail.x += flavor.freeHandXOff
        r.handTrail.y += flavor.freeHandYOff
        return r
    }
}

/// 스틱맨 렌더 — Rig 하나를 그린다. 로컬 (0,0) = 공이 놓인 지면 지점, y는 위쪽
/// 굵고 둥근 획의 회색 스틱맨. 두 팔: 리드 암(진하게) + 트레일 암(옅게 — 원근)
final class StickmanNode: SKNode {
    private let stickColor = NSColor(white: 0.88, alpha: 0.95)
    private let shaftColor = NSColor(white: 0.76, alpha: 0.9)
    private let clubHeadColor = NSColor(white: 0.93, alpha: 0.95) // 헤드가 또렷이 도드라진다
    private let gripColor = NSColor(white: 0.6, alpha: 0.9) // 그립 밴드 — 클럽다움의 디테일
    private let rimColor = NSColor(white: 0, alpha: 0.32) // 고대비 모드용 다크 림
    private let headShape = SKShapeNode(circleOfRadius: 10)
    private let hatNode = SKShapeNode() // 해금 모자 (기록·도전과제 보상) — 머리 자식이라 자동 추종
    private let bodyShape = SKShapeNode() // 척추+다리+리드 암 통합 경로
    private let trailArmShape = SKShapeNode() // 트레일 암 — 옅게 그려 원근을 만든다
    private let shaftShape = SKShapeNode()
    private let clubHeadShape = SKShapeNode()
    private let gripShape = SKShapeNode()
    private let headRim = SKShapeNode(circleOfRadius: 11.2)
    private let bodyRim = SKShapeNode()
    private let trailArmRim = SKShapeNode()
    private let shaftRim = SKShapeNode()
    private let clubHeadRim = SKShapeNode()

    override init() {
        super.init()
        headShape.fillColor = stickColor
        headShape.strokeColor = .clear
        headRim.fillColor = rimColor
        headRim.strokeColor = .clear
        bodyShape.strokeColor = stickColor
        bodyShape.lineWidth = 6
        bodyShape.lineCap = .round
        bodyShape.lineJoin = .round
        bodyRim.strokeColor = rimColor
        bodyRim.lineWidth = 8.4
        bodyRim.lineCap = .round
        bodyRim.lineJoin = .round
        trailArmShape.strokeColor = stickColor.withAlphaComponent(0.55)
        trailArmShape.lineWidth = 5.5
        trailArmShape.lineCap = .round
        trailArmRim.strokeColor = rimColor
        trailArmRim.lineWidth = 7.7
        trailArmRim.lineCap = .round
        shaftShape.strokeColor = shaftColor
        shaftShape.lineWidth = 3
        shaftShape.lineCap = .round
        shaftRim.strokeColor = rimColor
        shaftRim.lineWidth = 5.2
        shaftRim.lineCap = .round
        clubHeadShape.strokeColor = clubHeadColor
        clubHeadShape.fillColor = clubHeadColor
        clubHeadShape.lineCap = .round
        gripShape.strokeColor = gripColor
        gripShape.lineWidth = 4.6
        gripShape.lineCap = .round
        clubHeadRim.strokeColor = rimColor
        clubHeadRim.fillColor = rimColor
        clubHeadRim.lineCap = .round
        for n in [trailArmRim, bodyRim, shaftRim, clubHeadRim, headRim, trailArmShape, bodyShape,
                  shaftShape, clubHeadShape, gripShape, headShape] as [SKNode] {
            addChild(n)
        }
        headShape.addChild(hatNode) // 머리를 따라다닌다
        setHat(Records.shared.hat)
        applyContrast()
    }

    /// 해금 모자 착용 — 게임 회색 베이스 유지, 왕관만 포인트 (보상의 특별함)
    func setHat(_ hat: Hat) {
        hatNode.removeAllChildren()
        let path = CGMutablePath()
        var fill = NSColor(white: 0.82, alpha: 0.95)
        switch hat {
        case .none:
            hatNode.path = nil
            return
        case .straw: // 챙 넓은 밀짚 — 납작 타원 챙 + 낮은 크라운
            path.addEllipse(in: CGRect(x: -14, y: 6.5, width: 28, height: 4.5))
            path.addRect(CGRect(x: -6.5, y: 8, width: 13, height: 5.5))
            fill = NSColor(white: 0.86, alpha: 0.95)
        case .propeller: // 반구 캡 + 꼭지 프로펠러
            path.addArc(
                center: CGPoint(x: 0, y: 6), radius: 9.5,
                startAngle: 0, endAngle: .pi, clockwise: false
            )
            path.closeSubpath()
            path.addEllipse(in: CGRect(x: -8, y: 15.5, width: 16, height: 2.6)) // 날개
            path.addRect(CGRect(x: -0.9, y: 13.5, width: 1.8, height: 3))
        case .top: // 실크햇 — 챙 + 높은 원통
            path.addRect(CGRect(x: -11, y: 6.5, width: 22, height: 2.6))
            path.addRect(CGRect(x: -6.5, y: 9, width: 13, height: 12))
            fill = NSColor(white: 0.7, alpha: 0.95)
        case .crown: // 왕관 — 삼각 스파이크 3개 (유일한 포인트: 깃발 레드)
            path.move(to: CGPoint(x: -9, y: 7))
            path.addLine(to: CGPoint(x: -9, y: 15))
            path.addLine(to: CGPoint(x: -4.5, y: 10))
            path.addLine(to: CGPoint(x: 0, y: 16))
            path.addLine(to: CGPoint(x: 4.5, y: 10))
            path.addLine(to: CGPoint(x: 9, y: 15))
            path.addLine(to: CGPoint(x: 9, y: 7))
            path.closeSubpath()
            fill = NSColor(red: 0.894, green: 0.314, blue: 0.235, alpha: 0.95)
        }
        hatNode.path = path
        hatNode.fillColor = fill
        hatNode.strokeColor = .clear
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError()
    }

    /// 고대비 모드에서만 다크 림을 켠다 (기본은 원래의 가벼운 획)
    func applyContrast() {
        for r in [headRim, bodyRim, trailArmRim, shaftRim, clubHeadRim] as [SKNode] {
            r.isHidden = !Theme.highContrast
        }
    }

    // 임팩트 스미어용 최근 클럽 상태 스냅샷
    private var lastGrip = CGPoint.zero
    private var lastPhi = 0.0
    private var lastLen = 31.0
    private var lastDir = 1.0

    /// 임팩트 스미어 — 헤드 궤적을 따라가는 짧은 헤어라인 원호 잔상 (점·헤어라인 규칙 안, 리서치 P5)
    func impactSmear() {
        let path = CGMutablePath()
        let steps = 10
        for k in 0 ... steps {
            let ph = lastPhi - 0.85 * (1 - Double(k) / Double(steps))
            let pt = CGPoint(x: lastGrip.x + sin(ph) * lastLen * lastDir, y: lastGrip.y - cos(ph) * lastLen)
            if k == 0 {
                path.move(to: pt)
            } else {
                path.addLine(to: pt)
            }
        }
        let arc = SKShapeNode(path: path)
        arc.strokeColor = NSColor(white: 0.95, alpha: 0.38)
        arc.lineWidth = 2.5
        arc.lineCap = .round
        addChild(arc)
        arc.run(.sequence([.fadeOut(withDuration: 0.13), .removeFromParent()]))
    }

    func render(rig r: Rig, club: Club, prevClub: Club, headMorph: Double, visualLoft: Double, dir: Double) {
        func m(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x * dir, y: p.y)
        } // facing → 화면 미러
        let hip = m(r.hip)
        let shoulder = m(r.shoulder)
        let head = CGPoint(x: shoulder.x + dir * r.headDx, y: shoulder.y + r.headDy)
        headShape.position = head
        headRim.position = head

        let f1 = m(r.foot1), f2 = m(r.foot2)
        let k1 = m(r.knee1), k2 = m(r.knee2)
        let grip = m(r.grip)

        let body = CGMutablePath()
        // 척추 (살짝 굽음)
        body.move(to: shoulder)
        body.addQuadCurve(
            to: hip,
            control: CGPoint(x: (shoulder.x + hip.x) / 2 - dir * 2.5, y: (shoulder.y + hip.y) / 2)
        )
        // 다리 둘 (무릎 제어점 포함)
        body.move(to: hip)
        body.addQuadCurve(to: f1, control: k1)
        body.move(to: hip)
        body.addQuadCurve(to: f2, control: k2)
        // 리드 암
        body.move(to: shoulder)
        body.addQuadCurve(
            to: grip,
            control: CGPoint(x: (shoulder.x + grip.x) / 2 + dir * 2, y: (shoulder.y + grip.y) / 2 + 2)
        )
        bodyShape.path = body
        bodyRim.path = body

        // 트레일 암 — 같은 어깨 관절에서 시작 (옅은 톤과 팔꿈치 굽음으로만 구분)
        let hTrail = m(r.handTrail)
        let trail = CGMutablePath()
        trail.move(to: shoulder)
        trail.addQuadCurve(
            to: hTrail,
            control: CGPoint(x: (shoulder.x + hTrail.x) / 2 + dir * 1.0, y: (shoulder.y + hTrail.y) / 2 - 2)
        )
        trailArmShape.path = trail
        trailArmRim.path = trail

        // 클럽
        let tip = CGPoint(x: grip.x + sin(r.clubPhi) * r.clubLen * dir, y: grip.y - cos(r.clubPhi) * r.clubLen)
        let shaft = CGMutablePath()
        shaft.move(to: grip)
        shaft.addLine(to: tip)
        shaftShape.path = shaft
        shaftRim.path = shaft
        // 그립 밴드: 손 쪽 8px만 진하게 — 클럽다움을 만드는 단 하나의 디테일
        let gripBand = CGMutablePath()
        gripBand.move(to: grip)
        gripBand.addLine(to: CGPoint(
            x: grip.x + sin(r.clubPhi) * 8 * dir, y: grip.y - cos(r.clubPhi) * 8
        ))
        gripShape.path = gripBand

        // 클럽 헤드 — 모든 종류를 '캡슐(둥근 굵은 선)' 하나로 표현해, 종류 전환도 기하 morph로 이어진다
        let now = headParams(club: club, loft: visualLoft, tip: tip, phi: r.clubPhi, dir: dir)
        let prev = headParams(club: prevClub, loft: prevClub.loft, tip: tip, phi: r.clubPhi, dir: dir)
        let m = smoothstep(min(1, max(0, headMorph)))
        let headPath = CGMutablePath()
        headPath.move(to: mix(prev.a, now.a, m))
        headPath.addLine(to: mix(prev.b, now.b, m))
        // 퍼터 얼라인먼트 점은 블렌드에 따라 자라거나 사라진다
        let dotBlend = (club.cat == .putter ? m : 0) + (prevClub.cat == .putter ? 1 - m : 0)
        if dotBlend > 0.05, let dot = club.cat == .putter ? now.dot : prev.dot {
            let rr = 1.1 * dotBlend
            headPath.addEllipse(in: CGRect(x: dot.x - rr, y: dot.y - rr, width: rr * 2, height: rr * 2))
        }
        clubHeadShape.path = headPath
        clubHeadShape.lineWidth = mix(prev.lw, now.lw, m)
        clubHeadRim.path = headPath
        clubHeadRim.lineWidth = clubHeadShape.lineWidth + 2.2

        lastGrip = grip
        lastPhi = r.clubPhi
        lastLen = r.clubLen
        lastDir = dir
    }

    /// 헤드 캡슐 파라미터 — 시작점·끝점·굵기(·퍼터 점). 종류가 달라도 같은 표현이라 morph 가능
    private func headParams(
        club: Club, loft: Double, tip: CGPoint, phi: Double, dir: Double
    ) -> (a: CGPoint, b: CGPoint, lw: Double, dot: CGPoint?) {
        let along = CGVector(dx: sin(phi) * dir, dy: -cos(phi))
        let perp = CGVector(dx: cos(phi) * dir, dy: sin(phi))
        switch club.cat {
        case .wood: // 동글동글한 볼 헤드 — 막대사탕처럼 통통하게 (드라이버가 가장 크다)
            let w = 17 - (loft - 10.5) * 0.5 // DR 17 · 3W 14.8 · 5W 13
            let h = w * 0.8 // 거의 원형 (구 0.68 — 납작한 스머지로 읽혔다)
            let c = CGPoint(x: tip.x + perp.dx * 4.5, y: tip.y + perp.dy * 4.5)
            let half = (w - h) / 2
            return (
                CGPoint(x: c.x - perp.dx * half, y: c.y - perp.dy * half),
                CGPoint(x: c.x + perp.dx * half, y: c.y + perp.dy * half),
                h, nil
            )
        case .iron, .wedge: // 통통한 둥근 패들 — 짧고 두껍게, 웨지로 갈수록 조금 더
            let len = 8.5 + max(0, loft - 42) * 0.11
            let lo = loft * 0.9 * .pi / 180
            let bx = (perp.dx * cos(lo) - along.dx * sin(lo)) * len
            let by = (perp.dy * cos(lo) - along.dy * sin(lo)) * len
            return (tip, CGPoint(x: tip.x + bx, y: tip.y + by), 5 + max(0, loft - 42) * 0.055, nil)
        case .putter: // 미니 망치 — 짧고 도톰한 블록 + 얼라인먼트 점
            return (
                CGPoint(x: tip.x - perp.dx * 2.5, y: tip.y - perp.dy * 2.5),
                CGPoint(x: tip.x + perp.dx * 6.5, y: tip.y + perp.dy * 6.5),
                6.5,
                CGPoint(x: tip.x + perp.dx * 2 - along.dx * 5.5, y: tip.y + perp.dy * 2 - along.dy * 5.5)
            )
        }
    }
}
