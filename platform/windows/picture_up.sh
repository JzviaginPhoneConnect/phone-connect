#!/bin/zsh
# picture_up.sh PID OUTPUT_FILE — succeeds once scrcpy shows the picture: scrcpy
# only shows its window when the first frame arrives, so check for the window.
source "${0:A:h}/_windows.sh"
winpid=$(scrcpy_winpid "$1") || exit 1
PC_PID=$winpid run_ps '
$p = Get-Process -Id ([int]$env:PC_PID) -ErrorAction SilentlyContinue
if ($p -and $p.MainWindowHandle -ne [IntPtr]::Zero) { exit 0 }
exit 1' >/dev/null 2>&1
