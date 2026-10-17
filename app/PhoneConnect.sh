#!/bin/zsh
# PhoneConnect — mirror and control an Android phone with scrcpy.
# The same script runs on macOS and Windows (there with the zsh that ships in the
# app). Anything that differs between them is done by the scripts in platform/
# (one set per OS, same names; see platform/README.md), never by checks in here.
# Remembers several phones; asks which one to use when more than one is known.
# Asks whether to use DeX (if a DeX display exists) and whether to forward audio.
# Connects over USB, Ethernet (dock) or Wi-Fi, in that order of preference.
# Any extra arguments are passed straight to scrcpy, e.g.:  PhoneConnect --print-fps

# The build replaces @VERSION@ with the release version (e.g. 1.2.3).
export APP_VERSION="@VERSION@"

# zsh lowers the CPU priority of every job started with "&" (BG_NICE, on by default).
# scrcpy is started that way (so it can be watched), and at that priority its decoding
# and drawing stutter. Run background jobs at normal priority.
setopt NO_BG_NICE

# Paths, tools and files for this OS: TOOLS_DIR ADB SCRCPY SCRCPY_SERVER_PATH
# PHONES_FILE OLD_IPS_FILE LOG_FILE TMPDIR OS_INFO. Everything ships with the app,
# so nothing has to be installed. ${0:A:h} is this script's real folder.
PLATFORM="${0:A:h}/platform"
source "$PLATFORM/env.sh"

# ---- Log ----
# One log with timestamps for everything: this script's messages [app], every adb
# (and other tool) command with its exit code and output [cmd], and scrcpy's own
# output [scrcpy]. Each line also has this run's process id, in case two run at
# once. It's kept across runs; lines older than a day are dropped at start.
zmodload zsh/datetime
LOG=$LOG_FILE
[[ -t 1 ]] && ON_TERMINAL=1 || ON_TERMINAL=0

