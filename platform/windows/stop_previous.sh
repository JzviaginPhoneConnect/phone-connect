#!/bin/zsh
# stop_previous.sh PID — stops an earlier PhoneConnect run that is still going (the app
# script with that MSYS process id) and everything it started. Exit 1 if there's none.
# First a TERM, so it can clean up as usual (stop scrcpy, undo what it did to the
# phone); whatever is still there after 5 s, e.g. a command that hangs, is killed.
source "${0:A:h}/_windows.sh"
[[ -r /proc/$1/cmdline && "$(< /proc/$1/cmdline)" == *PhoneConnect* ]] || exit 1
zmodload zsh/zselect

# tree <pid>: that process and everything under it, as "pid winpid" lines. From
# `ps -l`: an optional status letter, then PID PPID PGID WINPID TTY UID STIME COMMAND.
tree() {
  ps -l | awk -v root="$1" '
    NR == 1 { next }
    {
      n = split(substr($0, 2), f, " ")      # drop the status letter column
      parent[f[1]] = f[2]; winpid[f[1]] = f[4]
    }
    END {
      want[root] = 1
      for (level = 0; level < 10; level++)
        for (p in parent) if (parent[p] in want) want[p] = 1
      for (p in want) if (p in winpid) print p, winpid[p]
    }'
}

typeset -a pids winpids
add() { local p w; while read -r p w; do pids+=($p) winpids+=(/PID $w); done }
add < <(tree "$1")
kill "${pids[@]}" 2>/dev/null
for i in {1..10}; do kill -0 "$1" 2>/dev/null || break; zselect -t 50; done
kill -0 "$1" 2>/dev/null && add < <(tree "$1")
# /T: also Windows programs those started (adb.exe starts its server that way)
"$SYSDIR/taskkill.exe" /T /F "${winpids[@]}" >/dev/null 2>&1
kill -9 "${pids[@]}" 2>/dev/null
exit 0
