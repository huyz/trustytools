#!/usr/bin/env bash
# Wraps sunshine to take additional flags:
#   -v for verbose output
#   --display for taking a string to match the display name (e.g. "DeskPad")
#     and automatically configure sunshine to use that display's ID as the display source.

#### Preamble (v2026-04-17)

# Requires root
#[ "${EUID:-$UID}" -eq 0 ] || exec sudo -p '[sudo] password for %u: ' -H "$BASH" "$0" "$@"
#[ "${EUID:-$UID}" -eq 0 ] || { echo "${BASH_SOURCE[0]}: ERROR: must be run as root" >&2; exit 1; }

# Check for bash 4 for `readarray`
# Check for bash 4 for associative arrays
# Check for bash 4 for preventing `-u` from giving error if dereferencing empty "${array[@]}"
#[ "${BASH_VERSINFO:-0}" -ge 4 ] || { echo "${BASH_SOURCE[0]}: ERROR: bash v4+ required." >&2; exit 1; }

set -euo pipefail
shopt -s failglob
# shellcheck disable=SC2329
function trap_err { echo "$(basename "${BASH_SOURCE[0]}"): ERR signal on line $(caller)" >&2; }
trap trap_err ERR
trap exit INT
export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

if [[ $OSTYPE == darwin* ]]; then
    _install_cmd="sudo port install"
    MAC_PREFIX=/opt/local
    ## Commands for root user
    if [[ "${EUID:-$UID}" -eq 0 ]]; then
        [[ -x "${GETOPT:="$MAC_PREFIX/bin/getopt"}" ]] || \
            { echo "$0: ERROR: \`$_install_cmd util-linux\` to install $GETOPT." >&2; exit 1; }
    ## Commands for non-root user
    else
        HOMEBREW_PREFIX=$( (/opt/homebrew/bin/brew --prefix || /usr/local/bin/brew --prefix || brew --prefix) 2>/dev/null )
        MAC_PREFIX="$HOMEBREW_PREFIX"
        [[ -x "${GETOPT:="$MAC_PREFIX/opt/gnu-getopt/bin/getopt"}" ]] || \
            { echo "$0: ERROR: \`$_install_cmd gnu-getopt\` to install $GETOPT." >&2; exit 1; }
    fi
    ## Commands for both root and non-root users from either MacPorts or Homebrew
    [[ -x "${REALPATH:="$MAC_PREFIX/bin/grealpath"}" ]] || \
        { echo "$0: ERROR: \`$_install_cmd coreutils\` to install $REALPATH." >&2; exit 1; }
else
    HOMEBREW_PREFIX=$( (/home/linuxbrew/.linuxbrew/bin/brew --prefix || brew --prefix) 2>/dev/null )
    GETOPT="getopt"
    REALPATH="realpath"
fi

# shellcheck disable=SC2034
SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")
SCRIPT=$($REALPATH --no-symlinks "${BASH_SOURCE[0]}")
# shellcheck disable=SC2034
SCRIPT_DIR=$(dirname "$SCRIPT")

#### Utils

STAT_FORMAT_FLAG=-c
if [[ $OSTYPE == darwin* ]]; then
    [[ $(which stat) != '/opt/homebrew/opt/coreutils/libexec/gnubin/stat' ]] && STAT_FORMAT_FLAG=-f
fi
function next_in_path {
    local script="$1"
    if [[ ! -e "$script" ]]; then
        echo "$SCRIPT_NAME: next_in_path: ERROR: $script not found" >&2
        exit 1
    fi
    local path p script_name
    script_name="$(basename "$script")"
    IFS=':' read -ra path <<< "$PATH"
    for p in "${path[@]}"; do
        local candidate="$p/$script_name"
        [[ -x "$candidate" ]] || continue
        # Skip this script itself
        [[ "$(stat -L "$STAT_FORMAT_FLAG" "%d:%i" "$script")" == \
            "$(stat -L "$STAT_FORMAT_FLAG" "%d:%i" "$candidate")" ]] && continue
        echo "$candidate"
        return
    done
    echo "$SCRIPT_NAME: next_in_path: ERROR: next $script_name not found in PATH" >&2
    exit 1
}

# shellcheck disable=SC2059,SC2329
function run_cmd {
    [[ -z ${opt_verbose-} ]] || printf "#❯%s\n" "$(printf " %q" "$@")" || true
    [[ -n ${opt_dry_run-} ]] || "$@"
}

# shellcheck disable=SC2329
function debug { [[ -z ${opt_debug-} ]] || printf "$SCRIPT_NAME: 🔧 DEBUG: %s\n" "$@" >&2; }
# shellcheck disable=SC2329
function info { [[ -z ${opt_verbose-} ]] || printf "%s\n" "$@" >&2; }
# shellcheck disable=SC2329
function warn { printf "$SCRIPT_NAME: ⚠️ WARNING: %s\n" "$@" >&2; }
# shellcheck disable=SC2329
function err { printf "$SCRIPT_NAME: ❗ ERROR: %s\n" "$@" >&2; }
# shellcheck disable=SC2329
function abort { printf "$SCRIPT_NAME: ❌ ERROR: %s\n" "$@" >&2; exit 1; }

