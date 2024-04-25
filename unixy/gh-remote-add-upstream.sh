#!/usr/bin/env bash
# Adds the upstream repo as a remote to your local checkout, if the origin
# is already configured.
#
# Usage: gh-remote-add-upstream [-t] [-f]
#   -t|--tags  : imports every tag from the upstream repo
#   -f|--force : overwrite any existing upstream (and its remote-tracking
#                branches and configuration settings)
#

# When debugging
#set -x

#### Preamble (v2024-04-22)

# Check for bash 4 for `readarray`
[ "${BASH_VERSINFO:-0}" -ge 4 ] || { echo "${BASH_SOURCE[0]}: Error: bash v4+ required." >&2; exit 1; }

set -euo pipefail
shopt -s failglob
# shellcheck disable=SC2317
function trap_err { echo "ERR signal on line $(caller)" >&2; }
trap trap_err ERR
trap exit INT
export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

if [[ $OSTYPE == darwin* ]]; then
    if [[ "${EUID:-$UID}" -eq 0 ]]; then
        MAC_PREFIX=/opt/local
        [[ -x "${REALPATH:="$MAC_PREFIX/bin/grealpath"}" ]] || \
            { echo "$0: Error: \`sudo port install coreutils\` to install $REALPATH." >&2; exit 1; }
        [[ -x "${GETOPT:=/opt/local/bin/getopt}" ]] || \
            { echo "$0: Error: \`sudo port install util-linux\` to install $GETOPT." >&2; exit 1; }
        [[ -x "${SED:=/opt/local/bin/gsed}" ]] || \
            { echo "$0: Error: \`sudo port install gsed\` to install $SED." >&2; exit 1; }
        [[ -x "${GH:=/opt/local/bin/gh}" ]] || \
            { echo "$0: Error: \`sudo port install gh\` to install $GH." >&2; exit 1; }
    else
        HOMEBREW_PREFIX="$( (/opt/homebrew/bin/brew --prefix || /usr/local/bin/brew --prefix || brew --prefix) 2>/dev/null)"
        MAC_PREFIX="$HOMEBREW_PREFIX"
        [[ -x "${REALPATH:="$MAC_PREFIX/bin/grealpath"}" ]] || \
            { echo "$0: Error: \`brew install coreutils\` to install $REALPATH." >&2; exit 1; }
        [[ -x "${GETOPT:="$MAC_PREFIX/opt/gnu-getopt/bin/getopt"}" ]] || \
            { echo "$0: Error: \`brew install gnu-getopt\` to install $GETOPT." >&2; exit 1; }
        [[ -x "${SED:="$MAC_PREFIX/bin/gsed"}" ]] || \
            { echo "$0: Error: \`brew install gnu-sed\` to install $SED." >&2; exit 1; }
        [[ -x "${GH:="$MAC_PREFIX/bin/gh"}" ]] || \
            { echo "$0: Error: \`brew install gh\` to install $GH." >&2; exit 1; }
    fi
#    READLINK="greadlink" # coreutils
#    DATE="gdate"         # coreutils
#    STAT="gstat"         # coreutils
#    TIMEOUT="gtimeout"   # coreutils
else
    HOMEBREW_PREFIX="$( (/home/linuxbrew/.linuxbrew/bin/brew --prefix || brew --prefix) 2>/dev/null)"
    REALPATH="realpath"
#    READLINK="readlink"
#    DATE="date"
#    STAT="stat"
#    TIMEOUT="timeout"
    GETOPT="getopt"
    SED="sed"
    [[ -x "${GH:="$HOMEBREW_PREFIX/bin/gh"}" ]] || \
        { echo "$0: Error: \`brew install gh\` to install $GH." >&2; exit 1; }
fi
GIT=git

# shellcheck disable=SC2034
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
# a) Uncomment to expand symlinks in order to find the proper .envrc for direnv
#SCRIPT="$($REALPATH "${BASH_SOURCE[0]}")"
# b) Uncomment in the general case
SCRIPT="$($REALPATH --no-symlinks "${BASH_SOURCE[0]}")"
# shellcheck disable=SC2034
SCRIPT_DIR="$(dirname "$SCRIPT")"

#### Options

