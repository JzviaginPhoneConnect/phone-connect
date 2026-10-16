#!/bin/zsh
# run_scrcpy.sh ARGS... — runs scrcpy in the foreground; PhoneConnect.sh starts this in
# the background and reads its output. (Its output comes through a pipe here, so it
# may arrive in bursts; picture_up.sh doesn't rely on it.)
exec "$SCRCPY" "$@" < /dev/null
