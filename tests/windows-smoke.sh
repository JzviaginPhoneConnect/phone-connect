#!/bin/zsh -f
# Smoke test of the Windows platform scripts, run on Windows with the app's own zsh:
#   zsh.exe -f tests/windows-smoke.sh <built app folder> <test window scrcpy.exe>
# Uses the real scripts against real Windows: PowerShell, TCP, processes, windows.
# Dialogs can't be clicked here, so their PowerShell code is only parsed.

APPDIR=${1:?usage: windows-smoke.sh <app folder> <test window .exe>}
APPDIR=${APPDIR:A}
P=$APPDIR/platform
export APP_VERSION=smoke-test
source $P/env.sh
source $P/_windows.sh     # SYSDIR, POWERSHELL
export SCRCPY=${2:A}
PASS=0 FAIL=0
check() {
  local what=$1; shift
  if "$@"; then (( PASS++ )); print -r -- "ok   - $what"; else (( FAIL++ )); print -r -- "FAIL - $what"; fi
}
plat() { local n=$1; shift; zsh -f "$P/$n.sh" "$@"; }

print "== env.sh"
check "ADB points at adb.exe (Windows path)" eval '[[ $ADB == ?:/*/tools/adb.exe ]]'
check "scrcpy-server path is a Windows path" eval '[[ $SCRCPY_SERVER_PATH == ?:/*/tools/scrcpy-server ]]'
check "data folder exists" eval '[[ -d ${PHONES_FILE:h} ]]'
check "temp folder usable" eval ': > $TMPDIR/pc-smoke && rm $TMPDIR/pc-smoke'
check "xmllint available" eval 'xmllint --version >/dev/null 2>&1'
check "OS info filled in" eval '[[ $OS_INFO == Windows* ]]'
print -r -- "       $OS_INFO"

print "== dialogs (PowerShell code parses)"
check "ask_question" eval 'PC_PS_CHECK=1 plat ask_question "Question?" "No" "Yes"'
check "choose_item" eval 'PC_PS_CHECK=1 plat choose_item "Which?" "b" "a" "b"'
check "settings_form" eval 'PC_PS_CHECK=1 plat settings_form "Settings" "Show:" "b" "$(print "a\nb ★ best")" "Sound:" "x" "x"'
check "show_alert" eval 'PC_PS_CHECK=1 plat show_alert "title" "message"'
check "unquarantine" eval 'PC_PS_CHECK=1 plat unquarantine'

print "== run_with_timeout"
check "passes output and exit code on" eval '[[ "$(plat run_with_timeout 5 echo hi)" == hi ]]'
check "stops a command that takes too long" eval 'plat run_with_timeout 1 sleep 10; [[ $? == 124 ]]'

print "== port_open"
"$POWERSHELL" -NoProfile -Command '
  $l = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 15555); $l.Start()
  Start-Sleep -Seconds 30; $l.Stop()' &
listener=$!
zmodload zsh/zselect; zselect -t 400
check "something listening -> open" plat port_open 127.0.0.1 15555
check "nothing listening -> closed" eval '! plat port_open 127.0.0.1 15556'
kill $listener 2>/dev/null

print "== run_scrcpy / picture_up / stop_scrcpy (with a test window)"
out=$TMPDIR/pc-smoke.out
zsh -f "$P/run_scrcpy.sh" > $out 2>&1 &
job=$!
up=1
for i in {1..20}; do plat picture_up $job $out && { up=0; break; }; zselect -t 50; done
check "window found under the background job" eval '(( up == 0 ))'
check "bring_to_front" plat bring_to_front $job
plat stop_scrcpy $job
zselect -t 100
check "stopped" eval '! kill -0 $job 2>/dev/null'
check "window process gone" eval '! "$SYSDIR/tasklist.exe" /FI "IMAGENAME eq scrcpy.exe" 2>/dev/null | grep -qi scrcpy.exe'
rm -f $out

print "== status_window (PhoneConnect.exe --status)"
status_running() { "$SYSDIR/tasklist.exe" /FI "IMAGENAME eq PhoneConnect.exe" 2>/dev/null | grep -qi PhoneConnect.exe; }
sf=$TMPDIR/pc-smoke.status
print 'Looking for phones on USB…' > $sf
{ for i in {1..40}; do : > $sf.alive; zselect -t 50; done } &!   # "PhoneConnect running" for 20 s
check "starts" plat status_window $sf
zselect -t 300
check "window process running" status_running
print __done__ >> $sf
zselect -t 200
check "closes on __done__" eval '! status_running'
print 'Waiting for the picture…' > $sf
: > $sf.alive
plat status_window $sf
zselect -t 300
check "running again" status_running
zselect -t 2200                                   # the alive file stops being refreshed
check "closes once PhoneConnect is gone (alive file stale)" eval '! status_running'
rm -f $sf $sf.alive $sf.cancel

print "== stop_previous (an earlier run, hanging in a Windows program)"
fakeapp=$TMPDIR/PhoneConnect-smoke.sh
print -r -- "\"$SYSDIR/ping.exe\" -n 60 127.0.0.1 >/dev/null" > $fakeapp
zsh -f $fakeapp &
prev=$!
sleep 30 &
other=$!
zselect -t 200
ping_running() { "$SYSDIR/tasklist.exe" /FI "IMAGENAME eq ping.exe" 2>/dev/null | grep -qi ping.exe; }
check "the Windows program is running" ping_running
check "leaves a process that isn't PhoneConnect alone" eval '! plat stop_previous $other && kill -0 $other'
check "stops the earlier run" plat stop_previous $prev
check "  ...gone" eval '! kill -0 $prev 2>/dev/null'
check "  ...with the Windows program it started" eval '! ping_running'
check "nothing to stop once it's gone" eval '! plat stop_previous $prev'
kill $other 2>/dev/null
rm -f $fakeapp

print
print "$PASS passed, $FAIL failed"
(( FAIL == 0 ))
