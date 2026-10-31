#!/bin/zsh
# PhoneConnect — mirror and control an Android phone with scrcpy.
# The same script runs on macOS and Windows (there with the zsh that ships in the
# app). Anything that differs between them is done by the scripts in platform/
# (one set per OS, same names; see platform/README.md), never by checks in here.
# Remembers several phones; asks which one to use when more than one is known.
# Asks for the session's settings in one window, remembered for each phone: DeX or
# the phone screen (if a DeX display exists), sound, and the video encoder (the best
# one the phone has is marked).
# Without one, on One UI 8+ / Android 16+ it offers a headless DeX / desktop mode on a
# display scrcpy creates (experimental, after a warning). For that session it turns on
# floating windows, and afterwards undoes that and restarts the phone's UI (tasks).
# Connects over USB, Ethernet (dock) or Wi-Fi, in that order of preference.
# Any extra arguments are passed straight to scrcpy, e.g.:  PhoneConnect --print-fps
#
# Layout: settings and helpers first, then one function per step, and main at the
# bottom, which runs the steps in order. Every step goes through `step`, which logs
# when it starts and how long it took. Steps hand their results over in the global
# variables below (never through their output) and return 0 (done), 1 (failed, the
# user has been told) or 2 (the user cancelled); only main exits.

# The build replaces @VERSION@ with the release version (e.g. 1.2.3).
export APP_VERSION="@VERSION@"

# zsh lowers the CPU priority of every job started with "&" (BG_NICE, on by default).
# scrcpy is started that way (so it can be watched), and at that priority its decoding
# and drawing stutter. Run background jobs at normal priority.
setopt NO_BG_NICE

# Paths, tools and files for this OS: TOOLS_DIR ADB SCRCPY SCRCPY_SERVER_PATH
# PHONES_FILE TASKS_FILE OLD_IPS_FILE LOG_FILE TMPDIR OS_INFO NETWORK_BLOCKED_HELP. Everything ships with the app,
# so nothing has to be installed. ${0:A:h} is this script's real folder.
SCRIPT="${0:A}"
PLATFORM="${SCRIPT:h}/platform"
source "$PLATFORM/env.sh"

zmodload zsh/datetime            # $EPOCHREALTIME, strftime
zmodload zsh/system              # $sysparams[pid]: this (sub)shell's own process id
zmodload zsh/zselect             # zselect -t N: wait N/100 s without starting a program
zmodload -F zsh/files b:zf_rm    # zf_rm: rm built into zsh

PORT=5555                        # adb's network port on the phone

# ---- Results the steps hand to each other ----
typeset -a P_ID P_NAME P_ETH P_WIFI   # saved phones (see "Saved phones")
typeset -a P_SCREEN P_AUDIO P_ENCODER # their saved settings: phone|dex|virtual, on|off, encoder name
typeset -A USB_OF                     # phone id -> USB serial, for phones plugged in now
typeset -a USB_SERIALS                # serials of the phones on USB
MIGRATE=0                             # 1: first run after an older version (old IPs file)
CHOSEN_ID=""                          # the phone to connect to
SERIAL=""                             # adb serial of the connection (USB serial or ip:port)
LINK=""                               # USB, Ethernet, Wi-Fi or Wireless debugging
PHONE_NAME=""                         # the chosen phone's name, for messages and the title
LEARNED_ID="" LEARNED_NAME="" LEARNED_ETH=""   # set by learnPhone
DEX_ID=""                             # id of the DeX display, if there is one
VIRTUAL_DESKTOP=""                    # label of the headless desktop option, if the phone supports it
TARGET="phone"                        # phone, dex or virtual (headless desktop)
typeset -a T_PHONE T_ACTION T_NS T_KEY T_VALUE  # tasks still to do on phones (see "Tasks")
TASKS_ADDED=0                         # 1: this run added tasks (run them again on exit)
TASK_SERIAL="" TASK_OPENED=""         # set by reachPhone
typeset -a E_CODEC E_NAME E_HW        # the phone's video encoders: h264|h265|av1, name, 1 = hardware
AUDIO=() AUDIO_CHOICE=""              # scrcpy's audio option, and the answer given
VIDEO=(--video-codec=h265) VIDEO_CHOICE=""   # scrcpy's codec and encoder options, and the answer given
SCRCPY_JOB=""                         # background job running scrcpy
NETWORK_BLOCKED=""                    # the phone answered, but the computer kept adb from it
STATUS_WATCHER=""                     # background loop for the status window

# =====================================================================
# Log
# One log with timestamps for everything: this script's messages [app], every adb
# (and other tool) command with its exit code and output [cmd], and scrcpy's own
# output [scrcpy]. Each line also has this run's process id, in case two run at
# once. It's kept across runs; lines older than a day are dropped at start.
# =====================================================================
LOG=$LOG_FILE
[[ -t 1 ]] && ON_TERMINAL=1 || ON_TERMINAL=0

