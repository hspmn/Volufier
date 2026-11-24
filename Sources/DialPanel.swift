import SwiftUI

private struct RotaryDrag {
    var position: Double
    var previousAngle: Double?
    var lastY: CGFloat
    let vertical: Bool
}

struct DialPanel: View {
    @ObservedObject var model: PanelModel
    @Environment(\.accessibilityReduceTransparency) private var opaque
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drag: RotaryDrag?
    @State private var lastSend = Date.distantPast

    private static let texture: NSImage = {
        guard let url = Bundle.main.url(forResource: "DialFace", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return NSImage() }
        return image
    }()
    private let diameter: CGFloat = 158
    private let center = CGPoint(x: 124, y: 108)
    private let scaleRadius: CGFloat = 94
    private var speaker: Speaker { model.speaker }
    private var available: Bool { speaker.phase == .ready || speaker.phase == .applying }
    private var level: Int { drag.map { Int($0.position.rounded()) } ?? speaker.volume ?? 0 }

    @ViewBuilder private var glass: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        if #available(macOS 26.0, *), !opaque {
            shape.fill(.clear).glassEffect(.regular.tint(Color(white: 0.15).opacity(0.53)), in: shape)
        } else {
            shape.fill(opaque ? Color(white: 0.19) : Color(white: 0.19).opacity(0.93))
        }
    }

    private var face: some View {
        // In the approved image the engraved pointer is seven degrees left of vertical.
        // Rotate the entire machined face about its spindle, under a fixed glass highlight.
        let position = drag?.position ?? Double(speaker.intendedLevel ?? 0)
        let degrees = -135 + position * DialGeometry.step + 7
        return ZStack {
            Image(nsImage: Self.texture).resizable().clipShape(Circle())
                .rotationEffect(.degrees(degrees))
                .animation(reduceMotion ? nil : .easeOut(duration: drag == nil ? 0.18 : 0.065), value: degrees)
            Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .clear, .black.opacity(0.14)],
                                                startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        }.frame(width: diameter, height: diameter)
        .shadow(color: .black.opacity(0.45), radius: 3.5, y: 3)
        .position(center)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            glass
            Canvas { context, _ in
                for step in 0...DialGeometry.limit {
                    let a = DialGeometry.position(level: step) * .pi / 180
                    let dx = CGFloat(sin(a)), dy = CGFloat(-cos(a))
                    var p = Path()
                    p.move(to: CGPoint(x: center.x + (scaleRadius - 7.5) * dx, y: center.y + (scaleRadius - 7.5) * dy))
                    p.addLine(to: CGPoint(x: center.x + scaleRadius * dx, y: center.y + scaleRadius * dy))
                    context.stroke(p, with: .color(.white.opacity(0.82)), lineWidth: 1.0)
                }
            }
            face
            Group {
                Text("0").position(x: 50, y: 184)
                Text("30").position(x: 198, y: 184)
            }.font(.system(size: 11, weight: .regular)).foregroundStyle(.white.opacity(0.84))
            if available {
                Text("\(level)").font(.system(size: 23, weight: .regular)).monospacedDigit()
                    .foregroundStyle(.white).position(x: center.x, y: 211)
            } else {
                Text(speaker.phase == .failed ? "Click to reconnect" : "Connecting…")
                    .font(.caption).foregroundStyle(.white.opacity(0.85)).position(x: center.x, y: 211)
            }
        }.frame(width: 248, height: 236)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged(track).onEnded { _ in
            if let drag, available { speaker.set(Int(drag.position.rounded())) }
            else if speaker.phase == .failed { speaker.start() }
            drag = nil
        })
        .modifier(VolumeAccessibility(speaker: speaker, value: level, name: "Speaker volume dial"))
        .modifier(DialFocusAppearance())

        .onDisappear { drag = nil }
    }

    private func track(_ event: DragGesture.Value) {
        guard available else { return }
        let x = event.location.x - center.x, y = event.location.y - center.y
        let radius = hypot(x, y)
        let angle = DialGeometry.angle(x: Double(x), y: Double(y))
        if drag == nil {
            let start = event.startLocation
            let sx = start.x - center.x, sy = start.y - center.y
            let r = hypot(sx, sy)
            guard r <= scaleRadius + 8 else { return }
            let onScale = r >= diameter / 2
            let startAngle = DialGeometry.angle(x: Double(sx), y: Double(sy))
            let initial = onScale ? DialGeometry.level(at: startAngle) : speaker.intendedLevel
            guard let initial else { return }
            drag = RotaryDrag(position: Double(initial), previousAngle: startAngle, lastY: start.y,
                              vertical: r < 20)
        }
        guard var current = drag else { return }
        if current.vertical {
            current.position += Double(current.lastY - event.location.y) / 5
        } else if radius < 13 {
            current.previousAngle = nil
        } else {
            if let previous = current.previousAngle {
                current.position += DialGeometry.change(from: previous, to: angle) / DialGeometry.step
            }
            current.previousAngle = angle
        }
        current.position = min(30, max(0, current.position))
        current.lastY = event.location.y
        drag = current
        if Date().timeIntervalSince(lastSend) >= 0.10 {
            speaker.set(Int(current.position.rounded()))
            lastSend = Date()
        }
    }
}

private struct DialFocusAppearance: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 14.0, *) { content.focusEffectDisabled() }
        else { content }
    }
}
