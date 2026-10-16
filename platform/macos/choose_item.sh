#!/bin/zsh
# choose_item.sh "Question" "Default item" "Item 1" "Item 2"... -> prints the chosen item (empty on Cancel)
osascript - "$APP_VERSION" "$@" 2>/dev/null <<'APPLESCRIPT'
on run argv
  activate
  set theItems to items 4 thru -1 of argv
  set answer to choose from list theItems with title ("PhoneConnect " & item 1 of argv) with prompt (item 2 of argv) default items {item 3 of argv} OK button name "Connect"
  if answer is false then return ""
  return item 1 of answer
end run
APPLESCRIPT
