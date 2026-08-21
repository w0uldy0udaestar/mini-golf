import AppKit
import GolfCore

/// 창 범퍼 모드 (2026-08-21 재미 확장 1번): 열려 있는 앱 창이 범퍼가 되어
/// 비행 중인 공이 튕긴다 — '데스크탑 오버레이 골프'만이 할 수 있는 재미.
///
/// 스냅샷은 샷 순간 한 번 (비행 중 실시간 추적은 불안정하고, 정지 화면 기준이
/// 플레이어의 예측 가능성에도 낫다). CGWindowList의 창 프레임은 별도 권한 불필요.
enum WindowBumpers {
    /// 현재 게임 화면 위의 앱 창들을 물리 좌표(미터) 범퍼로 변환
    /// - pxPerM/groundBase: 씬의 미터↔pt 변환 상수 (GameScene과 동일 정의)
    static func snapshot(screen: NSScreen, pxPerM: Double, groundBase: Double) -> [Bumper] {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        // CG 전역 좌표(주 화면 좌상단 원점, y 아래로)에서 게임 화면의 영역
        guard let idNum = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return [] }
        let display = CGDirectDisplayID(idNum.uint32Value)
        let db = CGDisplayBounds(display)
        let screenH = Double(screen.frame.height)

        let myPID = ProcessInfo.processInfo.processIdentifier
        var out: [Bumper] = []
        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0, // 일반 창만
                  let pid = info[kCGWindowOwnerPID as String] as? Int32, pid != myPID,
                  let alpha = info[kCGWindowAlpha as String] as? Double, alpha > 0.1,
                  let bd = info[kCGWindowBounds as String] as? [String: Double],
                  let wx = bd["X"], let wy = bd["Y"], let ww = bd["Width"], let wh = bd["Height"]
            else { continue }
            // 게임 화면과 겹치는 부분만, 화면 로컬(pt·좌하단 원점)로
            let ix0 = max(wx, Double(db.minX)), ix1 = min(wx + ww, Double(db.maxX))
            let iyT0 = max(wy, Double(db.minY)), iyT1 = min(wy + wh, Double(db.maxY))
            guard ix1 - ix0 > 90, iyT1 - iyT0 > 60 else { continue } // 팝오버·툴팁 등 잔챙이 제외
            let lx = ix0 - Double(db.minX)
            let lyBottom = screenH - (iyT1 - Double(db.minY)) // top-down → bottom-up
            // '키 큰' 창(상단이 화면 85% 위까지)은 제외 — 최대화·세로 분할 창은 어떤 샷으로도
            // 못 넘는 차단벽이 되어 게임을 부순다. 범퍼의 재미는 중간 크기 창들의 핀볼
            guard lyBottom + (iyT1 - iyT0) < screenH * 0.85 else { continue }
            // pt → 물리(미터): x는 스케일, y는 표고 역변환
            out.append(Bumper(
                x: lx / pxPerM,
                y: (lyBottom - groundBase) / pxPerM,
                w: (ix1 - ix0) / pxPerM,
                h: (iyT1 - iyT0) / pxPerM
            ))
        }
        return out
    }
}
