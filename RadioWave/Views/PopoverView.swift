import SwiftUI

struct PopoverView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var audioEngine: AudioEngine
    @AppStorage("audioEnabled") private var audioEnabled = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)

            Divider().opacity(0.3)

            // Waveform
            WaveformView(state: appState.radioState)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

            Divider().opacity(0.3)

            // Meters
            MetersView(
                signalStrength: appState.signalStrength,
                noiseLevel: appState.noiseLevel,
                cpuLoad: appState.cpuLoad,
                state: appState.radioState
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider().opacity(0.3)

            // State indicators — clickable for demo
            demoStateButtons
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

            Divider().opacity(0.3)

            // Footer
            footerSection
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .frame(width: 300)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("RadioWave")
                    .font(.system(size: 13, weight: .medium))
                Spacer()

                // Play/Stop button
                Button {
                    if audioEngine.isPlaying {
                        audioEngine.stop()
                        audioEnabled = false
                    } else {
                        audioEngine.start()
                        audioEnabled = true
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: audioEngine.isPlaying ? "stop.fill" : "play.fill")
                            .font(.system(size: 9))
                        Text(audioEngine.isPlaying ? "STOP" : "PLAY")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    }
                    .foregroundStyle(audioEngine.isPlaying ? Color.red : Color.radioGreen)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(audioEngine.isPlaying ? Color.red.opacity(0.1) : Color.radioGreen.opacity(0.1))
                            .overlay(
                                Capsule()
                                    .strokeBorder(
                                        audioEngine.isPlaying ? Color.red.opacity(0.3) : Color.radioGreen.opacity(0.3),
                                        lineWidth: 0.5
                                    )
                            )
                    )
                }
                .buttonStyle(.plain)

                statusBadge
            }

            Text(String(format: "%.1f MHz", appState.frequencyMHz))
                .font(.radioFrequency)
                .foregroundStyle(appState.radioState.color)

            HStack(spacing: 0) {
                Text("CLAUDE·FM — ")
                    .font(.radioCaption)
                    .foregroundStyle(.secondary)
                Text(appState.radioState.label)
                    .font(.radioCaption)
                    .foregroundStyle(appState.radioState.color)
            }
        }
    }

    private var statusBadge: some View {
        Text(appState.radioState.badgeText)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(badgeTextColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(appState.radioState.color.opacity(0.15))
                    .overlay(
                        Capsule()
                            .strokeBorder(appState.radioState.color.opacity(0.3), lineWidth: 0.5)
                    )
            )
    }

    private var badgeTextColor: Color {
        switch appState.radioState {
        case .idle: return .secondary
        default: return appState.radioState.color
        }
    }

    private var demoStateButtons: some View {
        VStack(spacing: 5) {
            HStack(spacing: 6) {
                ForEach([RadioState.idle, .connected, .thinking, .toolUse, .generating, .error], id: \.self) { state in
                    Button {
                        appState.demoMode = true
                        appState.transition(to: state, toolName: state == .toolUse ? "Bash" : "")
                        audioEngine.transition(to: state)
                    } label: {
                        Text(state.label)
                            .font(.system(size: 7, weight: .medium, design: .monospaced))
                            .foregroundStyle(appState.radioState == state ? state.color : .secondary.opacity(0.5))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(appState.radioState == state ? state.color.opacity(0.1) : .clear)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .strokeBorder(
                                                appState.radioState == state ? state.color.opacity(0.3) : .clear,
                                                lineWidth: 0.5
                                            )
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            if appState.demoMode {
                Button {
                    appState.demoMode = false
                } label: {
                    Text("EXIT DEMO — RESUME LIVE")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.radioOrange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .strokeBorder(Color.radioOrange.opacity(0.4), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var footerSection: some View {
        HStack {
            Button("Settings") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            Spacer()

            Text(appState.lastEventDescription)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
    }
}
