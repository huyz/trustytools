#!/usr/bin/env bash
# Facilitates adding interesting forks as remotes to your local checkout.
#
# Usage: gh-remote-add-fork [-u] [-t]
#   -u|--upstream : determine upstream repo and search for forks of the upstream.
#   -t|--tags     : imports every tag from the remotes added
#
#   In the interactive UI, you can select multiple forks using the Tab key.
#   (Use Shift+Tab to select and go backwards).
#   Tip: to match on years (and months), type single-quote and the date prefix: '2024-03
#
# The results are sorted by last push date, but the sort is done only per batch
# batch of forks (a few hundred forks as of 2024-04-24) returned by the GitHub API.
# So the end result will be out of order when more results stream in.
#
# Based on: https://gist.github.com/dreness/0486046c4735d7dc542057c106509abd
#
# Scenario:
# - you have a local checkout of a github repo
# - you're looking at public forks of that repo
# - you want to add a remote to your local checkout for one of the forks

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
        [[ -x "${FZF:=/opt/local/bin/fzf}" ]] || \
            { echo "$0: Error: \`sudo port install fzf\` to install $FZF." >&2; exit 1; }
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
        [[ -x "${FZF:="$MAC_PREFIX/bin/fzf"}" ]] || \
            { echo "$0: Error: \`brew install fzf\` to install $FZF." >&2; exit 1; }
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
    FZF="fzf"
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
opt_upstream=
#opt_argument=default

function usage {
#Usage: $SCRIPT_NAME [-h|--help] [-n|--dry-run] [-v|--verbose] [-a value|--argument value] [file...]
#        -a value|--argument value: pass value to the argument option (default $opt_argument)
    cat <<END >&2
Usage: $SCRIPT_NAME [-h|--help] [-n|--dry-run] [-v|--verbose] [-u|--upstream] [-t|--tags]
        -h|--help: get help
        -n|--dry-run: simulate write actions as much as possible
        -v|--verbose: turn on verbose mode
        -u|--upstream: Look for forks of the upstream repo's (instead of the current repo)
        -t|--tags: Import every tag from the remotes added
END
    exit 1
}

#opts=$($GETOPT --options hnva: --long help,dry-run,verbose,argument: --name "$SCRIPT_NAME" -- "$@") || usage
opts=$($GETOPT --options hnvut --long help,dry-run,verbose,upstream,tags --name "$SCRIPT_NAME" -- "$@") || usage
eval set -- "$opts"

while true; do
    case "$1" in
        -h | --help) usage ;;
        -n | --dry-run) opt_dry_run=opt_dry_run; shift ;;
        -v | --verbose) opt_verbose=opt_verbose; shift ;;
        -t | --tags) opt_tags=--tags; shift ;;
        -u | --upstream) opt_upstream=opt_upstream; shift ;;
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
function abort { printf "$SCRIPT_NAME: FATAL: %s\n" "$@" >&2; exit 1; }


##############################################################################
#### Config


#### Arguments

if [[ -z $opt_upstream ]]; then
    # Check if gh knows what the default repo is
    default_repo="$($GH repo set-default --view)"

    if [[ -n "${default_repo}" ]]; then
        # gh will fill in these template values
        owner="{owner}"
        repo="{repo}"
    fi
fi

# If we have to figure it out ourselves
if [[ -z "${owner:-}" || -z "${repo:-}" ]]; then
    remote=origin
    [[ -n "$opt_upstream" ]] && remote=upstream

    url="$($GIT config remote.$remote.url || true)"
    [[ -n "$url" ]] || abort "No \`$remote\` remote configured in git config."

    REGEX='^((git\+)?(https?|ssh|git)://[^/]+/|git@[^:]+:)([^/]+)/([^/]+).*'
    owner="$(<<<"$url" $SED -nE "s,$REGEX,\4,p")"
    repo="$( <<<"$url" $SED -nE "s,$REGEX,\5,p")"

    [[ -n "$owner" && -n "$repo" ]] || abort "Could not determine $remote owner and repo"
fi
repo="${repo%.git}"


##############################################################################
#### Main

echo "𐄫 Fetching forks of $owner/$repo"
echo
echo "TIP: results stream in batches. Wait longer for more results…"
echo

# Give some time for the user to know to wait for results
sleep 2

# Fetch all forks of the repo in the current directory.
# Sort by last pushed date.
# For each fork, print .pushed_at, owner.login, and .clone_url
# Use fzf to select a fork, and:
#   - don't include column 3 in the preview
#   - sort in reverse order (most recently pushed at the bottom)
# Redirect selection to the fifo; background so we don't block.
$GH api --paginate "repos/$owner/$repo/forks" \
    --jq '[ .[] ] | sort_by(.pushed_at) | reverse' \
    | jq -r '.[] | "\(.pushed_at) \(.owner.login) \(.clone_url)"' \
    | $FZF --with-nth=1,2 --multi \
        --bind 'ctrl-a:select-all' \
        --bind 'ctrl-t:toggle-all' \
        --header "(Shift+)Tab select  ^A all  ^T invert selection   ${_FZF_DEFAULT_HEADER:-}" \
    | while read -r _ fork_owner fork_clone_url; do
        [[ -n "$fork_owner" && -n "$fork_clone_url" ]] || continue
        echo "𐄬 Adding remote ${fork_owner} …"
        # `|| true` because we want to continue even if a remote is already there
        run_cmd $GIT remote add ${opt_tags:-} "$fork_owner" "$fork_clone_url" || true
    done
