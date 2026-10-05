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
            XCTAssertNil(Weather.clear.label)
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
    /// 로그(print·PlayLog·log3)와 주석은 제외, 허용 목록은 한국어 원본을 일부러 두는 자리
    func testNoBareKoreanLiteralsInSources() throws {
        let allow = ["name: \"", "\"한국어\"", "\"언어 · Language\""] // 클럽 원본 이름(displayName이 감싼다) · 언어 메뉴
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources")
        var offenders: [String] = []
        for dir in ["GolfCore", "MiniGolf"] {
            let folder = root.appendingPathComponent(dir)
            for file in try FileManager.default.contentsOfDirectory(atPath: folder.path)
                where file.hasSuffix(".swift") {
                let src = try String(contentsOf: folder.appendingPathComponent(file), encoding: .utf8)
                let body = Self
                    .stripLCalls(src.split(separator: "\n", omittingEmptySubsequences: false).map(Self.stripComment)
                        .joined(separator: "\n"))
                for (n, line) in body.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                    guard Self.hasKoreanLiteral(String(line)) else { continue }
                    if ["print(", "PlayLog.note(", "log3(", "fatalError("].contains(where: line.contains) {
                        continue
                    }
                    if allow.contains(where: line.contains) {
                        continue
                    }
                    offenders.append("\(dir)/\(file):\(n + 1): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty, "L(한국어, 영어) 밖의 한글 문구:\n" + offenders.joined(separator: "\n"))
    }

    /// 문자열 밖의 `//`부터 줄 끝까지 지운다
    private static func stripComment(_ line: Substring) -> String {
        var out = "", inString = false
        var prev: Character = " "
        var it = line.makeIterator()
        while let c = it.next() {
            if c == "\"", prev != "\\" {
                inString.toggle()
            }
            if !inString, c == "/", prev == "/" {
                out.removeLast()
                break
            }
            out.append(c)
            prev = c
        }
        return out
    }

    /// `L( … )` 호출을 괄호 짝을 맞춰 통째로 지운다 (여러 줄 호출 포함 — 줄 수는 유지)
    private static func stripLCalls(_ src: String) -> String {
        let chars = Array(src)
        var out = ""
        var i = 0
        while i < chars.count {
            let isCall = chars[i] == "L" && i + 1 < chars.count && chars[i + 1] == "("
                && (i == 0 || !(chars[i - 1].isLetter || chars[i - 1].isNumber || chars[i - 1] == "_"))
            guard isCall else {
                out.append(chars[i])
                i += 1
                continue
            }
            var depth = 0, inString = false
            var j = i + 1
            while j < chars.count {
                let c = chars[j]
                if c == "\"", chars[j - 1] != "\\" {
                    inString.toggle()
                }
                if c == "\n" {
                    out.append("\n")
                }
                if !inString {
                    if c == "(" {
                        depth += 1
                    }
                    if c == ")" {
                        depth -= 1
                        if depth == 0 {
                            break
                        }
                    }
                }
                j += 1
            }
            i = j + 1
        }
        return out
    }

    private static func hasKoreanLiteral(_ line: String) -> Bool {
        var inString = false, found = false
        var prev: Character = " "
        for c in line {
            if c == "\"", prev != "\\" {
                if inString, found {
                    return true
                }
                inString.toggle()
                found = false
            } else if inString, c.unicodeScalars.contains(where: { (0xAC00 ... 0xD7A3).contains($0.value) }) {
                found = true
            }
            prev = c
        }
        return false
    }
}
