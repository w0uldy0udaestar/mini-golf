import GolfCore
@testable import MiniGolf
import XCTest

/// 영어화 (2026-10-05 M6): 언어 전환·시스템 언어 판정, 그리고 "화면 문구는 `L(한국어, 영어)`로만"이라는 약속의 감시
final class LocalizationTests: XCTestCase {
    override func tearDown() {
        L10n.lang = .ko // 다른 테스트는 한국어 문구를 기대한다
        super.tearDown()
    }

    func testSwitchingLanguageChangesLabels() {
        L10n.lang = .ko
        XCTAssertEqual(scoreName(strokes: 3, par: 4), "버디")
        XCTAssertEqual(Surface.bunker.label, "벙커")
        XCTAssertEqual(ClubTable.all[0].displayName, "드라이버")
        XCTAssertEqual(Badge.firstBirdie.title, "첫 버디")
        L10n.lang = .en
        XCTAssertEqual(scoreName(strokes: 3, par: 4), "Birdie")
        XCTAssertEqual(Surface.bunker.label, "Bunker")
        XCTAssertEqual(ClubTable.all.map(\.displayName), [
            "Driver", "3 wood", "5 wood", "3 iron", "4 iron", "5 iron", "6 iron", "7 iron", "8 iron", "9 iron",
            "Pitching wedge", "Sand wedge", "Putter",
        ])
        XCTAssertEqual(Badge.firstBirdie.title, "First birdie")
        XCTAssertEqual(MissionKind.greenInReg.title(par: 3), "On the green in one")
        XCTAssertEqual(MissionKind.greenInReg.title(par: 5), "On the green in 3")
    }

    func testEveryCaseHasBothLanguages() {
        for lang in Lang.allCases {
            L10n.lang = lang
            for s in Surface.allCases {
                XCTAssertFalse(s.label.isEmpty)
            }
            for k in SignatureKind.allCases {
                XCTAssertFalse(k.displayName.isEmpty)
            }
            for b in Badge.allCases {
                XCTAssertFalse(b.title.isEmpty)
            }
            for h in Hat.allCases {
                XCTAssertFalse(h.title.isEmpty)
            }
            for m in MissionKind.allCases {
                XCTAssertFalse(m.title(par: 4).isEmpty)
            }
            XCTAssertNil(Weather.clear.cue)
            XCTAssertNotNil(Weather.rain.cue)
        }
        // 영어 화면에 한글이 섞여 나오지 않는다 (열거형 문구 전체)
        L10n.lang = .en
        let english = Surface.allCases.map(\.label) + SignatureKind.allCases.map(\.displayName) + Badge.allCases
            .map(\.title)
            + Hat.allCases.map(\.title) + MissionKind.allCases.map { $0.title(par: 4) } + RoughLie.allCases.map(\.label)
            + ClubTable.all.map(\.displayName) + SwingStyle.allCases.map(\.title) + [
                Weather.rain.cue ?? "",
                Weather.gale.cue ?? "",
            ]
            + (1 ... 8).map { scoreName(strokes: $0, par: 4) }
        for s in english {
            XCTAssertNil(s.unicodeScalars.first { (0xAC00 ... 0xD7A3).contains($0.value) }, "영어 문구에 한글: \(s)")
        }
    }

    func testSystemLanguageDetection() {
        XCTAssertEqual(LanguagePref.systemLanguage(["ko-KR", "en-US"]), .ko)
        XCTAssertEqual(LanguagePref.systemLanguage(["ko"]), .ko)
        XCTAssertEqual(LanguagePref.systemLanguage(["en-US", "ko-KR"]), .en, "첫째 선호 언어만 본다")
        XCTAssertEqual(LanguagePref.systemLanguage(["ja-JP"]), .en, "한국어가 아니면 영어")
        XCTAssertEqual(LanguagePref.systemLanguage([]), .en)
        XCTAssertEqual(LanguagePref.ko.resolved, .ko)
        XCTAssertEqual(LanguagePref.en.resolved, .en)
    }

