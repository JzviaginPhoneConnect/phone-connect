#!/bin/zsh
# status_window.sh STATUS_FILE PID — opens PhoneConnect's status window, which shows the
# lines PhoneConnect.sh writes to STATUS_FILE and closes when PID is gone. Returns at once.
# `open` launches it as a real app, so it comes to the front with the PhoneConnect icon.
app="${0:A:h:h:h}/Resources/PhoneConnect Status.app"
[[ -d "$app" ]] || { echo "$app is missing"; exit 1; }
exec open -n "$app" --args "$1" "$2"
