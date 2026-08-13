import AppKit
import GolfCore
import SpriteKit

// ═══════════════════════════════════════════════════════════════
// MiniGolf — 데스크탑 오버레이 골프 (M2: 스틱맨·HUD 칩·스코어카드·메뉴바)
// 조작: ←→ 클럽 · ↑↓ 백스윙 · Space 스윙 · R 새 라운드 · Esc 종료
// 다른 창을 클릭해 포커스를 잃으면 자동 일시정지 — 메뉴바 ⛳️에서 재개
// ═══════════════════════════════════════════════════════════════

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: OverlayPanel!
    private var scene: GameScene!
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_: Notification) {
        guard let screen = NSScreen.main else { NSApp.terminate(nil); return }

        panel = OverlayPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true // 마우스는 전부 아래 앱으로
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let skView = SKView(frame: screen.frame)
        skView.allowsTransparency = true // ⚠️ skView.backgroundColor는 설정 금지
        scene = GameScene(size: screen.frame.size)
        scene.scaleMode = .resizeFill
        panel.contentView = skView
        skView.presentScene(scene)

        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(scene)
        NSApp.activate(ignoringOtherApps: true)

        // 포커스 상실 → 자동 일시정지 (아래 앱으로 키가 새지 않도록 하는 동시에 상태 보존)
        NotificationCenter.default.addObserver(
            self, selector: #selector(panelResignedKey),
            name: NSWindow.didResignKeyNotification, object: panel
        )

        setupStatusItem()
    }

    /// 메뉴바 ⛳️ — 클릭 통과 창이라 포커스를 되찾을 유일한 통로
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "⛳️"
        let menu = NSMenu()
        menu.addItem(withTitle: "게임 재개 (키보드 잡기)", action: #selector(resumeGame), keyEquivalent: "g").target = self
        menu.addItem(withTitle: "새 라운드", action: #selector(newRound), keyEquivalent: "r").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "종료", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
    }

    @objc private func panelResignedKey() {
        scene.setGamePaused(true)
    }

    @objc private func resumeGame() {
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(scene)
        NSApp.activate(ignoringOtherApps: true)
        scene.setGamePaused(false)
    }

    @objc private func newRound() {
        scene.newRound()
        resumeGame()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
