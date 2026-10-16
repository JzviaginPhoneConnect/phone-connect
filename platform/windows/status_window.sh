#!/bin/zsh
# status_window.sh STATUS_FILE PID — opens PhoneConnect's status window (PhoneConnect.exe
# --status), which shows the lines PhoneConnect.sh writes to STATUS_FILE and closes when
# PID is gone. Returns at once. PID is an MSYS process id; the window needs the Windows one.
exe="${0:A:h:h}/PhoneConnect.exe"
[[ -f "$exe" ]] || { echo "$exe is missing"; exit 1; }
winpid=$(</proc/$2/winpid)
"$exe" --status "$(cygpath -w "$1")" "$winpid" < /dev/null > /dev/null 2>&1 &!
exit 0
