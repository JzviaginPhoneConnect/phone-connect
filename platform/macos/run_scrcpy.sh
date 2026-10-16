#!/bin/zsh
# run_scrcpy.sh ARGS... — runs scrcpy in the foreground; PhoneConnect.sh starts this in
# the background and reads its output.
# `script` runs scrcpy as if in a terminal, so its messages arrive immediately.
# Without it they sit in a buffer, the "Texture" (first frame) line shows up too
# late, and a working session gets killed as "stalled".
exec script -q /dev/null "$SCRCPY" "$@" < /dev/null
