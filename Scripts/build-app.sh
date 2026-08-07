#!/usr/bin/env bash
# Buduje VercelBar.app i VercelBar.zip. Wymaga tylko Swift toolchain (CLT wystarczą).
# Składanie i podpis w katalogu tymczasowym poza iCloud, bo atrybuty
# iCloud (com.apple.fileprovider.*) psują podpis kodu.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="VercelBar"
BUNDLE_ID="pl.zielinski.vercelbar"
VERSION="1.0.1"
OUT_DIR="$ROOT/build"
STAGE_ROOT="$(mktemp -d)"
STAGE="$STAGE_ROOT/$APP_NAME.app"
trap 'rm -rf "$STAGE_ROOT"' EXIT INT TERM   # sprzątaj staging po błędzie kompilacji i po przerwaniu

if [ ! -f "$ROOT/Resources/AppIcon.icns" ]; then
    echo "▸ Generuję ikonę..."
    swift "$ROOT/Scripts/MakeIcon.swift"
fi

echo "▸ Kompilacja (release)..."
swift build -c release --product vercelbar

BIN_DIR="$(swift build -c release --product vercelbar --show-bin-path)"
EXECUTABLE="$BIN_DIR/vercelbar"
[ -f "$EXECUTABLE" ] || { echo "BŁĄD: brak binarki: $EXECUTABLE"; exit 1; }

echo "▸ Składanie bundla (staging poza iCloud)..."
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp "$EXECUTABLE" "$STAGE/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/AppIcon.icns" "$STAGE/Contents/Resources/AppIcon.icns"

cat > "$STAGE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSHumanReadableCopyright</key><string>MIT</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
</dict>
</plist>
PLIST

echo "▸ Czyszczenie atrybutów i podpis ad-hoc..."
xattr -cr "$STAGE"
find "$STAGE" -name '._*' -delete 2>/dev/null || true
find "$STAGE" -name '.DS_Store' -delete 2>/dev/null || true
codesign --force --sign - "$STAGE"

echo "▸ Weryfikacja podpisu..."
codesign --verify --deep --strict "$STAGE" && echo "  podpis OK"

# Zip robimy ze STAGE (poza iCloud), nie z kopii w build/ — kopia w iCloud dostaje
# atrybuty com.apple.fileprovider.*, które trafiłyby do paczki i zepsuły podpis.
echo "▸ Pakowanie do $OUT_DIR ..."
mkdir -p "$OUT_DIR"
rm -rf "$OUT_DIR/$APP_NAME.app" "$OUT_DIR/$APP_NAME.zip"
ditto "$STAGE" "$OUT_DIR/$APP_NAME.app"
# --sequesterRsrc: bez tego zwykły `unzip` materializuje pliki AppleDouble (._*)
# wewnątrz bundla i psuje pieczęć podpisu.
ditto -c -k --sequesterRsrc --keepParent "$STAGE" "$OUT_DIR/$APP_NAME.zip"

# Kopia w build/ leży w iCloud i przy kopiowaniu dostaje com.apple.FinderInfo oraz
# com.apple.fileprovider.* — z nimi `codesign --verify` odmawia. Czyścimy (bez twardej
# weryfikacji: iCloud potrafi dopisać atrybuty z powrotem w dowolnym momencie).
xattr -cr "$OUT_DIR/$APP_NAME.app" 2>/dev/null || true

echo "✓ Gotowe:"
echo "    $OUT_DIR/$APP_NAME.app   (do uruchomienia lokalnie)"
echo "    $OUT_DIR/$APP_NAME.zip   (do wrzucenia na GitHub Releases)"
du -sh "$OUT_DIR/$APP_NAME.zip"
