#!/bin/zsh
# stop_scrcpy.sh PID — stops the background job running scrcpy, and everything under it
pkill -P "$1" 2>/dev/null; kill "$1" 2>/dev/null; sleep 1
pkill -9 -P "$1" 2>/dev/null; kill -9 "$1" 2>/dev/null
exit 0
