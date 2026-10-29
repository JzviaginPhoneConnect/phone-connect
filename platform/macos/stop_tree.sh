#!/bin/zsh
# stop_tree.sh PID — stops that process and everything under it. First a TERM, so it
# can clean up; whatever is still there after 5 s (e.g. a command that hangs) is killed.
zmodload zsh/zselect

# tree <pid>: that process and everything under it
tree() {
  ps -axo pid=,ppid= | awk -v root="$1" '
    { parent[$1] = $2 }
    END {
      want[root] = 1
      for (level = 0; level < 10; level++)
        for (p in parent) if (parent[p] in want) want[p] = 1
      for (p in want) print p
    }'
}

pids=($(tree "$1"))
kill "${pids[@]}" 2>/dev/null
for i in {1..10}; do kill -0 "$1" 2>/dev/null || break; zselect -t 50; done
kill -0 "$1" 2>/dev/null && pids+=($(tree "$1"))
kill -9 "${pids[@]}" 2>/dev/null
exit 0
