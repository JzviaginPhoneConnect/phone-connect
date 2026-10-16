#!/bin/zsh
# port_open.sh IP PORT — succeeds if something answers there (at most 2 s, never hangs).
# Uses zsh's own TCP support rather than PowerShell, which takes about a second to start.
exec timeout 2 zsh -fc 'zmodload zsh/net/tcp && ztcp "$1" "$2" && ztcp -c' port_open "$1" "$2" >/dev/null 2>&1