stamp() {         # stamp <source>: timestamp each line read and add it to the log
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

if [[ -f "$LOG" ]]; then
  strftime -s LOG_CUTOFF '%Y-%m-%d %H:%M:%S' $(( EPOCHSECONDS - 86400 ))
  awk -v c="$LOG_CUTOFF" '/^[0-9][0-9][0-9][0-9]-/ && substr($0, 1, 19) >= c' "$LOG" > "$LOG.$$" \
    && mv -f "$LOG.$$" "$LOG"
fi
exec > >(stamp app) 2>&1
exec 3> >(stamp cmd)

# logged <command...>: run it and pass its output on, writing the command, its
# exit code and its output to the log. LOGGED_LABEL= names the command in the log.
# It runs no helper programs of its own (starting a program is slow on Windows):
# the temp file name, removing it and the "  | " prefixes are all done by zsh.
zmodload zsh/system              # $sysparams[pid]: this (sub)shell's own process id
zmodload -F zsh/files b:zf_rm    # zf_rm: rm built into zsh
logged() {
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

adb() { LOGGED_LABEL="adb $*" logged "$ADB" "$@"; }

# platform <name> <args...>: run platform/<name>.sh, logged like any other command
platform() {
  local name=$1; shift
  LOGGED_LABEL="platform/$name $*" logged zsh -f "$PLATFORM/$name.sh" "$@"
}

echo "PhoneConnect $APP_VERSION starting — $OS_INFO, app: ${0:A}"

# ---- Status window ----
# A small PhoneConnect window shows the user what's happening, in plain words, until
# the picture appears. status "text" adds a line (also logged as "Status: text");
# status --done closes the window. The window only reads and writes files, never
# touches processes (antivirus scanners distrust small programs that kill others):
#   STATUS_FILE         the lines to show; "__done__" closes it
#   STATUS_FILE.alive   refreshed every 0.5 s while this script runs; when it goes
#                       stale (script gone, however it ended) the window closes
#   STATUS_FILE.cancel  created by the window's Cancel button; this script then stops
STATUS_FILE="$TMPDIR/PhoneConnect.$$.status"
status() {
  if [[ "$1" == --done ]]; then
    print -r -- "__done__" >> "$STATUS_FILE"
  else
    print -r -- "$1" >> "$STATUS_FILE"
    echo "Status: $1"
  fi
}
SCRCPY_JOB=""
STATUS_WATCHER=""
on_exit() {
  status --done
  [[ -n "$STATUS_WATCHER" ]] && kill $STATUS_WATCHER 2>/dev/null
  # stopped (e.g. Cancel) while still waiting for the picture: don't leave scrcpy behind
  [[ -n "$SCRCPY_JOB" ]] && kill -0 $SCRCPY_JOB 2>/dev/null && platform stop_scrcpy $SCRCPY_JOB
  zf_rm -f "$STATUS_FILE.alive" "$STATUS_FILE.cancel"
  # give the window a moment to read "__done__" before the file goes
  zselect -t 50
  zf_rm -f "$STATUS_FILE"
}
trap on_exit EXIT
trap 'exit 143' TERM INT HUP
zmodload zsh/zselect             # zselect -t N: wait N/100 s without starting a program
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
status "Starting…"
platform status_window "$STATUS_FILE" >/dev/null

platform unquarantine

# ask "Question" "Button A" "Button B" -> prints the chosen button (empty on Cancel)
ask() {
  local answer
  answer=$(platform ask_question "$@")
  echo "Asked: ${1//$'\n'/ } -> ${answer:-Cancel}" >&2
  print -r -- "$answer"
}

# choose "Question" "Default item" "Item 1" "Item 2"... -> prints the chosen item (empty on Cancel)
choose() {
  local answer
  answer=$(platform choose_item "$@")
  echo "Asked: $1 (${(j:, :)@[3,-1]}) -> ${answer:-Cancel}" >&2
  print -r -- "$answer"
}

# alert "Title" "Message": a warning the user has to click away
alert() { platform show_alert "$@" >/dev/null; }

for tool in "$ADB" "$SCRCPY"; do
  if [[ ! -x "$tool" ]]; then
    echo "$tool not found" >&2
    alert "${tool:t} missing" "PhoneConnect is incomplete. Please reinstall it."
    exit 1
  fi
done
echo "Tools: $("$ADB" version 2>&1 | head -1), $("$SCRCPY" --version 2>&1 | head -1)"

# Start adb's background server on its own, without capturing its output: started
# by a later captured command, it would inherit that output pipe and hold it open.
"$ADB" start-server >/dev/null 2>&1
echo "adb server started"

# ---- Saved phones ----
# One entry per phone, told apart by its serial number (not the model, since two
# phones can be the same model), with its last known Ethernet and Wi-Fi IPs.
# Most recently used first. The empty id is a phone saved by an older version
# whose serial isn't known yet; it gets its real id on the first connection.
# (PHONES_FILE and OLD_IPS_FILE, the older single-phone file, come from env.sh)
typeset -a P_ID P_NAME P_ETH P_WIFI

load_phones() {
  local n i
  P_ID=() P_NAME=() P_ETH=() P_WIFI=()
  [[ -s "$PHONES_FILE" ]] || return
  n=$(xmllint --xpath 'count(/phones/phone)' "$PHONES_FILE" 2>/dev/null)
  for (( i = 1; i <= ${n:-0}; i++ )); do
    P_ID+=("$(xmllint --xpath "string(/phones/phone[$i]/@id)" "$PHONES_FILE" 2>/dev/null)")
    P_NAME+=("$(xmllint --xpath "string(/phones/phone[$i]/@name)" "$PHONES_FILE" 2>/dev/null)")
    P_ETH+=("$(xmllint --xpath "string(/phones/phone[$i]/@eth)" "$PHONES_FILE" 2>/dev/null)")
    P_WIFI+=("$(xmllint --xpath "string(/phones/phone[$i]/@wifi)" "$PHONES_FILE" 2>/dev/null)")
  done
}

xml_escape() {
  local s=$1
  s=${s//&/&amp;}; s=${s//</&lt;}; s=${s//>/&gt;}; s=${s//\"/&quot;}; s=${s//\'/&apos;}
  print -r -- "$s"
}

remove_phone() {  # remove_phone <index>
  P_ID[$1]=() P_NAME[$1]=() P_ETH[$1]=() P_WIFI[$1]=()
}

write_phones() {
  local i tmp="$PHONES_FILE.tmp"
  # An old-version phone with no IPs left has nothing to remember
  for (( i = ${#P_ID}; i >= 1; i-- )); do
    [[ -z "${P_ID[i]}${P_ETH[i]}${P_WIFI[i]}" ]] && remove_phone $i
  done
  {
    print -r -- '<?xml version="1.0" encoding="UTF-8"?>'
    print -r -- '<phones>'
    for (( i = 1; i <= ${#P_ID}; i++ )); do
      print -r -- "  <phone id=\"$(xml_escape "${P_ID[i]}")\" name=\"$(xml_escape "${P_NAME[i]}")\" eth=\"$(xml_escape "${P_ETH[i]}")\" wifi=\"$(xml_escape "${P_WIFI[i]}")\"/>"
    done
    print -r -- '</phones>'
  } > "$tmp" && mv -f "$tmp" "$PHONES_FILE"
}

phone_index() {   # phone_index <id> -> prints its index, fails if not saved
  local i
  for (( i = 1; i <= ${#P_ID}; i++ )); do
    [[ "${P_ID[i]}" == "$1" ]] && { print $i; return 0; }
  done
  return 1
}

phone_saved_name() {  # phone_saved_name <id>
  local idx
  idx=$(phone_index "$1") && print -r -- "${P_NAME[idx]}"
}

# save_phone <id> <name> <eth ip> <wifi ip>
# Adds the phone (at the end) or updates it (an empty value keeps the saved one,
# e.g. no Ethernet IP while undocked), and takes its IPs off any other phone
# (the network gave them to this one).
save_phone() {
  local id=$1 name=$2 eth=$3 wifi=$4 idx i
  idx=$(phone_index "$id")
  if [[ -z "$idx" ]]; then
    P_ID+=("$id") P_NAME+=("") P_ETH+=("") P_WIFI+=("")
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
  write_phones
}

mark_used() {     # mark_used <id>: move the phone to the top (the default next time)
  local idx id name eth wifi
  idx=$(phone_index "$1") || return
  id=${P_ID[idx]} name=${P_NAME[idx]} eth=${P_ETH[idx]} wifi=${P_WIFI[idx]}
  remove_phone $idx
  P_ID=("$id" "${P_ID[@]}") P_NAME=("$name" "${P_NAME[@]}") P_ETH=("$eth" "${P_ETH[@]}") P_WIFI=("$wifi" "${P_WIFI[@]}")
  write_phones
}

forget_ip() {     # forget_ip <id> <ip>
  local idx
  idx=$(phone_index "$1") || return
  [[ "${P_ETH[idx]}"  == "$2" ]] && P_ETH[idx]=""
  [[ "${P_WIFI[idx]}" == "$2" ]] && P_WIFI[idx]=""
  write_phones
}

# ---- Talking to a phone ----
PORT=5555
SERIAL=""
LINK=""

# Run a command but give up after N seconds
with_timeout() {  # with_timeout SECONDS command...
  local secs=$1; shift
  LOGGED_LABEL="$* (time limit ${secs}s)" logged zsh -f "$PLATFORM/run_with_timeout.sh" "$secs" "$@"
}

phone_prop() {    # phone_prop <serial> <command...> -> one trimmed line ("null"/"unknown" = empty)
  local s=$1 v; shift
  v=$(with_timeout 8 adb -s "$s" shell "$@" 2>/dev/null | tr -d '\r' | head -1)
  v=${v//$'\t'/ }
  [[ "$v" == (null|unknown) ]] && v=""
  print -r -- "$v"
}

phone_id() {      # phone_id <serial> -> the phone's own serial number (same over USB and network)
  local id
  id=$(phone_prop "$1" getprop ro.serialno)
  [[ -z "$id" ]] && id=$(phone_prop "$1" getprop ro.boot.serialno)
  [[ -z "$id" ]] && id=$(phone_prop "$1" settings get secure android_id)
  print -r -- "$id"
}

phone_name() {    # phone_name <serial> -> the name set on the phone, else its model
  local name
  name=$(phone_prop "$1" settings get global device_name)
  [[ -z "$name" ]] && name=$(phone_prop "$1" getprop ro.product.model)
  print -r -- "${name:-Phone}"
}

iface_ip() {      # iface_ip <interface> <adb target args...>
  local ifc=$1; shift
  with_timeout 8 adb "$@" shell ip -f inet addr show $ifc 2>/dev/null \
    | awk '/inet /{print $2}' | cut -d/ -f1 | head -1
}

usb_ready() {     # usb_ready <serial>: wait up to ~10s for the USB connection to be usable
  local i
  for i in {1..10}; do
    [[ "$(adb -s "$1" get-state 2>/dev/null)" == "device" ]] && return 0
    sleep 1
  done
  return 1
}

port_open() {     # quick check that something answers at IP:PORT (1-2 s, never hangs)
  platform port_open "$1" "$PORT" >/dev/null 2>&1
}

try_connect() {   # try_connect IP  -> sets SERIAL on success
  local i j state
  # Skip quickly if nothing answers there (e.g. the Ethernet IP while undocked);
  # otherwise `adb connect` can hang for over a minute.
  if ! port_open "$1"; then
    echo "  $1 not reachable"
    status "$1 isn't answering"
    return 1
  fi
  for i in 1 2; do
    adb disconnect "${1}:${PORT}" >/dev/null 2>&1   # clear any stale/offline entry
    with_timeout 8 adb connect "${1}:${PORT}" >/dev/null 2>&1
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

# learn_phone <serial> <id if unreadable> [<ip used> <eth|wifi>]
# Reads which phone is at SERIAL and its current IPs, and saves them.
# Sets LEARNED_ID, LEARNED_NAME, LEARNED_ETH.
learn_phone() {
  local s=$1 ip=$3 kind=$4 eth wifi
  LEARNED_ID=$(phone_id "$s")
  [[ -z "$LEARNED_ID" ]] && LEARNED_ID=$2
  LEARNED_NAME=$(phone_name "$s")
  eth=$(iface_ip eth0 -s "$s")
  wifi=$(iface_ip wlan0 -s "$s")
  # The IP we came in on, in case the phone didn't report it
  if [[ -n "$ip" && "$ip" != "$eth" && "$ip" != "$wifi" ]]; then
    if [[ $kind == eth ]]; then eth=${eth:-$ip}; else wifi=${wifi:-$ip}; fi
  fi
  LEARNED_ETH=$eth
  save_phone "$LEARNED_ID" "$LEARNED_NAME" "$eth" "$wifi"
}

# claim_connection <wanted id> <ip> <eth|wifi>  (SERIAL = a new network connection)
# Succeeds if the wanted phone answered. If a different phone has this IP now,
# the IP is moved to that phone (it's added if it's new) and the connection dropped.
claim_connection() {
  local want=$1 idx ph
  learn_phone "$SERIAL" "$want" "$2" "$3"
  if [[ -z "$want" && -n "$LEARNED_ID" ]]; then
    # A phone saved by an older version: now we know which one it is
    ph=$(phone_index "")
    if [[ -n "$ph" ]]; then
      idx=$(phone_index "$LEARNED_ID")
      [[ -z "${P_ETH[idx]}"  ]] && P_ETH[idx]=${P_ETH[ph]}
      [[ -z "${P_WIFI[idx]}" ]] && P_WIFI[idx]=${P_WIFI[ph]}
      remove_phone $ph
      write_phones
    fi
    CHOSEN_ID=$LEARNED_ID
    return 0
  fi
  [[ "$LEARNED_ID" == "$want" ]] && return 0
  echo "  $2 is now another phone ($LEARNED_NAME) — moved the IP to it, disconnecting"
  status "$2 is now $LEARNED_NAME — trying the next address"
  forget_ip "$want" "$2"
  adb disconnect "$SERIAL" >/dev/null 2>&1
  SERIAL=""
  return 1
}

load_phones
[[ ! -e "$PHONES_FILE" && -e "$OLD_IPS_FILE" ]] && MIGRATE=1 || MIGRATE=0

# Drop wireless entries that are stuck "offline" (e.g. from an old IP)
adb devices | awk 'NR>1 && $2=="offline" && $1 ~ /:[0-9]+$/ {print $1}' | while read -r d; do
  adb disconnect "$d" >/dev/null 2>&1
done

# ---- Phones on USB ----
# For each phone plugged in: save its Ethernet and Wi-Fi IPs and turn on network
# mode, so later launches can connect without the cable (until the phone restarts).
typeset -A USB_OF      # phone id -> USB serial

# Phones on USB: every phone adb lists that isn't a network connection (IP:PORT)
# or found through Wireless debugging. (`adb devices -l` shows a "usb:" field only
# on macOS/Linux, so don't rely on it.)
usb_serials() {
  adb devices | awk 'NR > 1 && NF >= 2 && $2 != "offline" && $1 !~ /:[0-9]+$/ && $1 !~ /_adb-tls-connect/ {print $1}'
}

status "Looking for phones on USB…"
# The phone can vanish from USB for a moment (e.g. right after a mode switch)
[[ -n "$(usb_serials)" ]] || sleep 2

for usb in ${(f)"$(usb_serials)"}; do
  if ! usb_ready "$usb"; then
    echo "USB phone $usb isn't ready (tap Allow on the phone?) — skipping it"
    status "A phone on USB isn't ready — tap Allow on the phone"
    continue
  fi
  learn_phone "$usb" "$usb"
  USB_OF[$LEARNED_ID]=$usb
  idx=$(phone_index "$LEARNED_ID")
  echo "USB: $LEARNED_NAME ($LEARNED_ID) — saved IPs — Ethernet: ${P_ETH[idx]:-none}, Wi-Fi: ${P_WIFI[idx]:-none}"
  status "Found $LEARNED_NAME on USB"

  # Turn on network mode for later cable-free launches (only if it isn't on already,
  # because switching it restarts adb on the phone)
  if [[ "$(adb -s "$usb" shell getprop service.adb.tcp.port 2>/dev/null | tr -d '\r')" != "$PORT" ]]; then
    echo "Turning on network mode (port $PORT)"
    status "Setting up $LEARNED_NAME for cable-free use…"
    adb -s "$usb" tcpip $PORT >/dev/null 2>&1
    sleep 3
    usb_ready "$usb"
  fi
done

# ---- First run of this version: move the IPs saved by an older version ----
# They didn't record which phone they belong to, so ask whoever answers there.
# The old file only ever held one phone's IPs, so an IP nobody answers at goes
# to the phone found at the other IP (or the one plugged in by USB).
if (( MIGRATE )); then
  echo "Moving saved IPs from $OLD_IPS_FILE to $PHONES_FILE"
  OLD_ETH="" OLD_WIFI="" OLD_OWNER=""
  for line in ${(f)"$(<"$OLD_IPS_FILE")"}; do
    line=${line%$'\r'}                                 # written with Windows line ends there
    kind=${line%% *} ip=${line#* }
    [[ $kind == (eth|wifi) && -n "$ip" && "$ip" != "$kind" ]] || continue
    if (( ${P_ETH[(Ie)$ip]} )); then                        # already known from USB
      OLD_OWNER=${OLD_OWNER:-${P_ID[${P_ETH[(Ie)$ip]}]}}; continue
    elif (( ${P_WIFI[(Ie)$ip]} )); then
      OLD_OWNER=${OLD_OWNER:-${P_ID[${P_WIFI[(Ie)$ip]}]}}; continue
    fi
    echo "Checking which phone is at $ip..."
    status "Checking which phone is at $ip…"
    if try_connect "$ip"; then
      learn_phone "$SERIAL" "" "$ip" "$kind"
      OLD_OWNER=${OLD_OWNER:-$LEARNED_ID}
      SERIAL=""
    elif [[ $kind == eth ]]; then
      OLD_ETH=$ip
    else
      OLD_WIFI=$ip
    fi
  done
  (( ${#USB_OF} == 1 )) && OLD_OWNER=${OLD_OWNER:-${(k)USB_OF}}
  if [[ -n "$OLD_ETH$OLD_WIFI" ]]; then
    if idx=$(phone_index "$OLD_OWNER") && [[ -n "$OLD_OWNER" ]]; then
      [[ -z "${P_ETH[idx]}"  ]] && P_ETH[idx]=$OLD_ETH
      [[ -z "${P_WIFI[idx]}" ]] && P_WIFI[idx]=$OLD_WIFI
    elif ! phone_index "" >/dev/null; then
      # Nobody answered: keep the IPs, the phone gets identified on its first connection
      P_ID+=("") P_NAME+=("Phone") P_ETH+=("$OLD_ETH") P_WIFI+=("$OLD_WIFI")
    fi
  fi
  write_phones
  rm -f "$OLD_IPS_FILE"
fi

# ---- Which phone? ----
# Every saved phone, once each (a phone plugged in by USB is saved above, so it's
# in the list too, marked "USB"). Asked only when there's more than one.
if (( ${#P_ID} == 0 )); then
  echo "No phone found. Plug in the cable once (after each phone restart) to turn on network mode." >&2
  alert "no phone found" "Plug the phone in with a USB cable once (needed after every phone restart), so PhoneConnect can turn on network mode.

Make sure USB debugging is on and you tapped Allow on the phone."
  exit 1
fi

phone_label() {   # phone_label <index>
  local i=$1 j same=0 label=${P_NAME[$1]:-Phone}
  for (( j = 1; j <= ${#P_NAME}; j++ )); do
    [[ "${P_NAME[j]}" == "${P_NAME[i]}" ]] && (( same++ ))
  done
  [[ -z "${P_ID[i]}" ]] && label="$label (saved by an older version)"
  (( same > 1 )) && [[ -n "${P_ID[i]}" ]] && label="$label (…${P_ID[i]: -4})"
  [[ -n "${P_ID[i]}" && -n "${USB_OF[${P_ID[i]}]}" ]] && label="$label — USB"
  print -r -- "$label"
}

CHOSEN_ID=${P_ID[1]}
if (( ${#P_ID} > 1 )); then
  LABELS=() DEFAULT_LABEL=""
  for (( i = 1; i <= ${#P_ID}; i++ )); do
    LABELS+=("$(phone_label $i)")
    [[ -z "$DEFAULT_LABEL" && -n "${P_ID[i]}" && -n "${USB_OF[${P_ID[i]}]}" ]] && DEFAULT_LABEL=${LABELS[i]}
  done
  status "Choose a phone…"
  choice=$(choose "Which phone do you want to connect to?" "${DEFAULT_LABEL:-${LABELS[1]}}" "${LABELS[@]}")
  [[ -z "$choice" ]] && exit 0   # Cancel
  CHOSEN_ID=${P_ID[${LABELS[(ie)$choice]}]}
fi

# ---- Connect to it. Priority: 1. USB   2. Ethernet (dock)   3. Wi-Fi ----
if [[ -n "$CHOSEN_ID" && -n "${USB_OF[$CHOSEN_ID]}" ]]; then
  # ---- 1. USB ----
  SERIAL=${USB_OF[$CHOSEN_ID]}
  LINK="USB"
else
  # ---- 2. Ethernet, 3. Wi-Fi ----
  for kind in eth wifi; do
    idx=$(phone_index "$CHOSEN_ID") || break
    [[ $kind == eth ]] && ip=${P_ETH[idx]} || ip=${P_WIFI[idx]}
    [[ -z "$ip" ]] && continue
    echo "Trying $kind at $ip..."
    status "Connecting to $(phone_saved_name "$CHOSEN_ID") over ${${kind:s/eth/Ethernet}:s/wifi/Wi-Fi} ($ip)…"
    if try_connect "$ip" && claim_connection "$CHOSEN_ID" "$ip" $kind; then
      [[ $kind == eth ]] && LINK="Ethernet" || LINK="Wi-Fi"
      break
    fi
  done

  # Fallback: the phone connected through Android's Wireless debugging (found automatically)
  if [[ -z "$SERIAL" ]]; then
    for wd in ${(f)"$(adb devices | awk 'NR>1 && $2=="device" && $1 ~ /_adb-tls-connect\._tcp/ {print $1}')"}; do
      if [[ -z "$CHOSEN_ID" || "$(phone_id "$wd")" == "$CHOSEN_ID" ]]; then
        SERIAL=$wd
        LINK="Wireless debugging"
        learn_phone "$SERIAL" "$CHOSEN_ID"
        CHOSEN_ID=$LEARNED_ID
        break
      fi
    done
  fi

  if [[ -z "$SERIAL" ]]; then
    name=$(phone_saved_name "$CHOSEN_ID"); name=${name:-the phone}
    echo "Couldn't connect to $name: every connection attempt failed." >&2
    status "Couldn't connect to $name"
    alert "couldn't connect" "Couldn't connect to $name.

• Connect the phone to this computer with a USB cable, or
• make sure the phone is on the same network (Wi-Fi or dock Ethernet) as this computer.

After the phone restarts, the cable is needed once."
    exit 1
  fi

  # The saved IPs were refreshed while connecting (they may have changed).
  # This is also how the Ethernet IP gets learned: it only exists while the phone
  # is docked, and then there's no USB, so it's read over the Wi-Fi connection.
  # Docked but we came in over Wi-Fi: switch this session to Ethernet
  if [[ -n "$LEARNED_ETH" && "$LINK" != "Ethernet" ]]; then
    PREV_SERIAL=$SERIAL
    echo "Phone has Ethernet ($LEARNED_ETH) — switching to it"
    status "Switching to Ethernet ($LEARNED_ETH)…"
    if try_connect "$LEARNED_ETH" && claim_connection "$CHOSEN_ID" "$LEARNED_ETH" eth; then
      LINK="Ethernet"
    else
      SERIAL=$PREV_SERIAL
      echo "Ethernet not reachable, staying on $LINK"
    fi
  fi
fi

mark_used "$CHOSEN_ID"
PHONE_NAME=$(phone_saved_name "$CHOSEN_ID"); PHONE_NAME=${PHONE_NAME:-$LEARNED_NAME}
CONN=(-s "$SERIAL")
echo "Connection: $PHONE_NAME — $LINK ($SERIAL)"
status "Connected to $PHONE_NAME over $LINK"

status "Looking for a DeX screen…"

# ---- Look for a DeX (external) display: any display other than 0 ----
DEX_ID=$(LOGGED_LABEL="scrcpy ${CONN[*]} --list-displays" logged "$SCRCPY" "${CONN[@]}" --list-displays 2>&1 \
  | grep -o 'display-id=[0-9]*' \
  | cut -d= -f2 \
  | grep -v '^0$' \
  | head -1)

TARGET="phone"
if [[ -n "$DEX_ID" ]]; then
  choice=$(ask "A DeX display is connected. What do you want to mirror?" "Phone screen" "DeX")
  [[ -z "$choice" ]] && exit 0   # Cancel
  [[ "$choice" == "DeX" ]] && TARGET="dex"
fi

# ---- Audio ----
choice=$(ask "Play the phone's sound on this computer?

(While on, the phone's own speaker is muted.)" "No audio" "With audio")
[[ -z "$choice" ]] && exit 0   # Cancel
if [[ "$choice" == "With audio" ]]; then
  AUDIO=()
else
  AUDIO=(--no-audio)
fi

# Start scrcpy and watch it. Over the network it sometimes starts the server on
# the phone and then stalls instead of showing the picture. If no picture shows
# within 15 s, kill it, clear the tunnels and retry (up to 3 attempts).
run_scrcpy() {
  local attempt pid ok t rc out="$TMPDIR/PhoneConnect.$$.scrcpy.out"
  local extra=()
  for attempt in 1 2 3; do
    : > "$out"
    echo "Starting (attempt $attempt): scrcpy ${extra[*]} $*"
    if (( attempt == 1 )); then status "Waiting for the picture…"
    else status "No picture yet — retrying (attempt $attempt of 3)…"; fi
    zsh -f "$PLATFORM/run_scrcpy.sh" "${extra[@]}" "$@" < /dev/null > >(tee -a "$out" | stamp scrcpy) 2>&1 &
    pid=$!
    SCRCPY_JOB=$pid
    ok=0
    for t in {1..15}; do
      zsh -f "$PLATFORM/picture_up.sh" $pid "$out" && { ok=1; break; }   # first frame shown
      kill -0 $pid 2>/dev/null || break                                 # scrcpy exited
      sleep 1
    done
    if (( ok )); then
      echo "Picture is up"
      status --done
      platform bring_to_front $pid
      wait $pid; rc=$?
      echo "scrcpy ended (exit $rc)"
      rm -f "$out"
      exit $rc
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
  status "No picture from the phone after 3 tries"
  alert "couldn't start" "No picture from the phone after 3 tries. Details are in $LOG_FILE"
  exit 1
}

# -V debug: scrcpy's detailed messages, for the log
# bitrate-mode=1: variable bit rate. The bit rate is an average, so frames with a lot of
# motion (scrolling) may use more instead of being held back.
COMMON=(--video-codec=h265 --max-fps=60 --video-codec-options=bitrate-mode:int=1 -V debug "${AUDIO[@]}")

if [[ "$TARGET" == "dex" ]]; then
  echo "Mirroring DeX (display $DEX_ID), audio: $choice"
  run_scrcpy "${CONN[@]}" -K --display-id="$DEX_ID" "${COMMON[@]}" \
    --video-bit-rate=8M --window-title="PhoneConnect — $PHONE_NAME, DeX ($LINK)" "$@"
else
  echo "Mirroring phone screen, audio: $choice"
  run_scrcpy "${CONN[@]}" -K "${COMMON[@]}" \
    --max-size=1600 --video-bit-rate=6M \
    --window-title="PhoneConnect — $PHONE_NAME ($LINK)" "$@"
fi
