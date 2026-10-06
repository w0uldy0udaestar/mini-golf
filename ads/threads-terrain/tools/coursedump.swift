// 광고 데이터 도구 (앱에 포함되지 않음): 게임 코스 생성기·탄도 엔진(GolfCore)을 그대로 불러 홀 지형과 샷 궤적을 JSON으로 덤프한다.
// 빌드: swiftc -O -I .build/debug ads/threads-terrain/tools/coursedump.swift .build/debug/GolfCore.o -o <bin>
//   coursedump list <seed>                       → 홀마다 par·아키타입·티·컵·월드 폭·물
//   coursedump hole <seed> <n>                    → 그 홀의 1m 표고·구간·장애물(JSON)
//   coursedump sim <seed> <n> <x> <club> <h> <shape> <lie> [dir]  → 240Hz 탄도를 120Hz로 기록(JSON)
import Foundation
import GolfCore

let a = CommandLine.arguments
func out(_ o: Any) { let d = try! JSONSerialization.data(withJSONObject: o, options: []); print(String(data: d, encoding: .utf8)!) }
let seed = UInt32(a[2])!
let holes = CourseGenerator.makeCourse(seed: seed)
switch a[1] {
case "list":
    for (i, h) in holes.enumerated() {
        let water = h.segments.contains { $0.type == .water }
        print(i + 1, "par", h.par, h.signature.map { "\($0)" } ?? "plain", "tee", Int(h.teeX), "cup", Int(h.holeX), "W", Int(h.worldW),
              "water", water ? "\(h.waterRange.map { "\(Int($0.lowerBound))-\(Int($0.upperBound))" } ?? "seg")" : "-",
              "green", Int(h.greenStart), Int(h.greenEnd), "elev", String(format: "%.1f..%.1f", h.elevation.min()!, h.elevation.max()!))
    }
case "hole":
    let h = holes[Int(a[3])! - 1]
    out([
        "par": h.par, "sig": h.signature.map { "\($0)" } ?? "plain", "teeX": h.teeX, "holeX": h.holeX, "worldW": h.worldW, "wind": h.wind,
        "greenStart": h.greenStart, "greenEnd": h.greenEnd,
        "elev": h.elevation.map { (($0 * 100).rounded()) / 100 },
        "segs": h.segments.map { ["from": $0.from, "to": $0.to, "type": $0.type.rawValue] },
        "obs": h.obstacles.map { ["kind": $0.kind == .tree ? "tree" : "rock", "x": $0.x, "size": $0.size,
                                  "cy": $0.kind == .tree ? $0.canopyCenterY(above: 0) : $0.rockCenterY(above: 0)] },
        "water": h.waterRange.map { [$0.lowerBound, $0.upperBound] } ?? [],
    ])
case "sim":
    let h = holes[Int(a[3])! - 1]
    let x0 = Double(a[4])!, club = ClubTable.all.first { $0.id == a[5] }!, hp = Double(a[6])!
    let shape = ShotShape(rawValue: a[7]) ?? .standard, lie = Surface(rawValue: a[8]) ?? .fairway
    let dir = a.count > 9 ? Double(a[9])! : 1
    var b = BallState(x: x0, y: h.ground(at: x0) + (lie == .tee ? 0.15 : 0))
    Ballistics.launch(&b, club: club, heightPct: hp, lie: lie, dir: dir, slope: 0, shape: shape)
    var pts: [[Double]] = [], evs: [[Any]] = []
    var t = 0.0, k = 0
    pts.append([0, b.x, b.y])
    while t < 14 {
        let ev = Ballistics.step(&b, hole: h)
        t += Phys.dt; k += 1
        switch ev {
        case .none: break
        case .holed: evs.append([t, "holed", b.x])
        case .water: evs.append([t, "water", b.x])
        case let .bounce(speed, surface): evs.append([t, "bounce", b.x, speed, surface.rawValue])
        case .lipOut: evs.append([t, "lip", b.x])
        case .wall: evs.append([t, "wall", b.x])
        }
        if k % 2 == 0 { pts.append([(t * 1000).rounded() / 1000, (b.x * 1000).rounded() / 1000, (b.y * 1000).rounded() / 1000]) }
        if b.phase == .rest || ev == .holed || ev == .water { break }
    }
    out(["pts": pts, "ev": evs, "rest": [b.x, b.y], "t": t])
default: break
}
