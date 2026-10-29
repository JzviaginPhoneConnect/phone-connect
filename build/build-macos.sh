#!/usr/bin/env bash
# Builds PhoneConnect for macOS: a self-contained PhoneConnect.app with scrcpy
# and adb for both Apple Silicon and Intel Macs.
#
#   ./build/build-macos.sh          release files: dist/PhoneConnect.dmg (on a Mac)
#                                   and dist/PhoneConnect-macOS.zip
#   ./build/build-macos.sh --dev    developer build for testing a change: only
#                                   dist/dev/PhoneConnect.app, no dmg or zip
#   ./build/build-macos.sh --dev --run   ...and start it right away
#
# Runs on macOS (or Linux, without the .dmg). The version stamped into the app
# comes from APP_VERSION, e.g. APP_VERSION=1.2.3 (the GitHub workflow sets it).
# Without it, the build is marked as a developer build, e.g. 1.0.4-dev+3f2a1b9
# (the next version, then the commit it was built from).
set -euo pipefail

DEV=false
RUN=false
for arg in "$@"; do
  case "$arg" in
    --dev) DEV=true ;;
    --run) RUN=true; DEV=true ;;
    -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
    *) echo "Unknown option $arg (use --dev, --run)" >&2; exit 1 ;;
  esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=build/versions.env
source "$ROOT/build/versions.env"

dev_version() {
  local next sha dirty=""
  next="$("$ROOT/build/next-version.sh" 2>/dev/null || tr -d '[:space:]' < "$ROOT/VERSION")"
  sha="$(git -C "$ROOT" rev-parse --short=7 HEAD 2>/dev/null || echo local)"
  if [[ -n "$(git -C "$ROOT" status --porcelain 2>/dev/null)" ]]; then dirty=".changed"; fi
  echo "$next-dev+$sha$dirty"
}
VERSION="${APP_VERSION:-$(dev_version)}"
VERSION="$(printf '%s' "$VERSION" | tr -d '[:space:]')"
NUMERIC_VERSION="${VERSION%%-*}"   # macOS wants plain numbers in the app's version fields
DL="$ROOT/downloads"
DIST="$ROOT/dist"
if $DEV; then
  APP="$DIST/dev/PhoneConnect.app"
else
  APP="$DIST/macos/PhoneConnect.app"
fi

sha256() { if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }

