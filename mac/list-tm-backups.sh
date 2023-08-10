#!/usr/bin/env bash
# Lists the TM backups on

# For readarray
[ "${BASH_VERSINFO:-0}" -ge 4 ] || { echo "${BASH_SOURCE[0]}: Error: bash v4+ required." >&2; exit 1; }

set -euo pipefail
shopt -s failglob
trap exit INT

readarray -t destinations < <(tmutil destinationinfo | sed -n 's/^Mount Point *: *\(.*\)/\1/p')

if [[ -z ${destinations+x} ]]; then
    tmutil destinationinfo
    exit
fi

for mountpoint in "${destinations[@]}"; do
    echo "--- $mountpoint ---"
    tmutil listbackups -d "$mountpoint"
    echo
done
