import AppKit

/// 공유 팔레트 — 파일 간 흩어져 있던 기능색 리터럴의 단일 출처 (FINDING-002)
/// 알파는 쓰는 곳에서 withAlphaComponent로 조절한다 (색상 = 여기, 강도 = 사용처)
enum Palette {
    static let bunkerSand = NSColor(red: 0.82, green: 0.78, blue: 0.7, alpha: 1)
    static let waterBlue = NSColor(red: 0.62, green: 0.71, blue: 0.78, alpha: 1)
    static let roughGray = NSColor(white: 0.85, alpha: 1)
    static let hairline = NSColor(white: 0.94, alpha: 1) // 티·페어웨이·에이프런 지형선
}

/// 고대비 모드 — 밝은 배경 사용자를 위한 opt-in 듀얼톤 (기본 꺼짐 = 원래의 '조용한' 디자인)
/// 사용자 피드백(2026-08-14): 상시 다크 림은 이질감 → 기본값 복원, 토글로 전환
enum Theme {
    static var highContrast = UserDefaults.standard.bool(forKey: "highContrast") {
        didSet { UserDefaults.standard.set(highContrast, forKey: "highContrast") }
    }
}
