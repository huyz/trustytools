#!/bin/bash
# Return success if given app is running

set -euo pipefail
shopt -s failglob
# shellcheck disable=SC2317
function trap_err { echo "ERR signal on line $(caller)" >&2; }
trap trap_err ERR
trap exit INT
export PS4='+(BASH_SOURCE:LINENO): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

#### Arguments

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <app>" >&2
    exit 1
fi

#### Main

app="$1"

if osascript -e "tell application \"System Events\" to (name of processes) contains \"$app\"" | grep -q 'true'; then
    exit 0
else
    exit 1
fi

# Alternative implementation:
#if osascript -e "
#tell application \"System Events\"
#    if (name of processes) contains \"$app\"
#        error number 0
#    else
#        error number -1
#    end if
#end tell
#" 2>&1 >/dev/null | grep -qF -- '(-1)'; then
#    exit 1
#else
#    exit 0
#fi
