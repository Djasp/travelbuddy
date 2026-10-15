// Tekent het app-icoon (1024 px). Gebruik:
//   swiftc -o /tmp/make_icon scripts/make_icon.swift && /tmp/make_icon icon_1024.png
// en schaal daarna met sips naar de formaten in AppIcon.appiconset.

import AppKit

let size: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
let space = CGColorSpaceCreateDeviceRGB()

func c(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
}
func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
}

// macOS-raster: body 824x824 met marge 100, hoekradius ~185.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

// Schaduw onder de body.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: c(0x000000, 0.35))
ctx.addPath(shape); ctx.setFillColor(c(0x1E3A8A)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(shape); ctx.clip()

let horizon: CGFloat = 470
// Lucht: diepblauw boven, warme zonsondergang bij de horizon.
ctx.drawLinearGradient(gradient([c(0x1E3A8A), c(0x3B6FD8), c(0xF59E7B), c(0xFCD38D)], [0, 0.45, 0.85, 1]),
                       start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: horizon), options: [])
// Zon op de horizon.
ctx.saveGState()
ctx.clip(to: CGRect(x: 0, y: horizon, width: size, height: size))
ctx.drawRadialGradient(gradient([c(0xFFF7D6, 0.9), c(0xFDE68A, 0.0)], [0, 1]),
                       startCenter: CGPoint(x: 512, y: horizon), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: horizon), endRadius: 260, options: [])
ctx.setFillColor(c(0xFFF3C4)); ctx.fillEllipse(in: CGRect(x: 512 - 80, y: horizon - 80, width: 160, height: 160))
ctx.restoreGState()

// Land.
ctx.saveGState()
ctx.clip(to: CGRect(x: 0, y: 0, width: size, height: horizon))
ctx.drawLinearGradient(gradient([c(0x2F855A), c(0x14532D)], [0, 1]),
                       start: CGPoint(x: 0, y: horizon), end: CGPoint(x: 0, y: 100), options: [])
ctx.restoreGState()

// Weg in perspectief naar het verdwijnpunt.
let vanish = CGPoint(x: 512, y: horizon)
let roadBottomHalf: CGFloat = 330, roadTopHalf: CGFloat = 14
func roadX(_ y: CGFloat, _ side: CGFloat) -> CGFloat {
    let t = (y - 100) / (horizon - 100)
    return 512 + side * (roadBottomHalf + (roadTopHalf - roadBottomHalf) * t)
}
let road = CGMutablePath()
road.move(to: CGPoint(x: roadX(60, -1), y: 60)); road.addLine(to: CGPoint(x: roadX(horizon, -1), y: horizon))
road.addLine(to: CGPoint(x: roadX(horizon, 1), y: horizon)); road.addLine(to: CGPoint(x: roadX(60, 1), y: 60)); road.closeSubpath()
ctx.saveGState(); ctx.addPath(road); ctx.clip()
ctx.drawLinearGradient(gradient([c(0x6B7280), c(0x2D3340)], [0, 1]), start: vanish, end: CGPoint(x: 512, y: 100), options: [])
ctx.restoreGState()
// Witte kantlijnen.
for side: CGFloat in [-1, 1] {
    let edge = CGMutablePath()
    let inset: CGFloat = 0.9
    edge.move(to: CGPoint(x: 512 + (roadX(60, side) - 512) * inset, y: 60))
    edge.addLine(to: CGPoint(x: 512 + (roadX(horizon, side) - 512) * inset, y: horizon))
    edge.addLine(to: CGPoint(x: 512 + (roadX(horizon, side) - 512) * (inset - 0.04), y: horizon))
    edge.addLine(to: CGPoint(x: 512 + (roadX(60, side) - 512) * (inset - 0.04), y: 60)); edge.closeSubpath()
    ctx.addPath(edge); ctx.setFillColor(c(0xF3F4F6, 0.9)); ctx.fillPath()
}
// Gele middenstreep, streepjes krimpen richting horizon.
var y: CGFloat = 70
var dash: CGFloat = 140
while y < horizon - 8 {
    let top = min(y + dash, horizon - 4)
    let w0 = (roadX(y, 1) - 512) * 0.05, w1 = (roadX(top, 1) - 512) * 0.05
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 512 - w0, y: y)); p.addLine(to: CGPoint(x: 512 - w1, y: top))
    p.addLine(to: CGPoint(x: 512 + w1, y: top)); p.addLine(to: CGPoint(x: 512 + w0, y: y)); p.closeSubpath()
    ctx.addPath(p); ctx.setFillColor(c(0xFACC15)); ctx.fillPath()
    let gap = dash * 0.55
    y = top + gap
    dash *= 0.6
}
ctx.restoreGState()

// Klok rechtsboven: groene boog = normale reistijd, rode boog = vertraging.
let center = CGPoint(x: 718, y: 718), radius: CGFloat = 158
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: c(0x0B1530, 0.45))
ctx.setFillColor(c(0xFFFFFF)); ctx.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
ctx.restoreGState()
func angle(_ minutes: CGFloat) -> CGFloat { .pi / 2 - minutes / 60 * 2 * .pi } // 0 min = boven, met de klok mee
func arc(from: CGFloat, to: CGFloat, color: CGColor) {
    ctx.saveGState()
    ctx.addArc(center: center, radius: radius - 30, startAngle: angle(from), endAngle: angle(to), clockwise: true)
    ctx.setLineWidth(30); ctx.setLineCap(.round); ctx.setStrokeColor(color); ctx.strokePath()
    ctx.restoreGState()
}
arc(from: 0, to: 30, color: c(0x22C55E))
arc(from: 32, to: 44, color: c(0xEF4444))
// Uurstreepjes.
for i in 0..<12 {
    let a = CGFloat(i) / 12 * 2 * .pi
    let r0 = radius - 62, r1 = radius - (i % 3 == 0 ? 82 : 74)
    ctx.move(to: CGPoint(x: center.x + cos(a) * r0, y: center.y + sin(a) * r0))
    ctx.addLine(to: CGPoint(x: center.x + cos(a) * r1, y: center.y + sin(a) * r1))
}
ctx.setLineWidth(8); ctx.setLineCap(.round); ctx.setStrokeColor(c(0xCBD5E1)); ctx.strokePath()
// Wijzer naar het eind van de vertraging.
let handAngle = angle(44)
ctx.move(to: center); ctx.addLine(to: CGPoint(x: center.x + cos(handAngle) * 92, y: center.y + sin(handAngle) * 92))
ctx.setLineWidth(18); ctx.setStrokeColor(c(0x1E293B)); ctx.strokePath()
ctx.move(to: center); ctx.addLine(to: CGPoint(x: center.x, y: center.y + 64))
ctx.setLineWidth(18); ctx.setStrokeColor(c(0x1E293B)); ctx.strokePath()
ctx.setFillColor(c(0x1E293B)); ctx.fillEllipse(in: CGRect(x: center.x - 20, y: center.y - 20, width: 40, height: 40))

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
