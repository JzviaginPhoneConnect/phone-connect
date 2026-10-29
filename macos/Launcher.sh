#!/bin/zsh -f
# PhoneConnect.app/Contents/MacOS/PhoneConnect — what macOS starts when the app is opened.
# macOS runs an app only once: opening it again while it runs just activates the
# running copy. So the app script runs as a new instance of a small app inside the
# bundle (`open -n`, Resources/PhoneConnect Run.app → Run.sh → PhoneConnect.sh) and this
# exits at once. Every open starts a new run, which stops the one before if it's still
# going (stopPreviousRun). Started straight from here instead, the script would be
# stopped by macOS as soon as this exits.
here=${0:A:h}
# open -n checks the inner app on its own, so clear the download mark first
zsh -f "$here/platform/unquarantine.sh"
exec open -n "${here:h}/Resources/PhoneConnect Run.app" --args "$@"
