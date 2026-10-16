#!/bin/zsh -f
# Fake: an IP answers if it's in $FAKE/net
grep -q "^$1|" $FAKE/net
