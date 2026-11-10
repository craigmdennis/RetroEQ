// Renders a 1024×1024 app icon PNG: a dark bevelled panel with retro EQ bars.
// Usage: swift Scripts/make-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

func color(_ hex: UInt32) -> NSColor {
    NSColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

let panel = NSRect(x: 100, y: 100, width: 824, height: 824)
let path = NSBezierPath(roundedRect: panel, xRadius: 180, yRadius: 180)
NSGradient(starting: color(0x55557A), ending: color(0x262636))!.draw(in: path, angle: -90)

// Title stripes
for i in 0..<4 {
    let y = 790 - CGFloat(i) * 22
    color(0xE6C064).setFill(); NSRect(x: 200, y: y, width: 624, height: 9).fill()
    color(0x6E5420).setFill(); NSRect(x: 200, y: y - 9, width: 624, height: 9).fill()
}

// LCD well
let well = NSRect(x: 190, y: 190, width: 644, height: 480)
color(0x040704).setFill(); NSBezierPath(roundedRect: well, xRadius: 24, yRadius: 24).fill()

let levels: [CGFloat] = [0.95, 0.85, 0.7, 0.5, 0.4, 0.45, 0.55, 0.6, 0.7, 0.75]
let barWidth: CGFloat = 46, gap: CGFloat = 14
var x = well.minX + 22
for level in levels {
    let segments = 12
    for s in 0..<segments {
        let t = CGFloat(s) / CGFloat(segments - 1)
        let lit = t <= level
        let c: NSColor = t > 0.8 ? color(0xFF3C2F) : t > 0.55 ? color(0xFFE03C) : color(0x3CFF5A)
        (lit ? c : color(0x123A18)).setFill()
        NSRect(x: x, y: well.minY + 24 + CGFloat(s) * 36, width: barWidth, height: 28).fill()
    }
    x += barWidth + gap
}

image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
