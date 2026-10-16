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
sleep 60 &
fake_main=$!
check "starts" plat status_window $sf $fake_main
zselect -t 300
check "window process running" status_running
print __done__ >> $sf
zselect -t 200
check "closes on __done__" eval '! status_running'
print 'Waiting for the picture…' > $sf
plat status_window $sf $fake_main
zselect -t 300
kill $fake_main
zselect -t 200
check "closes when PhoneConnect is gone" eval '! status_running'
rm -f $sf

print
print "$PASS passed, $FAIL failed"
(( FAIL == 0 ))
