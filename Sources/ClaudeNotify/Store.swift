import AppKit
import Foundation
import Observation

/// One line of ~/.claude/notify/events.jsonl, written by ~/.claude/hooks/notify.sh.
struct HookEvent: Decodable, Identifiable {
    let ts: String
    let session_id: String
    let project: String
    let cwd: String
    let kind: String          // working | resumed | waiting | done | attention | ended
    let detail: String
    let background_running: Int?

    var id: String { "\(ts)-\(session_id)-\(kind)" }
    var date: Date { Store.iso.date(from: ts) ?? .distantPast }
}

enum Status: Int, Comparable {
    case idle, done, waiting, working, attention
    static func < (a: Status, b: Status) -> Bool { a.rawValue < b.rawValue }

    init(kind: String) {
        switch kind {
        case "working", "resumed": self = .working
        case "waiting": self = .waiting
        case "attention": self = .attention
        case "done": self = .done
        default: self = .idle
        }
    }

    var label: String {
        switch self {
        case .idle: "Idle"
        case .done: "Done"
        case .waiting: "Waiting on background tasks"
        case .working: "Working"
        case .attention: "Needs attention"
        }
    }

    var symbol: String {
        switch self {
        case .idle: "sparkle"
        case .done: "checkmark.circle"
        case .waiting: "hourglass"
        case .working: "ellipsis.circle"
        case .attention: "exclamationmark.bubble.fill"
        }
    }
}

struct Session: Identifiable {
    let id: String
    var project: String
    var cwd: String
    var status: Status
    var detail: String
    var updated: Date
    var workingSince: Date?
    var backgroundRunning: Int
}

@MainActor
@Observable
final class Store {
    nonisolated(unsafe) static let iso = ISO8601DateFormatter()
    static let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/notify")
    static let configURL = dir.appendingPathComponent("config.json")
    static let eventsURL = dir.appendingPathComponent("events.jsonl")

    /// Sessions with no activity for this long are hidden.
    private let staleAfter: TimeInterval = 12 * 3600

    // Config (mirrors config.json; unknown keys are preserved on write)
    var macEnabled = true
    var phoneEnabled = true
    var showWaiting = true
    var ntfyServer = "https://ntfy.sh"
    var ntfyTopic = ""
    var soundDone = "Glass"
    var soundAttention = "Sosumi"
    var soundWaiting = ""
    var mutedUntil: Date = .distantPast

    var events: [HookEvent] = []
    var sessions: [Session] = []
    var now = Date()

    private var rawConfig: [String: Any] = [:]
    private var configMTime: Date?
    private var eventsMTime: Date?
    private var timer: Timer?

