#!/bin/zsh -f
# PhoneConnect.app/Contents/Resources/PhoneConnect Run.app/Contents/MacOS/PhoneConnect —
# runs the app script (Contents/MacOS/PhoneConnect.sh) in this process. See Launcher.sh.
exec /bin/zsh "${0:A:h:h:h:h:h}/MacOS/PhoneConnect.sh" "$@"
