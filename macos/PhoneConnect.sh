#!/bin/zsh
# PhoneConnect (macOS) — mirror and control an Android phone with scrcpy.
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

# Started from Launchpad there's no Terminal to show messages, so keep a log
[[ -t 1 ]] || exec > /tmp/PhoneConnect.log 2>&1
echo "PhoneConnect $APP_VERSION ($(date '+%Y-%m-%d %H:%M:%S'))"

# A downloaded app is marked "quarantined" by macOS. Once you've allowed PhoneConnect to
# open, clear that mark from its own files, so the bundled scrcpy and adb don't
# each get blocked with their own "can't be opened" warning.
APP_BUNDLE="${0:A:h:h:h}"
xattr -dr com.apple.quarantine "$APP_BUNDLE" 2>/dev/null

notify() {
  osascript -e "display notification \"$2\" with title \"$1\"" 2>/dev/null
}

# ask "Question" "Button A" "Button B" -> prints the chosen button (empty on Cancel)
ask() {
  local answer
  answer=$(osascript -e "button returned of (display dialog \"$1\" with title \"PhoneConnect $APP_VERSION\" buttons {\"Cancel\", \"$2\", \"$3\"} default button \"$3\" cancel button \"Cancel\")" 2>/dev/null)
  print -r -- "$answer"
}

for tool in adb scrcpy; do
  if ! command -v $tool >/dev/null; then
    echo "$tool not found in $APP_TOOLS" >&2
    notify "PhoneConnect: $tool missing" "PhoneConnect.app is incomplete — reinstall it"
    exit 1
  fi
done

# ---- Pick the connection ----
# Priority: 1. USB   2. Ethernet (dock)   3. Wi-Fi
# While plugged in, the script also reads the phone's Ethernet and Wi-Fi IPs,
# saves both, and turns on network mode, so later launches can connect
# without the cable (until the phone restarts).
PORT=5555
IPS_FILE="$HOME/.phoneconnect_ips"    # lines: "eth <ip>" and "wifi <ip>"
[[ ! -e "$IPS_FILE" && -e "$HOME/.phone_ips" ]] && mv "$HOME/.phone_ips" "$IPS_FILE"   # from the old "Phone" app
SERIAL=""
LINK=""

iface_ip() {      # iface_ip <interface> <adb target args...>
  local ifc=$1; shift
  with_timeout 8 adb "$@" shell ip -f inet addr show $ifc 2>/dev/null \
    | awk '/inet /{print $2}' | cut -d/ -f1 | head -1
}

saved_ip() {      # saved_ip eth|wifi
  awk -v k="$1" '$1==k {print $2; exit}' "$IPS_FILE" 2>/dev/null
}

save_ips() {      # save_ips <eth ip> <wifi ip>  (keeps an old value if a new one is empty)
  local eth=${1:-$(saved_ip eth)} wifi=${2:-$(saved_ip wifi)}
  : > "$IPS_FILE"
  [[ -n "$eth"  ]] && print -r -- "eth $eth"   >> "$IPS_FILE"
  [[ -n "$wifi" ]] && print -r -- "wifi $wifi" >> "$IPS_FILE"
}

usb_ready() {     # wait up to ~10s for the USB connection to be usable
  local i
  for i in {1..10}; do
    [[ "$(adb -d get-state 2>/dev/null)" == "device" ]] && return 0
    sleep 1
  done
  return 1
}

