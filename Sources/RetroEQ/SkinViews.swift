import AppKit
import EQDSP
import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

enum Skin {
    static let bodyTop = Color(hex: 0x4A4A64)
    static let body = Color(hex: 0x34344A)
    static let inset = Color(hex: 0x23232F)
    static let bevelLight = Color(hex: 0x8282A2)
    static let bevelDark = Color(hex: 0x101018)
    static let title = Color(hex: 0x1E1E2E)
    static let gold = Color(hex: 0xE6C064)
    static let goldDark = Color(hex: 0x6E5420)
    static let label = Color(hex: 0xD4D4E8)
    static let labelDim = Color(hex: 0x7C7C98)
    static let lcd = Color(hex: 0x040704)
    static let lcdText = Color(hex: 0x3CFF5A)
    static let lcdDim = Color(hex: 0x123A18)
    static let lcdWarn = Color(hex: 0xFFB43C)
    static let ledOff = Color(hex: 0x163018)
    static let groove = Color(hex: 0x0A0A12)

    static func font(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .monospaced) }

    /// Slider fill colour: blue when cut, green at 0, yellow then red as the boost rises.
    static func barColor(_ v: Float) -> Color {
        let stops: [(Float, UInt32)] = [(-12, 0x2F9CFF), (0, 0x3CFF5A), (6, 0xFFE03C), (12, 0xFF3C2F)]
        let x = min(max(v, -12), 12)
        for i in 0..<(stops.count - 1) where x <= stops[i + 1].0 {
            let (a, ca) = stops[i], (b, cb) = stops[i + 1]
            let t = Double((x - a) / (b - a))
            func ch(_ c: UInt32, _ s: UInt32) -> Double { Double((c >> s) & 0xFF) / 255 }
            return Color(red: ch(ca, 16) + (ch(cb, 16) - ch(ca, 16)) * t,
                         green: ch(ca, 8) + (ch(cb, 8) - ch(ca, 8)) * t,
                         blue: ch(ca, 0) + (ch(cb, 0) - ch(ca, 0)) * t)
        }
        return Color(hex: 0xFF3C2F)
    }
}

struct Bevel: View {
    var raised = true
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            Path { p in
                p.move(to: CGPoint(x: 0.5, y: h))
                p.addLine(to: CGPoint(x: 0.5, y: 0.5))
                p.addLine(to: CGPoint(x: w, y: 0.5))
            }.stroke(raised ? Skin.bevelLight : Skin.bevelDark, lineWidth: 1)
            Path { p in
                p.move(to: CGPoint(x: w - 0.5, y: 0))
                p.addLine(to: CGPoint(x: w - 0.5, y: h - 0.5))
                p.addLine(to: CGPoint(x: 0, y: h - 0.5))
            }.stroke(raised ? Skin.bevelDark : Skin.bevelLight, lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

extension View {
    func bevel(_ raised: Bool = true) -> some View { overlay(Bevel(raised: raised)) }
}

// MARK: - Window chrome

struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct Stripes: View {
    var body: some View {
        Canvas { ctx, size in
            var y: CGFloat = 4
            while y + 2 <= size.height - 3 {
                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(Skin.gold))
                ctx.fill(Path(CGRect(x: 0, y: y + 1, width: size.width, height: 1)), with: .color(Skin.goldDark))
                y += 3
            }
        }
        .allowsHitTesting(false)
    }
}

struct TitleButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 7, weight: .black))
                .foregroundColor(Skin.label)
                .frame(width: 13, height: 11)
                .background(LinearGradient(colors: [Skin.bodyTop, Skin.body], startPoint: .top, endPoint: .bottom))
                .bevel()
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct TitleBar: View {
    let onMinimize: () -> Void
    let onClose: () -> Void
    var body: some View {
        ZStack {
            WindowDragArea()
            HStack(spacing: 6) {
                Stripes()
                Text("RETRO EQ")
                    .font(Skin.font(10))
                    .foregroundColor(Skin.gold)
                    .fixedSize()
                    .allowsHitTesting(false)
                Stripes()
                TitleButton(symbol: "minus", help: "Minimise", action: onMinimize)
                TitleButton(symbol: "xmark", help: "Hide (EQ keeps running in the menu bar)", action: onClose)
            }
            .padding(.horizontal, 6)
        }
        .frame(height: 20)
        .background(Skin.title)
    }
}

// MARK: - Buttons

