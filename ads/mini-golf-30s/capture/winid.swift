// 사용: swift winid.swift <pid>  → 해당 PID 소유의 화면 위 창 ID들 (layer, bounds) 출력
import CoreGraphics
import Foundation
let pid = Int32(CommandLine.arguments.dropFirst().first ?? "0") ?? 0
let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for w in info {
    guard let p = w[kCGWindowOwnerPID as String] as? Int32, pid == 0 || p == pid else { continue }
    let owner = w[kCGWindowOwnerName as String] as? String ?? ""
    guard pid != 0 || owner.contains("MiniGolf") else { continue }
    let id = w[kCGWindowNumber as String] as? Int ?? 0
    let layer = w[kCGWindowLayer as String] as? Int ?? 0
    let b = w[kCGWindowBounds as String] as? [String: Double] ?? [:]
    print(id, p, owner, layer, Int(b["Width"] ?? 0), Int(b["Height"] ?? 0))
}
