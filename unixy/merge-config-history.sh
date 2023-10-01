#!/usr/bin/env bash
# For a given app that automatically generates default configs (e.g. kitty,
# broot, powerlevel10k), this script does a three-way merge among the previous
# default config, the new default config, and your possibly-customized config.
#
# Setup:
#   1. In the given app's config directory, create a `.config-history/` subdirectory
#   2. In that subdirectory create a `save-default-config` executable script that
#      figures out the app's current version and then writes the config files
#      in a new `default-config-<VERSION_NUMBER>/` subdirectory
#   3. Create symlinks from the app's config directory to the corresponding files
#      (or subdirectories) in `.config-history/current-config/`
#   3a. If you want to work on one or a few config files with fixed filenames,
#      have VS Code installed. (E.g. kitty only has kitty.conf)
#   3b. If you want to work on a directory of files (where files come and go)
#      have Meld installed. (E.g. broot has a directory of config files)
#
#   If an app puts their config file(s) in a shared directory like your $HOME,
#   move them to somewhere more appropriate like `$HOME/.config/appname/`
#   and use symlinks.
#   (E.g., ~/.p10k.zsh -> ~/.config/powerlevel10k/.config-history/current-config/.p10k.zsh)
#
# After every new app version:
#   a. For files, run `merge-config-history ~/.config/kitty kitty.conf`
#      or `merge-config-history ~/.config/powerlevel10k .p10k.zsh`.
#      (Multiple filenames could be specified)
#   b. For a directory, simply run `merge-config-history ~/.config/broot`.
#

##############################################################################
# Script-wide block: this may allow updating the script as it's running (if under 8KB)
{

# For mapfile
[ "${BASH_VERSINFO:-0}" -ge 4 ] || { echo "${BASH_SOURCE[0]}: Error: bash v4+ required." >&2; exit 1; }

#### Preamble (v2023-09-24)

# Requires root
#[ "${EUID:-$UID}" -eq 0 ] || exec sudo -p '[sudo] password for %u: ' -H "$BASH" "$0" "$@"
#[ "${EUID:-$UID}"" -eq 0 ] || { echo "${BASH_SOURCE[0]}: Error: must be run as root" >&2; exit 1; }

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
        [ -x "${GETOPT:=/opt/local/bin/getopt}" ] || \
            { echo "$0: Error: \`sudo port install util-linux\` to install $GETOPT." >&2; exit 1; }
    else
        HOMEBREW_PREFIX="$( (/opt/homebrew/bin/brew --prefix || /usr/local/bin/brew --prefix || brew --prefix) 2>/dev/null)"
        [ -x "${REALPATH:="$HOMEBREW_PREFIX/bin/grealpath"}" ] || \
            { echo "$0: Error: \`brew install coreutils\` to install $REALPATH." >&2; exit 1; }
        [ -x "${GETOPT:="$HOMEBREW_PREFIX/opt/gnu-getopt/bin/getopt"}" ] || \
            { echo "$0: Error: \`brew install gnu-getopt\` to install $GETOPT." >&2; exit 1; }
    fi
else
    HOMEBREW_PREFIX="$( (/home/linuxbrew/.linuxbrew/bin/brew --prefix || brew --prefix) 2>/dev/null)"
    REALPATH="realpath"
    GETOPT="getopt"
fi

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
#SCRIPT="$($REALPATH -s "${BASH_SOURCE[0]}")"
#SCRIPT_DIR="$(dirname "$SCRIPT")"

#### Options

function usage {
#Usage: $SCRIPT_NAME [-h|--help] [-n|--dry-run] [-v|--verbose] [-a value|--argument value] [file...]
#        -a value|--argument value: pass value to the argument option
    cat <<END >&2
Usage: $SCRIPT_NAME [-h|--help] [-n|--dry-run] [-v|--verbose] config_dir [file…]
        -h|--help: get help
        -n|--dry-run: simulate write actions as much as possible
        -v|--verbose: turn on verbose mode

    In the config_dir, there must be a save-default-config executable script
    that writes the config file(s) in the
        \$config_dir/.config-history/default-config-<VERSION_NUMBER>
END
    exit 1
}

# Defaults
opt_dry_run=
opt_verbose=
#opt_argument=default

#opts=$($GETOPT --options hnva: --long help,dry-run,verbose,argument: --name "$SCRIPT_NAME" -- "$@") || usage
opts=$($GETOPT --options hnv --long help,dry-run,verbose --name "$SCRIPT_NAME" -- "$@") || usage
eval set -- "$opts"

while true; do
    case "$1" in
        -h | --help) usage ;;
        -n | --dry-run) opt_dry_run=opt_dry_run; shift ;;
        -v | --verbose) opt_verbose=opt_verbose; shift ;;
        #-a | --argument) opt_argument="$2"; shift 2 ;;
        --) shift; break ;;
        *) echo "$SCRIPT_NAME: Internal error: '$1'" >&2; exit 1 ;;
    esac
done

