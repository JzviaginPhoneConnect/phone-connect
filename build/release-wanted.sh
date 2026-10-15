#!/usr/bin/env bash
# Says whether a change landing on main should be released ("yes") or only
# built ("no"). A change is released unless one of these asks to skip it:
#   * the "Don't release this change" box is ticked in the pull request form
#   * the pull request has the label "no-release"
#   * the commit message contains "[no release]" or "[skip release]"
# Inputs come from the environment: PR_BODY, PR_LABELS, COMMIT_MSG.
# Skipped changes still count: they're included in the next release.
#
# Usage: ./build/release-wanted.sh            -> yes | no
#        ./build/release-wanted.sh --explain  -> also prints why, on stderr
set -euo pipefail

lower() { tr '[:upper:]' '[:lower:]'; }
labels="$(printf '%s' "${PR_LABELS:-}" | lower)"
body="$(printf '%s' "${PR_BODY:-}" | lower)"
msg="$(printf '%s' "${COMMIT_MSG:-}" | lower)"

answer="yes"; why="default"
if printf '%s\n' "$body" | grep -Eq '^\s*[-*]\s*\[x\].*release:skip'; then
  answer="no"; why="'Don't release' is ticked in the pull request"
elif [[ ",$labels," == *",no-release,"* ]]; then
  answer="no"; why="pull request label no-release"
elif [[ "$msg" == *"[no release]"* || "$msg" == *"[skip release]"* ]]; then
  answer="no"; why="[no release] in the commit message"
fi

if [[ "${1:-}" == "--explain" ]]; then
  if [[ $answer == yes ]]; then echo "Will release ($why)" >&2; else echo "Won't release ($why)" >&2; fi
fi
echo "$answer"
