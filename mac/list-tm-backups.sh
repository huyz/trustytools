#!/usr/bin/env bash
# Lists the backups made by Time Machine

# For readarray
[ "${BASH_VERSINFO:-0}" -ge 4 ] || { echo "${BASH_SOURCE[0]}: Error: bash v4+ required." >&2; exit 1; }

#### Preamble (v2023-10-01)

set -euo pipefail
shopt -s failglob
# shellcheck disable=SC2317
function trap_err { echo "ERR signal on line $(caller)" >&2; }
trap trap_err ERR
trap exit INT
export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

if [[ $OSTYPE == darwin* ]]; then
    if [[ "${EUID:-$UID}" -eq 0 ]]; then
        [ -x "${REALPATH:=/opt/local/bin/grealpath}" ] || \
            { echo "$0: Error: \`sudo port install coreutils\` to install $REALPATH." >&2; exit 1; }
        [ -x "${DATE:=/opt/local/bin/gdate}" ] || \
            { echo "$0: Error: \`sudo port install coreutils\` to install $DATE." >&2; exit 1; }
        [ -x "${GETOPT:=/opt/local/bin/getopt}" ] || \
            { echo "$0: Error: \`sudo port install util-linux\` to install $GETOPT." >&2; exit 1; }
    else
        HOMEBREW_PREFIX="$( (/opt/homebrew/bin/brew --prefix || /usr/local/bin/brew --prefix || brew --prefix) 2>/dev/null)"
        [ -x "${REALPATH:="$HOMEBREW_PREFIX/bin/grealpath"}" ] || \
            { echo "$0: Error: \`brew install coreutils\` to install $REALPATH." >&2; exit 1; }
        [ -x "${DATE:="$HOMEBREW_PREFIX/bin/gdate"}" ] || \
            { echo "$0: Error: \`brew install coreutils\` to install $DATE." >&2; exit 1; }
        [ -x "${GETOPT:="$HOMEBREW_PREFIX/opt/gnu-getopt/bin/getopt"}" ] || \
            { echo "$0: Error: \`brew install gnu-getopt\` to install $GETOPT." >&2; exit 1; }
    fi
else
    HOMEBREW_PREFIX="$( (/home/linuxbrew/.linuxbrew/bin/brew --prefix || brew --prefix) 2>/dev/null)"
    REALPATH="realpath"
    DATE="date"
    GETOPT="getopt"
fi

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
#SCRIPT="$($REALPATH "${BASH_SOURCE[0]}")"
#SCRIPT_DIR="$(dirname "$SCRIPT")"

#### Options

function usage {
    cat <<END >&2
Usage: $SCRIPT_NAME [-h|--help] [-n NUM | --lines NUM]
        -h | --help : get help
        -n NUM | --lines NUM : (like \`tail\`) output the last NUM lines for each volume
END
    exit 1
}

# Defaults
opt_lines=

opts=$($GETOPT --options hn: --long help,lines: --name "$SCRIPT_NAME" -- "$@") || usage
eval set -- "$opts"

while true; do
    case "$1" in
        -h | --help) usage ;;
        -n | --lines) opt_lines="$2"; shift 2 ;;
        --) shift; break ;;
        *) echo "$SCRIPT_NAME: Internal error: unrecognized option '$1'" >&2; exit 1 ;;
    esac
done

#### Arguments

[[ $# -eq 0 ]] || usage

##############################################################################
#### Util

function colored_icon {
    local icon timestamp_ts="$1"

    if [[ "$timestamp_ts" -gt "$($DATE -d '36 hours ago' +%s)" ]]; then
        icon="🟢"
    elif [[ "$timestamp_ts" -gt "$($DATE -d '7 days ago' +%s)" ]]; then
        icon="🟡"
    elif [[ "$timestamp_ts" -gt "$($DATE -d '30 days ago' +%s)" ]]; then
        icon="🟠"
    else
        icon="🔴"
    fi
    echo "$icon"
}

##############################################################################
#### Main

# Force network backup mount (necessary if your TM backups are through the network)
tmutil listbackups &>/dev/null || true

readarray -t destinations < <(tmutil destinationinfo | sed -n 's/^Mount Point *: *\(.*\)/\1/p')

if [[ -z ${destinations+x} ]]; then
    printf "No volumes mounted.\n\n"
    tmutil destinationinfo
    exit
fi

for mountpoint in "${destinations[@]}"; do
    echo "--- ${mountpoint/\/Volumes\//} ---"
    (tmutil listbackups -d "$mountpoint" -m || true) | while read -r backup; do
        # Convert from weird format to ISO 8601
        timestamp="$(sed -n 's,.*/\(.*\)\.backup$,\1,p' <<<"$backup" \
            | perl -pe 's/^(\d{4}-\d{2}-\d{2})-(\d{2})(\d{2})(\d{2})$/$1T$2:$3/')"
        timestamp_ts="$(TZ=America/Los_Angeles $DATE -d "$timestamp" +%s)"
        # Remove the `:` between hour and minute to save space
        timestamp="$(TZ=America/Los_Angeles $DATE -d "$timestamp" +%FT%H%M)"

        size="$(tmutil uniquesize "$backup" | awk '{print $1}')"

        printf "%s %s %7s\n" "$(colored_icon "$timestamp_ts")" "$timestamp" "$size"
    done | tail -n "${opt_lines:-99999}"
    echo
done
