#!/usr/bin/env bash
# Installs the latest VercelBar release into /Applications (or ~/Applications).
# Terminal downloads skip Gatekeeper's quarantine, so the app opens without
# the right-click → Open dance.
set -euo pipefail

REPO="adrian-zielinski/vercelbar"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT INT TERM

echo "▸ Downloading the latest VercelBar release..."
curl -fsSL -o "$TMP/VercelBar.zip" "https://github.com/$REPO/releases/latest/download/VercelBar.zip"

echo "▸ Unpacking..."
ditto -x -k "$TMP/VercelBar.zip" "$TMP"

DEST="/Applications"
[ -w "$DEST" ] || DEST="$HOME/Applications"
mkdir -p "$DEST"

echo "▸ Installing into $DEST..."
rm -rf "$DEST/VercelBar.app"
ditto "$TMP/VercelBar.app" "$DEST/VercelBar.app"
xattr -cr "$DEST/VercelBar.app" 2>/dev/null || true

open "$DEST/VercelBar.app"
echo "✓ VercelBar installed. Look for the ▲ triangle in your menu bar."
