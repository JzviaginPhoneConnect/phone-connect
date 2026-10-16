#!/bin/zsh
# bring_to_front.sh PID — brings scrcpy's window to the front (PID = the background
# job running scrcpy). Started from a background app, the window opens behind the
# others. Asks macOS directly (no permission needed), checks it worked, and tries
# again for up to 5 s, since a request made while the window is still starting is
# ignored. Don't use System Events `set frontmost`: it needs a permission prompt.

scrcpy_pid() {    # scrcpy_pid <pid>: the scrcpy process started under it (a few levels down:
  local level p procs=($1) kids   # the job is a zsh subshell, under it `script`, then scrcpy)
  for level in 1 2 3 4; do
    kids=()
    for p in $procs; do kids+=($(pgrep -P $p)); done
    for p in $kids; do
      [[ "$(ps -o comm= -p $p)" == */"PhoneConnect Mirror.app/Contents/MacOS/scrcpy" ]] && { print $p; return 0; }
    done
    procs=($kids)
  done
  return 1
}

spid=$(scrcpy_pid "$1")
if [[ -z "$spid" ]]; then
  echo "Couldn't find the scrcpy process under pid $1"
  exit 1
fi
for i in {1..20}; do
  osascript -l JavaScript -e "ObjC.import('AppKit');
    var app = \$.NSRunningApplication.runningApplicationWithProcessIdentifier($spid);
    app.isNil() ? false : app.activateWithOptions(\$.NSApplicationActivateAllWindows | \$.NSApplicationActivateIgnoringOtherApps)" >/dev/null 2>&1
  sleep 0.25
  front=$(lsappinfo info -only pid "$(lsappinfo front)" 2>/dev/null | grep -o 'pid = [0-9]*' | grep -o '[0-9]*$')
  if [[ "$front" == "$spid" ]]; then
    echo "scrcpy window (pid $spid) is in front (try $i)"
    exit 0
  fi
done
echo "Couldn't bring the scrcpy window (pid $spid) to the front; frontmost is pid ${front:-unknown}"
exit 1
