import AppKit

/// 공유 팔레트 — 파일 간 흩어져 있던 기능색 리터럴의 단일 출처 (FINDING-002)
/// 알파는 쓰는 곳에서 withAlphaComponent로 조절한다 (색상 = 여기, 강도 = 사용처)
enum Palette {
    static let bunkerSand = NSColor(red: 0.82, green: 0.78, blue: 0.7, alpha: 1)
    static let waterBlue = NSColor(red: 0.62, green: 0.71, blue: 0.78, alpha: 1)
    static let roughGray = NSColor(white: 0.85, alpha: 1)
    static let hairline = NSColor(white: 0.94, alpha: 1) // 티·페어웨이·에이프런 지형선
    static let flagRed = NSColor(red: 0.85, green: 0.3, blue: 0.24, alpha: 1) // 깃발 = 유일한 포인트 컬러
}

/// 고대비 모드 — 밝은 배경 사용자를 위한 opt-in 듀얼톤 (기본 꺼짐 = 원래의 '조용한' 디자인)
/// 사용자 피드백(2026-08-14): 상시 다크 림은 이질감 → 기본값 복원, 토글로 전환
enum Theme {
    static var highContrast = UserDefaults.standard.bool(forKey: "highContrast") {
        didSet { UserDefaults.standard.set(highContrast, forKey: "highContrast") }
    }

    /// 창 범퍼 모드 (2026-08-21 재미 확장 1번) — 기본 ON: 이 게임의 정체성 재미
    static var windowBumpers = UserDefaults.standard.object(forKey: "windowBumpers") as? Bool ?? true {
        didSet { UserDefaults.standard.set(windowBumpers, forKey: "windowBumpers") }
    }
}
