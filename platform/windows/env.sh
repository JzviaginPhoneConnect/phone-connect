# PhoneConnect platform layer, Windows: paths and tools (sourced by PhoneConnect.sh).
# Layout: {app}\PhoneConnect.exe, PhoneConnect.sh, platform\, tools\ (scrcpy, adb),
#         shell\usr\bin\ (the zsh and tools this runs on, from MSYS2)
# Paths here are in MSYS form (/c/Users/...); the ones handed to Windows programs
# (scrcpy reads ADB and SCRCPY_SERVER_PATH) are converted with cygpath -m (C:/Users/...).

PLATFORM_DIR=${${(%):-%x}:A:h}
APP_DIR=${PLATFORM_DIR:h}
TOOLS_DIR="$APP_DIR/tools"
export MSYS2_ARG_CONV_EXCL='*'     # pass arguments to Windows programs exactly as given
export LANG=C.UTF-8
export PATH="$TOOLS_DIR:$APP_DIR/shell/usr/bin:$PATH"
export ADB="$(cygpath -m "$TOOLS_DIR/adb.exe")"                       # the adb scrcpy should use
export SCRCPY_SERVER_PATH="$(cygpath -m "$TOOLS_DIR/scrcpy-server")"  # the part that runs on the phone
export SCRCPY="$TOOLS_DIR/scrcpy.exe"
export PC_APP_DIR="$(cygpath -w "$APP_DIR")"    # for the dialogs' window icon (PhoneConnect.ico)

DATA_DIR="$(cygpath -u "$APPDATA")/PhoneConnect"
mkdir -p "$DATA_DIR"
PHONES_FILE="$DATA_DIR/phones.xml"
TASKS_FILE="$DATA_DIR/tasks.xml"    # things still to do on phones
OLD_IPS_FILE="$DATA_DIR/ips.txt"    # older versions: lines "eth <ip>" and "wifi <ip>"
export TMPDIR="$(cygpath -u "$TEMP")"
export TMPPREFIX="$TMPDIR/zsh"     # zsh's own temporary files (here-documents)
LOG_FILE="$TMPDIR/PhoneConnect.log"
OS_INFO="Windows ${$(uname -s)#*_NT-} (${PROCESSOR_ARCHITEW6432:-$PROCESSOR_ARCHITECTURE})"
# what to do when the computer blocks PhoneConnect from the local network (adb gets
# "No route to host" where the phone answers)
NETWORK_BLOCKED_HELP="Allow PhoneConnect (adb.exe) in Windows Firewall or your security software, then open PhoneConnect again."
