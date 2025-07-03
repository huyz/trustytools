#!/bin/bash
# "Portable" version of `column` that supports both util-linux and BSD syntax by converting or
# dropping flags as needed

#### Preamble (v2025-02-09)

set -euo pipefail
shopt -s failglob
# shellcheck disable=SC2317
function trap_err { echo "$(basename "${BASH_SOURCE[0]}"): ERR signal on line $(caller)" >&2; }
trap trap_err ERR
trap exit INT  # So that ^C will stop the entire script, not just the current subprocess
export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

# shellcheck disable=SC2034
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
script="${BASH_SOURCE[0]}"
while [[ -L "$script" ]]; do
    script="$(readlink "$script")"
done
# shellcheck disable=SC2034
SCRIPT_DIR="$(dirname "$script")"

##############################################################################
#### Main

args=()

# Check version output
if ! command column --version 2>/dev/null | grep -q 'util-linux'; then
    # Go through all the util-linux flags and remove those except for `-t`, `-x`, `-c`, and `-s`
    # along with their parameters if applicable.
    skip_next=

    for arg in "${@}"; do
        if [[ -n $skip_next ]]; then
            skip_next=
            continue
        fi

        case "$arg" in
        # Flags that take an argument
        -o|--output-separator|-S|--use-spaces|-C|--table-column|-N|--table-columns|-l|--table-columns-list|-R|--table-right|-T|--table-truncate|-E|--table-noextreme|-W|--table-wrap|-H|--table-hide|-O|--table-order|-n|--table-name|-r|--tree|-i|--tree-id|-p|--tree-parent)
            skip_next=1
            ;;

        # Flags that need to be mapped to their BSD equivalents
        -x|--fillrows) args+=("-x") ;;
        -t|--table) args+=("-t") ;;
        -c|--output-width) args+=("-c") ;;
        -s|--separator) args+=("-s") ;;

        # Assume all other flags do not take an argument
        -*) ;;

        *)
            args+=("$arg")
            ;;
        esac
    done
    set -- "${args[@]}"
fi

exec column "$@"
