#!/usr/bin/env bash
# Prints the next PhoneConnect version (x.y.z), based on the newest vX.Y.Z tag.
#
# By default the last number goes up (1.2.3 -> 1.2.4). To bump the middle or
# first number instead, any one of these works (checked in this order):
#   BUMP=minor|major|patch                           e.g. from the manual "Run workflow" choice
#   PR_LABELS contains "release:major" / "release:minor"   (labels on the pull request)
#   PR_BODY has the box ticked in the pull request form    (see .github/pull_request_template.md)
#   COMMIT_MSG contains "[major]" / "[minor]"              (for a direct push without a pull request)
# With no vX.Y.Z tag yet, the first version is the one in the VERSION file.
#
# Usage: ./build/next-version.sh            -> 1.2.4
#        ./build/next-version.sh --explain  -> also prints why, on stderr
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
explain() { [[ "${1:-}" == "--explain" ]]; }
say() { if explain "${ARG:-}"; then echo "$*" >&2; fi; }
ARG="${1:-}"

latest="$(git -C "$ROOT" tag --list 'v[0-9]*.[0-9]*.[0-9]*' | sed 's/^v//' \
          | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1 || true)"

if [[ -z "$latest" ]]; then
  first="$(tr -d '[:space:]' < "$ROOT/VERSION")"
  if ! [[ "$first" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "VERSION must look like 1.0.0 (got '$first')" >&2; exit 1
  fi
  say "No version tag yet: first version comes from the VERSION file"
  echo "$first"
  exit 0
fi

lower() { tr '[:upper:]' '[:lower:]'; }
bump="${BUMP:-}"
bump="$(printf '%s' "$bump" | lower)"
why="manual choice"
if [[ -z "$bump" || "$bump" == "auto" ]]; then
  bump=""
  labels="$(printf '%s' "${PR_LABELS:-}" | lower)"
  body="$(printf '%s' "${PR_BODY:-}" | lower)"
  msg="$(printf '%s' "${COMMIT_MSG:-}" | lower)"
  if   [[ "$labels" == *release:major* ]]; then bump="major"; why="pull request label release:major"
  elif [[ "$labels" == *release:minor* ]]; then bump="minor"; why="pull request label release:minor"
  elif printf '%s\n' "$body" | grep -Eq '^\s*[-*]\s*\[x\].*bump:major'; then bump="major"; why="ticked in the pull request"
  elif printf '%s\n' "$body" | grep -Eq '^\s*[-*]\s*\[x\].*bump:minor'; then bump="minor"; why="ticked in the pull request"
  elif [[ "$msg" == *"[major]"* ]]; then bump="major"; why="[major] in the commit message"
  elif [[ "$msg" == *"[minor]"* ]]; then bump="minor"; why="[minor] in the commit message"
  else bump="patch"; why="default"
  fi
fi

IFS=. read -r x y z <<< "$latest"
case "$bump" in
  major) next="$((x + 1)).0.0" ;;
  minor) next="$x.$((y + 1)).0" ;;
  patch) next="$x.$y.$((z + 1))" ;;
  *) echo "Unknown bump '$bump' (use patch, minor or major)" >&2; exit 1 ;;
esac
say "Latest is $latest; bumping $bump ($why)"
echo "$next"
