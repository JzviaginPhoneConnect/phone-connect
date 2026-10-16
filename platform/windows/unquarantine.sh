#!/bin/zsh
# unquarantine.sh — files from a downloaded zip are marked "from the internet";
# clear that from the app's own files so Windows doesn't block the bundled tools.
# Done once per version (a marker file remembers it), in the background: it takes a
# few seconds, and programs the app starts itself aren't held up by the mark.
source "${0:A:h}/_windows.sh"
app=${0:A:h:h}
marker="$app/.unblocked-$APP_VERSION"
[[ -e "$marker" ]] && exit 0
: > "$marker" 2>/dev/null
PC_DIR="$(cygpath -w "$app")" run_ps '
Get-ChildItem -Path $env:PC_DIR -Recurse -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue' \
  < /dev/null > /dev/null 2>&1 &!
exit 0
