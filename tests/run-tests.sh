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
OLD_IPS_FILE="\$FAKE/old_ips.txt"
LOG_FILE="$WORK/test.log"
EOF

LOG=$WORK/test.log
zmodload zsh/zselect

# run_app <case dir>: one launch of the app in that fake world
run_app() {
  export FAKE=$1 HOME=$1/home
  mkdir -p $HOME
  rm -f $FAKE/choose_args $FAKE/alert $FAKE/scrcpy_args $FAKE/events
  : > $FAKE/connected
  RUN_START=$(wc -l < $LOG 2>/dev/null || print 0)
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
check "scrcpy got the phone-screen options" file_has scrcpy_args "-s 10.0.0.20:5555 -K --video-codec=h265 --max-fps=60 -V debug --no-audio --max-size=1600 --video-bit-rate=6M --window-title=PhoneConnect — Galaxy S23 (Wi-Fi)"

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

print
print "$PASS passed, $FAIL failed (log: $LOG)"
(( FAIL == 0 ))
