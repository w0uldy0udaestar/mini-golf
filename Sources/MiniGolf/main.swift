import AppKit
import GolfCore
import SpriteKit

// ═══════════════════════════════════════════════════════════════
// MiniGolf — 데스크탑 오버레이 골프
// 조작: ←→ 클럽 · ↑↓ 백스윙 · Space 스윙 · R 새 라운드 · Esc 종료
// 활성화: 메뉴바 ⛳️ 좌클릭 = 재개/일시정지 토글 · 우클릭 = 메뉴
// (전역 단축키는 사용자 설정 기능으로 추후 도입 — IDEAS.md)
// 다른 창을 클릭해 포커스를 잃으면 자동 일시정지된다
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
    private var statusMenu: NSMenu!
    private var soundMenuItem: NSMenuItem!
    private var contrastMenuItem: NSMenuItem!
    private var lastAutoPause = Date.distantPast

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

        // 포커스 상실 → 자동 일시정지 (아래 앱으로 키가 새지 않게 + 상태 보존)
        NotificationCenter.default.addObserver(
            self, selector: #selector(panelResignedKey),
            name: NSWindow.didResignKeyNotification, object: panel
        )

        setupStatusItem()
    }

    /// 메뉴바 ⛳️ = 활성화 버튼 — 좌클릭이 곧 재개/일시정지 토글, 메뉴는 우클릭으로
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "⛳️"
        statusItem.button?.toolTip = "게임 재개 / 일시정지 — 우클릭: 메뉴"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        statusMenu = NSMenu()
        statusMenu.addItem(withTitle: "게임 재개 / 일시정지", action: #selector(toggleGame), keyEquivalent: "g").target = self
        statusMenu.addItem(withTitle: "새 라운드", action: #selector(newRound), keyEquivalent: "r").target = self
        soundMenuItem = statusMenu.addItem(withTitle: "사운드", action: #selector(toggleSound), keyEquivalent: "")
        soundMenuItem.target = self
        soundMenuItem.state = SoundKit.shared.enabled ? .on : .off
        contrastMenuItem = statusMenu.addItem(
            withTitle: "고대비 모드 (밝은 배경용)",
            action: #selector(toggleContrast),
            keyEquivalent: ""
        )
        contrastMenuItem.target = self
        contrastMenuItem.state = Theme.highContrast ? .on : .off
        statusMenu.addItem(.separator())
        statusMenu.addItem(withTitle: "종료", action: #selector(quit), keyEquivalent: "q").target = self
        // statusItem.menu는 비워둔다 — 지정하면 좌클릭이 메뉴를 열어 버튼 동작을 삼킨다
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            statusItem.menu = statusMenu
            statusItem.button?.performClick(nil) // 메뉴 추적은 이 안에서 동기 실행됨
            statusItem.menu = nil
        } else {
            toggleGame()
        }
    }

    @objc private func toggleSound() {
        SoundKit.shared.enabled.toggle()
        soundMenuItem.state = SoundKit.shared.enabled ? .on : .off
    }

    @objc private func toggleContrast() {
        scene.setHighContrast(!Theme.highContrast)
        contrastMenuItem.state = Theme.highContrast ? .on : .off
    }

    @objc private func panelResignedKey() {
        lastAutoPause = Date()
        scene.setGamePaused(true)
    }

    /// 재개 ↔ 일시정지 토글: 게임이 키보드를 안 갖고 있으면 잡아오고, 갖고 있으면 쉬게 한다
    @objc func toggleGame() {
        // 버튼 클릭 자체가 포커스를 뺏어 방금 자동 일시정지됐다면, 클릭 의도는 '일시정지' — 그대로 둔다
        if scene.isGamePaused, Date().timeIntervalSince(lastAutoPause) < 0.4 {
            return
        }
        if scene.isGamePaused || !panel.isKeyWindow {
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(scene)
            NSApp.activate(ignoringOtherApps: true)
            scene.setGamePaused(false)
        } else {
            scene.setGamePaused(true)
        }
    }

    @objc private func newRound() {
        scene.newRound()
        if scene.isGamePaused {
            toggleGame()
        }
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
