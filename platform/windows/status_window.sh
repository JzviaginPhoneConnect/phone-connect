#!/bin/zsh
# status_window.sh STATUS_FILE — opens PhoneConnect's status window (PhoneConnect.exe
# --status), which shows the lines PhoneConnect.sh writes to STATUS_FILE (see "Status
# window" there). Returns at once.
exe="${0:A:h:h}/PhoneConnect.exe"
[[ -f "$exe" ]] || { echo "$exe is missing"; exit 1; }
"$exe" --status "$(cygpath -w "$1")" < /dev/null > /dev/null 2>&1 &!
exit 0
