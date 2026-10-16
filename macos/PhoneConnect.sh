#!/bin/zsh
# PhoneConnect (macOS) — mirror and control an Android phone with scrcpy.
# Remembers several phones; asks which one to use when more than one is known.
# Asks whether to use DeX (if a DeX display exists) and whether to forward audio.
# Connects over USB, Ethernet (dock) or Wi-Fi, in that order of preference.
# Any extra arguments are passed straight to scrcpy, e.g.:  PhoneConnect --print-fps

# The build replaces @VERSION@ with the release version (e.g. 1.2.3).
APP_VERSION="@VERSION@"

# Everything this needs (scrcpy, adb, scrcpy-server) ships inside PhoneConnect.app,
# so nothing has to be installed. There's one set of tools per Mac type.
# ${0:A:h} is this script's real folder, even when started through a link.
case "$(uname -m)" in
  arm64) MAC_ARCH=arm64 ;;     # Apple Silicon
  *)     MAC_ARCH=x86_64 ;;    # Intel
esac
APP_TOOLS="${0:A:h}/../Resources/tools/$MAC_ARCH"
export PATH="$APP_TOOLS:/usr/bin:/bin:/usr/sbin:/sbin"
export ADB="$APP_TOOLS/adb"                          # the adb scrcpy should use
export SCRCPY_SERVER_PATH="$APP_TOOLS/scrcpy-server"  # the part that runs on the phone
# scrcpy sits in a small app bundle of its own, so its window gets the PhoneConnect
# name and icon in the Dock (a bare program gets the generic "exec" icon)
SCRCPY="$APP_TOOLS/PhoneConnect Mirror.app/Contents/MacOS/scrcpy"

# ---- Log ----
# One log with timestamps for everything: this script's messages [app], every adb
# (and other tool) command with its exit code and output [cmd], and scrcpy's own
# output [scrcpy]. Each line also has this run's process id, in case two run at
# once. It's kept across runs; lines older than a day are dropped at start.
zmodload zsh/datetime
LOG=/tmp/PhoneConnect.log
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
logged() {
  local out err rc errf
  errf=$(/usr/bin/mktemp "${TMPDIR:-/tmp}/PhoneConnect.XXXXXX")
  out=$("$@" 2>"$errf"); rc=$?
  err=$(<"$errf"); rm -f "$errf"
  {
    print -r -- "\$ ${LOGGED_LABEL:-$*}  -> exit $rc"
    [[ -n "$out" ]] && print -r -- "$out" | sed 's/^/  | /'
    [[ -n "$err" ]] && print -r -- "$err" | sed 's/^/  ! /'
  } >&3
  [[ -n "$out" ]] && print -r -- "$out"
  [[ -n "$err" ]] && print -r -- "$err" >&2
  return $rc
}

adb() { LOGGED_LABEL="adb $*" logged "$APP_TOOLS/adb" "$@"; }

echo "PhoneConnect $APP_VERSION starting — macOS $(sw_vers -productVersion) ($MAC_ARCH), app: ${0:A}"

# A downloaded app is marked "quarantined" by macOS. Once you've allowed PhoneConnect to
# open, clear that mark from its own files, so the bundled scrcpy and adb don't
# each get blocked with their own "can't be opened" warning.
APP_BUNDLE="${0:A:h:h:h}"
xattr -dr com.apple.quarantine "$APP_BUNDLE" 2>/dev/null

notify() {
  osascript -e "display notification \"$2\" with title \"$1\"" 2>/dev/null
}

# ask "Question" "Button A" "Button B" -> prints the chosen button (empty on Cancel)
# (`activate` brings the dialog to the front, the app itself has no window)
ask() {
  local answer
  answer=$(osascript -e 'activate' -e "button returned of (display dialog \"$1\" with title \"PhoneConnect $APP_VERSION\" buttons {\"Cancel\", \"$2\", \"$3\"} default button \"$3\" cancel button \"Cancel\")" 2>/dev/null)
  echo "Asked: ${1//\\n/ } -> ${answer:-Cancel}" >&2
  print -r -- "$answer"
}

