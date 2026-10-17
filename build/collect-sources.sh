#!/usr/bin/env bash
# Collects the source code of everything PhoneConnect bundles (the SOURCE_* lines in
# build/versions.env): downloads each archive, checks its SHA-256, and writes a
# README.md describing them. The release job publishes the folder once per set of
# versions as the GitHub release $THIRD_PARTY_SOURCES_TAG, which THIRD_PARTY_NOTICES.md
# links to (the GPL and LGPL require the source to be available).
#
#   build/collect-sources.sh <output folder>
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?usage: collect-sources.sh <output folder>}"
# shellcheck source=build/versions.env
source "$ROOT/build/versions.env"
mkdir -p "$OUT"

sha256() { if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }

{
  echo "# Third-party sources ($THIRD_PARTY_SOURCES_TAG)"
  echo
  echo "The exact source code of the third-party software bundled in PhoneConnect releases"
  echo "that link here (see THIRD_PARTY_NOTICES.md in the app). Each archive is the"
  echo "upstream release (scrcpy and the libraries built into it) or MSYS2's source"
  echo "package (upstream source plus MSYS2's build recipe and patches)."
  echo
  echo "| File | From | SHA-256 |"
  echo "|---|---|---|"
} > "$OUT/README.md"

for var in $(compgen -v SOURCE_); do
  read -r url sum file <<< "${!var}"
  file="${file:-$(basename "$url")}"
  echo "Downloading $file"
  curl -fsSL --retry 3 -o "$OUT/$file" "$url"
  got="$(sha256 "$OUT/$file")"
  if [[ "$got" != "$sum" ]]; then
    echo "Checksum mismatch for $file: got $got, expected $sum" >&2
    exit 1
  fi
  echo "| \`$file\` | $url | \`$sum\` |" >> "$OUT/README.md"
done
echo "Collected $(compgen -v SOURCE_ | wc -l | tr -d ' ') source archives in $OUT"
