// 개발용 (앱에는 포함되지 않음) — scripts/capture-window.py의 짝.
// 사용: flatten in.png out.png [x y w h (창 크기에 대한 비율 0~1, 좌상단 원점)] [maxW px]
// 투명 배경 창 캡처를 어두운 회색 위에 얹고, 필요하면 잘라서 줄인다. 불투명 픽셀 비율도 출력한다 —
// 게임 그림만 찍혔다면 불투명은 1% 미만이다(바탕화면이 섞였으면 100%에 가깝다).
import AppKit
import CoreGraphics
import Foundation

let a = CommandLine.arguments
guard a.count >= 3, let src = NSImage(contentsOfFile: a[1]), let cg = src.cgImage(
    forProposedRect: nil,
    context: nil,
    hints: nil
) else {
    print("load fail"); exit(1)
}

let W = cg.width, H = cg.height
/// 불투명 픽셀 비율
let ctxA = CGContext(
    data: nil,
    width: W,
    height: H,
    bitsPerComponent: 8,
    bytesPerRow: W * 4,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!
ctxA.draw(cg, in: CGRect(x: 0, y: 0, width: W, height: H))
let buf = ctxA.data!.assumingMemoryBound(to: UInt8.self)
var opaque = 0, anyA = 0
for i in stride(from: 3, to: W * H * 4, by: 4) {
    if buf[i] > 250 {
        opaque += 1
    }; if buf[i] > 8 {
        anyA += 1
    }
}

var crop = CGRect(x: 0, y: 0, width: W, height: H)
var maxW = 1600
if a.count >= 7 { // 잘라낼 영역: 창 크기에 대한 비율 (x y w h, 0~1, 좌상단 원점)
    let v = a[3 ... 6].map { CGFloat(Double($0) ?? 0) }
    crop = CGRect(x: v[0] * CGFloat(W), y: v[1] * CGFloat(H), width: v[2] * CGFloat(W), height: v[3] * CGFloat(H))
        .intersection(crop)
    if a.count >= 8 {
        maxW = Int(a[7]) ?? 1600
    }
} else if a.count >= 4 {
    maxW = Int(a[3]) ?? 1600
}

guard let sub = cg.cropping(to: crop) else { print("crop fail"); exit(1) }
let k = min(1, CGFloat(maxW) / CGFloat(sub.width))
let ow = Int(CGFloat(sub.width) * k), oh = Int(CGFloat(sub.height) * k)
let ctx = CGContext(
    data: nil,
    width: ow,
    height: oh,
    bitsPerComponent: 8,
    bytesPerRow: ow * 4,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!
ctx.setFillColor(CGColor(gray: 0.17, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: ow, height: oh))
ctx.interpolationQuality = .high
ctx.draw(sub, in: CGRect(x: 0, y: 0, width: ow, height: oh))
let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[2]))
print(String(
    format: "src %dx%d opaque %.2f%% drawn %.2f%% → %dx%d",
    W,
    H,
    Double(opaque) * 100 / Double(W * H),
    Double(anyA) * 100 / Double(W * H),
    ow,
    oh
))