    /// 소스에 `L(…)` 밖의 한글 문자열 리터럴이 없어야 한다 — 새 토스트를 넣으며 영어를 빼먹으면 여기서 걸린다.
    /// 로그(print·PlayLog·log3·fatalError) 안과 주석은 제외, 허용 목록은 한국어 원본을 일부러 두는 자리.
    /// `L(a, b)`의 영어 자리(b)에 한글이 있어도 걸린다 (복사해 붙이고 번역을 잊은 경우)
    func testNoBareKoreanLiteralsInSources() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources")
        var offenders: [String] = []
        for dir in ["GolfCore", "MiniGolf"] {
            let folder = root.appendingPathComponent(dir)
            for file in try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
                where file.hasSuffix(".swift") {
                let src = try String(contentsOf: folder.appendingPathComponent(file), encoding: .utf8)
                offenders += Self.offendingLiterals(in: src, file: file).map { "\(dir)/\(file):\($0)" }
            }
        }
        XCTAssertTrue(offenders.isEmpty, "L(한국어, 영어) 밖의 한글 문구 또는 영어 자리의 한글:\n" + offenders.joined(separator: "\n"))
    }

    /// 스캐너 자체의 검증 — 놓치기 쉬운 꼴을 잡고, 정상 코드는 통과시키는가 (리뷰가 찾은 빈틈 6가지 + 오탐 1가지)
    func testScannerCatchesTrickyShapes() {
        func hits(_ src: String, file: String = "X.swift") -> Int {
            Self.offendingLiterals(in: src, file: file).count
        }
        XCTAssertEqual(hits(#"let a = "잡혀야 한다""#), 1, "대조군")
        XCTAssertEqual(hits(#"let a = L("한국어", "English")"#), 0)
        XCTAssertEqual(hits(#"let a = "\(n)\(n > 1 ? "개" : "")""#), 1, "보간 안의 중첩 리터럴")
        XCTAssertEqual(hits(#"let t = (name: "모자", size: 1)"#), 1, "name: 은 ClubTable에서만 허용")
        XCTAssertEqual(hits(#"Club(id: "DR", name: "드라이버", cat: .wood)"#, file: "ClubTable.swift"), 0)
        XCTAssertEqual(hits("let a = \"\"\"\n  여러 줄 문자열\n  \"\"\""), 1, "여러 줄 문자열")
        XCTAssertEqual(hits(#"let a = "ㅋㅋㅋ""#), 1, "자모만 있는 문자열")
        XCTAssertEqual(hits(#"print("x"); return "안녕""#), 1, "같은 줄에 print가 있어도 그 밖의 리터럴은 잡는다")
        XCTAssertEqual(hits(#"let a = L("한국어만", "한국어만")"#), 1, "영어 자리의 한글")
        XCTAssertEqual(hits(#"let a = L("\(n)개", "\(n > 1 ? "개" : "")")"#), 1, "영어 자리 보간 안의 한글")
        XCTAssertEqual(hits("PlayLog.note(\n    \"여러 줄 로그 호출의 둘째 줄\"\n)"), 0, "여러 줄 로그 호출은 통째로 제외")
        XCTAssertEqual(hits("PlayLog\n    .note(\"줄을 바꿔 이은 호출\")"), 0, "포매터가 체인을 줄바꿈해도 같은 호출")
        XCTAssertEqual(hits("let x = foo\nbar(\"앞 줄 식별자와 무관\")"), 1)
        XCTAssertEqual(hits(#"let a = "\\"; let b = "역슬래시 뒤""#), 1, "이스케이프된 역슬래시 뒤의 리터럴")
        XCTAssertEqual(hits("// \"주석 속 한글\"\nlet a = 1 /* \"블록 주석\" */"), 0)
        XCTAssertEqual(hits(#"toast(L("미션", "Mission") + " · " + title)"#), 0)
        XCTAssertEqual(hits(#"case .ko: "한국어""#, file: "Language.swift"), 0)
    }

    private static func hasHangul(_ s: String) -> Bool {
        s.unicodeScalars.contains { // 음절 · 호환 자모(ㅋ·ㅎ) · 조합 자모
            (0xAC00 ... 0xD7A3).contains($0.value) || (0x3131 ... 0x318E).contains($0.value) || (0x1100 ... 0x11FF)
                .contains($0.value)
        }
    }

    /// 한국어 원본을 일부러 두는 자리
    private static func allowed(_ text: String, file: String, callees: [String]) -> Bool {
        if file == "ClubTable.swift", callees.last == "Club" { // 클럽 원본 이름 — displayName이 L()로 감싼다
            return true
        }
        return text == "한국어" || text == "언어 · Language" // 언어 메뉴: 그 언어로 적는다
    }

    /// 소스를 훑어 문제가 되는 문자열 리터럴을 "줄: 내용"으로 돌려준다.
    /// 괄호마다 호출 이름(L·print·PlayLog.note…)과 인자 순번을 쌓아, 리터럴이 어느 호출의 몇 번째 인자 안에 있는지 안다.
    /// 문자열 보간 `\(…)`은 코드로 돌아갔다가 닫히면 문자열로 복귀한다 (중첩 리터럴·중첩 호출 처리)
    static func offendingLiterals(in src: String, file: String) -> [String] {
        struct Frame { var callee: String; var arg = 0; var resumesString = false; var tripleOnResume = false }
        let exempt: Set = ["print", "PlayLog.note", "log3", "fatalError"]
        let chars = Array(src)
        var out: [String] = []
        var frames: [Frame] = []
        var line = 1
        var i = 0
        var ident = "" // 직전 식별자 (점 포함) — "(" 앞에 있으면 호출 이름
        var spaced = false // ident 뒤에 공백이 있었다
        func at(_ k: Int) -> Character? {
            k < chars.count ? chars[k] : nil
        }

        // 문자열 본문을 읽는다: i는 여는 따옴표 다음. 보간을 만나면 프레임을 쌓고 코드로 돌아간다(반환 false = 아직 문자열이 안 끝남)
        var literal = ""
        var literalLine = 0
        func finishLiteral() {
            defer { literal = "" }
            guard hasHangul(literal) else { return }
            let callees = frames.map(\.callee)
            if allowed(literal, file: file, callees: callees) {
                return
            }
            if let l = frames.last(where: { $0.callee == "L" }) {
                if l.arg >= 1 { // 영어 자리
                    out.append("\(literalLine): 영어 자리의 한글 \"\(literal)\"")
                }
                return
            }
            if callees.contains(where: exempt.contains) {
                return
            }
            out.append("\(literalLine): \"\(literal)\"")
        }
        /// 반환: 문자열이 닫혔으면 true, 보간으로 코드에 들어갔으면 false
        func readString(triple: Bool) -> Bool {
            while i < chars.count {
                let c = chars[i]
                if c == "\n" {
                    line += 1
                }
                if c == "\\" {
                    if at(i + 1) == "(" { // 보간 시작 — 지금까지의 조각을 판정하고 코드로
                        finishLiteral()
                        frames.append(Frame(callee: "", resumesString: true, tripleOnResume: triple))
                        i += 2
                        return false
                    }
                    literal.append(c)
                    if let n = at(i + 1) {
                        literal.append(n)
                    }
                    i += 2
                    continue
                }
                if c == "\"" {
                    if triple {
                        if at(i + 1) == "\"", at(i + 2) == "\"" {
                            i += 3
                            finishLiteral()
                            return true
                        }
                    } else {
                        i += 1
                        finishLiteral()
                        return true
                    }
                }
                literal.append(c)
                i += 1
            }
            finishLiteral()
            return true
        }

        while i < chars.count {
            let c = chars[i]
            if c == "\n" {
                line += 1
                i += 1
                spaced = !ident.isEmpty
                continue
            }
            if c == "/", at(i + 1) == "/" { // 줄 주석
                while i < chars.count, chars[i] != "\n" {
                    i += 1
                }
                continue
            }
            if c == "/", at(i + 1) == "*" { // 블록 주석
                i += 2
                while i < chars.count, !(chars[i] == "*" && at(i + 1) == "/") {
                    if chars[i] == "\n" {
                        line += 1
                    }
                    i += 1
                }
                i += 2
                continue
            }
            if c == "\"" {
                let triple = at(i + 1) == "\"" && at(i + 2) == "\""
                i += triple ? 3 : 1
                literalLine = line
                _ = readString(triple: triple)
                ident = ""
                continue
            }
            if c == "(" {
                frames.append(Frame(callee: ident))
                ident = ""
                i += 1
                continue
            }
            if c == ")" {
                let closed = frames.popLast()
                ident = ""
                i += 1
                if let closed, closed.resumesString { // 보간이 끝났다 — 문자열 본문으로 복귀
                    literalLine = line
                    _ = readString(triple: closed.tripleOnResume)
                }
                continue
            }
            if c == ",", !frames.isEmpty {
                frames[frames.count - 1].arg += 1
                ident = ""
                i += 1
                continue
            }
            // 호출 이름 모으기. 줄을 바꿔 이어 쓴 체인(`PlayLog⏎    .note(`)도 한 이름으로 — 공백 뒤에 점이 오면 잇는다
            if c == " " || c == "\t" {
                spaced = !ident.isEmpty
            } else if c == ".", !ident.isEmpty {
                ident.append(c)
                spaced = false
            } else if c.isLetter || c.isNumber || c == "_" {
                if spaced {
                    ident = ""
                }
                ident.append(c)
                spaced = false
            } else {
                ident = ""
                spaced = false
            }
            i += 1
        }
        return out
    }
}
