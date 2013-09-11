#!/bin/sh
# $RCSfile: unln,v $ $Revision: 1.3 $ $Date: 2003/11/21 00:06:29 $
# Replaces a symlink with a real copy

# NOTE: we cannot use a tmp folder as intermediary because we can't move
# from different devices
for i in "$@"; do cp -p "$i" .$$ && mv -f .$$ "$i"; done
