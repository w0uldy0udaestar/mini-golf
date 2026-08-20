import AppKit

// 앱 아이콘 생성기 — 게임의 시각 언어(다크 카드·헤어라인 지형·스틱맨·깃발 레드)를
// CoreGraphics로 1024px에 그린다. 실행: swift scripts/gen-app-icon.swift <out.png>
// (WebKit 렌더는 모서리 투명도가 불안정해서 CG 직접 드로잉 — 결정론적)

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"
let S = 1024

let ink = CGColor(red: 0.957, green: 0.957, blue: 0.945, alpha: 1) // #F4F4F1
let line = CGColor(red: 0.725, green: 0.725, blue: 0.706, alpha: 0.9) // #B9B9B4
let red = CGColor(red: 0.894, green: 0.314, blue: 0.235, alpha: 1) // #E4503C
let bg = CGColor(red: 0.043, green: 0.047, blue: 0.055, alpha: 1) // #0B0C0E

let ctx = CGContext(
    data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!
// CG 좌표는 y가 위로 — 디자인 좌표(y 아래로)를 뒤집어서 쓴다
ctx.translateBy(x: 0, y: CGFloat(S))
ctx.scaleBy(x: 1, y: -1)

/// 라운드 카드 (macOS 아이콘 관례 비율 rx≈230/1024)
let card = CGPath(
    roundedRect: CGRect(x: 0, y: 0, width: S, height: S),
    cornerWidth: 230, cornerHeight: 230, transform: nil
)
ctx.addPath(card)
ctx.setFillColor(bg)
ctx.fillPath()
ctx.addPath(card)
ctx.clip()

/// 지면 곡선 (완만한 능선 → 그린)
func groundY(_ x: CGFloat) -> CGFloat {
    // 두 코사인 합성 — x∈[0,1024], y≈660~710
    let t = x / 1024
    return 690 + 26 * cos(t * 4.2 + 0.8) - 10 * cos(t * 1.7)
}

let ground = CGMutablePath()
ground.move(to: CGPoint(x: -20, y: groundY(-20)))
var gx: CGFloat = -20
while gx <= 1044 {
    ground.addLine(to: CGPoint(x: gx, y: groundY(gx)))
    gx += 8
}

ctx.addPath(ground)
ctx.setStrokeColor(line)
ctx.setLineWidth(10)
ctx.setLineCap(.round)
ctx.strokePath()

// 스틱맨 (어드레스 자세) — 발을 지면에 접지, 배너와 같은 비례 ×3.6
let sx: CGFloat = 330
let fy = groundY(sx)
let hip = CGPoint(x: sx, y: fy - 187)
let sh = CGPoint(x: sx + 4, y: fy - 295)
let head = CGPoint(x: sx + 7, y: fy - 360)
let hands = CGPoint(x: sx + 61, y: fy - 176)
let clubHead = CGPoint(x: sx + 198, y: groundY(sx + 198) - 11)
let ballPt = CGPoint(x: sx + 223, y: groundY(sx + 223) - 19)

func stroke(_ a: CGPoint, _ b: CGPoint, _ w: CGFloat, _ c: CGColor) {
    ctx.setStrokeColor(c)
    ctx.setLineWidth(w)
    ctx.setLineCap(.round)
    ctx.move(to: a)
    ctx.addLine(to: b)
    ctx.strokePath()
}

stroke(hip, CGPoint(x: sx - 54, y: groundY(sx - 54)), 27, ink) // 뒷다리
stroke(hip, CGPoint(x: sx + 47, y: groundY(sx + 47)), 27, ink) // 앞다리
stroke(hip, sh, 31, ink) // 몸통
stroke(sh, hands, 22, ink) // 팔
stroke(hands, clubHead, 12, ink) // 샤프트
// 헤드(원)·클럽 헤드(타원)·공
ctx.setFillColor(ink)
ctx.fillEllipse(in: CGRect(x: head.x - 47, y: head.y - 47, width: 94, height: 94))
ctx.saveGState()
ctx.translateBy(x: clubHead.x, y: clubHead.y)
ctx.rotate(by: -0.24)
ctx.fillEllipse(in: CGRect(x: -25, y: -14, width: 50, height: 28))
ctx.restoreGState()
ctx.fillEllipse(in: CGRect(x: ballPt.x - 19, y: ballPt.y - 19, width: 38, height: 38))

// 깃발 — 유일한 포인트 컬러
let px: CGFloat = 762
let py = groundY(px)
stroke(CGPoint(x: px, y: py), CGPoint(x: px, y: py - 240), 14, ink)
ctx.setFillColor(red)
ctx.move(to: CGPoint(x: px + 7, y: py - 240))
ctx.addLine(to: CGPoint(x: px + 190, y: py - 194))
ctx.addLine(to: CGPoint(x: px + 7, y: py - 148))
ctx.closePath()
ctx.fillPath()
// 홀컵
ctx.setFillColor(bg)
ctx.fillEllipse(in: CGRect(x: px - 34, y: py - 9, width: 68, height: 18))
ctx.setStrokeColor(ink)
ctx.setLineWidth(8)
ctx.strokeEllipse(in: CGRect(x: px - 34, y: py - 9, width: 68, height: 18))

let img = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: img)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("OK \(out)")
