#!/bin/zsh
# show_alert.sh "Title" "Message" — a warning the user has to click away
source "${0:A:h}/_windows.sh"
PC_TITLE="$1" PC_TEXT="$2" run_ps '
Add-Type -AssemblyName System.Windows.Forms
[void][System.Windows.Forms.MessageBox]::Show($env:PC_TEXT, "PhoneConnect $env:APP_VERSION - $env:PC_TITLE", "OK", "Warning")' >/dev/null
exit 0
