// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "mini-golf",
    platforms: [.macOS(.v13)],
    targets: [
        // M0 리스크 스파이크: 투명 오버레이·클릭 통과·키 캡처 검증용 (PLAN.md M0)
        .executableTarget(name: "MiniGolfSpike", path: "Sources/MiniGolfSpike")
    ]
)
