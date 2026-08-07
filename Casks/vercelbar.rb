cask "vercelbar" do
  version "1.2.2"
  sha256 "4a4b238fe5cde4ebc9c36d55d549012455f64afb02eefc3c564d43e773e5eed9"

  url "https://github.com/adrian-zielinski/vercel-bar-macOS/releases/download/v#{version}/VercelBar.zip"
  name "VercelBar"
  desc "Live Vercel deploy status in the macOS menu bar"
  homepage "https://github.com/adrian-zielinski/vercel-bar-macOS"

  depends_on macos: ">= :sonoma"

  app "VercelBar.app"

  uninstall quit: "pl.zielinski.vercelbar"

  zap trash: [
    "~/Library/Preferences/pl.zielinski.vercelbar.plist",
  ]

  caveats <<~EOS
    VercelBar ships without a paid Apple signature. If macOS blocks the first
    launch, right-click VercelBar.app → Open → Open (needed once), or install
    without quarantine:
      brew install --cask --no-quarantine vercelbar
  EOS
end