# shellcheck disable=SC2329
function get_file_mtime {
    local file="$1"
    if [[ $OSTYPE == darwin* ]]; then
        stat -f '%m' "$file"
    else
        stat -c '%Y' "$file"
    fi
}

#### Options

# Defaults
opt_verbose=
opt_display=

function usage {
    local exit_code="${1:-1}"
    cat <<END >&2
Wrapper Usage: $SCRIPT_NAME [-h|--help] [-v|--verbose] [--display opt_display] [file...]
        -h|--help: get help
        -v|--verbose: turn on verbose mode
        --display opt_display: detect opt_display from Sunshine logs and set output_name
END
    echo
    # Invoke the original sunshine command with --help to show its options as well
    $(next_in_path "$0") --help

    exit "$exit_code"
}

opts=$($GETOPT --options hv --long help,verbose,display: --name "$SCRIPT_NAME" -- "$@") || usage
eval set -- "$opts"

while true; do
    case "$1" in
        -h | --help) usage 0;;
        -v | --verbose) opt_verbose=opt_verbose; shift ;;
        --display) opt_display="$2"; shift 2 ;;
        --) shift; break ;;
        *)
            # Pass the rest to original sunshine command
            break
            ;;
    esac
done


##############################################################################
#### Config

CONFIG_FILE="${HOME}/.config/sunshine/sunshine.conf"
LOG_FILE="${HOME}/.config/sunshine/sunshine.log"

#### Main

sunshine_args=("$@")

# shellcheck disable=SC2329
function start_sunshine() {
    "$(next_in_path "$0")" "${sunshine_args[@]}" &
    sunshine_pid=$!
}

# shellcheck disable=SC2329
function restart_sunshine() {
    kill "$sunshine_pid" 2>/dev/null || true
    wait "$sunshine_pid" 2>/dev/null || true
    start_sunshine
}

# Start Sunshine normally in background
start_sunshine

# shellcheck disable=SC2329
function cleanup() {
    kill "$sunshine_pid" 2>/dev/null || true
}
trap cleanup EXIT

if [[ -n "$opt_display" ]]; then
    initial_log_mtime=""
    display_id=""

    if [[ -f "$LOG_FILE" ]]; then
        initial_log_mtime="$(get_file_mtime "$LOG_FILE")"
    fi

    # Wait for the logs to be written to (we don't want to look at old logfile content)
    # So we need to wait until the log file timestamp is fresh
    for _ in {1..100}; do
        if [[ -f "$LOG_FILE" ]]; then
            current_log_mtime="$(get_file_mtime "$LOG_FILE")"
            if [[ -z "$initial_log_mtime" || "$current_log_mtime" != "$initial_log_mtime" ]]; then
                break
            fi
        fi

        sleep 0.2
    done

    if [[ ! -f "$LOG_FILE" ]]; then
        echo "Failed to detect Sunshine log file" >&2
        wait "$sunshine_pid"
        exit 1
    fi

    if [[ -n "$initial_log_mtime" && "$(get_file_mtime "$LOG_FILE")" == "$initial_log_mtime" ]]; then
        echo "Failed to detect fresh Sunshine log output" >&2
        wait "$sunshine_pid"
        exit 1
    fi

    # Wait for Sunshine to emit display detection logs
    for _ in {1..100}; do
        if [[ -f "$LOG_FILE" ]]; then
            display_id="$(
                grep -F "Detected display: ${opt_display}" "$LOG_FILE" \
                    | tail -n1 \
                    | sed -nE 's/.*\(id: ([0-9]+)\).*/\1/p'
            )"

            if [[ -n "$display_id" ]]; then
                break
            fi
        fi

        sleep 0.2
    done

    if [[ -z "$display_id" ]]; then
        err "Failed to detect ${opt_display} display ID"
        wait "$sunshine_pid"
        exit 1
    fi

    info "Detected ${opt_display} display id: ${display_id}"

    config_snapshot="$(cat "$CONFIG_FILE" 2>/dev/null || true)"

    # Update Sunshine config in-place
    if grep -q '^output_name *=.*' "$CONFIG_FILE"; then
        sed -i.bak -E \
            "s/^output_name *=.*/output_name = ${display_id}/" \
            "$CONFIG_FILE"
    else
        echo "output_name = ${display_id}" >> "$CONFIG_FILE"
    fi

    info "Updated output_name to ${display_id}"

    if [[ "$(cat "$CONFIG_FILE" 2>/dev/null || true)" != "$config_snapshot" ]]; then
        info "Config changed; restarting Sunshine"
        restart_sunshine
    fi
fi

# Keep wrapper attached to Sunshine process
wait "$sunshine_pid"
