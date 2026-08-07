cask "vercelbar" do
  version "1.2.1"
  sha256 "15c6d706fab3fbd5ad5d8e7381e5dfef3beaacf5f44f4221b79dc59c1310ecd2"

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
