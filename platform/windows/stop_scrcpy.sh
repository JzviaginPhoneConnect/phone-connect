#!/bin/zsh
# stop_scrcpy.sh PID — stops the background job running scrcpy, and everything under it
source "${0:A:h}/_windows.sh"
winpid=$(scrcpy_winpid "$1") && "$SYSDIR/taskkill.exe" /T /F /PID "$winpid" >/dev/null 2>&1
kill "$1" 2>/dev/null; sleep 1
kill -9 "$1" 2>/dev/null
exit 0
