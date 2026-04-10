import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage("audioEnabled") private var audioEnabled = true
    @AppStorage("idleStaticEnabled") private var idleStaticEnabled = true
    @AppStorage("playOnLaunch") private var playOnLaunch = true
    @AppStorage("volume") private var volume: Double = 0.5
    @AppStorage("staticIntensity") private var staticIntensity: Double = 0.4
    @AppStorage("sensitivity") private var sensitivity: Double = 0.5
    @AppStorage("colorTheme") private var colorTheme = "Green"
    @AppStorage("hooksInstalled") private var hooksInstalled = false

    @State private var launchAtLogin = false

    var body: some View {
        TabView {
            audioTab
                .tabItem { Label("Audio", systemImage: "speaker.wave.2") }
            connectionTab
                .tabItem { Label("Connection", systemImage: "antenna.radiowaves.left.and.right") }
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 400, height: 280)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private var audioTab: some View {
        Form {
            Toggle("Enable audio feedback", isOn: $audioEnabled)
            Toggle("Play static when idle", isOn: $idleStaticEnabled)
            Toggle("Play on launch", isOn: $playOnLaunch)

            LabeledContent("Volume") {
                HStack {
                    Slider(value: $volume, in: 0...1)
                    Text("\(Int(volume * 100))%")
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                }
            }

            LabeledContent("Static intensity") {
                HStack {
                    Slider(value: $staticIntensity, in: 0...1)
                    Text("\(Int(staticIntensity * 100))%")
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var connectionTab: some View {
        Form {
            Section("Claude Code Hooks") {
                HStack {
                    Image(systemName: hooksInstalled ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(hooksInstalled ? .green : .secondary)
                    Text(hooksInstalled ? "Hooks installed" : "Hooks not installed")
                }

                Button(hooksInstalled ? "Reinstall Hooks" : "Install Hooks") {
                    HookInstaller.install()
                    hooksInstalled = HookInstaller.isInstalled()
                }

                if hooksInstalled {
                    Button("Remove Hooks", role: .destructive) {
                        HookInstaller.uninstall()
                        hooksInstalled = HookInstaller.isInstalled()
                    }
                }
            }

            Section("Detection") {
                LabeledContent("Sensitivity") {
                    Slider(value: $sensitivity, in: 0...1)
                }
                Text("Higher sensitivity means faster state transitions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var generalTab: some View {
        Form {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }

            Picker("Color theme", selection: $colorTheme) {
                Text("Green").tag("Green")
                Text("Blue").tag("Blue")
                Text("Amber").tag("Amber")
            }
        }
        .formStyle(.grouped)
    }

    private var aboutTab: some View {
        VStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 40))
                .foregroundStyle(Color.radioGreen)

            Text("RadioWave")
                .font(.title2.bold())

            Text("v1.0.0")
                .foregroundStyle(.secondary)

            Text("Radio-signal audio feedback for Claude Code")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Text("Built by Hirak Banerjee")
                .font(.caption)
                .foregroundStyle(.secondary)

            Link("GitHub", destination: URL(string: "https://github.com/hirakcoder/RadioWave")!)
                .font(.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
