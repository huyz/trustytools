#!/bin/bash
# Displays biggest objects in git repo

#### Preamble (template v2023-01-31)

set -euo pipefail
shopt -s failglob
# shellcheck disable=SC2317
function trap_err { echo "ERR signal on line $(caller)" >&2; }
trap trap_err ERR
trap exit INT
export PS4='+(BASH_SOURCE:LINENO): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

if [[ $OSTYPE == darwin* ]]; then
    if [[ $EUID -eq 0 ]]; then
        [ -x "${REALPATH:=/opt/local/bin/grealpath}" ] || \
            { echo "$0: Error: \`sudo port install coreutils\` to install $REALPATH." >&2; exit 1; }
    else
        HOMEBREW_PREFIX="$( (/opt/homebrew/bin/brew --prefix || /usr/local/bin/brew --prefix || brew --prefix) 2>/dev/null)"
        [ -x "${REALPATH:="$HOMEBREW_PREFIX/bin/grealpath"}" ] || \
            { echo "$0: Error: \`brew install coreutils\` to install $REALPATH." >&2; exit 1; }
    fi
else
    REALPATH="realpath"
fi

#SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
#SCRIPT="$($REALPATH -s "${BASH_SOURCE[0]}")"
#SCRIPT_DIR="$(dirname "$SCRIPT")"


#### Main

echo "𐄫 Analyzing…" >&2

objects="$(git rev-list --objects --all)"
git verify-pack -v .git/objects/pack/*.idx | sort -k 3 -n -r |
    while read -r line; do
        sha="$(cut -d' ' -f 1 <<< "$line")"
        output="$(<<<"$line" rev | cut -d' ' -f2- | rev)"
        filename="$(grep "^$sha" <<<"$objects" | cut -d' ' -f 2)"
        echo "$output $filename"
    done | less