# choose "Question" "Default item" "Item 1" "Item 2"... -> prints the chosen item (empty on Cancel)
choose() {
  local answer
  answer=$(osascript - "$APP_VERSION" "$@" 2>/dev/null <<'EOF'
on run argv
  activate
  set theItems to items 4 thru -1 of argv
  set answer to choose from list theItems with title ("PhoneConnect " & item 1 of argv) with prompt (item 2 of argv) default items {item 3 of argv} OK button name "Connect"
  if answer is false then return ""
  return item 1 of answer
end run
EOF
)
  echo "Asked: $1 (${(j:, :)@[3,-1]}) -> ${answer:-Cancel}" >&2
  print -r -- "$answer"
}

for tool in "$APP_TOOLS/adb" "$SCRCPY"; do
  if [[ ! -x "$tool" ]]; then
    echo "$tool not found" >&2
    notify "PhoneConnect: ${tool:t} missing" "PhoneConnect.app is incomplete — reinstall it"
    exit 1
  fi
done
echo "Tools: $("$APP_TOOLS/adb" version 2>&1 | head -1), $("$SCRCPY" --version 2>&1 | head -1)"

# ---- Saved phones ----
# One entry per phone, told apart by its serial number (not the model, since two
# phones can be the same model), with its last known Ethernet and Wi-Fi IPs.
# Most recently used first. The empty id is a phone saved by an older version
# whose serial isn't known yet; it gets its real id on the first connection.
PHONES_FILE="$HOME/.phoneconnect_phones.xml"
OLD_IPS_FILE="$HOME/.phoneconnect_ips"    # older versions: lines "eth <ip>" and "wifi <ip>"
[[ ! -e "$OLD_IPS_FILE" && -e "$HOME/.phone_ips" ]] && mv "$HOME/.phone_ips" "$OLD_IPS_FILE"   # from the old "Phone" app
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

# Run a command but give up after N seconds (macOS has no `timeout` command)
with_timeout() {  # with_timeout SECONDS command...
  local secs=$1; shift
  LOGGED_LABEL="$* (time limit ${secs}s)" logged perl -e 'alarm shift; exec @ARGV' "$secs" "$@"
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
  with_timeout 3 nc -z -G 2 "$1" "$PORT" >/dev/null 2>&1
}

