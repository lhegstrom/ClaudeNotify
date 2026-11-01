import AppKit
import ServiceManagement
import SwiftUI

@main
struct ClaudeNotifyApp: App {
    @State private var store = Store()

    var body: some Scene {
        MenuBarExtra {
            PanelView().environment(store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: Menu bar icon

struct MenuBarLabel: View {
    let store: Store

    /// "Done" text shows for this long after the last completion, then the bar returns to idle.
    static let doneTextDuration: TimeInterval = 10 * 60

    var body: some View {
        let status = store.overall
        HStack(spacing: 3) {
            Image(nsImage: Self.icon(status, muted: store.isMuted, unread: store.hasUnread))
            if let text = barText(status) { Text(text) }
        }
    }

    private func barText(_ status: Status) -> String? {
        let sessions = store.sessions
        switch status {
        case .attention:
            let needy = sessions.filter { $0.status == .attention }
            return needy.count == 1 ? "\(needy[0].project) needs you" : "\(needy.count) need you"
        case .working:
            return "\(sessions.filter { $0.status == .working }.count) working"
        case .waiting:
            let n = sessions.filter { $0.status == .waiting }.reduce(0) { $0 + max($1.backgroundRunning, 1) }
            return "⌛ \(n) bg task\(n == 1 ? "" : "s")"
        case .done:
            guard let last = sessions.filter({ $0.status == .done }).map(\.updated).max() else { return nil }
            let age = store.now.timeIntervalSince(last)
            guard age < Self.doneTextDuration else { return nil }
            return age < 60 ? "✓ Done" : "✓ Done \(Int(age / 60))m"
        case .idle:
            return nil
        }
    }

    static func icon(_ status: Status, muted: Bool, unread: Bool) -> NSImage {
        let name: String
        switch status {
        case .attention: name = "bell.badge.fill"
        case _ where muted: name = "bell.slash"
        case _ where unread: name = "bell.badge"
        default: name = "bell"
        }
        let base = NSImage(systemSymbolName: name, accessibilityDescription: status.label) ?? NSImage()
        guard status == .attention else { base.isTemplate = true; return base }
        let config = NSImage.SymbolConfiguration(paletteColors: [.systemOrange])
        let tinted = base.withSymbolConfiguration(config) ?? base
        tinted.isTemplate = false
        return tinted
    }
}

// MARK: Panel

struct PanelView: View {
    @Environment(Store.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            HooksBanner()
            Divider()
            SessionsSection()
            Divider()
            RecentSection()
            Divider()
            SettingsSection()
            Divider()
            footer
        }
        .padding(12)
        .onAppear { store.markSeen() }
        .onDisappear { store.markSeen() }
        .frame(width: 360)
    }

    private var header: some View {
        HStack {
            Image(systemName: store.overall.symbol)
                .foregroundStyle(store.overall == .attention ? .orange : .secondary)
            Text("Claude Code").font(.headline)
            Spacer()
            if store.isMuted {
                Label("Muted until \(store.mutedUntil.formatted(date: .omitted, time: .shortened))",
                      systemImage: "bell.slash")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(store.overall.label).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack {
            LaunchAtLoginToggle()
            Spacer()
            Menu {
                Button("Open config.json") { NSWorkspace.shared.open(Store.configURL) }
                Button("Open events history") { NSWorkspace.shared.open(Store.eventsURL) }
                Button("Reveal folder in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Store.configURL]) }
                Divider()
                Button("Reinstall Claude Code hooks") { Task { _ = await Hooks.run() } }
                Button("Remove Claude Code hooks") { Task { _ = await Hooks.run(uninstall: true) } }
            } label: { Image(systemName: "gearshape") }
                .menuStyle(.borderlessButton).fixedSize()
            Button("Quit") { NSApp.terminate(nil) }
        }
        .font(.callout)
    }
}

/// Shown when the Claude Code hook isn't set up (e.g. the app was installed from a plain download).
struct HooksBanner: View {
    @State private var installed = Hooks.isInstalled
    @State private var message = ""

    var body: some View {
        Group {
            if !installed {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label("Claude Code hooks aren't installed", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                        Spacer()
                        Button("Install") {
                            message = "Installing…"
                            Task {
                                message = await Hooks.run()
                                installed = Hooks.isInstalled
                            }
                        }
                        .font(.caption)
                    }
                    if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
        .onAppear { installed = Hooks.isInstalled }
    }
}

struct SessionsSection: View {
    @Environment(Store.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sessions").font(.subheadline.bold()).foregroundStyle(.secondary)
            if store.sessions.isEmpty {
                Text("No active sessions").font(.callout).foregroundStyle(.tertiary)
            }
            ForEach(store.sessions) { s in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: s.status.symbol)
                        .foregroundStyle(s.status == .attention ? .orange : .secondary)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack {
                            Text(s.project).bold()
                            Spacer()
                            Text(timing(s)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        Text(statusLine(s)).font(.caption).foregroundStyle(.secondary)
                        if !s.detail.isEmpty && s.status != .working {
                            Text(s.detail).font(.caption).foregroundStyle(.tertiary).lineLimit(2)
                        }
                    }
                }
                .contentShape(Rectangle())
                .help(s.cwd)
                .contextMenu {
                    Button("Reveal in Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: s.cwd)) }
                    Button("Copy path") { copy(s.cwd) }
                }
            }
        }
    }

    private func statusLine(_ s: Session) -> String {
        s.status == .waiting ? "Waiting on \(s.backgroundRunning) background task\(s.backgroundRunning == 1 ? "" : "s")"
                             : s.status.label
    }

    private func timing(_ s: Session) -> String {
        if (s.status == .working || s.status == .waiting), let start = s.workingSince {
            return elapsed(store.now.timeIntervalSince(start))
        }
        return s.updated.formatted(.relative(presentation: .named))
    }
}

struct RecentSection: View {
    @Environment(Store.self) private var store
    @State private var copiedID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Recent").font(.subheadline.bold()).foregroundStyle(.secondary)
                Spacer()
                if !store.recentEvents.isEmpty {
                    Button("Clear") { store.clearRecent() }
                        .buttonStyle(.borderless).font(.caption)
                }
            }
            if store.recentEvents.isEmpty {
                Text("Nothing yet").font(.callout).foregroundStyle(.tertiary)
            }
            ForEach(store.recentEvents) { e in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: Status(kind: e.kind).symbol).font(.caption).foregroundStyle(.secondary)
                    Text(e.date.formatted(date: .omitted, time: .shortened))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Text(e.project).font(.caption.bold())
                    Text(copiedID == e.id ? "Copied" : e.detail).font(.caption).lineLimit(1)
                        .foregroundStyle(copiedID == e.id ? .green : .primary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    copy(e.detail); copiedID = e.id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { if copiedID == e.id { copiedID = nil } }
                }
                .help("Click to copy")
            }
        }
    }
}

struct SettingsSection: View {
    @Environment(Store.self) private var store
    @State private var pushStatus = ""

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 8) {
            Text("Notifications").font(.subheadline.bold()).foregroundStyle(.secondary)

            if !Notifier.shared.authorized {
                HStack {
                    Label("Mac notifications are off for ClaudeNotify", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                    Spacer()
                    Button("Open Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                    }
                    .font(.caption)
                }
                .onAppear { Notifier.shared.refreshAuthorization() }
            }

            Toggle("Mac alerts", isOn: $store.macEnabled.onSet(store.save))
            Toggle("Phone pushes (ntfy)", isOn: $store.phoneEnabled.onSet(store.save))
            Toggle("“Waiting on background tasks” notes", isOn: $store.showWaiting.onSet(store.save))

            SoundPicker(title: "Finish sound", selection: $store.soundDone.onSet(store.save))
            SoundPicker(title: "Warning sound", selection: $store.soundAttention.onSet(store.save))
            SoundPicker(title: "Waiting sound", selection: $store.soundWaiting.onSet(store.save))

            HStack {
                Text("ntfy topic")
                TextField("topic", text: $store.ntfyTopic)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { store.save() }
            }
            HStack {
                Button("Send test push") {
                    store.save()
                    pushStatus = "Sending…"
                    Task { pushStatus = await store.sendTestPush() }
                }
                Text(pushStatus).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Menu(store.isMuted ? "Muted" : "Mute") {
                    Button("1 hour") { store.mute(for: 3600) }
                    Button("4 hours") { store.mute(for: 4 * 3600) }
                    Button("Until tomorrow 8 AM") { store.mute(for: untilTomorrow8()) }
                    if store.isMuted { Divider(); Button("Unmute") { store.mute(for: nil) } }
                }
                .fixedSize()
            }
        }
    }

    private func untilTomorrow8() -> TimeInterval {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date())!
        let target = cal.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow)!
        return target.timeIntervalSinceNow
    }
}

struct SoundPicker: View {
    let title: String
    @Binding var selection: String

    var body: some View {
        HStack {
            Picker(title, selection: $selection.onSet { Store.preview(selection) }) {
                Text("None").tag("")
                Divider()
                ForEach(Store.availableSounds, id: \.self) { Text($0).tag($0) }
            }
            Button { Store.preview(selection) } label: { Image(systemName: "speaker.wave.2") }
                .buttonStyle(.borderless)
                .disabled(selection.isEmpty)
                .help("Preview")
        }
    }
}

struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle("Launch at login", isOn: $enabled)
            .toggleStyle(.checkbox)
            .onChange(of: enabled) { _, on in
                do {
                    if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                } catch {
                    enabled = SMAppService.mainApp.status == .enabled
                }
            }
    }
}

// MARK: Helpers

extension Binding {
    /// Run `action` after the wrapped value is set.
    func onSet(_ action: @escaping () -> Void) -> Binding<Value> {
        Binding(get: { wrappedValue }, set: { wrappedValue = $0; action() })
    }
}

func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

func elapsed(_ t: TimeInterval) -> String {
    let s = max(0, Int(t))
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                     : String(format: "%d:%02d", s / 60, s % 60)
}
