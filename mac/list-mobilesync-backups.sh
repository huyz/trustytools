#!/bin/bash
# 2020-12-06 Lists the names and dates of the iTunes backups of iOS/iPadOS
#   devices
# Usage: -v for verbose mode (displays size)

set -euo pipefail
shopt -s failglob
trap exit INT


#### Config

DIR=~/"Library/Application Support/MobileSync/Backup"

#### Args

opt_verbose=
opt_utc=

while [[ $# -gt 0 ]]; do
    case "$1" in
        -u)
            opt_utc=opt_utc
            shift
            ;;
        -v)
            opt_verbose=opt_verbose
            shift
            ;;
        *)
            echo "Usage: $0 [-v] [-u]" >&2
            echo "   -v: verbose mode (displays size)" >&2
            echo "   -u: UTC time zone" >&2
            exit 1
            ;;
    esac
done

#### Main

cd "$DIR"

(
    if [[ -n $opt_verbose ]]; then
        echo "Directory|Device|Date|Size|Volume"
        echo "---------|------|----|----|------"
    else
        echo "Directory|Device|Date|Volume"
        echo "---------|------|----|------"
    fi

    # shellcheck disable=SC2012
    ls -1dt ./[0-9a-f]*/. | while read -r i; do
        i="$(dirname "$i")"
        if [[ ! -e "$i/Info.plist" ]]; then
            # Allow user to create Info.plist.is.missing to stop the warnings
            [[ ! -e "$i/Info.plist.is.missing" ]] &&
                echo "error: Can't find file $i/Info.plist" >&2
            continue
        fi
        name="$(plutil -p "$i/Info.plist" | sed -n 's/.*Device Name.*"\(.*\)"$/\1/p')"
        date="$(
            [[ -n $opt_utc ]] && export TZ=''
            stat -f "%Sm" -t "%Y-%m-%dT%H:%M%z" "$i/Info.plist" 2>/dev/null | sed 's/+0000/Z/')"
        vol="$(df "$i" | sed -n '2s,/Volumes/,,;2s/.*%[[:space:]]*//p')"
        printf "%s|%s|%s" "$i" "$name" "$date"

        if [[ -n $opt_verbose ]]; then
            size="$(du -shH "$i" | cut -f1)"
            printf "|%s" "$size"
        fi
        printf "|%s\n" "$vol"
    done
) | column -t -s '|'