try_connect() {   # try_connect IP  -> sets SERIAL on success
  local i j state
  # Skip quickly if nothing answers there (e.g. the Ethernet IP while undocked);
  # otherwise `adb connect` can hang for over a minute.
  if ! port_open "$1"; then
    echo "  $1 not reachable"
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

# The phone can vanish from USB for a moment (e.g. right after a mode switch)
adb devices -l | grep -q ' usb:' || sleep 2

for usb in ${(f)"$(adb devices -l | awk 'NR>1 && / usb:/ {print $1}')"}; do
  if ! usb_ready "$usb"; then
    echo "USB phone $usb isn't ready (tap Allow on the phone?) — skipping it"
    continue
  fi
  learn_phone "$usb" "$usb"
  USB_OF[$LEARNED_ID]=$usb
  idx=$(phone_index "$LEARNED_ID")
  echo "USB: $LEARNED_NAME ($LEARNED_ID) — saved IPs — Ethernet: ${P_ETH[idx]:-none}, Wi-Fi: ${P_WIFI[idx]:-none}"

  # Turn on network mode for later cable-free launches (only if it isn't on already,
  # because switching it restarts adb on the phone)
  if [[ "$(adb -s "$usb" shell getprop service.adb.tcp.port 2>/dev/null | tr -d '\r')" != "$PORT" ]]; then
    echo "Turning on network mode (port $PORT)"
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
    kind=${line%% *} ip=${line#* }
    [[ $kind == (eth|wifi) && -n "$ip" && "$ip" != "$kind" ]] || continue
    if (( ${P_ETH[(Ie)$ip]} )); then                        # already known from USB
      OLD_OWNER=${OLD_OWNER:-${P_ID[${P_ETH[(Ie)$ip]}]}}; continue
    elif (( ${P_WIFI[(Ie)$ip]} )); then
      OLD_OWNER=${OLD_OWNER:-${P_ID[${P_WIFI[(Ie)$ip]}]}}; continue
    fi
    echo "Checking which phone is at $ip..."
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
  notify "PhoneConnect: no device found" "Plug in the cable once to turn on network mode"
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
    echo "Couldn't reach $name. Plug in the cable once (after each phone restart) to turn on network mode." >&2
    notify "PhoneConnect: can't reach $name" "Plug in the cable once to turn on network mode"
    exit 1
  fi

  # The saved IPs were refreshed while connecting (they may have changed).
  # This is also how the Ethernet IP gets learned: it only exists while the phone
  # is docked, and then there's no USB, so it's read over the Wi-Fi connection.
  # Docked but we came in over Wi-Fi: switch this session to Ethernet
  if [[ -n "$LEARNED_ETH" && "$LINK" != "Ethernet" ]]; then
    PREV_SERIAL=$SERIAL
    echo "Phone has Ethernet ($LEARNED_ETH) — switching to it"
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
choice=$(ask "Play the phone's sound on the Mac?\n\n(While on, the phone's own speaker is muted.)" "No audio" "With audio")
[[ -z "$choice" ]] && exit 0   # Cancel
if [[ "$choice" == "With audio" ]]; then
  AUDIO=()
else
  AUDIO=(--no-audio)
fi

# Bring scrcpy's window to the front: started from a background app, it opens
# behind the other windows. Asks macOS directly (no permission needed), checks it
# worked, and tries again for up to 5 s, since a request made while the window is
# still starting up is ignored.
scrcpy_pid() {    # scrcpy_pid <pid>: the scrcpy process started under it (a few levels down)
  local level p procs=($1) kids
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

bring_to_front() {  # bring_to_front <pid of the background job running scrcpy>
  local spid i front
  spid=$(scrcpy_pid "$1")
  if [[ -z "$spid" ]]; then
    echo "Couldn't find the scrcpy process under pid $1"
    return 1
  fi
  for i in {1..20}; do
    osascript -l JavaScript -e "ObjC.import('AppKit');
      var app = \$.NSRunningApplication.runningApplicationWithProcessIdentifier($spid);
      app.isNil() ? false : app.activateWithOptions(\$.NSApplicationActivateAllWindows | \$.NSApplicationActivateIgnoringOtherApps)" >/dev/null 2>&1
    sleep 0.25
    front=$(lsappinfo info -only pid "$(lsappinfo front)" 2>/dev/null | grep -o 'pid = [0-9]*' | grep -o '[0-9]*$')
    if [[ "$front" == "$spid" ]]; then
      echo "scrcpy window (pid $spid) is in front (try $i)"
      return 0
    fi
  done
  echo "Couldn't bring the scrcpy window (pid $spid) to the front; frontmost is pid ${front:-unknown}"
}

# Start scrcpy and watch it. Over the network it sometimes starts the server on
# the phone and then stalls instead of showing the picture. If no video frame
# arrives within 15 s, kill it, clear the tunnels and retry (up to 3 attempts).
run_scrcpy() {
  local attempt pid ok t rc out="/tmp/PhoneConnect.$$.scrcpy.out"
  local extra=()
  for attempt in 1 2 3; do
    : > "$out"
    echo "Starting (attempt $attempt): scrcpy ${extra[*]} $*"
    # `script` runs scrcpy as if in a terminal, so its messages arrive immediately.
    # Without it they sit in a buffer, the "Texture" (first frame) line shows up
    # too late, and a working session gets killed.
    script -q /dev/null "$SCRCPY" "${extra[@]}" "$@" < /dev/null > >(tee -a "$out" | stamp scrcpy) 2>&1 &
    pid=$!
    ok=0
    for t in {1..15}; do
      grep -aq 'Texture' "$out" 2>/dev/null && { ok=1; break; }  # first frame decoded
      kill -0 $pid 2>/dev/null || break                           # scrcpy exited
      sleep 1
    done
    if (( ok )); then
      echo "Picture is up"
      bring_to_front $pid
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
    pkill -P $pid 2>/dev/null; kill $pid 2>/dev/null; sleep 1
    pkill -9 -P $pid 2>/dev/null; kill -9 $pid 2>/dev/null
    adb -s "$SERIAL" forward --remove-all >/dev/null 2>&1
    adb -s "$SERIAL" reverse --remove-all >/dev/null 2>&1
    extra=(--force-adb-forward)
    sleep 1
  done
  rm -f "$out"
  notify "PhoneConnect: couldn't start" "No picture after 3 tries — see /tmp/PhoneConnect.log"
  exit 1
}

# -V debug: scrcpy's detailed messages, for the log
COMMON=(--video-codec=h265 --max-fps=60 -V debug "${AUDIO[@]}")

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
