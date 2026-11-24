import SwiftUI

struct AdvancedPanel: View {
    @ObservedObject var model: PanelModel
    private var speaker: Speaker { model.speaker }

    var body: some View {
        Form {
            Section("Sound") {
                if let room = speaker.sound.room {
                    Picker("Sound mode", selection: binding(.mode, room)) {
                        Text("Monitor").tag(0); Text("Music").tag(1); Text("Custom").tag(2)
                    }.pickerStyle(.segmented)
                } else { Text("Waiting for sound settings").foregroundStyle(.secondary) }
            }.disabled(speaker.soundBusy)
            Section("Room tuning") {
                if let room = speaker.sound.room {
                    Picker("Low-cut frequency", selection: binding(.cutoff, room)) {
                        ForEach(SoundField.cutoff.values, id: \.self) { Text("\($0) Hz").tag($0) }
                    }
                    Picker("Low-cut slope", selection: binding(.slope, room)) {
                        ForEach(SoundField.slope.values, id: \.self) { Text("−\(($0 + 1) * 6) dB/octave").tag($0) }
                    }
                    Picker("Acoustic space", selection: binding(.space, room)) {
                        ForEach(SoundField.space.values, id: \.self) { Text("\(-$0) dB").tag($0) }
                    }
                    Toggle("Desktop reflection compensation", isOn: Binding(
                        get: { room[6] == 1 }, set: { speaker.editSound(.room(.desktop, $0 ? 1 : 0)) }))
                } else { Text("Waiting for room settings").foregroundStyle(.secondary) }
            }.disabled(speaker.soundBusy)
            Section {
                if speaker.sound.bands.isEmpty { Text("Waiting for EQ bands").foregroundStyle(.secondary) }
                if !speaker.sound.bands.isEmpty {
                    EqualiserGraph(bands: speaker.sound.bands) { i, gain in speaker.editSound(.gain(i, gain)) }
                }
            } header: { Text("Custom equaliser") } footer: {
                Text("Drag a point to adjust its gain. The scale shows steps from flat. Select Custom to hear the curve.")
            }.disabled(speaker.soundBusy)
            Section("Power") {
                if let power = speaker.sound.power {
                    Toggle("Automatic power saving", isOn: Binding(get: { power }, set: { speaker.editSound(.power($0)) }))
                } else { Text("Waiting for power setting").foregroundStyle(.secondary) }
            }.disabled(speaker.soundBusy)
        }.formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            HStack {
                if speaker.soundBusy { ProgressView().controlSize(.small) }
                Text(speaker.soundMessage.isEmpty ? speaker.status : speaker.soundMessage)
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(speaker.phase == .failed ? "Reconnect" : "Refresh") {
                    if speaker.phase == .failed { speaker.start(advanced: true) } else { speaker.refreshSound() }
                }.disabled(speaker.soundBusy || (speaker.phase != .ready && speaker.phase != .failed))
            }.padding(12).background(.bar)
        }.frame(minWidth: 390, idealWidth: 430, minHeight: 430, idealHeight: 625)
    }

    private func binding(_ field: SoundField, _ room: [UInt8]) -> Binding<Int> {
        Binding(get: { Int(room[field.rawValue]) }, set: { speaker.editSound(.room(field, $0)) })
    }
}