# download NAME EXPECTED_SHA256 -> path of the verified file (cached in downloads/)
# (optional third argument: the folder URL, if not the scrcpy release)
download() {
  local name=$1 want=$2 file="$DL/$1"
  local base=${3:-https://github.com/Genymobile/scrcpy/releases/download/v$SCRCPY_VERSION}
  mkdir -p "$DL"
  if [[ ! -f "$file" || "$(sha256 "$file")" != "$want" ]]; then
    echo "Downloading $name" >&2
    curl -fsSL -o "$file" "$base/$name"
  fi
  local got; got="$(sha256 "$file")"
  if [[ "$got" != "$want" ]]; then
    echo "Checksum mismatch for $name: got $got, expected $want" >&2
    exit 1
  fi
  echo "$file"
}

echo "Building PhoneConnect $VERSION for macOS (scrcpy $SCRCPY_VERSION)$($DEV && echo ' - developer build')"
if $DEV; then
  rm -rf "$APP"
else
  rm -rf "$DIST/macos" "$DIST/PhoneConnect-macOS.zip"
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/tools"

# ---- bundled tools, one set per Mac type ----
for arch in aarch64 x86_64; do
  if [[ $arch == aarch64 ]]; then sum=$SHA256_MACOS_AARCH64; dest=arm64; else sum=$SHA256_MACOS_X86_64; dest=x86_64; fi
  tgz="$(download "scrcpy-macos-$arch-v$SCRCPY_VERSION.tar.gz" "$sum")"
  tmp="$(mktemp -d)"
  tar -xzf "$tgz" -C "$tmp"
  src="$tmp/scrcpy-macos-$arch-v$SCRCPY_VERSION"
  tools="$APP/Contents/Resources/tools/$dest"
  mkdir -p "$tools"
  cp "$src/adb" "$src/scrcpy-server" "$tools/"
  cp "$src/LICENSE" "$tools/scrcpy-LICENSE.txt"
  # scrcpy goes in a small app bundle of its own, so its window shows up in the
  # Dock as PhoneConnect with the app's icon (a bare program gets the "exec" icon)
  mirror="$tools/PhoneConnect Mirror.app/Contents"
  mkdir -p "$mirror/MacOS" "$mirror/Resources"
  cp "$src/scrcpy" "$mirror/MacOS/scrcpy"
  cp "$ROOT/assets/PhoneConnect.png" "$mirror/MacOS/scrcpy.png"   # window icon; scrcpy looks next to itself
  cp "$src/disconnected.png" "$mirror/MacOS/"                      # shown in the window if the phone drops off
  cp "$ROOT/assets/PhoneConnect.icns" "$mirror/Resources/PhoneConnect.icns"
  cat > "$mirror/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>PhoneConnect</string>
  <key>CFBundleDisplayName</key><string>PhoneConnect</string>
  <key>CFBundleIdentifier</key><string>io.github.phoneconnect.mirror</string>
  <key>CFBundleExecutable</key><string>scrcpy</string>
  <key>CFBundleIconFile</key><string>PhoneConnect</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$NUMERIC_VERSION</string>
  <key>CFBundleVersion</key><string>$NUMERIC_VERSION</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF
  chmod 755 "$mirror/MacOS/scrcpy" "$tools/adb"
  rm -rf "$tmp"
done

# ---- the app itself ----
# the shared script (the same file as on Windows) plus the macOS platform scripts
sed "s/@VERSION@/$VERSION/g" "$ROOT/app/PhoneConnect.sh" > "$APP/Contents/MacOS/PhoneConnect.sh"
mkdir -p "$APP/Contents/MacOS/platform"
cp "$ROOT"/platform/macos/*.sh "$APP/Contents/MacOS/platform/"
cp "$ROOT/assets/PhoneConnect.icns" "$APP/Contents/Resources/PhoneConnect.icns"
# the launcher (the app's executable) starts the script as a new instance of a small
# inner app each time, so opening PhoneConnect again starts a new run (macos/Launcher.sh)
cp "$ROOT/macos/Launcher.sh" "$APP/Contents/MacOS/PhoneConnect"
run_app="$APP/Contents/Resources/PhoneConnect Run.app/Contents"
mkdir -p "$run_app/MacOS"
cp "$ROOT/macos/Run.sh" "$run_app/MacOS/PhoneConnect"
chmod 755 "$APP/Contents/MacOS/PhoneConnect" "$APP/Contents/MacOS/PhoneConnect.sh" "$run_app/MacOS/PhoneConnect"
cat > "$run_app/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>PhoneConnect</string>
  <key>CFBundleDisplayName</key><string>PhoneConnect</string>
  <key>CFBundleIdentifier</key><string>io.github.phoneconnect.run</string>
  <key>CFBundleExecutable</key><string>PhoneConnect</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$NUMERIC_VERSION</string>
  <key>CFBundleVersion</key><string>$NUMERIC_VERSION</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
EOF

# ---- the status window (what's happening, until the picture appears): a small Swift
# app, one file for Apple Silicon and Intel, with PhoneConnect's name and icon ----
status_app="$APP/Contents/Resources/PhoneConnect Status.app/Contents"
if command -v swiftc >/dev/null && command -v lipo >/dev/null; then
  mkdir -p "$status_app/MacOS" "$status_app/Resources"
  tmp="$(mktemp -d)"
  for arch in arm64 x86_64; do
    swiftc -O -target "$arch-apple-macos12" "$ROOT/macos/StatusWindow.swift" -o "$tmp/status-$arch"
  done
  lipo -create "$tmp/status-arm64" "$tmp/status-x86_64" -output "$status_app/MacOS/PhoneConnectStatus"
  rm -rf "$tmp"
  cp "$ROOT/assets/PhoneConnect.icns" "$status_app/Resources/PhoneConnect.icns"
  cat > "$status_app/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>PhoneConnect</string>
  <key>CFBundleDisplayName</key><string>PhoneConnect</string>
  <key>CFBundleIdentifier</key><string>io.github.phoneconnect.status</string>
  <key>CFBundleExecutable</key><string>PhoneConnectStatus</string>
  <key>CFBundleIconFile</key><string>PhoneConnect</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$NUMERIC_VERSION</string>
  <key>CFBundleVersion</key><string>$NUMERIC_VERSION</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF
else
  echo "Note: no Swift compiler (Xcode command line tools), so no status window in this build" >&2
fi
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/"

# ---- license texts: ours, the bundled software's, and adb's notice (from the
# Platform-Tools release the bundled adb comes from) ----
licenses="$APP/Contents/Resources/licenses"
mkdir -p "$licenses"
cp "$ROOT"/licenses/* "$licenses/"
cp "$ROOT/LICENSE" "$licenses/PhoneConnect-MIT.txt"
read -r pt_url pt_sum <<< "$PLATFORM_TOOLS_MACOS"
pt_zip="$(download "$(basename "$pt_url")" "$pt_sum" "$(dirname "$pt_url")")"
unzip -p "$pt_zip" platform-tools/NOTICE.txt > "$licenses/adb-NOTICE.txt"

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

# ---- developer build: stop here (and optionally start it) ----
if $DEV; then
  echo "Built: $APP (version $VERSION)"
  if $RUN; then
    if command -v open >/dev/null; then
      # quit a running copy first, so the new build is the one that starts
      pkill -f "PhoneConnect.app/Contents/MacOS/PhoneConnect" 2>/dev/null || true
      pkill -x scrcpy 2>/dev/null || true
      open "$APP"
      echo "Started. Log: /tmp/PhoneConnect.log"
    else
      echo "Can't start it here (--run needs macOS)"
    fi
  fi
  exit 0
fi

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
