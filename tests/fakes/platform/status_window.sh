#!/bin/zsh -f
# Fake: no window; the tests read the status file itself
print -r -- "$1" > $FAKE/status_file
