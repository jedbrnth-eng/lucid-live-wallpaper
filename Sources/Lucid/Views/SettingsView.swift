// Settings window.
import SwiftUI
import AppKit
import AVKit
import AVFoundation
import IOKit.ps
import ServiceManagement
import Security
import UniformTypeIdentifiers
import ImageIO

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var engine: WallpaperEngine
    @State private var battery = Pref.pauseOnBattery
    @State private var lowPower = Pref.pauseLowPower
    @State private var covered = Pref.pauseWhenCovered
    @State private var rotate = Pref.rotateMinutes
    @State private var login = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var keyInput: [KeyName: String] = [:]
    @AppStorage("seamlessLoops") private var seamless = true
    @State private var speed = Pref.speed
    @State private var fill = Pref.fillScreen
    @State private var dim = Pref.dim
    @State private var watch = Pref.watchDownloads

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Header(title: "Settings", subtitle: "Playback, power saving and content sources.")
            GroupBox("Look") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Fit", selection: $fill) {
                        Text("Fill screen (crop edges)").tag(true); Text("Fit whole video (may letterbox)").tag(false)
                    }.pickerStyle(.radioGroup)
                        .onChange(of: fill) { _, v in Pref.fillScreen = v; engine.applyLook() }
                    Picker("Playback speed", selection: $speed) {
                        ForEach([0.5, 0.75, 1.0, 1.25, 1.5], id: \.self) { Text(String(format: "%g×", $0)).tag($0) }
                    }.frame(maxWidth: 260)
                        .onChange(of: speed) { _, v in Pref.speed = v; engine.applyLook() }
                    HStack {
                        Text("Dim wallpaper")
                        Slider(value: $dim, in: 0...0.7).frame(maxWidth: 220)
                            .onChange(of: dim) { _, v in Pref.dim = v; engine.applyLook() }
                        Text("\(Int(dim * 100))%").monospacedDigit().foregroundStyle(.secondary)
                    }
                    Text("Dimming keeps desktop icons and widgets readable on bright wallpapers. Slower speed = calmer motion and less GPU.").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
            }
            GroupBox("Adding wallpapers") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Auto-add 4K videos and photos I download to ~/Downloads", isOn: $watch)
                        .onChange(of: watch) { _, v in Pref.watchDownloads = v; store.startDownloadsWatcher() }
                    Text("Only new files that are at least 3840×2160 are added; they're copied, so you can clear Downloads later. You can also drop files on the window or the Dock icon. Your library lives in ~/Library/Application Support/Lucid/Media.").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
            }
            GroupBox("Power saving") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Pause when the desktop is fully covered (full-screen apps, maximized windows)", isOn: $covered)
                        .onChange(of: covered) { _, v in Pref.pauseWhenCovered = v; engine.updatePlayback() }
                    Toggle("Pause in Low Power Mode", isOn: $lowPower)
                        .onChange(of: lowPower) { _, v in Pref.pauseLowPower = v; engine.updatePlayback() }
                    Toggle("Pause whenever running on battery", isOn: $battery)
                        .onChange(of: battery) { _, v in Pref.pauseOnBattery = v; engine.updatePlayback() }
                    Text("Always paused while the screen is locked or asleep. Video is muted and hardware-decoded.").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
            }
            GroupBox("General") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Auto-change wallpaper", selection: $rotate) {
                        Text("Never").tag(0); Text("Every 30 minutes").tag(30); Text("Every hour").tag(60)
                        Text("Every 6 hours").tag(360); Text("Daily").tag(1440)
                    }.frame(maxWidth: 340)
                        .onChange(of: rotate) { _, v in Pref.rotateMinutes = v; store.scheduleRotation() }
                    Toggle("Open at login", isOn: $login)
                        .onChange(of: login) { _, v in
                            do { if v { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; loginError = nil }
                            catch { loginError = error.localizedDescription; login = SMAppService.mainApp.status == .enabled }
                        }
                    if let e = loginError { Text(e).font(.caption).foregroundStyle(.orange) }
                    Toggle("Make Space Live clips loop seamlessly (cross-fades the end into the start after download)", isOn: $seamless)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
            }
            GroupBox("Content sources (API keys stay in your Keychain)") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(KeyName.allCases, id: \.self) { k in
                        HStack {
                            Text(k.label).frame(width: 70, alignment: .leading)
                            if store.keysPresent.contains(k) {
                                Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(accent)
                                Button("Remove") { store.saveKey(k, "") }
                            } else {
                                SecureField("Paste free API key", text: Binding(get: { keyInput[k] ?? "" }, set: { keyInput[k] = $0 }))
                                    .textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                                Button("Save") { store.saveKey(k, keyInput[k] ?? ""); keyInput[k] = "" }
                                Link("Get key ↗", destination: k.signupURL)
                            }
                        }
                    }
                    Text("Apple Aerials, NASA and Wikimedia need no key. Every source is filtered to ≥3840×2160.").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
            }
            GroupBox("Storage") {
                HStack {
                    Text("Downloaded: \(ByteCountFormatter.string(fromByteCount: store.libraryBytes, countStyle: .file))")
                    Spacer()
                    Button("Open Folder") { NSWorkspace.shared.open(Paths.media) }
                }.padding(6)
            }
            GroupBox("Licenses") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("• Apple Aerials: Apple content shipped with macOS — personal use on this Mac, no redistribution.")
                    Text("• NASA: generally public domain; credit NASA, don't imply endorsement.")
                    Text("• Pixabay: Pixabay Content License — free use; don't redistribute as-is.")
                    Text("• Wikimedia Commons: per-file license (often CC BY / CC BY-SA) shown on each item; credit the author if you share it.")
                }.font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(6)
            }
        }
    }
}
