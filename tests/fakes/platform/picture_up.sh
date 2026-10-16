#!/bin/zsh -f
# Fake: the fake scrcpy prints "Texture" when it "shows the picture"
grep -aq 'Texture' "$2" 2>/dev/null
