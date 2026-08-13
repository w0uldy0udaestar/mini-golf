import AppKit
import Carbon.HIToolbox
import GolfCore
import SpriteKit

// ═══════════════════════════════════════════════════════════════
// MiniGolf — 데스크탑 오버레이 골프
// 조작: ←→ 클럽 · ↑↓ 백스윙 · Space 스윙 · R 새 라운드 · Esc 종료
// 활성화: ⌃⇧G (전역 단축키 — 어디서든 게임 재개/일시정지 토글)
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
    private var hotKeyRef: EventHotKeyRef?

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
        registerGlobalHotKey()
    }

    /// ⌃⇧G — 어느 앱에 있든 게임을 다시 잡는 전역 단축키 (접근성 권한 불필요한 Carbon 핫키)
    private func registerGlobalHotKey() {
        let hotKeyID = EventHotKeyID(signature: OSType(0x4D47_4C46), id: 1) // 'MGLF'
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { delegate.toggleGame() }
                return noErr
            },
            1, &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            nil
        )
        RegisterEventHotKey(
            UInt32(kVK_ANSI_G),
            UInt32(controlKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    /// 메뉴바 ⛳️ — 단축키의 백업 통로
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "⛳️"
        let menu = NSMenu()
        menu.addItem(withTitle: "게임 재개 / 일시정지 (⌃⇧G)", action: #selector(toggleGame), keyEquivalent: "g").target = self
        menu.addItem(withTitle: "새 라운드", action: #selector(newRound), keyEquivalent: "r").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "종료", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
    }

    @objc private func panelResignedKey() {
        scene.setGamePaused(true)
    }

    /// 재개 ↔ 일시정지 토글: 게임이 키보드를 안 갖고 있으면 잡아오고, 갖고 있으면 쉬게 한다
    @objc func toggleGame() {
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
