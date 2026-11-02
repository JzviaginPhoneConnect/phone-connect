#!/bin/zsh -f
# Fake: answers with the first line of $FAKE/answers if it's one of the buttons (and
# takes that line off), else picks the first button; $FAKE/cancel_ask: Cancel
print -r -- "ask: $1" >> $FAKE/events
print -r -- "buttons: ${(j:|:)@[2,-1]}" >> $FAKE/events
[[ -e $FAKE/cancel_ask ]] && exit 0
if [[ -s $FAKE/answers ]]; then
  local next=${"$(<$FAKE/answers)"%%$'\n'*}
  if (( ${@[2,-1][(Ie)$next]} )); then
    tail -n +2 $FAKE/answers > $FAKE/answers.tmp; mv $FAKE/answers.tmp $FAKE/answers
    print -r -- "$next"; exit 0
  fi
fi
print -r -- "$2"
