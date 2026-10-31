#!/bin/zsh
# settings_form.sh "Text" "OK button" "Cancel button" "Label 1" "Default 1" "Bold item 1 (or "")"
#                  "Items 1 (one per line)" ["Label 2" ...]
#   -> the chosen item of each group, one per line (empty on Cancel)
# One window with a pop-up menu per group.
# An NSAlert with the menus below its text, through AppleScriptObjC (no permission
# needed; JavaScript for Automation can't make bold menu items); everything is passed
# as arguments, so quotes can't break it. The app's icon instead of osascript's.
osascript - "$APP_VERSION" "${0:A:h:h:h}/Resources/PhoneConnect.icns" "$@" 2>/dev/null <<'APPLESCRIPT'
use framework "AppKit"
use scripting additions
on run argv
  set ca to current application
  activate
  set groupCount to ((count of argv) - 5) div 4
  set rowH to 34
  set labelW to 120
  set popW to 360
  set theView to ca's NSView's alloc()'s initWithFrame:(ca's NSMakeRect(0, 0, labelW + popW, groupCount * rowH))
  set boldText to ca's NSDictionary's dictionaryWithObject:(ca's NSFont's boldSystemFontOfSize:13) forKey:(ca's NSFontAttributeName)
  set pops to {}
  repeat with k from 1 to groupCount
    set base to 6 + (k - 1) * 4
    set y to (groupCount - k) * rowH
    set theLabel to ca's NSTextField's labelWithString:(item base of argv)
    theLabel's setFrame:(ca's NSMakeRect(0, y + 8, labelW - 10, 18))
    theLabel's setAlignment:(ca's NSTextAlignmentRight)
    theView's addSubview:theLabel
    set pop to ca's NSPopUpButton's alloc()'s initWithFrame:(ca's NSMakeRect(labelW, y + 2, popW, 26)) pullsDown:false
    set AppleScript's text item delimiters to linefeed
    repeat with anItem in text items of (item (base + 3) of argv)
      set itemText to anItem as text
      (pop's addItemWithTitle:itemText)
      if itemText is (item (base + 2) of argv) then
        ((pop's lastItem())'s setAttributedTitle:(ca's NSAttributedString's alloc()'s initWithString:itemText attributes:boldText))
      end if
    end repeat
    (pop's selectItemWithTitle:(item (base + 1) of argv))
    theView's addSubview:pop
    set end of pops to pop
  end repeat

  set theAlert to ca's NSAlert's alloc()'s init()
  theAlert's setMessageText:("PhoneConnect " & item 1 of argv)
  theAlert's setInformativeText:(item 3 of argv)
  set theIcon to ca's NSImage's alloc()'s initWithContentsOfFile:(item 2 of argv)
  if theIcon is not missing value then theAlert's setIcon:theIcon
  theAlert's addButtonWithTitle:(item 4 of argv)
  theAlert's addButtonWithTitle:(item 5 of argv)
  theAlert's setAccessoryView:theView
  (theAlert's |window|())'s setLevel:(ca's NSFloatingWindowLevel)
  ca's NSApplication's sharedApplication()'s activateIgnoringOtherApps:true
  if (theAlert's runModal()) is not (ca's NSAlertFirstButtonReturn) then return ""
  set answers to {}
  repeat with pop in pops
    set end of answers to (pop's titleOfSelectedItem()) as text
  end repeat
  set AppleScript's text item delimiters to linefeed
  return answers as text
end run
APPLESCRIPT
