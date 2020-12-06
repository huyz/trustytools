#!/bin/bash
# 2020-12-06 Lists the names and dates of the iTunes backups of iOS/iPadOS
#   devices

set -euo pipefail
shopt -s failglob


DIR=~/"Library/Application Support/MobileSync/Backup"


cd "$DIR"

ls -1dt ./*/. | while read -r i; do
  i="$(dirname "$i")"
  name="$(plutil -p "$i/Info.plist" | sed -n 's/.*Device Name.*"\(.*\)"$/\1/p')"
  date="$(stat -x "$i/Info.plist" 2>/dev/null | sed -n 's/^Modify:[[:space:]]*//p')"
  echo "$i|$name|$date"
done | column -t -s '|'
