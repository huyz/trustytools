#!/bin/bash
# Source: https://apple.stackexchange.com/a/394594/6278
# Prerequisites: brew install terminal-notifier

set -euo pipefail
shopt -s failglob
trap 'echo "ERR signal on line $(caller)" >&2' ERR
trap exit INT
export PS4='+(BASH_SOURCE:LINENO): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

#### Utils

function notify {
    echo "$*"
    if [[ ! -t 1 ]]; then
        command -v terminal-notifier &>/dev/null &&
            terminal-notifier -title eject-all -message "$*"
    fi
}

#### Main

#script to eject all external drives
disks=$(diskutil list external | sed -n '/[Ss]cheme/s/.*B *//p')

if [ "$disks" ]; then
    fail=0
    echo "$disks" | while read -r line ; do
        diskutil unmountDisk "/dev/$line" || (( fail++ ))
    done
    if (( fail > 0 )); then
        notify "❌ Failed to eject $fail disk(s)."
        exit 1
    else
        notify "✅ Done."
    fi
else
    notify "✅ No disks to eject."
fi
