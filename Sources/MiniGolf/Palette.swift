import AppKit

/// 공유 팔레트 — 파일 간 흩어져 있던 기능색 리터럴의 단일 출처 (FINDING-002)
/// 알파는 쓰는 곳에서 withAlphaComponent로 조절한다 (색상 = 여기, 강도 = 사용처)
enum Palette {
    static let bunkerSand = NSColor(red: 0.82, green: 0.78, blue: 0.7, alpha: 1)
    static let waterBlue = NSColor(red: 0.62, green: 0.71, blue: 0.78, alpha: 1)
    static let roughGray = NSColor(white: 0.85, alpha: 1)
    static let hairline = NSColor(white: 0.94, alpha: 1) // 티·페어웨이·에이프런 지형선
}
