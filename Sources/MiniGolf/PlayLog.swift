import Foundation

/// 실플레이 증거 로그 — `~/Library/Logs/MiniGolf/play.log`에 append. `.app` 실행은 데모 stdout이 닿지 않아 판정 근거가
/// 남지 않았다(2026-09-23 "온그린 연출이 보이지 않음" — 데모에서는 발동, 실플레이 원인 미상). 홀·샷·정지·홀인·워터만 한 줄씩.
enum PlayLog {
    nonisolated(unsafe) static let handle: FileHandle? = {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/MiniGolf")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("play.log")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let h = try? FileHandle(forWritingTo: url)
        h?.seekToEndOfFile()
        return h
    }()

    nonisolated(unsafe) static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static func note(_ line: String) {
        guard let h = handle, let d = (stamp.string(from: Date()) + " " + line + "\n").data(using: .utf8) else { return }
        h.write(d)
    }
}
