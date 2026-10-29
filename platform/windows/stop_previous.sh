#!/bin/zsh
# stop_previous.sh PID — stops an earlier PhoneConnect run that is still going (the app
# script with that MSYS process id) and everything it started (stop_tree.sh: TERM, so
# it can clean up as usual, then kill what's left after 5 s). Exit 1 if there's none.
[[ -r /proc/$1/cmdline && "$(< /proc/$1/cmdline)" == *PhoneConnect* ]] || exit 1
exec zsh -f "${0:A:h}/stop_tree.sh" "$1"
