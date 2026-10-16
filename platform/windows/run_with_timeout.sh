#!/bin/zsh
# run_with_timeout.sh SECONDS command... — runs the command, stops it after SECONDS
exec timeout "$1" "${@:2}"