struct SkinButton: View {
    let title: String
    var led: Bool? = nil
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let led {
                    Rectangle()
                        .fill(led ? Skin.lcdText : Skin.ledOff)
                        .frame(width: 7, height: 7)
                        .shadow(color: led ? Skin.lcdText.opacity(0.9) : .clear, radius: 3)
                        .bevel(false)
                }
                Text(title).font(Skin.font(9)).foregroundColor(Skin.label)
            }
            .padding(.horizontal, 7)
            .frame(height: 18)
            .background(LinearGradient(colors: [Skin.bodyTop, Skin.body], startPoint: .top, endPoint: .bottom))
            .bevel()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Curve display

struct CurveDisplay: View {
    let gains: [Float]
    let preamp: Float
    let enabled: Bool

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let range = Double(EQModel.range) * 1.5
            func y(_ db: Double) -> CGFloat {
                h / 2 - CGFloat(max(-range, min(range, db)) / range) * (h / 2 - 3)
            }
            // Decade grid at 100 Hz, 1 kHz, 10 kHz (axis is 20 Hz...20 kHz).
            for f in [100.0, 1000.0, 10000.0] {
                let x = CGFloat(log10(f / 20) / 3) * w
                ctx.fill(Path(CGRect(x: x, y: 0, width: 1, height: h)), with: .color(Skin.lcdDim))
            }
            var zero = Path()
            zero.move(to: CGPoint(x: 0, y: h / 2))
            zero.addLine(to: CGPoint(x: w, y: h / 2))
            ctx.stroke(zero, with: .color(Skin.lcdDim), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))

            var pre = Path()
            pre.move(to: CGPoint(x: 0, y: y(Double(preamp))))
            pre.addLine(to: CGPoint(x: w, y: y(Double(preamp))))
            ctx.stroke(pre, with: .color(Skin.gold.opacity(0.45)), style: StrokeStyle(lineWidth: 1, dash: [1, 3]))

            var curve = Path()
            gains.withUnsafeBufferPointer { gp in
                for xi in 0...Int(w) {
                    let f = 20 * pow(1000, Double(xi) / Double(w))
                    let db = enabled ? eq_response_db(gp.baseAddress!, f) : 0
                    let pt = CGPoint(x: CGFloat(xi), y: y(db))
                    if xi == 0 { curve.move(to: pt) } else { curve.addLine(to: pt) }
                }
            }
            let shading = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [Color(hex: 0xFF3C2F), Color(hex: 0xFFE03C), Skin.lcdText, Color(hex: 0x2F9CFF)]),
                startPoint: CGPoint(x: 0, y: 2), endPoint: CGPoint(x: 0, y: h - 2))
            ctx.stroke(curve, with: shading, lineWidth: 1.5)
        }
        .frame(width: 230, height: 42)
        .background(Skin.lcd)
        .bevel(false)
        .help("Frequency response (20 Hz – 20 kHz). Dotted gold line is the preamp.")
    }
}

// MARK: - Sliders

struct EQSlider: View {
    let value: Float
    let onChange: (Float) -> Void
    static let height: CGFloat = 118
    private let thumbH: CGFloat = 11
    private let range = EQModel.range

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let travel = h - thumbH
            let norm = CGFloat((value + range) / (2 * range))
            let thumbY = thumbH / 2 + (1 - norm) * travel
            let zeroY = h / 2
            ZStack {
                Canvas { ctx, size in
                    for k in 0...4 {
                        let ty = thumbH / 2 + CGFloat(k) * travel / 4
                        let len: CGFloat = k == 2 ? 4 : 2
                        ctx.fill(Path(CGRect(x: 0, y: ty - 0.5, width: len, height: 1)), with: .color(Skin.labelDim))
                        ctx.fill(Path(CGRect(x: size.width - len, y: ty - 0.5, width: len, height: 1)), with: .color(Skin.labelDim))
                    }
                }
                Rectangle().fill(Skin.groove).frame(width: 7, height: h).bevel(false)
                Rectangle()
                    .fill(Skin.barColor(value))
                    .frame(width: 3, height: max(1, abs(thumbY - zeroY)))
                    .position(x: w / 2, y: (thumbY + zeroY) / 2)
                SliderThumb()
                    .frame(width: 14, height: thumbH)
                    .position(x: w / 2, y: thumbY)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                if NSEvent.modifierFlags.contains(.option) { onChange(0); return }
                let n = 1 - Float(min(max((drag.location.y - thumbH / 2) / travel, 0), 1))
                var v = (-range + n * 2 * range) * 2
                v = v.rounded() / 2
                if abs(v) <= 0.5 { v = 0 } // small detent at 0 dB
                onChange(v)
            })
        }
        .frame(width: 24, height: Self.height)
        .help("Drag to adjust. Option-click resets to 0 dB.")
    }
}

