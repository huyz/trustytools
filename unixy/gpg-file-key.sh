#!/bin/sh
# huy 2013-10-09
# Lists the keys used to encrypt the specified GPG files

for i in "$@"; do 
  echo "$i: \t\c"
  key=$(gpg --batch --list-only --decrypt --status-fd 1 $i 2>/dev/null | awk '/^\[GNUPG:\] ENC_TO / { print $3 }')
  gpg --list-keys "$key" | sed -n 's/uid[[:space:]]*//p'
done
