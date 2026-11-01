import Foundation

/// Installs/removes the Claude Code hook by running the bundled install-hooks.sh.
enum Hooks {
    static let scriptURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/hooks/notify.sh")
    static let settingsURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")

    static var isInstalled: Bool {
        guard FileManager.default.fileExists(atPath: scriptURL.path),
              let text = try? String(contentsOf: settingsURL, encoding: .utf8) else { return false }
        return text.contains("hooks/notify.sh")
    }

    /// Returns the script's output (or an error message).
    static func run(uninstall: Bool = false) async -> String {
        guard let script = Bundle.main.url(forResource: "install-hooks", withExtension: "sh") else {
            return "Installer missing from app bundle"
        }
        return await Task.detached {
            let p = Process()
            let pipe = Pipe()
            p.executableURL = URL(fileURLWithPath: "/bin/bash")
            p.arguments = [script.path] + (uninstall ? ["--uninstall"] : [])
            p.standardOutput = pipe
            p.standardError = pipe
            do { try p.run() } catch { return error.localizedDescription }
            let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            p.waitUntilExit()
            return out.trimmingCharacters(in: .whitespacesAndNewlines)
        }.value
    }
}
