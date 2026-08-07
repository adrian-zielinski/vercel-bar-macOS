cask "vercelbar" do
  version "1.0.1"
  sha256 "7bf3c3c5b10a350101417504cc1457a16fd1079f0c8fd78a6694b0fce3763cec"

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
