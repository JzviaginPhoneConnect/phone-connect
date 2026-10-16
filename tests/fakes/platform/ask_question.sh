#!/bin/zsh -f
# Fake: always picks the first button
print -r -- "ask: $1" >> $FAKE/events
print -r -- "$2"
