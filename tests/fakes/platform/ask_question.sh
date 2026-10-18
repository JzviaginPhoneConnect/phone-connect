#!/bin/zsh -f
# Fake: picks the first button, or the one written in $FAKE/answer if it's offered
print -r -- "ask: $1" >> $FAKE/events
print -r -- "buttons: ${(j:|:)@[2,-1]}" >> $FAKE/events
local b
if [[ -f $FAKE/answer ]]; then
  for b in "${@[2,-1]}"; do [[ "$b" == "$(<$FAKE/answer)" ]] && { print -r -- "$b"; exit 0; }; done
fi
print -r -- "$2"
