#!/bin/sh
# Filename:         clfu.sh
# Version:          0.1
# Description:
#   On OS X, eject a removable disk by volume name
#
# Platforms:        OS X
# Author:           Huy Z, http://huyzing.com/
# Created on:       2011-01-23
#
# Usage:
#   osxeject "volume name" ...

if [ $# -eq 0 ]; then
    echo "Usage: $0 \"Volume Name\" ..."
    exit 1
fi

for i in "$@"; do
  for j in $(mount | sed -n "s,^\\(/dev/[^ 	]*\\)[ 	][ 	]*on[ 	][ 	]*/Volumes/$i[ 	]*.*,\\1,p"); do
    hdiutil eject "$j"
  done
done
