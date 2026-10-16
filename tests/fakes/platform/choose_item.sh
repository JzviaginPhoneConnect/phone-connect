#!/bin/zsh -f
# Fake: picks the item in $FAKE/choice, else the default.
# With $FAKE/cancel_on_choose: presses the status window's Cancel instead (creates the
# .cancel file) and stays open a moment, like a dialog the user hasn't answered yet.
print -rl -- "$@" > $FAKE/choose_args
if [[ -e $FAKE/cancel_on_choose ]]; then
  : > "$(<$FAKE/status_file).cancel"
  zmodload zsh/zselect; zselect -t 200
fi
if [[ -s $FAKE/choice ]]; then print -r -- "$(<$FAKE/choice)"; else print -r -- "$2"; fi
