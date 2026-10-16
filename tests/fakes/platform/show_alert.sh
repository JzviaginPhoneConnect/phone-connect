#!/bin/zsh -f
# Fake: records the alert
print -rl -- "$@" > $FAKE/alert