[[ $# -lt 1 ]] && usage
config_root="$1"
shift
filenames=("$@")

#### Terminal colors

#declare bold='' underline='' standout='' normal='' black='' red='' green='' yellow='' blue='' magenta='' cyan='' white=''
#if [ -t 1 ]; then # if terminal
#    ncolors="$(which tput > /dev/null && tput colors)" # supports color
#    if test -n "$ncolors" && test "$ncolors" -ge 8; then
#        termcols=$(tput cols) bold="$(tput bold)" underline="$(tput smul)" standout="$(tput smso)" normal="$(tput sgr0)" black="$(tput setaf 0)" red="$(tput setaf 1)" green="$(tput setaf 2)" yellow="$(tput setaf 3)" blue="$(tput setaf 4)" magenta="$(tput setaf 5)" cyan="$(tput setaf 6)" white="$(tput setaf 7)"
#    fi
#fi

#### Utils

# shellcheck disable=SC2317 disable=SC2120
function indent_stdout {
    local prefix=
    [[ $# -gt 0 &&${1:-} == -p ]] && { prefix="$2"; shift 2; }
    perl -pe "s/^/${prefix}░░░░/"
}

# shellcheck disable=SC2317 disable=SC2120
function indent_stderr {
    local prefix=
    [[ ${1:-} == -p ]] && { prefix="$2"; shift 2; }
    perl -ne "s/^/${prefix}░░░░/; print STDERR"
}

# shellcheck disable=SC2317
function printf_log {
    # shellcheck disable=SC2059
    printf -- "$@"
    # shellcheck disable=SC2059
    [[ -z ${LOG_FILE-} ]] || printf -- "$@" >> "$LOG_FILE"
}

# shellcheck disable=SC2317
function printf_err_log {
    # shellcheck disable=SC2059
    printf -- "$@" >&2
    if [[ -n ${ERR_LOG_FILE-} ]]; then
        # shellcheck disable=SC2059
        printf -- "$@" >> "$ERR_LOG_FILE"
    else
        # shellcheck disable=SC2059
        [[ -z ${LOG_FILE-} ]] || printf -- "$@" >> "$LOG_FILE"
    fi
}

# shellcheck disable=SC2317
function run_cmd {
    [[ -z ${opt_verbose-} ]] || printf_log "#❯%s\n" "$(printf " %q" "$@")" || true
    [[ -n ${opt_dry_run-} ]] || "$@"
}

# shellcheck disable=SC2317
function warn {
    printf_err_log "$SCRIPT_NAME: WARNING: $*\n"
}

# shellcheck disable=SC2317
function error {
    printf_err_log "$SCRIPT_NAME: ERROR: $*\n"
}

# shellcheck disable=SC2317
function abort {
    printf_err_log "$SCRIPT_NAME: FATAL: $*\n"
    exit 1
}


##############################################################################
#### Config

CONFIG_HISTORY_DIR="$config_root/.config-history"
PREVIOUS_CONFIG_DIR="previous-config"
CURRENT_CONFIG_DIR="current-config"

#### Main

cd "$CONFIG_HISTORY_DIR" || usage

# Save the new default configs
if [[ -x ./save-default-config ]]; then
    run_cmd ./save-default-config
else
    abort "$config_root/save-default-config not found."
fi

# Figure out the last 2 recent versions of default configs including the new ones
mapfile -t < <(find . -name 'default-config-*' | sort -V | tail -2)

if [[ ${#MAPFILE[@]} -ne 2 ]]; then
    abort "expected 2 default configs, found ${#MAPFILE[@]}."
fi

# Save current-config to previous-config
# NOTE: for folder merge (with Meld), we don't need the previous-config here but
# we do it for consistency because VS Code needs it when doing a 3-way merge.
[[ -d "$PREVIOUS_CONFIG_DIR" ]] && run_cmd rm -rf "$PREVIOUS_CONFIG_DIR"
if [[ -d "$CURRENT_CONFIG_DIR" ]]; then
    run_cmd cp -a "$CURRENT_CONFIG_DIR" "$PREVIOUS_CONFIG_DIR"
else
    abort "$CONFIG_HISTORY_DIR/$CURRENT_CONFIG_DIR not found."
fi

# If no filenames are specified, then we assume folder merge
if [[ ${#filenames[@]} -eq 0 ]]; then
    # Invoke the 3-way merge with meld
    run_cmd meld "${MAPFILE[0]}" "${MAPFILE[1]}" "$CURRENT_CONFIG_DIR"
else
    for name in "${filenames[@]}"; do
        for file in \
            "${MAPFILE[1]}/$name" \
            "$PREVIOUS_CONFIG_DIR/$name" \
            "${MAPFILE[0]}/$name" \
            "$CURRENT_CONFIG_DIR/$name"
        do
            if [[ ! -e "$file" ]]; then
                error "$CONFIG_HISTORY_DIR/$file not found. Skipping…"
                continue 2
            fi
        done
        run_cmd code --merge "${MAPFILE[1]}/$name" "$PREVIOUS_CONFIG_DIR/$name" "${MAPFILE[0]}/$name" "$CURRENT_CONFIG_DIR/$name"
    done
fi

##############################################################################
# end of script-wide block
exit
}