# Run a command but give up after N seconds (macOS has no `timeout` command)
with_timeout() {  # with_timeout SECONDS command...
  perl -e 'alarm shift; exec @ARGV' "$@"
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

# Drop wireless entries that are stuck "offline" (e.g. from an old IP)
adb devices | awk 'NR>1 && $2=="offline" && $1 ~ /:[0-9]+$/ {print $1}' | while read -r d; do
  adb disconnect "$d" >/dev/null 2>&1
done

# The phone can vanish from USB for a moment (e.g. right after a mode switch)
adb devices -l | grep -q ' usb:' || sleep 2

if adb devices -l | grep -q ' usb:'; then
  # ---- 1. USB ----
  usb_ready
  ETH_NOW=$(iface_ip eth0 -d)
  WIFI_NOW=$(iface_ip wlan0 -d)
  save_ips "$ETH_NOW" "$WIFI_NOW"
  echo "Saved IPs — Ethernet: ${ETH_NOW:-none}, Wi-Fi: ${WIFI_NOW:-none}"

  # Turn on network mode for later cable-free launches (only if it isn't on already,
  # because switching it restarts adb on the phone)
  if [[ "$(adb -d shell getprop service.adb.tcp.port 2>/dev/null | tr -d '\r')" != "$PORT" ]]; then
    echo "Turning on network mode (port $PORT)"
    adb -d tcpip $PORT >/dev/null 2>&1
    sleep 3
    usb_ready
  fi

  SERIAL=$(adb -d get-serialno 2>/dev/null)
  LINK="USB"
else
  # ---- 2. Ethernet, 3. Wi-Fi ----
  for kind in eth wifi; do
    ip=$(saved_ip $kind)
    [[ -z "$ip" ]] && continue
    echo "Trying $kind at $ip..."
    if try_connect "$ip"; then
      [[ $kind == eth ]] && LINK="Ethernet" || LINK="Wi-Fi"
      break
    fi
  done

  # Fallback: a phone connected through Android's Wireless debugging (found automatically)
  if [[ -z "$SERIAL" ]]; then
    SERIAL=$(adb devices | awk 'NR>1 && $2=="device" && $1 ~ /_adb-tls-connect\._tcp/ {print $1; exit}')
    [[ -n "$SERIAL" ]] && LINK="Wireless debugging"
  fi

  if [[ -z "$SERIAL" ]]; then
    echo "No phone found. Plug in the cable once (after each phone restart) to turn on network mode." >&2
    notify "PhoneConnect: no device found" "Plug in the cable once to turn on network mode"
    exit 1
  fi

  # Refresh the saved IPs while we're connected (they may have changed).
  # This is also how the Ethernet IP gets learned: it only exists while the phone
  # is docked, and then there's no USB, so it's read over the Wi-Fi connection.
  ETH_NOW=$(iface_ip eth0 -s "$SERIAL")
  save_ips "$ETH_NOW" "$(iface_ip wlan0 -s "$SERIAL")"

  # Docked but we came in over Wi-Fi: switch this session to Ethernet
  if [[ -n "$ETH_NOW" && "$LINK" != "Ethernet" ]]; then
    PREV_SERIAL=$SERIAL
    echo "Phone has Ethernet ($ETH_NOW) — switching to it"
    if try_connect "$ETH_NOW"; then
      LINK="Ethernet"
    else
      SERIAL=$PREV_SERIAL
      echo "Ethernet not reachable, staying on $LINK"
    fi
  fi
fi

CONN=(-s "$SERIAL")
echo "Connection: $LINK ($SERIAL)"

# ---- Look for a DeX (external) display: any display other than 0 ----
DEX_ID=$(scrcpy "${CONN[@]}" --list-displays 2>&1 \
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

# Start scrcpy and watch it. Over the network it sometimes starts the server on
# the phone and then stalls instead of showing the picture. If no video frame
# arrives within 15 s, kill it, clear the tunnels and retry (up to 3 attempts).
run_scrcpy() {
  local attempt pid ok t out=/tmp/PhoneConnect.scrcpy.out
  local extra=()
  for attempt in 1 2 3; do
    : > "$out"
    # `script` runs scrcpy as if in a terminal, so its messages arrive immediately.
    # Without it they sit in a buffer, the "Texture" (first frame) line shows up
    # too late, and a working session gets killed.
    script -q /dev/null scrcpy "${extra[@]}" "$@" < /dev/null > >(tee -a "$out") 2>&1 &
    pid=$!
    ok=0
    for t in {1..15}; do
      grep -aq 'Texture' "$out" 2>/dev/null && { ok=1; break; }  # first frame decoded
      kill -0 $pid 2>/dev/null || break                           # scrcpy exited
      sleep 1
    done
    if (( ok )); then
      wait $pid
      exit $?
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
  notify "PhoneConnect: couldn't start" "No picture after 3 tries — see /tmp/PhoneConnect.log"
  exit 1
}

COMMON=(--video-codec=h265 --max-fps=60 "${AUDIO[@]}")

if [[ "$TARGET" == "dex" ]]; then
  echo "Mirroring DeX (display $DEX_ID), audio: $choice"
  run_scrcpy "${CONN[@]}" -K --display-id="$DEX_ID" "${COMMON[@]}" \
    --video-bit-rate=8M --window-title="PhoneConnect — DeX ($LINK)" "$@"
else
  echo "Mirroring phone screen, audio: $choice"
  run_scrcpy "${CONN[@]}" -K "${COMMON[@]}" \
    --max-size=1600 --video-bit-rate=6M \
    --window-title="PhoneConnect ($LINK)" "$@"
fi
