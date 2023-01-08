#!/bin/bash
# 2020-12-06 Lists the names and dates of the iTunes backups of iOS/iPadOS
#   devices

set -euo pipefail
shopt -s failglob
trap exit INT


DIR=~/"Library/Application Support/iMobie/Backup"

cd "$DIR"

ls -1dt ./[0-9a-f]*/. | while read -r i; do
    i="$(dirname "$i")"
    if [[ ! -e "$i/Info.plist" ]]; then
        # Allow user to create Info.plist.is.missing to stop the warnings
        [[ ! -e "$i/Info.plist.is.missing" ]] &&
            echo "error: Can't find file $i/Info.plist" >&2
        continue
    fi
    name="$(plutil -p "$i/Info.plist" | sed -n 's/.*Device Name.*"\(.*\)"$/\1/p')"
    date="$(stat -x "$i/Info.plist" 2>/dev/null | sed -n 's/^Modify:[[:space:]]*//p')"
    echo "$i|$name|$date"
done | column -t -s '|'
