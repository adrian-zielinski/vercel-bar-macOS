cask "vercelbar" do
  version "1.1.0"
  sha256 "c7831adba7469e19349cb94f8ad7db85ce26d8309e8c35ed6f5f107f11e266b3"

  url "https://github.com/adrian-zielinski/vercelbar/releases/download/v#{version}/VercelBar.zip"
  name "VercelBar"
  desc "Live Vercel deploy status in the macOS menu bar"
  homepage "https://github.com/adrian-zielinski/vercelbar"

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
