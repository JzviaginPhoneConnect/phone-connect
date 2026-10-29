#!/bin/zsh -f
# Logic tests for PhoneConnect.sh, the same on macOS and Windows.
#
#   zsh -f tests/run-tests.sh platform/macos        on a Mac
#   zsh.exe -f tests/run-tests.sh <built platform\>  on Windows, with the app's own zsh
#
# Runs the real PhoneConnect.sh with the real platform scripts for paths, timeouts and
# starting/stopping scrcpy, and fakes (tests/fakes) for adb, scrcpy, the dialogs,
# the port probe and the "picture is up" check. Prints ok/FAIL per check; exit 1 on
# any failure. Nothing outside a temporary folder is touched.

ROOT=${0:A:h:h}
PLAT=${1:?usage: run-tests.sh <platform dir>}
PLAT=${PLAT:A}
# zsh writes here-documents to $TMPPREFIX (default /tmp/zsh); in the app's Windows
# shell /tmp doesn't exist, so keep zsh's temporary files in TMPDIR too
export TMPDIR=${TMPDIR:-/tmp}
export TMPPREFIX="$TMPDIR/zsh"
WORK=$(mktemp -d "$TMPDIR/phoneconnect-tests.XXXXXX")
PASS=0 FAIL=0

# ---- a test copy of the app: real script + platform, fakes on top ----
APP=$WORK/app
mkdir -p $APP/platform $WORK/fakes
cp $ROOT/app/PhoneConnect.sh $APP/
cp $PLAT/*.sh $APP/platform/
mv $APP/platform/env.sh $APP/platform/env.real.sh
cp $ROOT/tests/fakes/platform/*.sh $APP/platform/
cp $ROOT/tests/fakes/bin/* $WORK/fakes/
chmod +x $WORK/fakes/* $APP/platform/*.sh
cat > $APP/platform/env.sh <<EOF
# test env: the real one, then fake tools and files in the test folder
source "\${\${(%):-%x}:A:h}/env.real.sh"
export PATH="$WORK/fakes:\$PATH"
export ADB="$WORK/fakes/adb" SCRCPY="$WORK/fakes/scrcpy"
PHONES_FILE="\$FAKE/phones.xml"
TASKS_FILE="\$FAKE/tasks.xml"
OLD_IPS_FILE="\$FAKE/old_ips.txt"
LOG_FILE="$WORK/test.log"
export TMPDIR="$WORK/tmp"   # own status and pid files: never touch a real PhoneConnect run
EOF
mkdir -p $WORK/tmp

LOG=$WORK/test.log
zmodload zsh/zselect

# run_app <case dir>: one launch of the app in that fake world
run_app() {
  export FAKE=$1 HOME=$1/home
  mkdir -p $HOME
  rm -f $FAKE/choose_args $FAKE/alert $FAKE/scrcpy_args $FAKE/events
  : > $FAKE/connected
  if [[ -f $LOG ]]; then RUN_START=$(wc -l < $LOG); else RUN_START=0; fi
  zsh -f $APP/PhoneConnect.sh < /dev/null > $WORK/last-run.txt 2>&1
  zselect -t 50                          # let the log writers finish
}
run_log() { tail -n +$(( RUN_START + 1 )) $LOG; }   # this run's part of the log

check() {         # check <description> <command...>
  local what=$1; shift
  if "$@"; then
    (( PASS++ )); print -r -- "ok   - $what"
  else
    (( FAIL++ )); print -r -- "FAIL - $what"
  fi
}
logged_line()  { run_log | grep -qF -- "$1"; }
xml_is()       { [[ "$(<$FAKE/phones.xml)" == "$1" ]] || { print -r -- "       got:"; sed 's/^/       /' $FAKE/phones.xml; return 1; } }
file_has()     { [[ -f $FAKE/$1 ]] && grep -qF -- "$2" $FAKE/$1; }
no_file()      { [[ ! -e $1 ]]; }
xml() { print -r -- '<?xml version="1.0" encoding="UTF-8"?>'; print -r -- '<phones>'; print -rl -- "$@"; print -r -- '</phones>'; }

# ==== 1. two phones of the same model, IP changes, IP taken by another phone ====
C=$WORK/multi; mkdir -p $C
print "== migration from the old single-phone file (Windows line ends)"
printf 'eth 192.168.1.50\r\nwifi 10.0.0.7\r\n' > $C/old_ips.txt
print '10.0.0.7|AAA1111|Galaxy S23||10.0.0.7' > $C/net
run_app $C
check "old IPs moved to the phone found there" xml_is "$(xml '  <phone id="AAA1111" name="Galaxy S23" eth="192.168.1.50" wifi="10.0.0.7"/>')"
check "old file removed" no_file $C/old_ips.txt
check "connected over Wi-Fi" logged_line "Connection: Galaxy S23 — Wi-Fi (10.0.0.7:5555)"
check "no chooser for one phone" no_file $C/choose_args

print "== two USB phones of the same model"
print 'usbA|AAA1111|Galaxy S23||10.0.0.7|5555\nusbB|BBB2222|Galaxy S23||10.0.0.8|' > $C/usb
print 'Galaxy S23 (…2222) — USB' > $C/choice
run_app $C
check "chooser lists each phone once, told apart" file_has choose_args 'Galaxy S23 (…1111) — USB'
check "chooser has the second phone" file_has choose_args 'Galaxy S23 (…2222) — USB'
check "chosen USB phone used over USB" logged_line "Connection: Galaxy S23 — USB (usbB)"
check "status: looking for USB phones" logged_line "Status: Looking for phones on USB…"
check "status: found each USB phone" logged_line "Status: Found Galaxy S23 on USB"
check "status: setting up for cable-free use" logged_line "Status: Setting up Galaxy S23 for cable-free use…"
check "status: asked to choose" logged_line "Status: Choose a phone…"
check "status: waiting for the picture" logged_line "Status: Waiting for the picture…"
check "status window started with the status file" file_has status_file "PhoneConnect."
check "network mode turned on only where it was off" file_has events "tcpip usbB"
check "  ...not on the phone that had it" eval '! file_has events "tcpip usbA"'
check "both phones saved, used one first" xml_is "$(xml '  <phone id="BBB2222" name="Galaxy S23" eth="" wifi="10.0.0.8"/>' '  <phone id="AAA1111" name="Galaxy S23" eth="192.168.1.50" wifi="10.0.0.7"/>')"

print "== docked, with a new Wi-Fi IP"
: > $C/usb
print '192.168.1.50|AAA1111|Galaxy S23|192.168.1.50|10.0.0.20' > $C/net
print 'Galaxy S23 (…1111)' > $C/choice
run_app $C
check "connected over Ethernet" logged_line "Connection: Galaxy S23 — Ethernet (192.168.1.50:5555)"
check "Wi-Fi IP updated, no new phone" xml_is "$(xml '  <phone id="AAA1111" name="Galaxy S23" eth="192.168.1.50" wifi="10.0.0.20"/>' '  <phone id="BBB2222" name="Galaxy S23" eth="" wifi="10.0.0.8"/>')"

print "== saved IP now belongs to a new phone"
print '10.0.0.8|CCC3333|Pixel 8||10.0.0.8' > $C/net
print 'Galaxy S23 (…2222)' > $C/choice
run_app $C
check "noticed the other phone" logged_line "10.0.0.8 is now another phone (Pixel 8)"
check "status: tried Wi-Fi" logged_line "Status: Connecting to Galaxy S23 over Wi-Fi (10.0.0.8)…"
check "status: the address belongs to another phone" logged_line "Status: 10.0.0.8 is now Pixel 8 — trying the next address"
check "status: couldn't connect" logged_line "Status: Couldn't connect to Galaxy S23"
check "told the user it couldn't connect" file_has alert "Couldn't connect to Galaxy S23."
check "IP moved to the new phone" xml_is "$(xml '  <phone id="AAA1111" name="Galaxy S23" eth="192.168.1.50" wifi="10.0.0.20"/>' '  <phone id="BBB2222" name="Galaxy S23" eth="" wifi=""/>' '  <phone id="CCC3333" name="Pixel 8" eth="" wifi="10.0.0.8"/>')"

print "== saved IP now belongs to another known phone"
print '192.168.1.50|BBB2222|Galaxy S23|192.168.1.50|10.0.0.30\n10.0.0.20|AAA1111|Galaxy S23||10.0.0.20' > $C/net
print 'Galaxy S23 (…1111)' > $C/choice
run_app $C
check "dropped the wrong phone, used the next IP" logged_line "Connection: Galaxy S23 — Wi-Fi (10.0.0.20:5555)"
check "IP moved between known phones" xml_is "$(xml '  <phone id="AAA1111" name="Galaxy S23" eth="" wifi="10.0.0.20"/>' '  <phone id="BBB2222" name="Galaxy S23" eth="192.168.1.50" wifi="10.0.0.30"/>' '  <phone id="CCC3333" name="Pixel 8" eth="" wifi="10.0.0.8"/>')"
# The same priority as the app itself (CI runners may run everything at a raised nice level)
BASE_NICE=$(ps -o nice= -p $$ 2>/dev/null); BASE_NICE=${BASE_NICE// /}
check "scrcpy runs at the app's own priority (not lowered for background jobs)" eval '[[ ! -s $FAKE/scrcpy_nice || -z $BASE_NICE || "$(<$FAKE/scrcpy_nice)" == "$BASE_NICE" ]]'
check "scrcpy got the phone-screen options" file_has scrcpy_args "-s 10.0.0.20:5555 -K --video-codec=h265 --max-fps=60 --video-codec-options=bitrate-mode:int=1 -V debug --no-audio --max-size=1600 --video-bit-rate=6M --window-title=PhoneConnect — Galaxy S23 (Wi-Fi)"

# ==== 2. old IPs nobody answers at, identified later; switch to Ethernet ====
C=$WORK/later; mkdir -p $C
print "== migration with the phone unreachable"
print 'eth 192.168.1.50\nwifi 10.0.0.7' > $C/old_ips.txt
run_app $C
check "IPs kept for a phone not identified yet" xml_is "$(xml '  <phone id="" name="Phone" eth="192.168.1.50" wifi="10.0.0.7"/>')"
check "told the user it couldn't connect" file_has alert "Couldn't connect to Phone."
print "== the phone answers again"
print '10.0.0.7|DDD4444|Moto G||10.0.0.7' > $C/net
run_app $C
check "identified on its first connection" xml_is "$(xml '  <phone id="DDD4444" name="Moto G" eth="192.168.1.50" wifi="10.0.0.7"/>')"
print "== docked: came in over Wi-Fi, switches to the new Ethernet IP"
print '10.0.0.7|DDD4444|Moto G|192.168.1.60|10.0.0.7\n192.168.1.60|DDD4444|Moto G|192.168.1.60|10.0.0.7' > $C/net
run_app $C
check "switched to Ethernet" logged_line "Connection: Moto G — Ethernet (192.168.1.60:5555)"
check "status: switching to Ethernet" logged_line "Status: Switching to Ethernet (192.168.1.60)…"
check "status file removed at the end" eval '[[ ! -e "$(<$FAKE/status_file)" ]]'
check "Ethernet IP learned" xml_is "$(xml '  <phone id="DDD4444" name="Moto G" eth="192.168.1.60" wifi="10.0.0.7"/>')"

# ==== 3. nothing saved, nothing plugged in ====
C=$WORK/empty; mkdir -p $C
print "== no phone at all"
run_app $C
check "told the user to plug it in" file_has alert "no phone found"

# ==== 4. a name with characters XML has to escape ====
C=$WORK/names; mkdir -p $C
print "== phone name with & ' < >"
print "usbN|NNN5555|Jacob's S23 & <co>||10.0.0.9|5555" > $C/usb
run_app $C
check "name escaped in the file" xml_is "$(xml '  <phone id="NNN5555" name="Jacob&apos;s S23 &amp; &lt;co&gt;" eth="" wifi="10.0.0.9"/>')"
: > $C/usb; print "10.0.0.9|NNN5555|Jacob's S23 & <co>||10.0.0.9" > $C/net
run_app $C
check "name read back unchanged" logged_line "Connection: Jacob's S23 & <co> — Wi-Fi (10.0.0.9:5555)"

# ==== 5. the log ====
print "== log"
logged_re() { run_log | grep -qE -- "$1"; }
check "adb commands logged with exit code" logged_re '\[[0-9]+ cmd\] \$ adb devices  -> exit 0'
check "command output logged" logged_re '\[[0-9]+ cmd\]   \| List of devices attached'
check "platform calls logged" logged_re '\[[0-9]+ cmd\] \$ platform/port_open 10\.0\.0\.9 5555  -> exit 0'
check "scrcpy output logged" logged_re '\[[0-9]+ scrcpy\] INFO: Texture: 1080x2340'
check "timestamps with milliseconds" eval "run_log | head -1 | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3} \['"
{ print '2000-01-01 10:00:00.000 [1 app] a very old line'; print 'PhoneConnect 1.0.0 (old format)'; cat $LOG; } > $LOG.new && mv $LOG.new $LOG
run_app $C
check "lines older than a day dropped" eval "! grep -qF 'a very old line' $LOG && ! grep -qF 'old format' $LOG"
check "earlier runs kept" eval "grep -qF 'Galaxy S23 — USB (usbB)' $LOG"

# ==== 6. Cancel in the status window ====
C=$WORK/cancel; mkdir -p $C
print "== Cancel pressed while the phone list is open"
print '10.0.0.7|AAA1111|Galaxy S23||10.0.0.7\n10.0.0.8|BBB2222|Pixel 8||10.0.0.8' > $C/net
xml '  <phone id="AAA1111" name="Galaxy S23" eth="" wifi="10.0.0.7"/>' '  <phone id="BBB2222" name="Pixel 8" eth="" wifi="10.0.0.8"/>' > $C/phones.xml
: > $C/cancel_on_choose
run_app $C
check "the app stopped itself" logged_line "Cancel pressed in the status window — stopping"
check "  ...and didn't go on to connect" eval '! run_log | grep -qF "Connection:"'
check "status window files cleaned up" eval '[[ -z "$(print -l $(<$FAKE/status_file)*(N))" ]]'
rm -f $C/cancel_on_choose

# ==== 7. headless DeX / desktop mode (a display scrcpy creates) ====
C=$WORK/headless; mkdir -p $C
print 'usbH|HHH6666|Galaxy S25||10.0.0.11|5555' > $C/usb
asked_buttons() { file_has events "buttons: $1"; }
setting_is()    { [[ "$(grep -F "HHH6666 global enable_freeform_support=" $FAKE/settings 2>/dev/null)" == "${1:+HHH6666 global enable_freeform_support=$1}" ]]; }
no_tasks()      { [[ ! -e $FAKE/tasks.xml ]]; }
print "== Samsung, One UI 8, no external display: headless DeX, warning, Continue"
export FAKE_ONEUI=80000
print 'DeX headless (experimental)\nContinue' > $C/answers
run_app $C
check "offered as DeX headless" asked_buttons "Phone screen|DeX headless (experimental)"
check "warned, with Go back as an option" eval 'file_has events "ask: DeX headless is experimental." && asked_buttons "Continue|Go back"'
check "scrcpy got a new display, not a display id" eval 'file_has scrcpy_args "--new-display=1920x1080/160 --video-bit-rate=8M --window-title=PhoneConnect — Galaxy S25, DeX headless (USB)" && ! file_has scrcpy_args "--display-id"'
check "floating windows turned on before scrcpy started" eval 'run_log | grep -n -e "Floating windows turned on" -e "Starting (attempt 1)" | head -1 | grep -qF "Floating windows"'
check "...and off again afterwards (it wasn't set before)" eval 'file_has events "settings delete global enable_freeform_support (HHH6666)" && setting_is ""'
check "headless display switched to floating windows" file_has events "display 7 windowing mode 5"
check "phone UI restarted" file_has events "systemui restarted (HHH6666)"
check "no tasks left" no_tasks
check "cleanup is a step in main, after scrcpy ended" eval 'run_log | grep -e "scrcpy ended" -e "Step start: finishTasks" | head -2 | tail -1 | grep -qF finishTasks'
check "  ...run once (not again on exit)" eval '[[ $(run_log | grep -c "Step start: executeTasks") == 2 ]]'
check "no other phone setting changed" eval '! grep -E "settings (put|delete)" $FAKE/adb.log | grep -v enable_freeform_support | grep -q . && ! grep -q setprop $FAKE/adb.log'

print "== floating windows already on: left on"
print 'HHH6666 global enable_freeform_support=1' > $C/settings
print 'DeX headless (experimental)\nContinue' > $C/answers
run_app $C
check "setting not touched" eval '! file_has events "enable_freeform_support" && setting_is 1'
check "phone UI restarted" file_has events "systemui restarted (HHH6666)"
check "no tasks left" no_tasks
rm -f $C/settings

print "== Go back, then the phone screen"
print 'DeX headless (experimental)\nGo back\nPhone screen' > $C/answers
run_app $C
check "asked again after Go back" eval '[[ $(grep -c "ask: What do you want to mirror?" $FAKE/events) == 2 ]]'
check "phone screen mirrored" file_has scrcpy_args "--max-size=1600"
check "nothing done to the phone" eval '! file_has events "settings " && ! file_has events "systemui" && ! file_has events "windowing mode" && no_tasks'

print "== headless over USB, cable pulled during the session: cleanup over Wi-Fi"
print 'usbH|HHH6666|Galaxy S25||10.0.0.11|5555' > $C/usb
print '10.0.0.11|HHH6666|Galaxy S25||10.0.0.11' > $C/net
print ": > $C/usb" > $C/on_scrcpy
print 'DeX headless (experimental)\nContinue' > $C/answers
run_app $C
check "connected over USB" logged_line "Connection: Galaxy S25 — USB (usbH)"
check "cleanup reached the phone over Wi-Fi" eval 'grep -qF "adb connect 10.0.0.11:5555" $FAKE/adb.log && file_has events "systemui restarted (HHH6666)"'
check "setting put back, no tasks left" eval 'setting_is "" && no_tasks'
check "no alert" no_file $C/alert

print "== headless, phone unreachable when the session ends: alert, tasks kept"
print 'usbH|HHH6666|Galaxy S25||10.0.0.11|5555' > $C/usb
print ": > $C/usb; : > $C/net" > $C/on_scrcpy
print 'DeX headless (experimental)\nContinue' > $C/answers
run_app $C
check "told the user to reconnect and run again" file_has alert "open PhoneConnect again"
check "tasks kept" eval 'file_has tasks.xml "action=\"restart-systemui\"" && file_has tasks.xml "key=\"enable_freeform_support\" value=\"\""'
check "setting still on" setting_is 1
rm -f $C/on_scrcpy

print "== next run, two phones saved, the phone back on Wi-Fi: tasks done before the chooser"
print '10.0.0.11|HHH6666|Galaxy S25||10.0.0.11\n10.0.0.12|JJJ7777|Pixel 9||10.0.0.12' > $C/net
xml '  <phone id="HHH6666" name="Galaxy S25" eth="" wifi="10.0.0.11"/>' '  <phone id="JJJ7777" name="Pixel 9" eth="" wifi="10.0.0.12"/>' > $C/phones.xml
print 'Pixel 9' > $C/choice
run_app $C
check "cleanup ran before the phone chooser" eval 'run_log | grep -n -e "Step end: executeTasks" -e "Status: Choose a phone" | head -1 | grep -qF executeTasks'
check "UI restarted, setting put back, no tasks left" eval 'file_has events "systemui restarted (HHH6666)" && setting_is "" && no_tasks'
check "then connected to the chosen phone" logged_line "Connection: Pixel 9 — Wi-Fi (10.0.0.12:5555)"
rm -f $C/choice $C/phones.xml
: > $C/net

print "== Cancel in the status window during a headless session: cleanup on exit"
print 'usbH|HHH6666|Galaxy S25||10.0.0.11|5555' > $C/usb
print ": > \"\$(<$C/status_file).cancel\"; zmodload zsh/zselect; zselect -t 300" > $C/on_scrcpy
print 'DeX headless (experimental)\nContinue' > $C/answers
run_app $C
check "stopped by Cancel" logged_line "Cancel pressed in the status window — stopping"
check "UI restarted, setting put back, no tasks left" eval 'file_has events "systemui restarted (HHH6666)" && setting_is "" && no_tasks'
rm -f $C/on_scrcpy

print "== Samsung, One UI 7: not offered"
export FAKE_ONEUI=70000
run_app $C
check "no mirror question" eval '! file_has events "What do you want to mirror?"'
check "phone screen mirrored" file_has scrcpy_args "--max-size=1600"
print "== Samsung, One UI 8, real DeX display: only the old question"
export FAKE_ONEUI=80000 FAKE_DEX_DISPLAY=2
run_app $C
check "real DeX offered" asked_buttons "Phone screen|DeX"
check "  ...headless not offered" eval '! file_has events "headless"'
check "nothing done to the phone" eval '! file_has events "settings " && ! file_has events "systemui" && ! file_has events "windowing mode" && no_tasks'
unset FAKE_DEX_DISPLAY FAKE_ONEUI
print "== other phone, Android 16"
export FAKE_MAKER=Google FAKE_SDK=36
run_app $C
check "offered as desktop mode headless" asked_buttons "Phone screen|Desktop mode headless (experimental)"
print "== other phone, Android 15: not offered"
export FAKE_SDK=35
run_app $C
check "no mirror question" eval '! file_has events "What do you want to mirror?"'
unset FAKE_MAKER FAKE_SDK

# ==== reopened while an earlier run hangs ====
C=$WORK/reopen; mkdir -p $C
print "== opened again while the previous run hangs: it's stopped, this run goes on"
print 'usbR|RRR8888|Pixel 7||10.0.0.40|5555' > $C/usb
export FAKE=$C HOME=$C/home; mkdir -p $HOME
FAKE_HANG_START=1 zsh -f $APP/PhoneConnect.sh < /dev/null > /dev/null 2>&1 &
old=$!
for i in {1..100}; do [[ -s $C/hung_adb ]] && break; zselect -t 10; done
check "previous run hanging in adb start-server" eval '[[ -s $C/hung_adb ]] && kill -0 $old'
run_app $C
check "previous run stopped" eval '! kill -0 $old 2>/dev/null'
check "  ...and its hung adb (deaf to TERM) too" eval '! kill -0 $(<$C/hung_adb) 2>/dev/null'
check "logged" logged_line "Stopped the previous run (pid $old)"
check "this run went on" logged_line "Connection: Pixel 7 — USB (usbR)"
check "its pid file removed at the end" no_file $WORK/tmp/PhoneConnect.pid
run_app $C
check "nothing to stop next time" eval '! logged_line "Stopped the previous run"'

print
print "$PASS passed, $FAIL failed (log: $LOG)"
(( FAIL == 0 ))
