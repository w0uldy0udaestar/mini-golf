/// 표시 언어 (2026-10-05 영어화, M6). 문구는 호출부에 두 언어를 나란히 적는다 — `L("버디", "Birdie")`.
/// 문자열 키 파일(.strings) 대신 인라인인 이유: 앱 번들을 Makefile이 손으로 조립해 리소스 번들 경로가 하나 더 깨질 자리이고,
/// 문구가 200개 남짓이라 호출부에서 바로 읽히는 쪽이 고치기 쉽다. 언어가 셋 이상이 되면 그때 키 파일로 옮긴다
public enum Lang: String, Sendable, CaseIterable {
    case ko, en
}

public enum L10n {
    /// 현재 표시 언어 — 앱이 실행 시·메뉴 선택 시 정한다 (GolfCore는 읽기만). 기본 한국어라 테스트는 영향 없음
    public static var lang = Lang.ko
}

/// 현재 언어의 문구
public func L(_ ko: String, _ en: String) -> String {
    L10n.lang == .ko ? ko : en
}
