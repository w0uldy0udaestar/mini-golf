import AppKit
import GolfCore
import SpriteKit

// ═══════════════════════════════════════════════════════════════
// MiniGolf — 데스크탑 오버레이 골프
// 조작: ←→ 클럽 · ↑↓ 백스윙 · Space 스윙 · R 새 라운드 · Esc 종료
// 활성화: 메뉴바 ⛳️ 좌클릭 = 재개/일시정지 토글 · 우클릭 = 메뉴
// (전역 단축키는 사용자 설정 기능으로 추후 도입 — IDEAS.md)
// 다른 창을 클릭해 포커스를 잃어도 게임은 계속 흐른다 — 입력 홀드만 풀린다 (일시정지는 ⛳️ 수동)
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
    private var bumperMenuItem: NSMenuItem!
    private var monitorMenu: NSMenu!
    private var lastResignKey = Date.distantPast

    /// ── 모니터 선택 (2026-08-20 듀얼 모니터 요청): ⛳️ 메뉴에서 선택, 세션 간 기억 ──
    private let screenPrefKey = "preferredDisplayID"

    private func displayID(_ s: NSScreen) -> UInt32 {
        (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// 저장된 선택 > 주 디스플레이 (선택한 모니터가 분리됐으면 주 디스플레이로 폴백).
    /// NSScreen.main은 '키 윈도의 화면'이라 실행 순간의 포커스를 따라간다 — 폴백으로 부적합
    private var preferredScreen: NSScreen? {
        let saved = UInt32(UserDefaults.standard.integer(forKey: screenPrefKey))
        return NSScreen.screens.first { displayID($0) == saved } ?? NSScreen.screens.first
    }

    func applicationDidFinishLaunching(_: Notification) {
        let launchArgs = ProcessInfo.processInfo.arguments
        // --screen N: 실행 시 모니터 지정 (0부터, 검증·프리셋용 — 저장하지 않음)
        var flagScreen: NSScreen?
        if let i = launchArgs.firstIndex(of: "--screen"), i + 1 < launchArgs.count,
           let n = Int(launchArgs[i + 1]), NSScreen.screens.indices.contains(n) {
            flagScreen = NSScreen.screens[n]
        }
        guard let screen = flagScreen ?? preferredScreen else { NSApp.terminate(nil); return }

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
        // --demo: 자동 스윙 반복 · --demo-wall: 벽 스탠스 시나리오 강제 (모션 관찰·디버그 전용, 사운드 끔)
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--demo") || args.contains("--demo-wall") {
            scene.demoMode = true
            scene.demoWallForce = args.contains("--demo-wall")
            SoundKit.shared.enabled = false
        }
        scene.demoCardPreview = args.contains("--demo-card")
        scene.demoNoClamp = args.contains("--no-wall-clamp") // 침범 재현·검증 전용
        if let i = args.firstIndex(of: "--seed"), i + 1 < args.count { // 코스 시드 고정 (시각 검증 전용)
            scene.demoSeed = UInt32(args[i + 1])
        }
        scene.demoTripForce = args.contains("--demo-trip") // 넘어지기 강제 (모션 관찰용)
        scene.demoIdleForce = args.contains("--demo-idle") // 조준 유지 (아이들 관찰용)
        scene.demoMotionShowcase = args.contains("--demo-motions") // 모션 100종 순서 시연 (카탈로그)
        scene.demoShowpieceForce = args.contains("--demo-memes") // 쇼피스 밈 12종 순환 (카탈로그)
        panel.contentView = skView
        skView.presentScene(scene)

        // --demo-switch T: T초 후 다음 모니터로 이동 — 런타임 전환 관찰용 (메뉴 선택과 동일 경로)
        if let i = args.firstIndex(of: "--demo-switch"), i + 1 < args.count, let t = Double(args[i + 1]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak self] in
                guard let self, let cur = panel.screen,
                      let idx = NSScreen.screens.firstIndex(of: cur) else { return }
                move(to: NSScreen.screens[(idx + 1) % NSScreen.screens.count])
            }
        }

        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(scene)
        NSApp.activate(ignoringOtherApps: true)

        // 포커스 상실 → 입력 홀드만 해제 (키는 어차피 아래 앱으로 가고, 게임은 멈추지 않는다)
        NotificationCenter.default.addObserver(
            self, selector: #selector(panelResignedKey),
            name: NSWindow.didResignKeyNotification, object: panel
        )
        // 모니터 구성 변화(분리·해상도 변경) → 선호 화면으로 재정렬
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )

        setupStatusItem()
    }

    // ── 모니터 전환 ──

    private func move(to screen: NSScreen) {
        guard panel.frame != screen.frame else { return }
        panel.setFrame(screen.frame, display: true) // contentView(SKView)가 따라 리사이즈 → 씬 didChangeSize
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(scene)
    }

    @objc private func selectMonitor(_ sender: NSMenuItem) {
        guard let id = (sender.representedObject as? NSNumber)?.uint32Value,
              let screen = NSScreen.screens.first(where: { displayID($0) == id }) else { return }
        UserDefaults.standard.set(Int(id), forKey: screenPrefKey)
        move(to: screen)
    }

    @objc private func screensChanged() {
        if let s = preferredScreen {
            move(to: s)
        }
    }

    private func rebuildMonitorMenu() {
        monitorMenu.removeAllItems()
        for s in NSScreen.screens {
            let item = monitorMenu.addItem(
                withTitle: s.localizedName,
                action: #selector(selectMonitor(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = NSNumber(value: displayID(s))
            item.state = panel.screen == s ? .on : .off
        }
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
        bumperMenuItem = statusMenu.addItem(
            withTitle: "창 범퍼 (공이 앱 창에 튕김)",
            action: #selector(toggleBumpers),
            keyEquivalent: ""
        )
        bumperMenuItem.target = self
        bumperMenuItem.state = Theme.windowBumpers ? .on : .off
        let monitorItem = statusMenu.addItem(withTitle: "모니터", action: nil, keyEquivalent: "")
        monitorMenu = NSMenu()
        monitorItem.submenu = monitorMenu // 항목은 열 때마다 재구성 (연결 상태 반영)
        statusMenu.addItem(.separator())
        statusMenu.addItem(withTitle: "종료", action: #selector(quit), keyEquivalent: "q").target = self
        // statusItem.menu는 비워둔다 — 지정하면 좌클릭이 메뉴를 열어 버튼 동작을 삼킨다
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            rebuildMonitorMenu()
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

    @objc private func toggleBumpers() {
        Theme.windowBumpers.toggle()
        bumperMenuItem.state = Theme.windowBumpers ? .on : .off
    }

    @objc private func toggleContrast() {
        scene.setHighContrast(!Theme.highContrast)
        contrastMenuItem.state = Theme.highContrast ? .on : .off
    }

    /// 포커스를 잃어도 게임은 계속 흐른다 — 눌린 키만 풀어준다 (2026-08-15 사용자 요청 4번)
    @objc private func panelResignedKey() {
        lastResignKey = Date()
        scene.releaseHeldInput()
    }

    /// 재개 ↔ 일시정지 토글: 키보드를 갖고 플레이하던 중이면 쉬게 하고, 아니면 키보드를 잡아온다
    @objc func toggleGame() {
        if scene.isGamePaused {
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(scene)
            NSApp.activate(ignoringOtherApps: true)
            scene.setGamePaused(false)
        } else if panel.isKeyWindow || Date().timeIntervalSince(lastResignKey) < 0.4 {
            // ⛳️ 클릭 자체가 방금 포커스를 뺏었을 수 있다 — 직전까지 키를 갖고 있었다면 '일시정지' 의도.
            // (다른 창 클릭 후 0.4초 내 ⛳️ 클릭이면 오분류되지만, 물리적으로 거의 불가능한 조합)
            scene.setGamePaused(true)
        } else { // 게임은 돌고 있고 키보드만 다른 앱에 — 키보드 회수
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(scene)
            NSApp.activate(ignoringOtherApps: true)
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
