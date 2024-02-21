#!/bin/bash
# Usage: eject [-a] VOLUME…
#   -a to eject all the other volumes on the same physical disks of the specified VOLUMEs

set -euo pipefail
shopt -s failglob
# shellcheck disable=SC2317
function trap_err { echo "ERR signal on line $(caller)" >&2; }
trap trap_err ERR
trap exit INT
export PS4='+(BASH_SOURCE:LINENO): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

#### Arguments

if [[ $# -eq 0 ]]; then
    echo "Usage: $SCRIPT_NAME VOLUME…" >&2
    exit 1
fi

opt_all=
if [[ $1 == -a ]]; then
    shift
    opt_all=1
fi

#### Main

for name in "$@"; do
    for dev in $(mount | sed -n "s,^\\(/dev/[^[:space:]]*\\)[[:space:]][[:space:]]*on[[:space:]][[:space:]]*/Volumes/${name} (.*),\\1,p"); do
        if [[ -n $opt_all ]]; then
            dev="${dev%s?}"
        fi
        echo hdiutil eject "$dev"
        hdiutil eject "$dev"
    done
done
