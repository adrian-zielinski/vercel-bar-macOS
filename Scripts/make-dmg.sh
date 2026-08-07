#!/usr/bin/env bash
# Pakuje build/VercelBar.zip w build/VercelBar.dmg (aplikacja + skrót do Programów).
# Źródłem jest zip, nie build/VercelBar.app: kopia w build/ leży w iCloud, który
# dokleja atrybuty psujące pieczęć podpisu — zip jest od nich wolny.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ZIP="$ROOT/build/VercelBar.zip"
[ -f "$ZIP" ] || { echo "BŁĄD: brak $ZIP — najpierw ./Scripts/build-app.sh"; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT INT TERM

ditto -x -k "$ZIP" "$STAGE"
ln -s /Applications "$STAGE/Applications"

rm -f "$ROOT/build/VercelBar.dmg"
hdiutil create -volname "VercelBar" -srcfolder "$STAGE" -format UDZO -quiet "$ROOT/build/VercelBar.dmg"
echo "✓ build/VercelBar.dmg"