    init() {
        reload(force: true)
        Notifier.shared.start()
        Hooks.syncOnLaunch()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reload(force: false)
                Notifier.shared.drain()
            }
        }
    }

    var isMuted: Bool { mutedUntil > now }

    // MARK: Unread

    /// Last time the panel was opened; done/attention events after this show a badge on the bell.
    var lastSeen = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: "lastSeen"))

    var hasUnread: Bool {
        events.contains { ($0.kind == "done" || $0.kind == "attention") && $0.date > lastSeen }
    }

    func markSeen() {
        lastSeen = Date()
        UserDefaults.standard.set(lastSeen.timeIntervalSince1970, forKey: "lastSeen")
    }

    var overall: Status {
        sessions.map(\.status).max() ?? .idle
    }

    var activeCount: Int {
        sessions.filter { $0.status == .working || $0.status == .waiting || $0.status == .attention }.count
    }

    // MARK: Loading

    private func mtime(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    func reload(force: Bool) {
        now = Date()
        let cm = mtime(Self.configURL)
        if force || cm != configMTime { configMTime = cm; loadConfig() }
        let em = mtime(Self.eventsURL)
        if force || em != eventsMTime { eventsMTime = em; loadEvents() }
        else { rebuildSessions() } // keep staleness current
    }

    private func loadConfig() {
        guard let data = try? Data(contentsOf: Self.configURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        rawConfig = obj
        macEnabled = obj["mac_enabled"] as? Bool ?? true
        phoneEnabled = obj["phone_enabled"] as? Bool ?? true
        showWaiting = obj["show_waiting"] as? Bool ?? true
        ntfyServer = obj["ntfy_server"] as? String ?? "https://ntfy.sh"
        ntfyTopic = obj["ntfy_topic"] as? String ?? ""
        soundDone = obj["sound_done"] as? String ?? "Glass"
        soundAttention = obj["sound_attention"] as? String ?? "Sosumi"
        soundWaiting = obj["sound_waiting"] as? String ?? ""
        let mu = (obj["muted_until"] as? NSNumber)?.doubleValue ?? 0
        mutedUntil = Date(timeIntervalSince1970: mu)
    }

    private func loadEvents() {
        guard let text = try? String(contentsOf: Self.eventsURL, encoding: .utf8) else {
            events = []; rebuildSessions(); return
        }
        let decoder = JSONDecoder()
        events = text.split(separator: "\n").compactMap {
            try? decoder.decode(HookEvent.self, from: Data($0.utf8))
        }
        rebuildSessions()
    }

    private func rebuildSessions() {
        var byID: [String: Session] = [:]
        for e in events {
            if e.kind == "ended" { byID[e.session_id] = nil; continue }
            var s = byID[e.session_id] ?? Session(id: e.session_id, project: e.project, cwd: e.cwd,
                                                   status: .idle, detail: "", updated: e.date,
                                                   workingSince: nil, backgroundRunning: 0)
            s.status = Status(kind: e.kind)
            s.updated = e.date
            s.backgroundRunning = e.background_running ?? 0
            if e.kind == "working" { s.workingSince = e.date; s.detail = "" }
            else if e.kind == "resumed" { s.detail = "" } // approved; keep the original timer
            else if !e.detail.isEmpty { s.detail = e.detail }
            if e.kind == "done" { s.workingSince = nil }
            byID[e.session_id] = s
        }
        sessions = byID.values
            .filter { now.timeIntervalSince($0.updated) < staleAfter }
            .sorted { ($0.status, $0.updated) > ($1.status, $1.updated) }
    }

    static let recentLimit = 10

    /// Events before this are hidden from Recent (the file is kept so session state survives).
    var recentClearedAt = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: "recentClearedAt"))

    var recentEvents: [HookEvent] {
        Array(events
            .filter { !["working", "resumed", "ended"].contains($0.kind) && $0.date > recentClearedAt }
            .suffix(Self.recentLimit)
            .reversed())
    }

    // MARK: Saving

    func save() {
        rawConfig["mac_enabled"] = macEnabled
        rawConfig["phone_enabled"] = phoneEnabled
        rawConfig["show_waiting"] = showWaiting
        rawConfig["ntfy_server"] = ntfyServer
        rawConfig["ntfy_topic"] = ntfyTopic
        rawConfig["sound_done"] = soundDone
        rawConfig["sound_attention"] = soundAttention
        rawConfig["sound_waiting"] = soundWaiting
        rawConfig["muted_until"] = mutedUntil > Date() ? Int(mutedUntil.timeIntervalSince1970) : 0
        guard let data = try? JSONSerialization.data(withJSONObject: rawConfig,
                                                     options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: Self.configURL, options: .atomic)
        configMTime = mtime(Self.configURL)
    }

    func mute(for interval: TimeInterval?) {
        mutedUntil = interval.map { Date().addingTimeInterval($0) } ?? .distantPast
        save()
        now = Date()
    }

    func clearRecent() {
        recentClearedAt = Date()
        UserDefaults.standard.set(recentClearedAt.timeIntervalSince1970, forKey: "recentClearedAt")
    }

    // MARK: Sounds

    static let availableSounds: [String] = {
        let fm = FileManager.default
        let dirs = ["/System/Library/Sounds", "/Library/Sounds",
                    fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Sounds").path]
        var names = Set<String>()
        for d in dirs {
            for f in (try? fm.contentsOfDirectory(atPath: d)) ?? [] {
                let url = URL(fileURLWithPath: f)
                if ["aiff", "aif", "wav", "caf", "m4a", "mp3"].contains(url.pathExtension.lowercased()) {
                    names.insert(url.deletingPathExtension().lastPathComponent)
                }
            }
        }
        return names.sorted()
    }()

    static func preview(_ name: String) {
        guard !name.isEmpty else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }

    // MARK: Test push (generic content only)

    func sendTestPush() async -> String {
        let base = ntfyServer.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard !ntfyTopic.isEmpty, let url = URL(string: "\(base)/\(ntfyTopic)") else { return "No topic set" }
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.httpMethod = "POST"
        req.setValue("Claude Code", forHTTPHeaderField: "Title")
        req.setValue("bell", forHTTPHeaderField: "Tags")
        req.httpBody = Data("Test notification".utf8)
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            return code == 200 ? "Sent ✓" : "HTTP \(code)"
        } catch {
            return "Failed: \(error.localizedDescription)"
        }
    }
}
