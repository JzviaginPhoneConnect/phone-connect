#!/usr/bin/env bash
# Builds dist/PhoneConnect-macOS.zip: a self-contained PhoneConnect.app with
# scrcpy and adb for both Apple Silicon and Intel Macs.
# Runs on macOS or Linux. Usage:  ./build/build-macos.sh
# The version stamped into the app comes from APP_VERSION, e.g.
#   APP_VERSION=1.2.3 ./build/build-macos.sh
# (the GitHub workflow sets it). Without it, a local build is "<next version>-dev".
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/build/versions.env"
VERSION="${APP_VERSION:-$("$ROOT/build/next-version.sh" 2>/dev/null || cat "$ROOT/VERSION")-dev}"
VERSION="$(printf '%s' "$VERSION" | tr -d '[:space:]')"
NUMERIC_VERSION="${VERSION%%-*}"   # macOS wants plain numbers in the app's version fields
DL="$ROOT/downloads"
DIST="$ROOT/dist"
APP="$DIST/macos/PhoneConnect.app"

sha256() { if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }

# download NAME EXPECTED_SHA256 -> path of the verified file (cached in downloads/)
download() {
  local name=$1 want=$2 file="$DL/$1"
  mkdir -p "$DL"
  if [[ ! -f "$file" || "$(sha256 "$file")" != "$want" ]]; then
    echo "Downloading $name" >&2
    curl -fsSL -o "$file" "https://github.com/Genymobile/scrcpy/releases/download/v$SCRCPY_VERSION/$name"
  fi
  local got; got="$(sha256 "$file")"
  if [[ "$got" != "$want" ]]; then
    echo "Checksum mismatch for $name: got $got, expected $want" >&2
    exit 1
  fi
  echo "$file"
}

echo "Building PhoneConnect $VERSION for macOS (scrcpy $SCRCPY_VERSION)"
rm -rf "$DIST/macos" "$DIST/PhoneConnect-macOS.zip"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/tools"

# ---- bundled tools, one set per Mac type ----
for arch in aarch64 x86_64; do
  if [[ $arch == aarch64 ]]; then sum=$SHA256_MACOS_AARCH64; dest=arm64; else sum=$SHA256_MACOS_X86_64; dest=x86_64; fi
  tgz="$(download "scrcpy-macos-$arch-v$SCRCPY_VERSION.tar.gz" "$sum")"
  tmp="$(mktemp -d)"
  tar -xzf "$tgz" -C "$tmp"
  src="$tmp/scrcpy-macos-$arch-v$SCRCPY_VERSION"
  mkdir -p "$APP/Contents/Resources/tools/$dest"
  cp "$src/scrcpy" "$src/adb" "$src/scrcpy-server" "$APP/Contents/Resources/tools/$dest/"
  cp "$src/LICENSE" "$APP/Contents/Resources/tools/$dest/scrcpy-LICENSE.txt"
  chmod 755 "$APP/Contents/Resources/tools/$dest/scrcpy" "$APP/Contents/Resources/tools/$dest/adb"
  rm -rf "$tmp"
done

# ---- the app itself ----
sed "s/@VERSION@/$VERSION/g" "$ROOT/macos/PhoneConnect.sh" > "$APP/Contents/MacOS/PhoneConnect"
chmod 755 "$APP/Contents/MacOS/PhoneConnect"
cp "$ROOT/assets/PhoneConnect.icns" "$APP/Contents/Resources/PhoneConnect.icns"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>PhoneConnect</string>
  <key>CFBundleDisplayName</key><string>PhoneConnect</string>
  <key>CFBundleIdentifier</key><string>io.github.phoneconnect</string>
  <key>CFBundleExecutable</key><string>PhoneConnect</string>
  <key>CFBundleIconFile</key><string>PhoneConnect</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$NUMERIC_VERSION</string>
  <key>CFBundleVersion</key><string>$NUMERIC_VERSION</string>
  <key>CFBundleGetInfoString</key><string>PhoneConnect $VERSION</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <!-- the launcher has no Dock icon of its own; scrcpy's window has one -->
  <key>LSUIElement</key><true/>
</dict>
</plist>
EOF

# ---- zip it (keeping the executables executable) ----
cd "$DIST/macos"
if command -v ditto >/dev/null; then
  ditto -c -k --keepParent PhoneConnect.app "$DIST/PhoneConnect-macOS.zip"
else
  zip -qry "$DIST/PhoneConnect-macOS.zip" PhoneConnect.app
fi
echo "Built: $DIST/PhoneConnect-macOS.zip (version $VERSION)"

# ---- installer window (.dmg): only possible on a Mac, since it needs hdiutil ----
if ! command -v hdiutil >/dev/null; then
  echo "Skipping PhoneConnect.dmg (needs macOS)"
  exit 0
fi
rm -f "$DIST/PhoneConnect.dmg"

# dmgbuild lays out the window without needing Finder, so it works on build servers
VENV="$DL/dmgbuild-venv"
if [[ ! -x "$VENV/bin/dmgbuild" ]]; then
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --quiet "dmgbuild==1.6.7"
fi

# one background file holding both normal and Retina resolutions
BG="$DIST/macos/dmg-background.tiff"
tiffutil -cathidpicheck "$ROOT/assets/dmg-background.png" "$ROOT/assets/dmg-background@2x.png" -out "$BG" >/dev/null

"$VENV/bin/dmgbuild" -s "$ROOT/build/dmg-settings.py" \
  -D app="$APP" -D background="$BG" -D icon="$ROOT/assets/PhoneConnect.icns" \
  "PhoneConnect $VERSION" "$DIST/PhoneConnect.dmg"
echo "Built: $DIST/PhoneConnect.dmg"
