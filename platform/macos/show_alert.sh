#!/bin/zsh
# show_alert.sh "Title" "Message" — a warning the user has to click away
osascript - "$APP_VERSION" "$@" >/dev/null 2>&1 <<'APPLESCRIPT'
on run argv
  activate
  display alert ("PhoneConnect " & item 1 of argv & ": " & item 2 of argv) message (item 3 of argv) as warning buttons {"OK"} default button "OK"
end run
APPLESCRIPT
exit 0
