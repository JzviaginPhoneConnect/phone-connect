# PhoneConnect platform layer, macOS: paths and tools (sourced by PhoneConnect.sh).
# Layout: PhoneConnect.app/Contents/MacOS/{PhoneConnect (launcher), PhoneConnect.sh, platform/}
#         PhoneConnect.app/Contents/Resources/tools/{arm64,x86_64}/

PLATFORM_DIR=${${(%):-%x}:A:h}
APP_BUNDLE=${PLATFORM_DIR:h:h:h}
case "$(uname -m)" in
  arm64) MAC_ARCH=arm64 ;;     # Apple Silicon
  *)     MAC_ARCH=x86_64 ;;    # Intel
esac
TOOLS_DIR="$APP_BUNDLE/Contents/Resources/tools/$MAC_ARCH"
export PATH="$TOOLS_DIR:/usr/bin:/bin:/usr/sbin:/sbin"
export ADB="$TOOLS_DIR/adb"                          # the adb scrcpy should use
export SCRCPY_SERVER_PATH="$TOOLS_DIR/scrcpy-server"  # the part that runs on the phone
# scrcpy sits in a small app bundle of its own, so its window gets the PhoneConnect
# name and icon in the Dock (a bare program gets the generic "exec" icon)
export SCRCPY="$TOOLS_DIR/PhoneConnect Mirror.app/Contents/MacOS/scrcpy"

PHONES_FILE="$HOME/.phoneconnect_phones.xml"
TASKS_FILE="$HOME/.phoneconnect_tasks.xml"   # things still to do on phones
OLD_IPS_FILE="$HOME/.phoneconnect_ips"    # older versions: lines "eth <ip>" and "wifi <ip>"
[[ ! -e "$OLD_IPS_FILE" && -e "$HOME/.phone_ips" ]] && mv "$HOME/.phone_ips" "$OLD_IPS_FILE"   # from the old "Phone" app
LOG_FILE=/tmp/PhoneConnect.log
export TMPDIR=${TMPDIR:-/tmp}
OS_INFO="macOS $(sw_vers -productVersion) ($MAC_ARCH)"
# what to do when the computer blocks PhoneConnect from the local network (adb gets
# "No route to host" where the phone answers)
NETWORK_BLOCKED_HELP="Turn on PhoneConnect in System Settings → Privacy & Security → Local Network, then open PhoneConnect again."
