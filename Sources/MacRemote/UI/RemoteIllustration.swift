import MacRemoteKit
import SwiftUI

/// A drawing of a Fire TV (Alexa Voice) remote whose buttons light up while
/// they are held. Every size comes from the width, so it draws at any scale.
/// The remote's own colors are a depiction of the real object: they stay
/// the same in light and dark mode, like a product photo would.
struct RemoteIllustration: View {
    var layout = RemoteLayout()
    var lit: Set<RemoteButton> = []
    var width: CGFloat
    /// Dimmed while no remote is connected.
    var isConnected = true

    var body: some View {
        Canvas { context, size in
            Drawing(layout: layout, lit: lit, size: size).draw(in: &context)
        }
        .frame(width: width, height: width * layout.aspect)
        // Lifts the black remote off a dark card.
        .shadow(color: .black.opacity(0.3), radius: width / 12, x: 0, y: width / 24)
        .opacity(isConnected ? 1 : 0.45)
        .accessibilityElement()
        .accessibilityLabel("Fire TV remote")
    }
}

private struct Drawing {
    let layout: RemoteLayout
    let lit: Set<RemoteButton>
    let size: CGSize

    private var w: CGFloat { size.width }
    private var h: CGFloat { size.height }

    // The remote's materials.
    private let bodyTop = Color(.sRGB, red: 0.17, green: 0.17, blue: 0.18)
    private let bodyBottom = Color(.sRGB, red: 0.09, green: 0.09, blue: 0.10)
    private let ringColor = Color(.sRGB, red: 0.14, green: 0.14, blue: 0.15)
    private let keyColor = Color(.sRGB, red: 0.12, green: 0.12, blue: 0.13)
    private let iconColor = Color(.sRGB, red: 0.85, green: 0.85, blue: 0.87)
    private let ledColor = Color(.sRGB, red: 0.12, green: 0.23, blue: 0.32)
    private let edge = Color.white.opacity(0.16)
    private let accent = Color.accentColor

    func draw(in context: inout GraphicsContext) {
        drawBody(&context)
        drawTop(&context)
        drawPad(&context)
        let rows: [[(RemoteButton, String)]] = [
            [(.back, "arrow.uturn.backward"), (.home, "house.fill"), (.menu, "line.3.horizontal")],
            [(.rewind, "backward.fill"), (.playPause, "playpause.fill"), (.fastForward, "forward.fill")],
            [(.volumeDown, "minus"), (.mute, "speaker.slash.fill"), (.volumeUp, "plus")],
        ]
        for (y, keys) in zip(layout.rowYs, rows) {
            for (index, key) in keys.enumerated() {
                let x = w * [0.22, 0.5, 0.78][index]
                drawKey(&context, key.0, symbol: key.1, center: CGPoint(x: x, y: w * y), diameter: w * 0.25)
            }
        }
    }

    private func drawBody(_ context: inout GraphicsContext) {
        let shape = Path(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5),
                         cornerRadius: w * 0.4, style: .continuous)
        context.fill(shape, with: .linearGradient(Gradient(colors: [bodyTop, bodyBottom]),
                                                  startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
        context.stroke(shape, with: .color(edge), lineWidth: 1)
    }

    private func drawTop(_ context: inout GraphicsContext) {
        if layout.hasTVControls {
            drawKey(&context, .power, symbol: "power", center: CGPoint(x: w * 0.2, y: w * layout.powerY),
                    diameter: w * 0.17)
        }
        guard layout.hasVoice else { return }
        // The light bar, which glows while you talk to Alexa.
        let led = CGRect(x: w * 0.36, y: w * 0.19, width: w * 0.28, height: max(2, w * 0.035))
        context.fill(Path(roundedRect: led, cornerRadius: led.height / 2),
                     with: .color(lit.contains(.voice) ? accent : ledColor))
        drawKey(&context, .voice, symbol: "mic.fill", center: CGPoint(x: w / 2, y: w * layout.voiceY),
                diameter: w * 0.3)
    }

    private func drawPad(_ context: inout GraphicsContext) {
        let center = CGPoint(x: w / 2, y: w * layout.padY)
        let outer = w * 0.42
        let inner = w * 0.2
        var ring = Path()
        ring.addEllipse(in: circle(center, outer))
        ring.addEllipse(in: circle(center, inner + w * 0.02))
        context.fill(ring, with: .color(ringColor), style: FillStyle(eoFill: true))
        context.stroke(Path(ellipseIn: circle(center, outer)), with: .color(edge), lineWidth: 1)

        let band = outer - inner - w * 0.02
        let middle = (outer + inner + w * 0.02) / 2
        let directions: [(RemoteButton, Double)] = [(.right, 0), (.down, 90), (.left, 180), (.up, 270)]
        for (button, angle) in directions {
            if lit.contains(button) {
                var arc = Path()
                arc.addArc(center: center, radius: middle, startAngle: .degrees(angle - 38),
                           endAngle: .degrees(angle + 38), clockwise: false)
                context.stroke(arc, with: .color(accent), lineWidth: band * 0.86)
            }
            // The small dot on the ring for each direction.
            let radians = angle * .pi / 180
            let dot = CGPoint(x: center.x + cos(radians) * middle, y: center.y + sin(radians) * middle)
            context.fill(Path(ellipseIn: circle(dot, w * 0.018)),
                         with: .color(lit.contains(button) ? .white : iconColor.opacity(0.55)))
        }

        let select = Path(ellipseIn: circle(center, inner))
        context.fill(select, with: .color(lit.contains(.select) ? accent : keyColor))
        context.stroke(select, with: .color(edge), lineWidth: 1)
    }

    private func drawKey(_ context: inout GraphicsContext, _ button: RemoteButton, symbol: String,
                         center: CGPoint, diameter: CGFloat) {
        let on = lit.contains(button)
        let key = Path(ellipseIn: circle(center, diameter / 2))
        context.fill(key, with: .color(on ? accent : keyColor))
        context.stroke(key, with: .color(edge), lineWidth: 1)

        var image = context.resolve(Image(systemName: Symbol.named(symbol)))
        image.shading = .color(on ? .white : iconColor)
        let box = diameter * 0.46
        let scale = min(box / max(image.size.width, 1), box / max(image.size.height, 1))
        let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        context.draw(image, in: CGRect(x: center.x - drawn.width / 2, y: center.y - drawn.height / 2,
                                       width: drawn.width, height: drawn.height))
    }

    private func circle(_ center: CGPoint, _ radius: CGFloat) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }
}