struct SliderThumb: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0xE4E4F0), Color(hex: 0x8C8CA4)], startPoint: .top, endPoint: .bottom)
            Rectangle().fill(Color.black.opacity(0.55)).frame(height: 1)
        }
        .bevel()
    }
}

struct BandLabel: View {
    let text: String
    var body: some View {
        Text(text).font(Skin.font(8)).foregroundColor(Skin.label).fixedSize()
    }
}

struct DBScale: View {
    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text("+12 DB")
            Spacer()
            Text("+0 DB")
            Spacer()
            Text("-12 DB")
        }
        .font(Skin.font(7))
        .foregroundColor(Skin.labelDim)
        .padding(.vertical, 1)
        .frame(height: EQSlider.height)
    }
}

struct SliderBank: View {
    @ObservedObject var model: EQModel
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 5) {
                EQSlider(value: model.preamp) { model.setPreamp($0) }
                BandLabel(text: "PREAMP")
            }
            .frame(width: 48)
            DBScale().frame(width: 40)
            Rectangle().fill(Skin.bevelDark).frame(width: 1, height: EQSlider.height).padding(.horizontal, 6)
            ForEach(0..<Int(EQ_BAND_COUNT), id: \.self) { i in
                VStack(spacing: 5) {
                    EQSlider(value: model.gains[i]) { model.setGain(i, $0) }
                    BandLabel(text: EQModel.bandLabels[i])
                }
                .frame(width: 34)
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 8)
        .background(Skin.inset)
        .bevel(false)
    }
}

// MARK: - Status LCD

struct LevelBars: View {
    let left: Float
    let right: Float
    private let segments = 14
    var body: some View {
        VStack(spacing: 2) {
            row(left)
            row(right)
        }
    }
    private func row(_ level: Float) -> some View {
        HStack(spacing: 1) {
            ForEach(0..<segments, id: \.self) { i in
                let lit = Float(i) < level * Float(segments)
                let t = Float(i) / Float(segments - 1)
                let color = t > 0.85 ? Color(hex: 0xFF3C2F) : t > 0.65 ? Color(hex: 0xFFE03C) : Skin.lcdText
                Rectangle().fill(lit ? color : Skin.lcdDim).frame(width: 3, height: 4)
            }
        }
    }
}

struct StatusLCD: View {
    @ObservedObject var model: EQModel
    @ObservedObject var meter: LevelMeter

    var body: some View {
        HStack(spacing: 10) {
            Text(text)
                .font(Skin.font(10))
                .foregroundColor(model.errorMessage != nil && model.ticker == nil ? Skin.lcdWarn : Skin.lcdText)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            LevelBars(left: meter.left, right: meter.right)
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(Skin.lcd)
        .bevel(false)
    }

    private var text: String {
        if let ticker = model.ticker { return ticker }
        if let error = model.errorMessage { return "\(error.uppercased()) — CHECK SYSTEM AUDIO RECORDING PERMISSION" }
        let out = model.outputName.uppercased()
        return model.enabled ? "▶ \(model.presetName.uppercased())  ·  \(out)" : "■ EQ OFF  ·  \(out)"
    }
}

// MARK: - Window

struct EQWindowView: View {
    @ObservedObject var model: EQModel
    let meter: LevelMeter
    let onMinimize: () -> Void
    let onClose: () -> Void
    let showPresets: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TitleBar(onMinimize: onMinimize, onClose: onClose)
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    SkinButton(title: "ON", led: model.enabled) { model.setEnabled(!model.enabled) }
                        .help("Turn the equalizer on or off")
                    SkinButton(title: "FLAT") { model.apply(.flat) }
                        .help("Reset all bands to 0 dB")
                    Spacer(minLength: 8)
                    CurveDisplay(gains: model.gains, preamp: model.preamp, enabled: model.enabled)
                    Spacer(minLength: 8)
                    SkinButton(title: "PRESETS ▾", action: showPresets)
                }
                SliderBank(model: model)
                StatusLCD(model: model, meter: meter)
            }
            .padding(10)
        }
        .background(LinearGradient(colors: [Skin.bodyTop, Skin.body], startPoint: .top, endPoint: .bottom))
        .bevel()
        .fixedSize()
    }
}
