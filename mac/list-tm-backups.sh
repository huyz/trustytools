#!/usr/bin/env bash
# Lists the backups made by Time Machine

# For readarray
[ "${BASH_VERSINFO:-0}" -ge 4 ] || { echo "${BASH_SOURCE[0]}: Error: bash v4+ required." >&2; exit 1; }

#### Preamble (template v2023-01-31)

set -euo pipefail
shopt -s failglob
# shellcheck disable=SC2317
function trap_err { echo "ERR signal on line $(caller)" >&2; }
trap trap_err ERR
trap exit INT
export PS4='+(BASH_SOURCE:LINENO): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

if [[ $EUID -eq 0 ]]; then
    [ -x "${GETOPT:=/opt/local/bin/getopt}" ] || \
        { echo "$0: Error: \`sudo port install util-linux\` to install $GETOPT." >&2; exit 1; }
else
    HOMEBREW_PREFIX="$( (/opt/homebrew/bin/brew --prefix || /usr/local/bin/brew --prefix || brew --prefix) 2>/dev/null)"
    [ -x "${GETOPT:="$HOMEBREW_PREFIX/opt/util-linux/bin/getopt"}" ] || \
        { echo "$0: Error: \`brew install util-linux\` to install $GETOPT." >&2; exit 1; }
fi

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

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


#### Main

# Force network backup mount (necessary if your TM backups are through the network)
tmutil listbackups &>/dev/null || true

readarray -t destinations < <(tmutil destinationinfo | sed -n 's/^Mount Point *: *\(.*\)/\1/p')

if [[ -z ${destinations+x} ]]; then
    tmutil destinationinfo
    exit
fi

for mountpoint in "${destinations[@]}"; do
    echo "--- ${mountpoint/\/Volumes\//} ---"
    (tmutil listbackups -d "$mountpoint" -m || true) | while read -r backup; do
        time="$(sed -n 's,.*/\(.*\)\.backup$,\1,p' <<<"$backup")"
        size="$(tmutil uniquesize "$backup" | awk '{print $1}')"
        printf "%s %8s\n" "$time" "$size"
    done | tail -n "${opt_lines:-99999}"
    echo
done
