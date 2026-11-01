# Homebrew cask. This repo doubles as a tap:
#   brew tap lhegstrom/claudenotify https://github.com/lhegstrom/ClaudeNotify
#   brew install --cask lhegstrom/claudenotify/claudenotify   (fully qualified name = trusts just this cask)
# version and sha256 are updated by scripts/release.sh.
# The app installs the Claude Code hooks itself on first launch: cask steps are sandboxed away from ~/.claude.
cask "claudenotify" do
  version "1.0.1"
  sha256 "662ae589e34f74defb87bd42892a6535f832567aeafc41a758bc2f5b219ee92d"

  url "https://github.com/lhegstrom/ClaudeNotify/releases/download/v#{version}/ClaudeNotify.zip"
  name "ClaudeNotify"
  desc "Menu bar notifier for Claude Code sessions (unofficial)"
  homepage "https://github.com/lhegstrom/ClaudeNotify"

  depends_on macos: :sequoia

  app "ClaudeNotify.app"

  # The app is ad-hoc signed (not notarized), so clear the download quarantine.
  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/ClaudeNotify.app"]
  end

  uninstall quit: "local.claudenotify"

  zap trash: [
    "~/.claude/notify",
    "~/Library/Preferences/local.claudenotify.plist",
  ]

  caveats <<~EOS
    Open ClaudeNotify once; it adds its Claude Code hooks to ~/.claude/settings.json.
    Before uninstalling, remove them with the gear menu → "Remove Claude Code hooks", or run:
      #{appdir}/ClaudeNotify.app/Contents/Resources/install-hooks.sh --uninstall
  EOS
end