# Defaults
opt_dry_run=
opt_verbose=
opt_tags=
opt_force=
#opt_argument=default

function usage {
#Usage: $SCRIPT_NAME [-h|--help] [-n|--dry-run] [-v|--verbose] [-a value|--argument value] [file...]
#        -a value|--argument value: pass value to the argument option (default $opt_argument)
    cat <<END >&2
Usage: $SCRIPT_NAME [-h|--help] [-n|--dry-run] [-v|--verbose] [-t|--tags] [-f|--force]
        -h|--help: get help
        -n|--dry-run: simulate write actions as much as possible
        -v|--verbose: turn on verbose mode
        -t|--tags: imports every tag from the upstream repo
        -f|--force: overwrite any existing upstream (and its remote-tracking
                    branches and configuration settings)
END
    exit 1
}

#opts=$($GETOPT --options hnva: --long help,dry-run,verbose,argument: --name "$SCRIPT_NAME" -- "$@") || usage
opts=$($GETOPT --options hnvtf --long help,dry-run,verbose,tags,upstream --name "$SCRIPT_NAME" -- "$@") || usage
eval set -- "$opts"

while true; do
    case "$1" in
        -h | --help) usage ;;
        -n | --dry-run) opt_dry_run=opt_dry_run; shift ;;
        -v | --verbose) opt_verbose=opt_verbose; shift ;;
        -t | --tags) opt_tags=--tags; shift ;;
        -f | --force) opt_force=opt_force; shift ;;
        #-a | --argument) opt_argument="$2"; shift 2 ;;
        --) shift; break ;;
        *) echo "$SCRIPT_NAME: Internal error: '$1'" >&2; exit 1 ;;
    esac
done

#### Utils

# shellcheck disable=SC2059,SC2317
function run_cmd {
    [[ -z ${opt_verbose-} ]] || printf "#❯%s\n" "$(printf " %q" "$@")" || true
    [[ -n ${opt_dry_run-} ]] || "$@"
}

# shellcheck disable=SC2317
function warn { printf "$SCRIPT_NAME: WARNING: %s\n" "$@" >&2; }
# shellcheck disable=SC2317
function err { printf "$SCRIPT_NAME: ERROR: %s\n" "$@" >&2; }
# shellcheck disable=SC2317
function abort { printf "$SCRIPT_NAME: ERROR: %s\n" "$@" >&2; exit 1; }


##############################################################################
#### Main


prior_upstream_url="$($GIT config remote.upstream.url || true)"

[[ -z "$prior_upstream_url" || -n $opt_force ]] \
    || abort "A remote \`upstream\` already exists in git config." \
        "    Use -f to overwrite the remote (and its remote-tracking branches and settings)."

# Check if gh knows what the default repo is
default_repo="$($GH repo set-default --view 2>/dev/null || true)"

if [[ -n "${default_repo}" ]]; then
    # gh will fill in these template values
    owner="{owner}"
    repo="{repo}"

# Else, we have to figure it out ourselves
else
    remote=origin
    url="$($GIT config remote.$remote.url || true)"
    [[ -n "$url" ]] || abort "No \`$remote\` remote configured in git config."

    REGEX='^((git\+)?(https?|ssh|git)://[^/]+/|git@[^:]+:)([^/]+)/([^/]+).*'
    owner="$(<<<"$url" $SED -nE "s,$REGEX,\4,p")"
    repo="$( <<<"$url" $SED -nE "s,$REGEX,\5,p")"

    [[ -n "$owner" && -n "$repo" ]] || abort "Could not determine $remote owner and repo"
fi
repo="${repo%.git}"


# Determine upstream URL
upstream_url="$($GH api "repos/$owner/$repo" | jq -r '.parent.html_url')"

if [[ -z "$upstream_url" || "$upstream_url" == "null" ]]; then
    abort "Could not determine URL of upstream of $owner/$repo"
fi


##############################################################################
#### Main

echo "𐄬 Adding upstream …"

if [[ -n "$prior_upstream_url" ]]; then
    run_cmd $GIT remote remove upstream
fi

# `|| true` because we want to continue even if a remote is already there
run_cmd $GIT remote add ${opt_tags:-} upstream "$upstream_url" || true
