#!/bin/bash
# Quits an app if it's running
# If the name of the app has two or more dots, it's assumed to be the bundle identifier.

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
Usage: $SCRIPT_NAME [-h|--help] [-d|--debug] [-n|--dry-run] [-y|--yes] [-p|--prompt prompt] app...
        -h|--help: get help
        -d|--debug: turn on debug mode
        -n|--dry-run: do not make any modifications
        -y|--yes: auto-confirm (do not prompt)
        -p prompt|--prompt prompt: string to display to confirm whether to quit the app
            (without a question mark; app name will be appended before question mark)
            Default: "Quit app"
END
    exit 1
}

# Defaults
opt_debug=
opt_dry_run=
opt_yes=
opt_prompt="Quit app"

opts=$($GETOPT --options hdnyp: --long help,debug,dry-run,yes,prompt: --name "$SCRIPT_NAME" -- "$@") || usage
eval set -- "$opts"

while true; do
    case "$1" in
        -h | --help) usage ;;
        -d | --debug) opt_debug=opt_debug; shift ;;
        -n | --dry-run) opt_dry_run=opt_dry_run; shift ;;
        -y | --yes) opt_yes=opt_yes; shift ;;
        -p | --prompt) opt_prompt="$2"; shift 2 ;;
        --) shift; break ;;
        *) echo "$SCRIPT_NAME: Internal error: unrecognized option '$1'" >&2; exit 1 ;;
    esac
done

#### Arguments

[[ $# -gt 0 ]] || usage

#### Utils

function confirm {
    local message="Quit"
    if [[ "$1" == -p ]]; then
        message="$2"
        shift 2
    fi
    if [[ -n $opt_yes ]]; then
        REPLY=yes
    else
        read -rp "$message? [Y/n]" -n 1
        echo
    fi
    case "$REPLY" in
        n|N)
            # Must return successful exit code to not abort the script
            return 0
            ;;
        *)
            "$@"
            return $?
            ;;
    esac
}

#### Main



for app in "$@"; do
    [[ -n $opt_debug ]] && echo "𐄫 Checking app ${app}…"
    if is-app-running "$app"; then
        if [[ "$app" == *.*.* ]]; then
            property="id"
        else
            property=""
        fi

        if [[ -n $opt_dry_run ]]; then
            confirm -p "$opt_prompt $app" echo "⋱ would have run: osascript -e \"quit app $property \\\"$app\\\"\""
        else
            confirm -p "$opt_prompt $app" osascript -e "quit app $property \"$app\"" || true
        fi
    fi
done
