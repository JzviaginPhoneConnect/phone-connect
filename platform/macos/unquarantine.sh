#!/bin/zsh
# unquarantine.sh — a downloaded app is marked "quarantined" by macOS. Once the user
# has allowed PhoneConnect to open, clear that mark from its own files, so the
# bundled scrcpy and adb don't each get blocked with their own warning.
xattr -dr com.apple.quarantine "${0:A:h:h:h:h}" 2>/dev/null
exit 0