stampLines() {    # stampLines <source>: timestamp each line read and add it to the log
  local line t ts
  while IFS= read -r line || [[ -n "$line" ]]; do
    t=$EPOCHREALTIME
    strftime -s ts '%Y-%m-%d %H:%M:%S' ${t%.*}
    line=${line//$'\r'/}; line=${line//$'\b'/}; line=${line#'^D'}   # terminal leftovers from `script`
    line="$ts.${${t#*.}[1,3]} [$$ $1] $line"
    print -r -- "$line" >> "$LOG"
    (( ON_TERMINAL )) && print -r -- "$line" > /dev/tty
  done
}

startLog() {
  if [[ -f "$LOG" ]]; then
    local cutoff
    strftime -s cutoff '%Y-%m-%d %H:%M:%S' $(( EPOCHSECONDS - 86400 ))
    awk -v c="$cutoff" '/^[0-9][0-9][0-9][0-9]-/ && substr($0, 1, 19) >= c' "$LOG" > "$LOG.$$" \
      && mv -f "$LOG.$$" "$LOG"
  fi
  exec > >(stampLines app) 2>&1
  exec 3> >(stampLines cmd)
}

# step <function> <args...>: run one step of the program, logging when it starts and
# how long it took. Steps can contain steps; each is timed on its own.
step() {
  local name=$1 start=$EPOCHREALTIME rc
  local -i ms
  shift
  echo "Step start: $name"
  "$name" "$@"
  rc=$?
  (( ms = (EPOCHREALTIME - start) * 1000 ))
  echo "Step end: $name ($ms ms, exit $rc)"
  return $rc
}

# runLogged <command...>: run it and pass its output on, writing the command, its
# exit code and its output to the log. LOGGED_LABEL= names the command in the log.
# It runs no helper programs of its own (starting a program is slow on Windows):
# the temp file name, removing it and the "  | " prefixes are all done by zsh.
runLogged() {
  local out err rc errf="$TMPDIR/PhoneConnect.${sysparams[pid]}.$RANDOM.err"
  local -a lines
  out=$("$@" 2>"$errf"); rc=$?
  err=$(<"$errf"); zf_rm -f "$errf"
  out=${out//$'\r'/} err=${err//$'\r'/}   # Windows programs end lines with CR LF
  {
    print -r -- "\$ ${LOGGED_LABEL:-$*}  -> exit $rc"
    if [[ -n "$out" ]]; then lines=("${(@f)out}"); print -rl -- "${lines[@]/#/  | }"; fi
    if [[ -n "$err" ]]; then lines=("${(@f)err}"); print -rl -- "${lines[@]/#/  ! }"; fi
  } >&3
  [[ -n "$out" ]] && print -r -- "$out"
  [[ -n "$err" ]] && print -r -- "$err" >&2
  return $rc
}

adb() { LOGGED_LABEL="adb $*" runLogged "$ADB" "$@"; }

# platform <name> <args...>: run platform/<name>.sh, logged like any other command
platform() {
  local name=$1; shift
  LOGGED_LABEL="platform/$name $*" runLogged zsh -f "$PLATFORM/$name.sh" "$@"
}

# withTimeout <seconds> <command...>: run a command but give up after that long
withTimeout() {
  local secs=$1; shift
  LOGGED_LABEL="$* (time limit ${secs}s)" runLogged zsh -f "$PLATFORM/run_with_timeout.sh" "$secs" "$@"
}

# =====================================================================
# Status window and dialogs
# A small PhoneConnect window shows the user what's happening, in plain words, until
# the picture appears. showStatus "text" adds a line (also logged as "Status: text");
# showStatus --done closes the window. The window only reads and writes files, never
# touches processes (antivirus scanners distrust small programs that kill others):
#   STATUS_FILE         the lines to show; "__done__" closes it
#   STATUS_FILE.alive   refreshed every 0.5 s while this script runs; when it goes
#                       stale (script gone, however it ended) the window closes
#   STATUS_FILE.cancel  created by the window's Cancel button; this script then stops
# =====================================================================
STATUS_FILE="$TMPDIR/PhoneConnect.$$.status"
PID_FILE="$TMPDIR/PhoneConnect.pid"       # the latest run's process id (stopPreviousRun)

showStatus() {
  if [[ "$1" == --done ]]; then
    print -r -- "__done__" >> "$STATUS_FILE"
  else
    print -r -- "$1" >> "$STATUS_FILE"
    echo "Status: $1"
  fi
}

# askQuestion "Question" "Button A" "Button B" -> prints the chosen button (empty on Cancel)
askQuestion() {
  local answer
  answer=$(platform ask_question "$@")
  echo "Asked: ${1//$'\n'/ } -> ${answer:-Cancel}" >&2
  print -r -- "$answer"
}

# chooseItem "Question" "Default item" "Item 1" "Item 2"... -> prints the chosen item (empty on Cancel)
chooseItem() {
  local answer
  answer=$(platform choose_item "$@")
  echo "Asked: $1 (${(j:, :)@[3,-1]}) -> ${answer:-Cancel}" >&2
  print -r -- "$answer"
}

# settingsForm "Text" "OK button" "Cancel button" "Label 1" "Default 1" "Bold item 1 (or "")"
#              "Items 1 (one per line)" ["Label 2" ...]
#   -> the chosen item of each group, one per line (empty on Cancel)
settingsForm() {
  local answer
  answer=$(platform settings_form "$@")
  echo "Asked: $1 -> ${${answer//$'\n'/ | }:-Cancel}" >&2
  print -r -- "$answer"
}

# showAlert "Title" "Message": a warning the user has to click away
showAlert() { platform show_alert "$@" >/dev/null; }

# When this script ends, however it ends: close the window, stop the watcher, and
# don't leave a still-starting scrcpy behind (e.g. after Cancel)
onExit() {
  [[ -n "$STATUS_WATCHER" ]] && kill $STATUS_WATCHER 2>/dev/null
  [[ -n "$SCRCPY_JOB" ]] && kill -0 $SCRCPY_JOB 2>/dev/null && platform stop_scrcpy $SCRCPY_JOB
  # main runs finishTasks after the session; this is for runs stopped before that
  # (Cancel in the status window, TERM/INT/HUP)
  (( TASKS_ADDED )) && step finishTasks
  showStatus --done
  zf_rm -f "$STATUS_FILE.alive" "$STATUS_FILE.cancel"
  [[ -e "$PID_FILE" && "$(<"$PID_FILE")" == $$ ]] && zf_rm -f "$PID_FILE"
  # give the window a moment to read "__done__" before the file goes
  zselect -t 50
  zf_rm -f "$STATUS_FILE"
}

# =====================================================================
# Saved phones
# One entry per phone, told apart by its serial number (not the model, since two
# phones can be the same model), with its last known Ethernet and Wi-Fi IPs, in
# PHONES_FILE (XML), and the settings last used with it (screen, audio, encoder; left
# out until set). Most recently used first. The empty id is a phone saved by an
# older version whose serial isn't known yet; it gets its real id on the first
# connection. OLD_IPS_FILE is the older single-phone file.
# =====================================================================
xmlEscape() {
  local s=$1
  s=${s//&/&amp;}; s=${s//</&lt;}; s=${s//>/&gt;}; s=${s//\"/&quot;}; s=${s//\'/&apos;}
  print -r -- "$s"
}

removePhone() {   # removePhone <index>
  P_ID[$1]=() P_NAME[$1]=() P_ETH[$1]=() P_WIFI[$1]=()
  P_SCREEN[$1]=() P_AUDIO[$1]=() P_ENCODER[$1]=()
}

addPhone() {      # addPhone <id> <name> <eth> <wifi>: at the end, no settings yet
  P_ID+=("$1") P_NAME+=("$2") P_ETH+=("$3") P_WIFI+=("$4")
  P_SCREEN+=("") P_AUDIO+=("") P_ENCODER+=("")
}

settingAttributes() {   # settingAttributes <index>: the phone's saved settings as XML attributes
  local i=$1 a=""
  [[ -n "${P_SCREEN[i]}"  ]] && a+=" screen=\"$(xmlEscape "${P_SCREEN[i]}")\""
  [[ -n "${P_AUDIO[i]}"   ]] && a+=" audio=\"$(xmlEscape "${P_AUDIO[i]}")\""
  [[ -n "${P_ENCODER[i]}" ]] && a+=" encoder=\"$(xmlEscape "${P_ENCODER[i]}")\""
  print -r -- "$a"
}

writeSavedDevices() {
  local i tmp="$PHONES_FILE.tmp"
  # An old-version phone with no IPs left has nothing to remember
  for (( i = ${#P_ID}; i >= 1; i-- )); do
    [[ -z "${P_ID[i]}${P_ETH[i]}${P_WIFI[i]}" ]] && removePhone $i
  done
  {
    print -r -- '<?xml version="1.0" encoding="UTF-8"?>'
    print -r -- '<phones>'
    for (( i = 1; i <= ${#P_ID}; i++ )); do
      print -r -- "  <phone id=\"$(xmlEscape "${P_ID[i]}")\" name=\"$(xmlEscape "${P_NAME[i]}")\" eth=\"$(xmlEscape "${P_ETH[i]}")\" wifi=\"$(xmlEscape "${P_WIFI[i]}")\"$(settingAttributes $i)/>"
    done
    print -r -- '</phones>'
  } > "$tmp" && mv -f "$tmp" "$PHONES_FILE"
}

phoneIndex() {    # phoneIndex <id> -> prints its index, fails if not saved
  local i
  for (( i = 1; i <= ${#P_ID}; i++ )); do
    [[ "${P_ID[i]}" == "$1" ]] && { print $i; return 0; }
  done
  return 1
}

savedName() {     # savedName <id>
  local idx
  idx=$(phoneIndex "$1") && print -r -- "${P_NAME[idx]}"
}

# savePhone <id> <name> <eth ip> <wifi ip>
# Adds the phone (at the end) or updates it (an empty value keeps the saved one,
# e.g. no Ethernet IP while undocked), and takes its IPs off any other phone
# (the network gave them to this one).
savePhone() {
  local id=$1 name=$2 eth=$3 wifi=$4 idx i
  idx=$(phoneIndex "$id")
  if [[ -z "$idx" ]]; then
    addPhone "$id" "" "" ""
    idx=${#P_ID}
  fi
  for (( i = 1; i <= ${#P_ID}; i++ )); do
    (( i == idx )) && continue
    [[ -n "${P_ETH[i]}"  && ( "${P_ETH[i]}"  == "$eth" || "${P_ETH[i]}"  == "$wifi" ) ]] && P_ETH[i]=""
    [[ -n "${P_WIFI[i]}" && ( "${P_WIFI[i]}" == "$eth" || "${P_WIFI[i]}" == "$wifi" ) ]] && P_WIFI[i]=""
  done
  [[ -n "$name" ]] && P_NAME[idx]=$name
  [[ -n "$eth"  ]] && P_ETH[idx]=$eth
  [[ -n "$wifi" ]] && P_WIFI[idx]=$wifi
  writeSavedDevices
}

markUsed() {      # markUsed <id>: move the phone to the top (the default next time)
  local idx id name eth wifi screen audio encoder
  idx=$(phoneIndex "$1") || return
  id=${P_ID[idx]} name=${P_NAME[idx]} eth=${P_ETH[idx]} wifi=${P_WIFI[idx]}
  screen=${P_SCREEN[idx]} audio=${P_AUDIO[idx]} encoder=${P_ENCODER[idx]}
  removePhone $idx
  P_ID=("$id" "${P_ID[@]}") P_NAME=("$name" "${P_NAME[@]}") P_ETH=("$eth" "${P_ETH[@]}") P_WIFI=("$wifi" "${P_WIFI[@]}")
  P_SCREEN=("$screen" "${P_SCREEN[@]}") P_AUDIO=("$audio" "${P_AUDIO[@]}") P_ENCODER=("$encoder" "${P_ENCODER[@]}")
  writeSavedDevices
}

forgetIp() {      # forgetIp <id> <ip>
  local idx
  idx=$(phoneIndex "$1") || return
  [[ "${P_ETH[idx]}"  == "$2" ]] && P_ETH[idx]=""
  [[ "${P_WIFI[idx]}" == "$2" ]] && P_WIFI[idx]=""
  writeSavedDevices
}

# =====================================================================
# Tasks
# Things still to do on a phone, kept in TASKS_FILE (XML) until they're done, so they
# get done even when the phone was out of reach at the end of a session:
#   <task phone="id" action="setting" namespace="global" key="k" value="v"/>
#       put a setting back (empty value: delete it, it wasn't set before)
#   <task phone="id" action="restart-systemui"/>
#       restart the phone's interface (SystemUI)
# executeTasks runs them at start; finishTasks after the session (from main, or from
# onExit if the run was stopped early). A task is only written when the app is about to
# make the change it undoes, and removed once done.
# =====================================================================
loadTasks() {
  local n i
  T_PHONE=() T_ACTION=() T_NS=() T_KEY=() T_VALUE=()
  [[ -s "$TASKS_FILE" ]] || return 0
  n=$(xmllint --xpath 'count(/tasks/task)' "$TASKS_FILE" 2>/dev/null)
  for (( i = 1; i <= ${n:-0}; i++ )); do
    T_PHONE+=("$(xmllint --xpath "string(/tasks/task[$i]/@phone)" "$TASKS_FILE" 2>/dev/null)")
    T_ACTION+=("$(xmllint --xpath "string(/tasks/task[$i]/@action)" "$TASKS_FILE" 2>/dev/null)")
    T_NS+=("$(xmllint --xpath "string(/tasks/task[$i]/@namespace)" "$TASKS_FILE" 2>/dev/null)")
    T_KEY+=("$(xmllint --xpath "string(/tasks/task[$i]/@key)" "$TASKS_FILE" 2>/dev/null)")
    T_VALUE+=("$(xmllint --xpath "string(/tasks/task[$i]/@value)" "$TASKS_FILE" 2>/dev/null)")
  done
  return 0
}

writeTasks() {
  local i tmp="$TASKS_FILE.tmp"
  if (( ${#T_PHONE} == 0 )); then
    zf_rm -f "$TASKS_FILE"
    return 0
  fi
  {
    print -r -- '<?xml version="1.0" encoding="UTF-8"?>'
    print -r -- '<tasks>'
    for (( i = 1; i <= ${#T_PHONE}; i++ )); do
      if [[ "${T_ACTION[i]}" == setting ]]; then
        print -r -- "  <task phone=\"$(xmlEscape "${T_PHONE[i]}")\" action=\"setting\" namespace=\"$(xmlEscape "${T_NS[i]}")\" key=\"$(xmlEscape "${T_KEY[i]}")\" value=\"$(xmlEscape "${T_VALUE[i]}")\"/>"
      else
        print -r -- "  <task phone=\"$(xmlEscape "${T_PHONE[i]}")\" action=\"$(xmlEscape "${T_ACTION[i]}")\"/>"
      fi
    done
    print -r -- '</tasks>'
  } > "$tmp" && mv -f "$tmp" "$TASKS_FILE"
}

addTask() {       # addTask <phone id> <action> [<namespace> <key> <value>]
  loadTasks
  T_PHONE+=("$1") T_ACTION+=("$2") T_NS+=("$3") T_KEY+=("$4") T_VALUE+=("$5")
  writeTasks
  TASKS_ADDED=1
  echo "Task added for $1: $2${3:+ $3 $4=${5:-(delete)}}"
}

removeTask() {    # removeTask <index> (call writeTasks afterwards)
  T_PHONE[$1]=() T_ACTION[$1]=() T_NS[$1]=() T_KEY[$1]=() T_VALUE[$1]=()
}

pendingPhoneNames() {   # the names of the phones that still have tasks, e.g. "Galaxy S23"
  local id name
  local -aU names
  loadTasks
  for id in "${T_PHONE[@]}"; do
    name=$(savedName "$id")
    names+=("${name:-the phone}")
  done
  print -r -- "${(j:, :)names}"
}

restartSystemUi() {     # restartSystemUi <serial>: done once SystemUI runs under a new pid
  local before after t
  before=$(phoneProp "$1" pidof com.android.systemui)
  withTimeout 8 adb -s "$1" shell am crash com.android.systemui >/dev/null 2>&1
  for t in {1..10}; do
    after=$(phoneProp "$1" pidof com.android.systemui)
    if [[ -n "$after" && "$after" != "$before" ]]; then
      echo "SystemUI restarted (pid ${before:-?} -> $after)"
      return 0
    fi
    zselect -t 50
  done
  echo "SystemUI didn't restart (pid ${before:-?} -> ${after:-?})"
  return 1
}

putSetting() {         # putSetting <serial> <namespace> <key> <value>: empty value deletes it
  if [[ -z "$4" ]]; then
    withTimeout 8 adb -s "$1" shell settings delete "$2" "$3" >/dev/null 2>&1
  else
    withTimeout 8 adb -s "$1" shell settings put "$2" "$3" "$4" >/dev/null 2>&1
  fi
  [[ "$(phoneProp "$1" settings get "$2" "$3")" == "$4" ]]
}

# runTasksFor <phone id> <serial>: settings first, the UI restart last (it also makes
# the phone pick the settings up); each task that worked is removed
runTasksFor() {
  local id=$1 s=$2 i pass
  local -a done_idx
  loadTasks
  for pass in setting restart-systemui; do
    for (( i = 1; i <= ${#T_PHONE}; i++ )); do
      [[ "${T_PHONE[i]}" == "$id" && "${T_ACTION[i]}" == "$pass" ]] || continue
      case $pass in
        setting)
          if putSetting "$s" "${T_NS[i]}" "${T_KEY[i]}" "${T_VALUE[i]}"; then
            echo "Setting ${T_NS[i]} ${T_KEY[i]} put back to ${T_VALUE[i]:-(not set)}"
            done_idx+=($i)
          else
            echo "Couldn't put back setting ${T_NS[i]} ${T_KEY[i]}"
          fi ;;
        restart-systemui)
          restartSystemUi "$s" && done_idx+=($i) ;;
      esac
    done
  done
  for i in ${(On)done_idx}; do removeTask $i; done
  writeTasks
}

# reachPhone <phone id> -> TASK_SERIAL: any way to talk to that phone right now — the
# current connection, its USB serial, then its saved Ethernet and Wi-Fi IPs (the last
# connection may be gone, e.g. a USB session whose cable was pulled). TASK_OPENED is a
# network connection opened just for this.
reachPhone() {
  local id=$1 s ip idx keep=$SERIAL
  TASK_SERIAL="" TASK_OPENED=""
  for s in "$SERIAL" "${USB_OF[$id]}"; do
    [[ -n "$s" ]] || continue
    [[ "$(adb -s "$s" get-state 2>/dev/null)" == device ]] || continue
    [[ "$(phoneId "$s")" == "$id" ]] && { TASK_SERIAL=$s; return 0; }
  done
  idx=$(phoneIndex "$id") || return 1
  for ip in "${P_ETH[idx]}" "${P_WIFI[idx]}"; do
    [[ -n "$ip" && "${ip}:${PORT}" != "$keep" ]] || continue
    if connectTo "$ip"; then
      s=$SERIAL; SERIAL=$keep
      if [[ "$(phoneId "$s")" == "$id" ]]; then
        TASK_SERIAL=$s; TASK_OPENED=$s
        return 0
      fi
      adb disconnect "$s" >/dev/null 2>&1
    fi
    SERIAL=$keep
  done
  return 1
}

# =====================================================================
# Talking to a phone
# =====================================================================
phoneProp() {     # phoneProp <serial> <command...> -> one trimmed line ("null"/"unknown" = empty)
  local s=$1 v; shift
  v=$(withTimeout 8 adb -s "$s" shell "$@" 2>/dev/null | tr -d '\r' | head -1)
  v=${v//$'\t'/ }
  [[ "$v" == (null|unknown) ]] && v=""
  print -r -- "$v"
}

phoneId() {       # phoneId <serial> -> the phone's own serial number (same over USB and network)
  local id
  id=$(phoneProp "$1" getprop ro.serialno)
  [[ -z "$id" ]] && id=$(phoneProp "$1" getprop ro.boot.serialno)
  [[ -z "$id" ]] && id=$(phoneProp "$1" settings get secure android_id)
  print -r -- "$id"
}

phoneName() {     # phoneName <serial> -> the name set on the phone, else its model
  local name
  name=$(phoneProp "$1" settings get global device_name)
  [[ -z "$name" ]] && name=$(phoneProp "$1" getprop ro.product.model)
  print -r -- "${name:-Phone}"
}

interfaceIp() {   # interfaceIp <interface> <adb target args...>
  local ifc=$1; shift
  withTimeout 8 adb "$@" shell ip -f inet addr show $ifc 2>/dev/null \
    | awk '/inet /{print $2}' | cut -d/ -f1 | head -1
}

waitUsbReady() {  # waitUsbReady <serial>: wait up to ~10s for the USB connection to be usable
  local i
  for i in {1..10}; do
    [[ "$(adb -s "$1" get-state 2>/dev/null)" == "device" ]] && return 0
    sleep 1
  done
  return 1
}

portOpen() {      # portOpen <ip>: quick check that something answers at IP:PORT (1-2 s, never hangs)
  platform port_open "$1" "$PORT" >/dev/null 2>&1
}

connectTo() {     # connectTo <ip> -> sets SERIAL on success
  local i j state out
  # Skip quickly if nothing answers there (e.g. the Ethernet IP while undocked);
  # otherwise `adb connect` can hang for over a minute.
  if ! portOpen "$1"; then
    echo "  $1 not reachable"
    showStatus "$1 isn't answering"
    return 1
  fi
  for i in 1 2; do
    adb disconnect "${1}:${PORT}" >/dev/null 2>&1   # clear any stale/offline entry
    out=$(withTimeout 8 adb connect "${1}:${PORT}" 2>&1)
    # The port answered (portOpen), yet no route: the computer blocks adb, not the
    # network (macOS Local Network permission)
    [[ "$out" == *"No route to host"* ]] && NETWORK_BLOCKED=1
    for j in 1 2 3; do                               # give it a moment to come online
      state=$(adb devices | awk -v d="${1}:${PORT}" '$1==d {print $2}')
      if [[ "$state" == "device" ]]; then
        SERIAL="${1}:${PORT}"; return 0
      fi
      sleep 1
    done
  done
  adb disconnect "${1}:${PORT}" >/dev/null 2>&1
  return 1
}

# learnPhone <serial> <id if unreadable> [<ip used> <eth|wifi>]
# Reads which phone is at SERIAL and its current IPs, and saves them.
# Sets LEARNED_ID, LEARNED_NAME, LEARNED_ETH.
learnPhone() {
  local s=$1 ip=$3 kind=$4 eth wifi
  LEARNED_ID=$(phoneId "$s")
  [[ -z "$LEARNED_ID" ]] && LEARNED_ID=$2
  LEARNED_NAME=$(phoneName "$s")
  eth=$(interfaceIp eth0 -s "$s")
  wifi=$(interfaceIp wlan0 -s "$s")
  # The IP we came in on, in case the phone didn't report it
  if [[ -n "$ip" && "$ip" != "$eth" && "$ip" != "$wifi" ]]; then
    if [[ $kind == eth ]]; then eth=${eth:-$ip}; else wifi=${wifi:-$ip}; fi
  fi
  LEARNED_ETH=$eth
  savePhone "$LEARNED_ID" "$LEARNED_NAME" "$eth" "$wifi"
}

# claimConnection <wanted id> <ip> <eth|wifi>  (SERIAL = a new network connection)
# Succeeds if the wanted phone answered. If a different phone has this IP now,
# the IP is moved to that phone (it's added if it's new) and the connection dropped.
claimConnection() {
  local want=$1 idx ph
  learnPhone "$SERIAL" "$want" "$2" "$3"
  if [[ -z "$want" && -n "$LEARNED_ID" ]]; then
    # A phone saved by an older version: now we know which one it is
    ph=$(phoneIndex "")
    if [[ -n "$ph" ]]; then
      idx=$(phoneIndex "$LEARNED_ID")
      [[ -z "${P_ETH[idx]}"  ]] && P_ETH[idx]=${P_ETH[ph]}
      [[ -z "${P_WIFI[idx]}" ]] && P_WIFI[idx]=${P_WIFI[ph]}
      removePhone $ph
      writeSavedDevices
    fi
    CHOSEN_ID=$LEARNED_ID
    return 0
  fi
  [[ "$LEARNED_ID" == "$want" ]] && return 0
  echo "  $2 is now another phone ($LEARNED_NAME) — moved the IP to it, disconnecting"
  showStatus "$2 is now $LEARNED_NAME — trying the next address"
  forgetIp "$want" "$2"
  adb disconnect "$SERIAL" >/dev/null 2>&1
  SERIAL=""
  return 1
}

# Phones on USB: every phone adb lists that isn't a network connection (IP:PORT)
# or found through Wireless debugging. (`adb devices -l` shows a "usb:" field only
# on macOS/Linux, so don't rely on it.)
usbSerials() {
  adb devices | awk 'NR > 1 && NF >= 2 && $2 != "offline" && $1 !~ /:[0-9]+$/ && $1 !~ /_adb-tls-connect/ {print $1}'
}

phoneLabel() {    # phoneLabel <index>: how a saved phone is listed in the chooser
  local i=$1 j same=0 label=${P_NAME[$1]:-Phone}
  for (( j = 1; j <= ${#P_NAME}; j++ )); do
    [[ "${P_NAME[j]}" == "${P_NAME[i]}" ]] && (( same++ ))
  done
  [[ -z "${P_ID[i]}" ]] && label="$label (saved by an older version)"
  (( same > 1 )) && [[ -n "${P_ID[i]}" ]] && label="$label (…${P_ID[i]: -4})"
  [[ -n "${P_ID[i]}" && -n "${USB_OF[${P_ID[i]}]}" ]] && label="$label — USB"
  print -r -- "$label"
}

# =====================================================================
# Steps (run by main, in this order)
# =====================================================================

# Open the status window and keep it informed; its Cancel stops this script
startStatusWindow() {
  : > "$STATUS_FILE"
  : > "$STATUS_FILE.alive"
  # Keeps STATUS_FILE.alive fresh, and stops this script when Cancel was pressed
  {
    while true; do
      if [[ -e "$STATUS_FILE.cancel" ]]; then
        echo "Cancel pressed in the status window — stopping"
        kill -TERM $$
        break
      fi
      : > "$STATUS_FILE.alive"
      zselect -t 50
    done
  } &!
  STATUS_WATCHER=$!
  showStatus "Starting…"
  platform status_window "$STATUS_FILE" >/dev/null
  platform unquarantine
  return 0
}

# Stop an earlier run that is still going (e.g. stuck on a command that hangs), with
# everything it started, so opening the app again is always a way out. PID_FILE holds
# the process id of the latest run.
stopPreviousRun() {
  local old
  [[ -s "$PID_FILE" ]] && old=$(<"$PID_FILE")
  if [[ "$old" == <-> && "$old" != $$ ]] && platform stop_previous "$old"; then
    echo "Stopped the previous run (pid $old)"
    # its status window, if it couldn't close it itself
    if [[ -e "$TMPDIR/PhoneConnect.$old.status" ]]; then
      print -r -- "__done__" >> "$TMPDIR/PhoneConnect.$old.status"
      zselect -t 50
      zf_rm -f "$TMPDIR/PhoneConnect.$old.status"{,.alive,.cancel}
    fi
  fi
  print -r -- $$ > "$PID_FILE"
  return 0
}

# Make sure adb and scrcpy are there
checkTools() {
  local tool
  for tool in "$ADB" "$SCRCPY"; do
    if [[ ! -x "$tool" ]]; then
      echo "$tool not found" >&2
      showAlert "${tool:t} missing" "PhoneConnect is incomplete. Please reinstall it."
      return 1
    fi
  done
  echo "Tools: $("$ADB" version 2>&1 | head -1), $("$SCRCPY" --version 2>&1 | head -1)"
}

# Start adb's background server on its own, without capturing its output: started
# by a later captured command, it would inherit that output pipe and hold it open.
# adb's own USB code can hang for good while the server starts (seen on a Mac with a
# USB-C dock: stuck opening one of the dock's devices), so each try gets 10 s: first as
# usual, then with libusb instead, then without USB (phones over the network only). The
# setting stays exported for this run's adb commands; a server started that way keeps
# running for later runs too, until the computer restarts or adb kill-server.
startAdbServer() {
  local mode job i
  for mode in "" ADB_LIBUSB=1 ADB_USB=0; do
    [[ -n "$mode" ]] && export "$mode"
    "$ADB" start-server >/dev/null 2>&1 &
    job=$!
    for (( i = 0; i < 40; i++ )); do kill -0 $job 2>/dev/null || break; zselect -t 25; done
    if ! kill -0 $job 2>/dev/null; then
      echo "adb server started${mode:+ ($mode)}"
      return 0
    fi
    echo "adb start-server${mode:+ ($mode)} hung for 10 s — stopping it" >&2
    platform stop_tree $job
    case $mode in
      "")           showStatus "USB isn't answering — trying another way…" ;;
      ADB_LIBUSB=1) showStatus "USB isn't working — using the network only" ;;
    esac
  done
  showStatus "A USB device is blocking PhoneConnect"
  showAlert "couldn't start" "A USB device is blocking PhoneConnect. Unplug USB accessories (or the dock) and open PhoneConnect again."
  return 1
}

# Read the saved phones; note whether the older single-phone file still has to be moved
loadSavedDevices() {
  local n i
  P_ID=() P_NAME=() P_ETH=() P_WIFI=() P_SCREEN=() P_AUDIO=() P_ENCODER=()
  [[ ! -e "$PHONES_FILE" && -e "$OLD_IPS_FILE" ]] && MIGRATE=1 || MIGRATE=0
  [[ -s "$PHONES_FILE" ]] || return 0
  n=$(xmllint --xpath 'count(/phones/phone)' "$PHONES_FILE" 2>/dev/null)
  for (( i = 1; i <= ${n:-0}; i++ )); do
    P_ID+=("$(xmllint --xpath "string(/phones/phone[$i]/@id)" "$PHONES_FILE" 2>/dev/null)")
    P_NAME+=("$(xmllint --xpath "string(/phones/phone[$i]/@name)" "$PHONES_FILE" 2>/dev/null)")
    P_ETH+=("$(xmllint --xpath "string(/phones/phone[$i]/@eth)" "$PHONES_FILE" 2>/dev/null)")
    P_WIFI+=("$(xmllint --xpath "string(/phones/phone[$i]/@wifi)" "$PHONES_FILE" 2>/dev/null)")
    P_SCREEN+=("$(xmllint --xpath "string(/phones/phone[$i]/@screen)" "$PHONES_FILE" 2>/dev/null)")
    P_AUDIO+=("$(xmllint --xpath "string(/phones/phone[$i]/@audio)" "$PHONES_FILE" 2>/dev/null)")
    P_ENCODER+=("$(xmllint --xpath "string(/phones/phone[$i]/@encoder)" "$PHONES_FILE" 2>/dev/null)")
  done
  return 0
}

# Drop wireless entries that are stuck "offline" (e.g. from an old IP)
dropOfflineConnections() {
  local d
  for d in ${(f)"$(adb devices | awk 'NR>1 && $2=="offline" && $1 ~ /:[0-9]+$/ {print $1}')"}; do
    adb disconnect "$d" >/dev/null 2>&1
  done
  return 0
}

# Which phones are plugged in by USB now -> USB_SERIALS
listConnectedDevices() {
  showStatus "Looking for phones on USB…"
  # The phone can vanish from USB for a moment (e.g. right after a mode switch)
  [[ -n "$(usbSerials)" ]] || sleep 2
  USB_SERIALS=(${(f)"$(usbSerials)"})
  echo "Phones on USB: ${USB_SERIALS[*]:-none}"
  return 0
}

# For each phone plugged in: save its Ethernet and Wi-Fi IPs and turn on network
# mode, so later launches can connect without the cable (until the phone restarts).
prepareUsbDevices() {
  local usb idx
  for usb in $USB_SERIALS; do
    if ! waitUsbReady "$usb"; then
      echo "USB phone $usb isn't ready (tap Allow on the phone?) — skipping it"
      showStatus "A phone on USB isn't ready — tap Allow on the phone"
      continue
    fi
    learnPhone "$usb" "$usb"
    USB_OF[$LEARNED_ID]=$usb
    idx=$(phoneIndex "$LEARNED_ID")
    echo "USB: $LEARNED_NAME ($LEARNED_ID) — saved IPs — Ethernet: ${P_ETH[idx]:-none}, Wi-Fi: ${P_WIFI[idx]:-none}"
    showStatus "Found $LEARNED_NAME on USB"
    step enableNetworkMode "$usb"
  done
  return 0
}

# Turn on network mode for later cable-free launches (only if it isn't on already,
# because switching it restarts adb on the phone)
enableNetworkMode() {    # enableNetworkMode <usb serial>
  [[ "$(adb -s "$1" shell getprop service.adb.tcp.port 2>/dev/null | tr -d '\r')" == "$PORT" ]] && return 0
  echo "Turning on network mode (port $PORT)"
  showStatus "Setting up $LEARNED_NAME for cable-free use…"
  adb -s "$1" tcpip $PORT >/dev/null 2>&1
  sleep 3
  waitUsbReady "$1"
}

# First run of this version: move the IPs saved by an older version. They didn't
# record which phone they belong to, so ask whoever answers there. The old file only
# ever held one phone's IPs, so an IP nobody answers at goes to the phone found at
# the other IP (or the one plugged in by USB).
migrateOldSavedIps() {
  (( MIGRATE )) || return 0
  local line kind ip idx old_eth="" old_wifi="" old_owner=""
  echo "Moving saved IPs from $OLD_IPS_FILE to $PHONES_FILE"
  for line in ${(f)"$(<"$OLD_IPS_FILE")"}; do
    line=${line%$'\r'}                                 # written with Windows line ends there
    kind=${line%% *} ip=${line#* }
    [[ $kind == (eth|wifi) && -n "$ip" && "$ip" != "$kind" ]] || continue
    if (( ${P_ETH[(Ie)$ip]} )); then                        # already known from USB
      old_owner=${old_owner:-${P_ID[${P_ETH[(Ie)$ip]}]}}; continue
    elif (( ${P_WIFI[(Ie)$ip]} )); then
      old_owner=${old_owner:-${P_ID[${P_WIFI[(Ie)$ip]}]}}; continue
    fi
    echo "Checking which phone is at $ip..."
    showStatus "Checking which phone is at $ip…"
    if connectTo "$ip"; then
      learnPhone "$SERIAL" "" "$ip" "$kind"
      old_owner=${old_owner:-$LEARNED_ID}
      SERIAL=""
    elif [[ $kind == eth ]]; then
      old_eth=$ip
    else
      old_wifi=$ip
    fi
  done
  (( ${#USB_OF} == 1 )) && old_owner=${old_owner:-${(k)USB_OF}}
  if [[ -n "$old_eth$old_wifi" ]]; then
    if idx=$(phoneIndex "$old_owner") && [[ -n "$old_owner" ]]; then
      [[ -z "${P_ETH[idx]}"  ]] && P_ETH[idx]=$old_eth
      [[ -z "${P_WIFI[idx]}" ]] && P_WIFI[idx]=$old_wifi
    elif ! phoneIndex "" >/dev/null; then
      # Nobody answered: keep the IPs, the phone gets identified on its first connection
      addPhone "" "Phone" "$old_eth" "$old_wifi"
    fi
  fi
  writeSavedDevices
  rm -f "$OLD_IPS_FILE"
  return 0
}

# Nothing saved and nothing plugged in: tell the user to plug the phone in
# Do what's still to do on phones (see "Tasks"), for every phone that has something —
# at start (before choosing a phone) and on exit. Returns 1 if anything is left.
executeTasks() {
  local id name
  local -aU ids
  loadTasks
  ids=("${T_PHONE[@]}")
  for id in $ids; do
    name=$(savedName "$id"); name=${name:-the phone}
    showStatus "Finishing cleanup on $name…"
    if reachPhone "$id"; then
      runTasksFor "$id" "$TASK_SERIAL"
      [[ -n "$TASK_OPENED" ]] && adb disconnect "$TASK_OPENED" >/dev/null 2>&1
    else
      echo "Couldn't reach $name ($id) — its tasks wait for the next run"
    fi
  done
  loadTasks
  (( ${#T_PHONE} == 0 ))
}

# After a session that added tasks: do them now; if some phone can't be reached, tell
# the user how to finish. Runs once (TASKS_ADDED back to 0).
finishTasks() {
  (( TASKS_ADDED )) || return 0
  TASKS_ADDED=0
  step executeTasks && return 0
  showAlert "couldn't finish cleanup" "Couldn't reach $(pendingPhoneNames) to finish cleaning up after headless mode (turn floating windows back off, restart the phone's interface).

Connect the phone (USB, or the same network) and open PhoneConnect again — it finishes this first. Until then the phone's back gesture may not work; restarting the phone also fixes it."
  return 1
}

checkAnyDeviceKnown() {
  (( ${#P_ID} > 0 )) && return 0
  echo "No phone found. Plug in the cable once (after each phone restart) to turn on network mode." >&2
  showAlert "no phone found" "Plug the phone in with a USB cable once (needed after every phone restart), so PhoneConnect can turn on network mode.

Make sure USB debugging is on and you tapped Allow on the phone."
  return 1
}

# Which phone? Every saved phone, once each (a phone plugged in by USB is saved by
# now, so it's in the list too, marked "USB"). Asked only when there's more than one.
# -> CHOSEN_ID
displayDeviceChoiceDialog() {
  local i choice default_label=""
  local -a labels
  CHOSEN_ID=${P_ID[1]}
  (( ${#P_ID} > 1 )) || return 0
  for (( i = 1; i <= ${#P_ID}; i++ )); do
    labels+=("$(phoneLabel $i)")
    [[ -z "$default_label" && -n "${P_ID[i]}" && -n "${USB_OF[${P_ID[i]}]}" ]] && default_label=${labels[i]}
  done
  showStatus "Choose a phone…"
  choice=$(chooseItem "Which phone do you want to connect to?" "${default_label:-${labels[1]}}" "${labels[@]}")
  [[ -z "$choice" ]] && return 2   # Cancel
  CHOSEN_ID=${P_ID[${labels[(ie)$choice]}]}
  return 0
}

# ---- Connecting. Priority: 1. USB   2. Ethernet (dock)   3. Wi-Fi ----

tryUsbConnection() {
  [[ -n "$CHOSEN_ID" && -n "${USB_OF[$CHOSEN_ID]}" ]] || return 1
  SERIAL=${USB_OF[$CHOSEN_ID]}
  LINK="USB"
  return 0
}

# tryNetworkConnection <eth|wifi>: connect to the chosen phone's saved IP of that kind
tryNetworkConnection() {
  local kind=$1 idx ip
  idx=$(phoneIndex "$CHOSEN_ID") || return 1
  [[ $kind == eth ]] && ip=${P_ETH[idx]} || ip=${P_WIFI[idx]}
  if [[ -z "$ip" ]]; then
    echo "No saved $kind IP"
    return 1
  fi
  echo "Trying $kind at $ip..."
  showStatus "Connecting to $(savedName "$CHOSEN_ID") over ${${kind:s/eth/Ethernet}:s/wifi/Wi-Fi} ($ip)…"
  connectTo "$ip" && claimConnection "$CHOSEN_ID" "$ip" $kind || return 1
  [[ $kind == eth ]] && LINK="Ethernet" || LINK="Wi-Fi"
  return 0
}

tryEthernetConnection() { tryNetworkConnection eth; }
tryWifiConnection()     { tryNetworkConnection wifi; }

# Fallback: the phone connected through Android's Wireless debugging (found automatically)
tryWirelessDebuggingConnection() {
  local wd
  for wd in ${(f)"$(adb devices | awk 'NR>1 && $2=="device" && $1 ~ /_adb-tls-connect\._tcp/ {print $1}')"}; do
    if [[ -z "$CHOSEN_ID" || "$(phoneId "$wd")" == "$CHOSEN_ID" ]]; then
      SERIAL=$wd
      LINK="Wireless debugging"
      learnPhone "$SERIAL" "$CHOSEN_ID"
      CHOSEN_ID=$LEARNED_ID
      return 0
    fi
  done
  return 1
}

# The saved IPs were refreshed while connecting (they may have changed). This is also
# how the Ethernet IP gets learned: it only exists while the phone is docked, and then
# there's no USB, so it's read over the Wi-Fi connection. Docked but we came in over
# Wi-Fi: switch this session to Ethernet.
switchToEthernetIfDocked() {
  local prev_serial=$SERIAL
  [[ -n "$LEARNED_ETH" && "$LINK" != "Ethernet" ]] || return 0
  echo "Phone has Ethernet ($LEARNED_ETH) — switching to it"
  showStatus "Switching to Ethernet ($LEARNED_ETH)…"
  if connectTo "$LEARNED_ETH" && claimConnection "$CHOSEN_ID" "$LEARNED_ETH" eth; then
    LINK="Ethernet"
  else
    SERIAL=$prev_serial
    echo "Ethernet not reachable, staying on $LINK"
  fi
  return 0
}

reportConnectionFailure() {
  local name
  name=$(savedName "$CHOSEN_ID"); name=${name:-the phone}
  echo "Couldn't connect to $name: every connection attempt failed." >&2
  showStatus "Couldn't connect to $name"
  if [[ -n "$NETWORK_BLOCKED" ]]; then
    echo "The phone answered, but adb was blocked (No route to host)" >&2
    showAlert "couldn't connect" "$name is on the network, but this computer is blocking PhoneConnect from reaching it.

$NETWORK_BLOCKED_HELP"
    return 0
  fi
  showAlert "couldn't connect" "Couldn't connect to $name.

• Connect the phone to this computer with a USB cable, or
• make sure the phone is on the same network (Wi-Fi or dock Ethernet) as this computer.

After the phone restarts, the cable is needed once."
}

# Connect to the chosen phone -> SERIAL, LINK, PHONE_NAME
connectToChosenDevice() {
  if ! step tryUsbConnection; then
    step tryEthernetConnection || step tryWifiConnection || step tryWirelessDebuggingConnection
    if [[ -z "$SERIAL" ]]; then
      reportConnectionFailure
      return 1
    fi
    step switchToEthernetIfDocked
  fi
  markUsed "$CHOSEN_ID"
  PHONE_NAME=$(savedName "$CHOSEN_ID"); PHONE_NAME=${PHONE_NAME:-$LEARNED_NAME}
  echo "Connection: $PHONE_NAME — $LINK ($SERIAL)"
  showStatus "Connected to $PHONE_NAME over $LINK"
  return 0
}

# Look for a DeX (external) display: any display other than 0 -> DEX_ID. In the same
# call, the phone's video encoders (scrcpy can show the picture with), best first ->
# E_CODEC E_NAME E_HW; aliases (other names for the same encoder) are left out.
findDisplaysAndEncoders() {
  local out line
  showStatus "Looking for a DeX screen…"
  out=$(LOGGED_LABEL="scrcpy -s $SERIAL --list-displays --list-encoders" runLogged "$SCRCPY" -s "$SERIAL" --list-displays --list-encoders 2>&1)
  DEX_ID=$(print -r -- "$out" | grep -o 'display-id=[0-9]*' | cut -d= -f2 | grep -v '^0$' | head -1)
  E_CODEC=() E_NAME=() E_HW=()
  for line in ${(f)out}; do
    [[ "$line" == *alias* ]] && continue
    [[ "$line" =~ '--video-codec=(h264|h265|av1) --video-encoder=([^ ]+) +\(([a-z]+)\)' ]] || continue
    E_CODEC+=("${match[1]}") E_NAME+=("${match[2]}")
    [[ "${match[3]}" == sw ]] && E_HW+=(0) || E_HW+=(1)
  done
  sortEncoders
  echo "Video encoders: ${(j:, :)E_NAME:-none}"
  return 0
}

# sortEncoders: best first. One done by the phone's hardware (software ones are slow,
# and their limits make scrcpy shrink the picture), then H.265 > H.264 > AV1 (H.265:
# sharper at the same bit rate; AV1 is decoded by the Mac's or PC's hardware only on
# recent ones).
sortEncoders() {
  local want i
  local -a codec name hw
  for want in 1h265 1h264 1av1 0h264 0h265 0av1; do
    for (( i = 1; i <= ${#E_NAME}; i++ )); do
      [[ "${E_HW[i]}${E_CODEC[i]}" == $want ]] || continue
      codec+=("${E_CODEC[i]}") name+=("${E_NAME[i]}") hw+=("${E_HW[i]}")
    done
  done
  E_CODEC=("${codec[@]}") E_NAME=("${name[@]}") E_HW=("${hw[@]}")
}

encoderLabel() {  # encoderLabel <index>: how an encoder is listed in the settings
  local i=$1 codec
  case ${E_CODEC[i]} in h264) codec=H.264 ;; h265) codec=H.265 ;; *) codec=AV1 ;; esac
  if (( E_HW[i] )); then
    print -r -- "$codec · hardware · ${E_NAME[i]}"
  else
    print -r -- "$codec · software (slow) · ${E_NAME[i]}"
  fi
}

# Without a DeX display: can the phone run its desktop headless, on a display scrcpy
# creates (--new-display)? Samsung renders DeX there from One UI 8, other phones their
# desktop mode from Android 16. Only reads the phone's version; changes no settings.
# -> VIRTUAL_DESKTOP (the option's label, empty if not supported)
checkVirtualDesktop() {
  local maker oneui sdk
  VIRTUAL_DESKTOP=""
  [[ -n "$DEX_ID" ]] && return 0
  maker=$(phoneProp "$SERIAL" getprop ro.product.manufacturer)
  if [[ "${(L)maker}" == samsung ]]; then
    oneui=$(phoneProp "$SERIAL" getprop ro.build.version.oneui)
    [[ "$oneui" == <-> ]] && (( oneui >= 80000 )) && VIRTUAL_DESKTOP="DeX headless (experimental)"
    echo "Samsung, One UI ${oneui:-unknown}: headless DeX ${${VIRTUAL_DESKTOP:+supported}:-not supported}"
  else
    sdk=$(phoneProp "$SERIAL" getprop ro.build.version.sdk)
    [[ "$sdk" == <-> ]] && (( sdk >= 36 )) && VIRTUAL_DESKTOP="Desktop mode headless (experimental)"
    echo "${maker:-Unknown maker}, Android SDK ${sdk:-unknown}: headless desktop mode ${${VIRTUAL_DESKTOP:+supported}:-not supported}"
  fi
  return 0
}

# The session's settings, in one window, remembered for this phone (the saved ones are
# the defaults next time):
#   Show           the phone screen, DeX (if a DeX display is connected) or the
#                  headless desktop (if the phone can run it); only with a choice
#   Sound          on the phone, or on this computer
#   Video encoder  every encoder the phone has; the best one is marked ★ (and bold) and
#                  is the default until another one was chosen
# Without saved settings: DeX if it's connected, else the phone screen; sound on this
# computer.
# -> TARGET, AUDIO, AUDIO_CHOICE, VIDEO, VIDEO_CHOICE
askSettings() {
  local idx i choice show sound encoder
  local -a screens encoders groups answers
  local sound_off="On the phone" sound_on="On this computer (phone muted)"
  idx=$(phoneIndex "$CHOSEN_ID")
  screens=("Phone screen")
  [[ -n "$DEX_ID" ]] && screens+=("DeX")
  [[ -n "$VIRTUAL_DESKTOP" ]] && screens+=("$VIRTUAL_DESKTOP")
  case ${idx:+${P_SCREEN[idx]}} in
    phone)   show="Phone screen" ;;
    dex)     show="DeX" ;;
    virtual) show=$VIRTUAL_DESKTOP ;;
  esac
  # not saved (or not there now): DeX if it's connected, else the phone screen
  (( ${screens[(Ie)$show]} )) || show=${${DEX_ID:+DeX}:-Phone screen}
  [[ "${idx:+${P_AUDIO[idx]}}" == off ]] && sound=$sound_off || sound=$sound_on
  for (( i = 1; i <= ${#E_NAME}; i++ )); do
    encoders+=("$(encoderLabel $i)")
    (( i == 1 )) && encoders[i]+="  ★ best"
    [[ -n "$idx" && "${E_NAME[i]}" == "${P_ENCODER[idx]}" ]] && encoder=${encoders[i]}
  done
  encoder=${encoder:-${encoders[1]}}

  while true; do
    groups=()
    (( ${#screens} > 1 )) && groups+=("Show:" "$show" "" "${(pj:\n:)screens}")
    groups+=("Sound:" "$sound" "" "$sound_off"$'\n'"$sound_on")
    (( ${#encoders} )) && groups+=("Video encoder:" "$encoder" "${encoders[1]}" "${(pj:\n:)encoders}")
    showStatus "Choose the settings…"
    answers=(${(f)"$(settingsForm "Settings for ${PHONE_NAME} — remembered for this phone." "Start" "Cancel" "${groups[@]}")"})
    (( ${#answers} )) || return 2   # Cancel
    (( ${#screens} > 1 )) && { show=${answers[1]}; shift answers; }
    sound=${answers[1]} encoder=${answers[2]}
    [[ "$show" == "$VIRTUAL_DESKTOP" && -n "$show" ]] || break
    # "Go back" is the default button
    choice=$(askQuestion "${VIRTUAL_DESKTOP% \(experimental\)} is experimental.

• After the session the phone's back gesture stops working until its interface restarts. PhoneConnect restarts it when you close the window (the status bar flickers once).

• To give apps their own windows, PhoneConnect turns on \"freeform windows\" (Developer options) for the session and turns it off afterwards.

• If the phone loses its connection before that, connect it again and open PhoneConnect to finish. Restarting the phone also fixes the back gesture." "Continue" "Go back")
    [[ -z "$choice" ]] && return 2   # Cancel
    [[ "$choice" == "Continue" ]] && break
  done

  case $show in
    DeX)               TARGET="dex" ;;
    "$VIRTUAL_DESKTOP") TARGET="virtual" ;;
    *)                 TARGET="phone" ;;
  esac
  AUDIO_CHOICE=$sound
  [[ "$sound" == "$sound_on" ]] && AUDIO=() || AUDIO=(--no-audio)
  i=${encoders[(ie)$encoder]}
  if (( i <= ${#E_NAME} )); then
    VIDEO=(--video-codec=${E_CODEC[i]} --video-encoder=${E_NAME[i]}) VIDEO_CHOICE=${E_NAME[i]}
  else
    VIDEO_CHOICE="the phone's default H.265 (its encoders weren't listed)"
  fi
  # Remember them; what to show only if there was a choice (an undocked phone keeps DeX)
  if [[ -n "$idx" ]]; then
    (( ${#screens} > 1 )) && P_SCREEN[idx]=$TARGET
    [[ "$sound" == "$sound_on" ]] && P_AUDIO[idx]=on || P_AUDIO[idx]=off
    (( ${#E_NAME} )) && P_ENCODER[idx]=${E_NAME[i]}
    writeSavedDevices
  fi
  return 0
}

# Headless session: write the tasks that undo it, then turn on floating windows (only
# if it's off; then it's turned off again afterwards). The UI restart is always needed.
prepareHeadless() {
  local id old
  [[ "$TARGET" == virtual ]] || return 0
  id=$(phoneId "$SERIAL"); id=${id:-$CHOSEN_ID}
  addTask "$id" restart-systemui
  old=$(phoneProp "$SERIAL" settings get global enable_freeform_support)
  if [[ "$old" == 1 ]]; then
    echo "Floating windows already on — left as is"
    return 0
  fi
  addTask "$id" setting global enable_freeform_support "$old"
  if putSetting "$SERIAL" global enable_freeform_support 1; then
    echo "Floating windows turned on (was ${old:-not set})"
  else
    echo "Couldn't turn on floating windows"
  fi
  return 0
}

# useFloatingWindows <scrcpy output file>: open apps on the headless display in
# resizable windows. Only that display is switched (its id is in scrcpy's "New display:
# … (id=N)" line); it's gone, setting and all, when scrcpy ends.
useFloatingWindows() {
  local id t
  for t in {1..10}; do      # on Windows scrcpy's output can arrive a little late
    id=$(grep -o 'New display: .*(id=[0-9]*)' "$1" 2>/dev/null | tail -1 | grep -o 'id=[0-9]*' | cut -d= -f2)
    [[ -n "$id" ]] && break
    zselect -t 20
  done
  if [[ -z "$id" ]]; then
    echo "Couldn't find the headless display's id — apps open full screen"
    return 1
  fi
  withTimeout 8 adb -s "$SERIAL" shell cmd window set-display-windowing-mode -d "$id" 5 >/dev/null 2>&1
  echo "Headless display $id: $(phoneProp "$SERIAL" cmd window get-display-windowing-mode -d "$id")"
  return 0
}

# waitForPicture <job pid> <output file>: up to 15 s for the first frame; fails if
# none came or scrcpy ended
waitForPicture() {
  local t
  for t in {1..15}; do
    zsh -f "$PLATFORM/picture_up.sh" $1 "$2" && return 0   # first frame shown
    kill -0 $1 2>/dev/null || return 1                      # scrcpy exited
    sleep 1
  done
  return 1
}

# Start scrcpy and watch it. Over the network it sometimes starts the server on the
# phone and then stalls instead of showing the picture. If no picture shows within
# 15 s, stop it, clear the tunnels and retry (up to 3 attempts). Returns scrcpy's
# exit code once the session ends.
runScrcpyWithRetries() {
  local attempt pid rc out="$TMPDIR/PhoneConnect.$$.scrcpy.out"
  local -a args extra
  # -V debug: scrcpy's detailed messages, for the log
  # VIDEO: the codec and encoder chosen in the settings
  # bitrate-mode=1: variable bit rate. The bit rate is an average, so frames with a lot
  # of motion (scrolling) may use more instead of being held back.
  local -a common=(-s "$SERIAL" -K "${VIDEO[@]}" --max-fps=60 --video-codec-options=bitrate-mode:int=1 -V debug "${AUDIO[@]}")
  echo "Video encoder: $VIDEO_CHOICE"
  if [[ "$TARGET" == "dex" ]]; then
    echo "Mirroring DeX (display $DEX_ID), audio: $AUDIO_CHOICE"
    args=("${common[@]}" --display-id="$DEX_ID" --video-bit-rate=8M
          --window-title="PhoneConnect — $PHONE_NAME, DeX ($LINK)" "$@")
  elif [[ "$TARGET" == "virtual" ]]; then
    # a new display only for this session (gone when scrcpy ends); the phone runs its
    # desktop on it
    echo "Mirroring ${VIRTUAL_DESKTOP}, audio: $AUDIO_CHOICE"
    args=("${common[@]}" --new-display=1920x1080/160 --video-bit-rate=8M
          --window-title="PhoneConnect — $PHONE_NAME, ${VIRTUAL_DESKTOP% \(experimental\)} ($LINK)" "$@")
  else
    echo "Mirroring phone screen, audio: $AUDIO_CHOICE"
    args=("${common[@]}" --max-size=1600 --video-bit-rate=6M
          --window-title="PhoneConnect — $PHONE_NAME ($LINK)" "$@")
  fi

  for attempt in 1 2 3; do
    : > "$out"
    echo "Starting (attempt $attempt): scrcpy ${extra[*]} ${args[*]}"
    if (( attempt == 1 )); then showStatus "Waiting for the picture…"
    else showStatus "No picture yet — retrying (attempt $attempt of 3)…"; fi
    zsh -f "$PLATFORM/run_scrcpy.sh" "${extra[@]}" "${args[@]}" < /dev/null > >(tee -a "$out" | stampLines scrcpy) 2>&1 &
    pid=$!
    SCRCPY_JOB=$pid
    if step waitForPicture $pid "$out"; then
      echo "Picture is up"
      [[ "$TARGET" == virtual ]] && step useFloatingWindows "$out"
      showStatus --done
      platform bring_to_front $pid
      wait $pid; rc=$?
      echo "scrcpy ended (exit $rc)"
      rm -f "$out"
      return $rc
    fi
    if (( attempt < 3 )); then
      echo "scrcpy didn't connect (attempt $attempt of 3) — retrying"
    else
      echo "scrcpy didn't connect (attempt 3 of 3) — giving up"
    fi
    platform stop_scrcpy $pid
    adb -s "$SERIAL" forward --remove-all >/dev/null 2>&1
    adb -s "$SERIAL" reverse --remove-all >/dev/null 2>&1
    extra=(--force-adb-forward)
    sleep 1
  done
  rm -f "$out"
  showStatus "No picture from the phone after 3 tries"
  showAlert "couldn't start" "No picture from the phone after 3 tries. Details are in $LOG_FILE"
  return 1
}

# =====================================================================
# main: the program, step by step. Exit codes: 0 done or cancelled, 1 failed
# (the user has been told), otherwise scrcpy's own.
# =====================================================================
main() {
  local rc
  startLog
  echo "PhoneConnect $APP_VERSION starting — $OS_INFO, app: $SCRIPT"

  step startStatusWindow
  step stopPreviousRun
  step checkTools               || exit 1
  step startAdbServer            || exit 1
  step loadSavedDevices
  step dropOfflineConnections
  step listConnectedDevices
  step prepareUsbDevices
  step migrateOldSavedIps
  step executeTasks                             # left over from an earlier run
  step checkAnyDeviceKnown       || exit 1
  step displayDeviceChoiceDialog || exit 0      # 2 = cancelled
  step connectToChosenDevice     || exit 1
  step findDisplaysAndEncoders
  step checkVirtualDesktop
  step askSettings               || exit 0      # cancelled
  step prepareHeadless
  step runScrcpyWithRetries "$@"
  rc=$?
  step finishTasks                              # undo what the session did to the phone
  exit $rc
}

# (set here, not inside main: in zsh an EXIT trap set in a function is that function's)
trap onExit EXIT
trap 'exit 143' TERM INT HUP
main "$@"
