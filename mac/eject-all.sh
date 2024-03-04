#!/bin/bash
# Eject all external, physical drives.
# Source: https://apple.stackexchange.com/a/394594/6278
# Prerequisites: brew install terminal-notifier

set -euo pipefail
shopt -s failglob
# shellcheck disable=SC2317
function trap_err { echo "ERR signal on line $(caller)" >&2; }
trap trap_err ERR
trap exit INT
export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

#### Utils

function notify {
    echo "$*"
    if [[ ! -t 1 ]]; then
        command -v terminal-notifier &>/dev/null &&
            terminal-notifier -title eject-all -message "$*"
    fi
}

#### Init

# To find diskutil
export PATH=/usr/sbin:$PATH

#### Main

disks=$(list external physical | sed -n 's/^\([^[:space:]]*\)[[:space:]].*external, physical.*$/\1/p')

if [[ -n "$disks" ]]; then
    fail=0
    while read -r disk ; do
        diskutil eject "$disk" || (( fail++ ))
    done <<< "$disks"
    if (( fail > 0 )); then
        notify "❌ Failed to eject $fail disk(s)."
        exit 1
    else
        notify "✅ Done."
    fi
else
    notify "✅ No disks to eject."
fi
