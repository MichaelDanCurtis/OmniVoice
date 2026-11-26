import OmniVoiceCore
import SwiftUI

/// Independent SwiftUI view for the Recording Cues card in Settings → Appearance,
/// isolating slider & cue-preview updates from the rest of `SettingsView`.
struct SettingsRecordingCuesCard: View {
    @Bindable var model: AppModel

    var body: some View {
        OmniGlassCard(theme: model.activeTheme, cornerRadius: 14, strong: false, padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Recording Cues", systemImage: "speaker.wave.2")
                    .font(.subheadline.weight(.semibold))
                    .fontDesign(model.activeTheme.look.headerFontDesign)

                Toggle("Sound cues", isOn: Binding(
                    get: { model.preferences.recordingSoundCuesEnabled },
                    set: { model.setRecordingSoundCuesEnabled($0) }
                ))
                .help("Play a short sound when recording starts and stops.")

                Picker("Timing", selection: Binding(
                    get: { model.preferences.recordingCueTiming },
                    set: { model.setRecordingCueTiming($0) }
                )) {
                    ForEach(RecordingCueTiming.allCases, id: \.self) { timing in
                        Text(timing.displayName).tag(timing)
                    }
                }
                .pickerStyle(.segmented)
                .help("Choose whether recording cues play at start, stop, or both.")
                .disabled(!model.preferences.recordingSoundCuesEnabled)

                Picker("Cue set", selection: Binding(
                    get: { model.preferences.recordingCueSet },
                    set: { model.setRecordingCueSet($0) }
                )) {
                    ForEach(RecordingCueSet.allCases, id: \.self) { cueSet in
                        Text(cueSet.displayName).tag(cueSet)
                    }
                }
                .disabled(!model.preferences.recordingSoundCuesEnabled)

                LabeledContent("Volume") {
                    HStack(spacing: 10) {
                        Slider(value: Binding(
                            get: { model.preferences.recordingCueVolume },
                            set: { model.setRecordingCueVolume($0) }
                        ), in: 0...1)
                        .frame(maxWidth: 220)
                        Text("\(Int((model.preferences.recordingCueVolume * 100).rounded()))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 42, alignment: .trailing)
                    }
                }
                .disabled(!model.preferences.recordingSoundCuesEnabled)

                HStack {
                    Button {
                        model.previewRecordingCue(.start)
                    } label: {
                        Label("Preview Start", systemImage: "record.circle")
                    }

                    Button {
                        model.previewRecordingCue(.stop)
                    } label: {
                        Label("Preview Stop", systemImage: "stop.circle")
                    }

                    Button {
                        model.previewRecordingCue(.empty)
                    } label: {
                        Label("Preview Empty", systemImage: "waveform.slash")
                    }
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .disabled(!model.preferences.recordingSoundCuesEnabled)
            }
        }
    }
}
