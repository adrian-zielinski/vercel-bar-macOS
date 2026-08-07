# ▲ VercelBar

**Your Vercel deploys, live in the macOS menu bar.**

A small triangle sits in your menu bar and shows the state of your deploys at a glance: green means everything shipped, pulsing blue means a build is running, red means a deploy failed. Click it for the details. You stop cmd-tabbing to the dashboard.

**⬇️ [Download VercelBar for macOS](../../releases/latest)**

## Features

- ✅ **Live status triangle** in the menu bar: green / pulsing blue / red / gray, driven by the worst state among your watched projects
- ✅ **Deploy feed** with the last 3, 5 or 10 deploys across your projects: branch, commit message, relative time and a build timer that ticks every second while a build runs
- ✅ **Notifications with sound**: 🚀 when a deploy starts, ✅ when it ships (click opens the preview), ❌ when it fails (click opens the logs)
- ✅ **Teams**: watch your personal account or any team you belong to
- ✅ **Token lives in the Keychain**, never in a file
- ✅ **English + Polish**, following your system language
- ✅ **Light and dark mode**, respects Reduce Motion
- ✅ **Tiny native Swift app**: 1.4 MB on disk, zero dependencies, no Electron

## Screenshots

<p>
  <img src="docs/screenshots/popover.png" width="360" alt="VercelBar popover with the deploy feed">
  <img src="docs/screenshots/settings.png" width="480" alt="VercelBar settings window">
</p>

## Install

1. Download `VercelBar.zip` from [Releases](../../releases/latest) and unpack it.
2. Drag `VercelBar.app` into your Applications folder.
3. On first launch: right-click → Open, then Open again. The app ships without a paid Apple signature; this dance happens once.

## Setup

1. Create a token at [vercel.com](https://vercel.com) → Account Settings → **Tokens**. Pick the account or team you want to watch as the scope.
2. Click the triangle → **Connect to Vercel** → paste the token.
3. Open the **Projects** tab and check the projects you care about.

VercelBar polls the Vercel API every 30 seconds, and every 10 seconds while a build runs. On API errors it backs off exponentially, up to 5 minutes. macOS will ask for notification permission on first launch and for keychain access after an app update; choose "Always Allow" and it stays quiet.

## Uninstall

1. Quit VercelBar from the popover.
2. Delete `VercelBar.app` from Applications.
3. Remove the login item in System Settings → General → Login Items, if you enabled it.
4. VercelBar keeps your token in the login keychain. To remove it:

```bash
security delete-generic-password -s pl.zielinski.vercelbar
```

## Build from source

Requires Swift 6+ (Command Line Tools from Xcode 16 or newer). No third-party dependencies.

```bash
git clone https://github.com/adrian-zielinski/vercelbar.git
cd vercelbar

# Build build/VercelBar.app and build/VercelBar.zip
./Scripts/build-app.sh

# Run in place (dev mode; shows a Dock icon that the bundled app doesn't have)
swift run vercelbar

# Core test suite (283 tests)
swift run vercelbar-tests
```

## How it works

VercelBar polls Vercel's REST API (`/v9/projects`, `/v6/deployments`) over HTTPS with your token, keeping at most four requests in flight. A pure notification engine turns state transitions into events and dedupes them per deployment, so a flapping API never notifies twice. The UI is plain SwiftUI with a `MenuBarExtra`; the token sits in the login keychain and gets cached in memory after the first read.

Known limits: the project list caps at 100 entries (no pagination yet), and the deploy feed shows what the API returns for the projects you watch.

## Languages

The app ships with English and Polish and follows the system language. Strings live in [`Sources/VercelBarKit/L10n.swift`](Sources/VercelBarKit/L10n.swift); pull requests with new languages are welcome.

## License

[MIT](LICENSE).

