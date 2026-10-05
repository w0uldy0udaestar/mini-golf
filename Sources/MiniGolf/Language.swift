import Foundation
import GolfCore

/// 표시 언어 설정 (2026-10-05 영어화, M6). ⛳️ 메뉴 → 언어. 기본은 시스템 설정을 따른다 — macOS 선호 언어 첫째가 한국어면 한국어, 아니면 영어.
/// 문구 자체는 호출부의 `L("한국어", "English")` (GolfCore/L10n.swift)
enum LanguagePref: String, CaseIterable {
    case system, ko, en

    static let key = "language"

    static var saved: LanguagePref {
        get { UserDefaults.standard.string(forKey: key).flatMap(LanguagePref.init(rawValue:)) ?? .system }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }

    /// 시스템 선호 언어 목록 → 표시 언어
    static func systemLanguage(_ preferred: [String] = Locale.preferredLanguages) -> Lang {
        let first = (preferred.first ?? "en").lowercased() // "ko"·"ko-KR"·"ko_KR" — "kok"(콘칸어)처럼 ko로 시작하는 다른 언어는 제외
        return first == "ko" || first.hasPrefix("ko-") || first.hasPrefix("ko_") ? .ko : .en
    }

    var resolved: Lang {
        switch self {
        case .system: Self.systemLanguage()
        case .ko: .ko
        case .en: .en
        }
    }

    /// 메뉴 항목 — 언어 이름은 그 언어로 적는다 (지금 언어를 못 읽는 사람도 자기 언어는 찾는다)
    var title: String {
        switch self {
        case .system: L("시스템 설정 따름", "Follow System")
        case .ko: "한국어"
        case .en: "English"
        }
    }
}
