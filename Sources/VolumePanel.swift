import SwiftUI

struct VolumePanel: View {
    @ObservedObject var model: PanelModel
    @State private var pointerValue: Double?
    @State private var tracking = false
    @Environment(\.accessibilityReduceTransparency) private var opaque
    private var speaker: Speaker { model.speaker }
    private var available: Bool { speaker.phase == .ready || speaker.phase == .applying }
    private var level: Int { speaker.intendedLevel ?? 0 }

    private var slider: some View {
        Slider(value: Binding(get: { pointerValue ?? Double(level) }, set: { value in
            if tracking { pointerValue = value }
            let target = Int(value.rounded())
            if target != speaker.intendedLevel { speaker.set(target) }
        }), in: 0...30, onEditingChanged: { editing in
            tracking = editing
            if !editing { pointerValue = nil }
        })
        .labelsHidden()
        .accessibilityLabel("Speaker master volume")
        .accessibilityValue("\(level) of 30")
        .onMoveCommand { direction in
            if direction == .left || direction == .down { pointerValue = nil; speaker.set(max(0,level-1)) }
            if direction == .right || direction == .up { pointerValue = nil; speaker.set(min(30,level+1)) }
        }
        .help("Speaker volume · \(level) of 30")
    }

    @ViewBuilder private var panelGlass: some View {
        let shape = RoundedRectangle(cornerRadius: 17, style: .continuous)
        if opaque { shape.fill(Color(nsColor: .windowBackgroundColor)) }
        else if #available(macOS 26.0, *) { shape.fill(.clear).glassEffect(.regular, in: shape) }
        else { shape.fill(.regularMaterial) }
    }

    var body: some View {
        Group {
            if available {
                HStack(spacing: 6) {
                    Image(systemName: "speaker.fill").font(.system(size: 13))
                    if #available(macOS 26.0, *) {
                        slider.sliderThumbVisibility(.visible).focusEffectDisabled()
                    } else { slider }
                    Image(systemName: "speaker.wave.3.fill").font(.system(size: 15))
                }.foregroundStyle(.secondary).controlSize(.regular)
            } else if speaker.phase == .failed {
                Button("Reconnect to MR5") { speaker.start() }.buttonStyle(.plain).help(speaker.status)
            } else { ProgressView("Connecting…").controlSize(.small) }
        }.padding(.horizontal, 14).frame(width: 308, height: 44).background { panelGlass }
        .onDisappear { pointerValue = nil }
    }
}

struct VolumeAccessibility: ViewModifier {
    let speaker: Speaker
    let value: Int
    let name: String
    private var available: Bool { speaker.phase == .ready || speaker.phase == .applying }
    func body(content: Content) -> some View {
        content
            .accessibilityRepresentation {
                if available {
                    Slider(value: Binding(get: { Double(value) }, set: { speaker.set(Int($0.rounded())) }),
                           in: 0...30, step: 1) { Text(name) }
                           .accessibilityValue("\(value) of 30")
                } else {
                    Button(speaker.status) { if speaker.phase == .failed { speaker.start() } }
                }
            }
            .focusable()
            .onMoveCommand { direction in
                guard available else { return }
                if direction == .left || direction == .down { speaker.set(max(0, (speaker.intendedLevel ?? value) - 1)) }
                if direction == .right || direction == .up { speaker.set(min(30, (speaker.intendedLevel ?? value) + 1)) }
            }
            .help(available ? "Speaker volume · \(value) of 30" : speaker.status)
    }
}
