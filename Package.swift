// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "mini-golf",
    platforms: [.macOS(.v13)],
    targets: [
        // 게임 코어: 클럽·코스 생성·탄도 물리 — UI 의존 없는 순수 로직 (단위 테스트 대상)
        .target(name: "GolfCore"),
        // M0 리스크 스파이크: 투명 오버레이·클릭 통과·키 캡처 검증용 (PLAN.md M0)
        .executableTarget(name: "MiniGolfSpike", path: "Sources/MiniGolfSpike"),
        // M1: 1홀 플레이 가능한 오버레이 앱
        .executableTarget(name: "MiniGolf", dependencies: ["GolfCore"], path: "Sources/MiniGolf"),
        .testTarget(name: "GolfCoreTests", dependencies: ["GolfCore"]),
    ]
)
