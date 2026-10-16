#!/bin/zsh
# port_open.sh IP PORT — succeeds if something answers there (1-2 s, never hangs)
exec perl -e 'alarm shift; exec @ARGV' 3 nc -z -G 2 "$1" "$2" >/dev/null 2>&1
