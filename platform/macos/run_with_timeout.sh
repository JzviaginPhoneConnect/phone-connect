#!/bin/zsh
# run_with_timeout.sh SECONDS command... — runs the command, stops it after SECONDS
# (macOS has no `timeout` command; perl's alarm does the same)
exec perl -e 'alarm shift; exec @ARGV' "$@"
