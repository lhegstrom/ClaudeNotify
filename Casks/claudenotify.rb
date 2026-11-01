# Homebrew cask. This repo doubles as a tap:
#   brew tap lhegstrom/claudenotify https://github.com/lhegstrom/ClaudeNotify
#   brew install --cask claudenotify
# version and sha256 are updated by scripts/release.sh.
cask "claudenotify" do
  version "1.0.0"
  sha256 "6930769b530695b0a16ef39384e5a7d42dc60dbf0efa2d20fe1efc5ce62e74da"

  url "https://github.com/lhegstrom/ClaudeNotify/releases/download/v#{version}/ClaudeNotify.zip"
  name "ClaudeNotify"
  desc "Menu bar notifier for Claude Code sessions (unofficial)"
  homepage "https://github.com/lhegstrom/ClaudeNotify"

  depends_on macos: ">= :sequoia"

  app "ClaudeNotify.app"

  # The app is ad-hoc signed (not notarized), so clear the download quarantine,
  # then install/update the Claude Code hook script and settings entries.
  postflight do
    system_command "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "#{appdir}/ClaudeNotify.app"]
    system_command "#{appdir}/ClaudeNotify.app/Contents/Resources/install-hooks.sh"
  end

  uninstall quit: "local.claudenotify"

  zap trash: [
    "~/.claude/notify",
    "~/Library/Preferences/local.claudenotify.plist",
  ]

  caveats <<~EOS
    Hooks were added to ~/.claude/settings.json. Before uninstalling, remove them with
    the gear menu → "Remove Claude Code hooks", or run:
      #{appdir}/ClaudeNotify.app/Contents/Resources/install-hooks.sh --uninstall
  EOS
end
