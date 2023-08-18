#!/usr/bin/env bash
# Lists the backups made by Time Machine

# For readarray
[ "${BASH_VERSINFO:-0}" -ge 4 ] || { echo "${BASH_SOURCE[0]}: Error: bash v4+ required." >&2; exit 1; }

set -euo pipefail
shopt -s failglob
trap exit INT

# Force network backup mount (necessary if your TM backups are through the network)
tmutil listbackups &>/dev/null

readarray -t destinations < <(tmutil destinationinfo | sed -n 's/^Mount Point *: *\(.*\)/\1/p')

if [[ -z ${destinations+x} ]]; then
    tmutil destinationinfo
    exit
fi

for mountpoint in "${destinations[@]}"; do
    echo "--- $mountpoint ---"
    tmutil listbackups -d "$mountpoint" -m | while read -r backup; do
        time="$(sed -n 's,.*/\(.*\)\.backup$,\1,p' <<<"$backup")"
        size="$(tmutil uniquesize "$backup" | awk '{print $1}')"
        printf "%s %8s\n" "$time" "$size"
    done
    echo
done
