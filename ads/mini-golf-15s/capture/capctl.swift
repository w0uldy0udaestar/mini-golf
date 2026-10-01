// 캡처 보조 도구 (광고 캡처 전용 — 게임 소스와 무관)
//   capctl front            → 지금 앞에 있는 앱의 PID
//   capctl activate <pid>   → 그 앱을 다시 앞으로 (개발 인스턴스가 실행 시 포커스를 가져가는 것 복구)
//   capctl winid <pid>      → 그 PID의 화면 위 창 ID (여러 개면 가장 큰 것)
//   capctl stream <pid> <outdir> <fps> <seconds> <scale>
//        → ScreenCaptureKit 단일 창 스트림, 알파 보존 PNG 연사 (scale 1 = 포인트 해상도, 2 = 레티나)
import AppKit
import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit
import UniformTypeIdentifiers

let args = CommandLine.arguments
_ = NSApplication.shared // CGS 초기화 (SCK·CGWindowList가 요구)
func winID(_ pid: Int32) -> Int? {
    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    var best: (Int, Double)?
    for w in info where (w[kCGWindowOwnerPID as String] as? Int32) == pid {
        let b = w[kCGWindowBounds as String] as? [String: Double] ?? [:]
        let area = (b["Width"] ?? 0) * (b["Height"] ?? 0)
        let id = w[kCGWindowNumber as String] as? Int ?? 0
        if best == nil || area > best!.1 { best = (id, area) }
    }
    return best?.0
}

final class Sink: NSObject, SCStreamOutput {
    let out: URL; let q = DispatchQueue(label: "png", attributes: .concurrent)
    var n = 0; var t0: CMTime?; let group = DispatchGroup(); var times: [Double] = []; var walls: [Double] = []
    init(out: URL) { self.out = out }
    func stream(_: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sb.isValid, let pb = sb.imageBuffer else { return }
        // 새 프레임만 (idle 프레임은 attachments status로 거른다)
        if let arr = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let raw = arr.first?[.status] as? Int, let st = SCFrameStatus(rawValue: raw), st != .complete { return }
        let pts = sb.presentationTimeStamp
        if t0 == nil { t0 = pts }
        let t = CMTimeGetSeconds(CMTimeSubtract(pts, t0!))
        let ci = CIImage(cvPixelBuffer: pb)
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(ci, from: ci.extent, format: .BGRA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else { return }
        let idx = n; n += 1; times.append(t); walls.append(Date().timeIntervalSince1970)
        let url = out.appendingPathComponent(String(format: "f%05d.png", idx))
        group.enter()
        q.async {
            if let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) {
                CGImageDestinationAddImage(d, cg, nil); CGImageDestinationFinalize(d)
            }
            self.group.leave()
        }
    }
}

switch args.count > 1 ? args[1] : "" {
case "front":
    print(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0)
case "activate":
    if let pid = Int32(args[2]), let app = NSRunningApplication(processIdentifier: pid) {
        print(app.activate() ? "ok" : "fail")
    }
case "winid":
    print(winID(Int32(args[2]) ?? 0) ?? 0)
case "stream":
    let pid = Int32(args[2])!; let out = URL(fileURLWithPath: args[3])
    let fps = Int32(args[4])!; let secs = Double(args[5])!; let scale = Int(args[6])!
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let sem = DispatchSemaphore(value: 0)
    let sink = Sink(out: out)
    Task.detached {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let win = content.windows.first(where: { $0.owningApplication?.processID == pid && $0.frame.width > 400 }) else {
                print("no window"); sem.signal(); return
            }
            let filter = SCContentFilter(desktopIndependentWindow: win)
            let cfg = SCStreamConfiguration()
            cfg.width = Int(win.frame.width) * scale; cfg.height = Int(win.frame.height) * scale
            cfg.minimumFrameInterval = CMTime(value: 1, timescale: fps)
            cfg.pixelFormat = kCVPixelFormatType_32BGRA
            cfg.showsCursor = false
            cfg.queueDepth = 8
            if #available(macOS 14.0, *) { cfg.shouldBeOpaque = false; cfg.ignoreShadowsSingleWindow = true }
            let s = SCStream(filter: filter, configuration: cfg, delegate: nil)
            try s.addStreamOutput(sink, type: .screen, sampleHandlerQueue: DispatchQueue(label: "cap"))
            try await s.startCapture()
            try await Task.sleep(nanoseconds: UInt64(secs * 1e9))
            try await s.stopCapture()
            sink.group.wait()
            let span = sink.times.last ?? 0
            print(String(format: "frames %d span %.2fs fps %.1f", sink.n, span, span > 0 ? Double(sink.n - 1) / span : 0))
            try? zip(sink.times, sink.walls).map { String(format: "%.4f %.3f", $0.0, $0.1) }.joined(separator: "\n")
                .write(to: out.appendingPathComponent("times.txt"), atomically: true, encoding: .utf8)
        } catch { print("error \(error)") }
        sem.signal()
    }
    sem.wait()
default:
    print("usage: capctl front|activate|winid|stream")
}
