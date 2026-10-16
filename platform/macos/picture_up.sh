#!/bin/zsh
# picture_up.sh PID OUTPUT_FILE — succeeds once scrcpy shows the picture:
# scrcpy prints a "Texture" line when the first frame is decoded
grep -aq 'Texture' "$2" 2>/dev/null
