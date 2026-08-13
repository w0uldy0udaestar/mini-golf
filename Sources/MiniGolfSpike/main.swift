import AppKit
import SpriteKit

// ═══════════════════════════════════════════════════════════════
// M0 스파이크 — PLAN.md의 최대 불확실성 3가지를 최소 코드로 검증:
//  ① 투명 NSPanel + SpriteKit .clear 씬에 도형 렌더
//  ② 창 전체 클릭 통과(ignoresMouseEvents) + 키보드 이벤트 수신
//  ③ 포커스 상실 감지 (실전에서는 자동 일시정지 지점)
// 조작: ←→ 공 이동 · Space 샷 흉내 · Esc 종료
// ═══════════════════════════════════════════════════════════════

final class SpikeScene: SKScene {
    private let ball = SKShapeNode(circleOfRadius: 9)

    override func didMove(to _: SKView) {
        backgroundColor = .clear // ⚠️ skView.backgroundColor는 절대 설정하지 않는다 (투명이 깨짐)

        ball.fillColor = .white
        ball.strokeColor = NSColor(white: 0, alpha: 0.25)
        ball.position = CGPoint(x: size.width / 2, y: 120)
        addChild(ball)

        let ground = SKShapeNode(rectOf: CGSize(width: size.width, height: 3))
        ground.fillColor = NSColor(white: 0.92, alpha: 0.9)
        ground.position = CGPoint(x: size.width / 2, y: 110)
        addChild(ground)

        let flag = SKShapeNode(rectOf: CGSize(width: 30, height: 20))
        flag.fillColor = NSColor(red: 0.84, green: 0.27, blue: 0.20, alpha: 1)
        flag.position = CGPoint(x: size.width * 0.75, y: 160)
        addChild(flag)
    }

    override func keyDown(with event: NSEvent) {
        print("[spike] keyDown code=\(event.keyCode)")
        switch event.keyCode {
        case 123: ball.run(.moveBy(x: -30, y: 0, duration: 0.1)) // ←
        case 124: ball.run(.moveBy(x: 30, y: 0, duration: 0.1)) // →
        case 49: // Space: 포물선 샷 흉내
            ball.run(.sequence([
                .moveBy(x: 60, y: 90, duration: 0.25),
                .moveBy(x: 60, y: -90, duration: 0.3),
            ]))
        case 53: NSApp.terminate(nil) // Esc
        default: break
        }
    }
}

final class SpikePanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    } // borderless 패널도 키 입력을 받게
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: SpikePanel!

    func applicationDidFinishLaunching(_: Notification) {
        guard let screen = NSScreen.main else { NSApp.terminate(nil); return }

        panel = SpikePanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true // ② 마우스는 전부 아래 앱으로 통과
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let skView = SKView(frame: screen.frame)
        skView.allowsTransparency = true // ① 투명 렌더 (backgroundColor는 건드리지 않음)
        let scene = SpikeScene(size: screen.frame.size)
        scene.scaleMode = .resizeFill
        panel.contentView = skView
        skView.presentScene(scene)

        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(scene) // 키 이벤트를 씬으로
        NSApp.activate(ignoringOtherApps: true)

        // ③ 포커스 상실 감지
        NotificationCenter.default.addObserver(
            self, selector: #selector(lostKey),
            name: NSWindow.didResignKeyNotification, object: panel
        )
        print("[spike] overlay up — ←→ 공 이동, Space 샷 흉내, Esc 종료")
    }

    @objc private func lostKey() {
        print("[spike] 포커스 상실 감지 — 실전에서는 여기서 자동 일시정지")
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // 독·Cmd-Tab에 나타나지 않는 오버레이 앱
let delegate = AppDelegate()
app.delegate = delegate
app.run()
