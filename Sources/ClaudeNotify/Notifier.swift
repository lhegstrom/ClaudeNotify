import AppKit
import Foundation
import Observation
import UserNotifications

/// Posts Mac notifications on behalf of ~/.claude/hooks/notify.sh so they carry this app's icon.
/// The hook drops one JSON file per notification into ~/.claude/notify/queue/; we post and delete it.
@MainActor
@Observable
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    static let queueURL = Store.dir.appendingPathComponent("queue")

    private struct Request: Decodable {
        let title: String
        let subtitle: String
        let body: String
        let sound: String
        let ts: Double
    }

    var authorized = true
    @ObservationIgnored private var source: DispatchSourceFileSystemObject?

    func start() {
        try? FileManager.default.createDirectory(at: Self.queueURL, withIntermediateDirectories: true)
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in
            Task { @MainActor in self.refreshAuthorization() }
        }

        drain(staleAfter: 120) // don't replay a backlog from while we weren't running

        let fd = open(Self.queueURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        src.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.drain() } }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    func refreshAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let ok = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            Task { @MainActor in self.authorized = ok }
        }
    }

    /// Called from the 1s store timer as a backstop for missed directory events.
    func drain(staleAfter: TimeInterval = 300) {
        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(at: Self.queueURL, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let now = Date().timeIntervalSince1970
        for url in files {
            defer { try? fm.removeItem(at: url) }
            guard let data = try? Data(contentsOf: url),
                  let req = try? JSONDecoder().decode(Request.self, from: data),
                  now - req.ts < staleAfter else { continue }
            post(req)
        }
    }

    private func post(_ req: Request) {
        let content = UNMutableNotificationContent()
        content.title = req.title
        content.subtitle = req.subtitle
        content.body = req.body
        // Sound is played via NSSound so any system or ~/Library/Sounds name works.
        let note = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(note) { error in
            guard error != nil else { return }
            Task { @MainActor in
                self.authorized = false
                Self.fallback(req) // notifications disabled for this app: use osascript
            }
        }
        Store.preview(req.sound)
    }

    private static func fallback(_ req: Request) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "on run argv", "-e",
                       "display notification (item 3 of argv) with title (item 1 of argv) subtitle (item 2 of argv)",
                       "-e", "end run", req.title, req.subtitle, req.body]
        try? p.run()
    }

    // Show banners even while the menu bar panel is open.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}
