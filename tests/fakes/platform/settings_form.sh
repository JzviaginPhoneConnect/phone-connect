#!/bin/zsh -f
# Fake: records the window in $FAKE/events ("form: <title>", then per group
# "group: <label> <item|item…> default: <item>"). For each group it answers with the
# first line of $FAKE/answers if that's one of the group's items (and takes that line
# off), else the default. With $FAKE/cancel_settings: Cancel.
typeset -a items out
typeset next pick
print -r -- "form: $1" >> $FAKE/events
shift
while (( $# >= 3 )); do
  items=("${(@f)3}")
  print -r -- "group: $1 ${(j:|:)items} default: $2" >> $FAKE/events
  pick=$2
  if [[ -s $FAKE/answers ]]; then
    next=${"$(<$FAKE/answers)"%%$'\n'*}
    if (( ${items[(Ie)$next]} )); then
      tail -n +2 $FAKE/answers > $FAKE/answers.tmp; mv $FAKE/answers.tmp $FAKE/answers
      pick=$next
    fi
  fi
  out+=("$pick")
  shift 3
done
[[ -e $FAKE/cancel_settings ]] && exit 0
print -rl -- "${out[@]}"
