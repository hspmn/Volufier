import SwiftUI

struct EqualiserGraph: View {
    let bands: [SoundSettings.Band]
    let commit: (Int, Int) -> Void
    @State private var editing: Int?
    @State private var draft = 6

    private func frequency(_ hz: Int) -> String { hz >= 1000 ? "\(hz / 1000)k" : "\(hz)" }
    private func gain(_ i: Int) -> Int { i == editing ? draft : bands[i].gain }

    var body: some View {
        GeometryReader { geometry in
            let inset: CGFloat = 30, end: CGFloat = 16, top: CGFloat = 15
            let width = geometry.size.width - inset - end
            let height = geometry.size.height - 41
            let step = width / CGFloat(max(1, bands.count - 1))
            let points = bands.indices.map { i in
                CGPoint(x: inset + CGFloat(i) * step, y: top + height * (1 - CGFloat(gain(i)) / 12))
            }
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    guard let first = points.first, let last = points.last else { return }
                    for value in [0, 3, 6, 9, 12] {
                        let y = top + height * (1 - CGFloat(value) / 12)
                        var grid = Path()
                        grid.move(to: CGPoint(x: inset, y: y)); grid.addLine(to: CGPoint(x: last.x, y: y))
                        ctx.stroke(grid, with: .color(.secondary.opacity(value == 6 ? 0.48 : 0.18)), lineWidth: 1)
                    }
                    var curve = Path(); curve.move(to: first)
                    for point in points.dropFirst() { curve.addLine(to: point) }
                    var area = curve
                    area.addLine(to: CGPoint(x: last.x,y: top + height))
                    area.addLine(to: CGPoint(x: first.x,y: top + height)); area.closeSubpath()
                    ctx.fill(area, with: .linearGradient(Gradient(colors: [.accentColor.opacity(0.23), .accentColor.opacity(0.02)]),
                                                          startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: top + height)))
                    ctx.stroke(curve, with: .color(.accentColor), lineWidth: 2)
                }
                ForEach([12, 6, 0], id: \.self) { gain in
                    Text(gain == 12 ? "+6" : gain == 6 ? "0" : "−6")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        .position(x: 11, y: top + height * (1 - CGFloat(gain) / 12))
                }
                ForEach(bands.indices, id: \.self) { i in
                    Circle().fill(Color(nsColor: .windowBackgroundColor))
                        .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2))
                        .frame(width: editing == i ? 13 : 10, height: editing == i ? 13 : 10).position(points[i])
                    Text(frequency(bands[i].hz)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        .position(x: points[i].x,y: top + height + 15)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { d in
                    if editing == nil {
                        guard d.startLocation.y <= top + height + 5 else { return }
                        editing = min(bands.count - 1,max(0,Int(((d.startLocation.x - inset) / step).rounded())))
                    }
                    draft = min(12,max(0,Int((12 * (1 - (d.location.y - top) / height)).rounded())))
                }
                .onEnded { _ in
                    if let i = editing { commit(i,draft) }
                    editing = nil
                })
            .accessibilityRepresentation {
                HStack {
                    ForEach(bands.indices, id: \.self) { i in
                        Slider(value: Binding(get: { Double(bands[i].gain) }, set: { commit(i,Int($0.rounded())) }),
                               in: 0...12, step: 1) { Text("\(bands[i].hz) Hz") }
                            .accessibilityValue("\(bands[i].gain - 6) steps")
                    }
                }
            }
        }.frame(height: 163)
    }
}
