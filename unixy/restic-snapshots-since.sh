#!/usr/bin/env bash
# List the snapshots IDs that are newer than the given date (using GNU date expression,
# which supports "X days ago")

# If this script must be run as root
# '-HE' because we want to inherit the $RESTIC_*jj vars from the regular user
[ $EUID -eq 0 ] || exec sudo -HE "$BASH" "$0" "$@"

#### Preamble (v2025-08-22)

set -euo pipefail
shopt -s failglob
# shellcheck disable=SC2329
function trap_err { echo "$(basename "${BASH_SOURCE[0]}"): ERR signal on line $(caller)" >&2; }
trap trap_err ERR
trap exit INT  # So that ^C will stop the entire script, not just the current subprocess
export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

_install_cmd='brew install'
if [[ $OSTYPE == darwin* ]]; then
    HOMEBREW_PREFIX="$( (/opt/homebrew/bin/brew --prefix || /usr/local/bin/brew --prefix || brew --prefix) 2>/dev/null)"
    MAC_PREFIX="$HOMEBREW_PREFIX"
    [[ -x "${GETOPT:="$MAC_PREFIX/opt/gnu-getopt/bin/getopt"}" ]] || \
        { echo "$0: ERROR: \`$_install_cmd gnu-getopt\` to install $GETOPT." >&2; exit 1; }
#        [[ -x "${SED:="$MAC_PREFIX/bin/gsed"}" ]] || \
#            { echo "$0: ERROR: \`$_install_cmd gnu-sed\` to install $SED." >&2; exit 1; }
    [[ -x "${REALPATH:="$MAC_PREFIX/bin/grealpath"}" ]] || \
        { echo "$0: ERROR: \`$_install_cmd coreutils\` to install $REALPATH." >&2; exit 1; }
    DATE="gdate"         # also coreutils
    command -v "${JQ:=jq}" &>/dev/null || \
        { echo "$0: ERROR: \`$_install_cmd jq\` to install $JQ." >&2; exit 1; }
else
    HOMEBREW_PREFIX="$( (/home/linuxbrew/.linuxbrew/bin/brew --prefix || brew --prefix) 2>/dev/null)"
    GETOPT="getopt"
    REALPATH="realpath"
    DATE="date"
    JQ="jq"
fi


SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

##############################################################################
#### Main

function usage {
    echo "Usage: $SCRIPT_NAME <GNU date expression>" >&2
    echo "       $SCRIPT_NAME '2026-06-13T17:52:20-07:00'" >&2
    echo "       $SCRIPT_NAME '1 month ago'" >&2
    exit 1
}

if [[ $# -ne 1 || "$1" == -h || "$1" == --help ]]; then
    usage
fi

cutoff=$($DATE -d "$1" +%s)

restic snapshots --json | jq -r --argjson cutoff "$cutoff" '
    .[] |
    select(
        (
        .time
        | sub("\\.[0-9]+"; "")
        | sub("(?<hh>[+-][0-9]{2}):(?<mm>[0-9]{2})$"; "\(.hh)\(.mm)")
        | strptime("%Y-%m-%dT%H:%M:%S%z")
        | mktime
        ) >= $cutoff
    ) |
    .id
'
