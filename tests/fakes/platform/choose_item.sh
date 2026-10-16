#!/bin/zsh -f
# Fake: picks the item in $FAKE/choice, else the default
print -rl -- "$@" > $FAKE/choose_args
if [[ -s $FAKE/choice ]]; then print -r -- "$(<$FAKE/choice)"; else print -r -- "$2"; fi
