import AppKit
import Carbon.HIToolbox
import GolfCore
import SpriteKit

// ═══════════════════════════════════════════════════════════════
// MiniGolf — 데스크탑 오버레이 골프
// 조작: ←→ 클럽 · ↑↓ 백스윙 · Space 스윙 · R 새 라운드 · Esc 종료
// 활성화: 메뉴바 ⛳️ 좌클릭 = 재개/일시정지 토글 · 우클릭 = 메뉴
// 불러내기 단축키: ⛳️ 메뉴에서 사용자가 직접 정한다 (기본값 없음 — Hotkey.swift)
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
    private var practiceMenuItem: NSMenuItem!
    private var hotkeyMenuItem: NSMenuItem!
    private var summonedFrom: NSRunningApplication? // 단축키로 불러내기 직전에 쓰던 앱 — 쉬게 할 때 키보드를 돌려준다
    private var monitorMenu: NSMenu!
    private var hatMenu: NSMenu!
    private var lastResignKey = Date.distantPast

    /// ── 모니터 선택 (2026-08-20 듀얼 모니터 요청): ⛳️ 메뉴에서 선택, 세션 간 기억 ──
    private let screenPrefKey = "preferredDisplayID"

    private func displayID(_ s: NSScreen) -> UInt32 {
        (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// 저장된 선택 > 주 디스플레이 (선택한 모니터가 분리됐으면 주 디스플레이로 폴백).
    /// NSScreen.main은 '키 윈도의 화면'이라 포커스를 따라가고, screens.first도 Sidecar/AirPlay
    /// 연결 순서에 따라 주가 아닐 수 있다 (2026-08-31 실측 — 게임이 Sidecar에 떠 "업데이트
    /// 실종"으로 보임). 전역 좌표 원점(0,0) 화면이 곧 메뉴바 있는 주 디스플레이다.
    private var preferredScreen: NSScreen? {
        let saved = UInt32(UserDefaults.standard.integer(forKey: screenPrefKey))
        return NSScreen.screens.first { displayID($0) == saved }
            ?? NSScreen.screens.first { $0.frame.origin == .zero }
            ?? NSScreen.screens.first
    }

    func applicationDidFinishLaunching(_: Notification) {
        let demo = DemoOptions(arguments: ProcessInfo.processInfo.arguments) // 관찰·디버그 플래그 — 실플레이는 전부 기본값
        L10n.lang = demo.lang ?? LanguagePref.saved.resolved // 표시 언어 — 씬·메뉴가 문구를 만들기 전에
        // --screen N: 실행 시 모니터 지정 (0부터, 검증·프리셋용 — 저장하지 않음)
        var flagScreen: NSScreen?
        if let n = demo.screenIndex, NSScreen.screens.indices.contains(n) {
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
        scene.demo = demo // presentScene(didMove) 전에 — 시드·배경·시작 홀을 씬 구성이 읽는다
        scene.motionCursor = demo.motionCursorStart
        if demo.active {
            SoundKit.shared.muted = true // 세션 한정 — 사용자 사운드 설정 보존
        }
        PlayLog.toStdout = demo.active
        if let st = demo.swingStyle {
            scene.swingStyle = st // 스윙 스타일 지정 (관찰·캡처용, 저장 안 함)
        }
        if let h = demo.hat {
            scene.applyHat(h) // 모자 시각 검증용 (저장 안 함)
        }
        if demo.recordsCard { // 기록 카드 레이아웃 검증용
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak scene] in scene?.showRecordsCard() }
        }
        panel.contentView = skView
        skView.presentScene(scene)

        // --demo-switch T: T초 후 다음 모니터로 이동 — 런타임 전환 관찰용 (메뉴 선택과 동일 경로)
        if let t = demo.switchAfter {
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak self] in
                guard let self, let cur = panel.screen,
                      let idx = NSScreen.screens.firstIndex(of: cur) else { return }
                move(to: NSScreen.screens[(idx + 1) % NSScreen.screens.count])
            }
        }

        if demo.active {
            // 관찰 모드는 자동 플레이라 키보드가 필요 없다 — 포커스를 가져가면 사용자가 치던 글자가 게임으로 샌다(R·Esc·Space가 전부 동작).
            // 창만 앞에 띄운다 (2026-10-05)
            panel.orderFrontRegardless()
        } else {
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(scene)
            NSApp.activate(ignoringOtherApps: true)
        }

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

        if !demo.active { // 관찰 모드는 사용자의 실제 게임과 같은 조합을 두고 다투지 않는다
            HotkeyCenter.shared.onPress = { [weak self] in self?.hotkeyPressed() }
            HotkeyCenter.shared.register(HotkeyCombo.saved) // 그사이 다른 앱이 가져갔으면 조용히 실패 — 메뉴 제목이 알려 준다
            updateHotkeyMenuTitle()
        }
        if demo.hotkeyUI { // 기록 대화상자 관찰 (키 입력 없이): 띄우고 → 견본 조합을 처리 함수에 직접 넣어 본다
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.demoHotkeyUI() }
        }
    }

    // ── 불러내기 단축키 ──

    private func updateHotkeyMenuTitle() {
        let saved = HotkeyCombo.saved
        let title: String = if let saved, HotkeyCenter.shared.current == saved {
            L("불러내기 단축키: \(saved.display)…", "Summon shortcut: \(saved.display)…")
        } else if let saved { // 저장은 돼 있는데 등록이 안 됐다 = 다른 앱이 먼저 잡았다
            L("불러내기 단축키: \(saved.display) (다른 앱이 사용 중)…", "Summon shortcut: \(saved.display) (in use elsewhere)…")
        } else {
            L("불러내기 단축키 설정…", "Set summon shortcut…")
        }
        hotkeyMenuItem?.title = title
    }

    @objc private func configureHotkey() {
        let before = HotkeyCombo.saved
        HotkeyCenter.shared.unregister() // 기록하는 동안에는 지금 단축키가 게임을 토글하지 않게 (그 조합을 다시 고를 수도 있다)
        switch HotkeyRecorder(current: before).run() {
        case let .set(combo): HotkeyCombo.saved = combo // 등록은 대화상자가 이미 했다
        case .cleared: HotkeyCombo.saved = nil
        case .cancelled: HotkeyCenter.shared.register(before)
        }
        updateHotkeyMenuTitle()
        panel.makeKeyAndOrderFront(nil) // 대화상자가 가져간 키보드를 게임으로
        panel.makeFirstResponder(scene)
    }

    /// 단축키 = ⛳️ 좌클릭과 같은 토글. 손이 키보드에 있으니, 쉬게 할 때는 불러내기 전에 쓰던 앱으로 키보드를 돌려준다
    /// (⛳️ 클릭은 마우스가 이미 다른 곳을 누를 수 있지만, 단축키는 그대로 두면 일시정지된 게임이 계속 키를 받는다)
    private func hotkeyPressed() {
        if let front = NSWorkspace.shared.frontmostApplication, front != NSRunningApplication.current {
            summonedFrom = front
        }
        toggleGame()
        if scene.isGamePaused, let app = summonedFrom, !app.isTerminated {
            if #available(macOS 14.0, *) {
                NSApp.yieldActivation(to: app)
                app.activate()
            } else {
                app.activate(options: [])
            }
        }
    }

    /// --demo-hotkey-ui: 대화상자를 포커스 없이 띄우고, 0.8초 뒤 견본 키 입력(⌃⌥⇧F19)을 처리 함수에 직접 넘긴다 — 시스템에 키를 보내지 않는다
    private func demoHotkeyUI() {
        let recorder = HotkeyRecorder(current: HotkeyCombo(
            keyCode: UInt32(kVK_ANSI_G),
            modifiers: UInt32(controlKey | optionKey),
            label: "G"
        ))
        let timer = Timer(timeInterval: 0.8, repeats: false) { _ in
            print("HOTKEYUI open window \(recorder.window.windowNumber)")
            fflush(stdout)
            let feed = Timer(timeInterval: 1.6, repeats: false) { _ in
                let plain = NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                    characters: "g", charactersIgnoringModifiers: "g", isARepeat: false, keyCode: UInt16(kVK_ANSI_G)
                )
                print("HOTKEYUI plain-key passes through: \(plain.map { recorder.handle($0) != nil } ?? false)")
                let combo = NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: [.control, .option, .shift], timestamp: 0,
                    windowNumber: 0,
                    context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false,
                    keyCode: UInt16(kVK_F19)
                )
                if let combo {
                    _ = recorder.handle(combo)
                }
            }
            RunLoop.main.add(feed, forMode: .common)
        }
        RunLoop.main.add(timer, forMode: .common) // 모달 실행 루프에서도 돈다
        let outcome = recorder.run(activate: false)
        print("HOTKEYUI outcome \(outcome) registered \(HotkeyCenter.shared.current?.display ?? "-")")
        HotkeyCenter.shared.unregister() // 견본 조합은 남기지 않는다 (저장도 하지 않았다)
        fflush(stdout)
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
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        buildStatusMenu()
    }

    /// 메뉴 본체 — 언어를 바꾸면 통째로 다시 만든다 (항목 제목이 전부 문구)
    private func buildStatusMenu() {
        statusItem.button?.toolTip = L("게임 재개 / 일시정지 — 우클릭: 메뉴", "Resume / pause — right-click for the menu")
        statusMenu = NSMenu()
        statusMenu.addItem(
            withTitle: L("게임 재개 / 일시정지", "Resume / Pause"), action: #selector(toggleGame), keyEquivalent: "g"
        ).target = self
        statusMenu.addItem(withTitle: L("새 라운드", "New Round"), action: #selector(newRound), keyEquivalent: "r")
            .target = self
        practiceMenuItem = statusMenu.addItem(
            withTitle: L("연습장", "Driving Range"), action: #selector(togglePractice), keyEquivalent: ""
        )
        practiceMenuItem.target = self
        soundMenuItem = statusMenu.addItem(
            withTitle: L("사운드", "Sound"),
            action: #selector(toggleSound),
            keyEquivalent: ""
        )
        soundMenuItem.target = self
        soundMenuItem.state = SoundKit.shared.enabled ? .on : .off
        contrastMenuItem = statusMenu.addItem(
            withTitle: L("고대비 모드 (밝은 배경용)", "High Contrast (for light backgrounds)"),
            action: #selector(toggleContrast),
            keyEquivalent: ""
        )
        contrastMenuItem.target = self
        contrastMenuItem.state = Theme.highContrast ? .on : .off
        let hatItem = statusMenu.addItem(withTitle: L("모자", "Hat"), action: nil, keyEquivalent: "")
        hatMenu = NSMenu()
        hatItem.submenu = hatMenu // 항목은 열 때마다 재구성 (해금 반영)
        let styleItem = statusMenu.addItem(withTitle: L("스윙 스타일", "Swing Style"), action: nil, keyEquivalent: "")
        styleMenu = NSMenu()
        styleItem.submenu = styleMenu
        rebuildStyleMenu()
        statusMenu.addItem(withTitle: L("기록", "Records"), action: #selector(showRecords), keyEquivalent: "")
            .target = self
        let monitorItem = statusMenu.addItem(withTitle: L("모니터", "Display"), action: nil, keyEquivalent: "")
        monitorMenu = NSMenu()
        monitorItem.submenu = monitorMenu // 항목은 열 때마다 재구성 (연결 상태 반영)
        hotkeyMenuItem = statusMenu.addItem(withTitle: "", action: #selector(configureHotkey), keyEquivalent: "")
        hotkeyMenuItem.target = self
        updateHotkeyMenuTitle()
        // 언어 — 제목을 두 언어로 적어 지금 언어를 못 읽어도 찾을 수 있게
        let languageItem = statusMenu.addItem(withTitle: "언어 · Language", action: nil, keyEquivalent: "")
        let languageMenu = NSMenu()
        for pref in LanguagePref.allCases {
            let item = languageMenu.addItem(
                withTitle: pref.title,
                action: #selector(selectLanguage(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = pref.rawValue
            item.state = LanguagePref.saved == pref ? .on : .off
        }
        languageItem.submenu = languageMenu
        statusMenu.addItem(.separator())
        statusMenu.addItem(withTitle: L("종료", "Quit"), action: #selector(quit), keyEquivalent: "q").target = self
        // statusItem.menu는 비워둔다 — 지정하면 좌클릭이 메뉴를 열어 버튼 동작을 삼킨다
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let pref = LanguagePref(rawValue: raw) else { return }
        LanguagePref.saved = pref
        L10n.lang = pref.resolved
        buildStatusMenu()
        scene.languageChanged()
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            rebuildMonitorMenu()
            rebuildHatMenu()
            practiceMenuItem.state = scene.inPractice ? .on : .off // R로 나갔을 수도 있다 — 열 때마다 맞춘다
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

    /// 스윙 스타일 서브메뉴 — 프로 선수 실측 키프레임 (2026-09-15)
    private var styleMenu = NSMenu()
    private func rebuildStyleMenu() {
        styleMenu.removeAllItems()
        for style in SwingStyle.allCases {
            let item = styleMenu.addItem(withTitle: style.title, action: #selector(selectStyle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = style.rawValue
            item.state = scene.swingStyle == style ? .on : .off
        }
    }

    @objc private func selectStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let style = SwingStyle(rawValue: raw) else { return }
        scene.setSwingStyle(style)
        rebuildStyleMenu()
    }

    /// 모자 서브메뉴 — 해금된 것만 선택 가능, 잠긴 것은 필요 배지 수 안내
    private func rebuildHatMenu() {
        hatMenu.removeAllItems()
        let unlocked = Records.shared.unlockedHats
        for hat in Hat.allCases {
            let locked = !unlocked.contains(hat)
            let title = locked
                ? L("\(hat.title) — 잠김 (\(hat.lockHint))", "\(hat.title) — locked (\(hat.lockHint))") : hat.title
            let item = hatMenu.addItem(withTitle: title, action: #selector(selectHat(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = hat.rawValue
            item.isEnabled = !locked
            item.state = Records.shared.hat == hat ? .on : .off
        }
    }

    @objc private func selectHat(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let hat = Hat(rawValue: raw) else { return }
        Records.shared.hat = hat
        Records.shared.save()
        scene.applyHat(hat)
    }

    @objc private func showRecords() {
        scene.showRecordsCard()
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

    /// 연습장 ↔ 라운드. 연습장에서 다시 누르면 새 라운드로 돌아온다 (진행 중이던 라운드는 접힌다 — R과 같은 무게)
    @objc private func togglePractice() {
        if scene.inPractice {
            scene.newRound()
        } else {
            scene.enterPractice()
        }
        if scene.isGamePaused { // '새 라운드'와 같은 규칙 — 멈춰 있었으면 재개
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
