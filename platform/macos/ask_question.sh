#!/bin/zsh
# ask_question.sh "Question" "Button A" "Button B" -> prints the chosen button (empty on Cancel)
# Passed as arguments, so quotes in the text can't break the AppleScript;
# `activate` brings the dialog to the front (the app itself has no window).
osascript - "$APP_VERSION" "$@" 2>/dev/null <<'APPLESCRIPT'
on run argv
  activate
  try
    return button returned of (display dialog (item 2 of argv) with title ("PhoneConnect " & item 1 of argv) buttons {"Cancel", item 3 of argv, item 4 of argv} default button (item 4 of argv) cancel button "Cancel")
  on error
    return ""
  end try
end run
APPLESCRIPT
