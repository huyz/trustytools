#!/bin/bash
# Check if the Wi-Fi MAC address is private (e.g., randomized) or not
# Returns exit code of 0 if private MAC is enabled, 1 if disabled, and 2 if inconclusive
# Optional: Works best if https://github.com/noperator/wifi-unredactor is installed
#
# Usage: is-mac-addr-private [-v|--verbose] [ssid]
#   If no ssid is provided, it will check the currently connected Wi-Fi network.

#### Preamble (v2026-01-27)

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
    ## MacPorts commands for both root and non-root users
#    [[ -x "${CHRONIC:="$MAC_PREFIX/bin/chronic"}" ]] || \
#        { echo "$0: ERROR: \`$_install_cmd moreutils\` to install $CHRONIC." >&2; exit 1; }
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
    command -v "${JQ:=jq}" &>/dev/null || \
        { echo "$0: ERROR: \`$_install_cmd jq\` to install $JQ." >&2; exit 1; }
else
#    _install_cmd="brew install"
    HOMEBREW_PREFIX=$( (/home/linuxbrew/.linuxbrew/bin/brew --prefix || brew --prefix) 2>/dev/null )
    GETOPT="getopt"
    REALPATH="realpath"
    JQ="jq"
fi

# shellcheck disable=SC2034
SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")
SCRIPT=$($REALPATH --no-symlinks "${BASH_SOURCE[0]}")
# shellcheck disable=SC2034
SCRIPT_DIR=$(dirname "$SCRIPT")

#### Utils

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

#### Options

# Defaults
opt_verbose=

function usage {
    local exit_code="${1:-1}"
    cat <<END >&2
Usage: $SCRIPT_NAME [-h|--help] [-v|--verbose] [file...]
        -h|--help: get help
        -v|--verbose: turn on verbose mode
END
    exit "$exit_code"
}

opts=$($GETOPT --options hv --long help,verbose --name "$SCRIPT_NAME" -- "$@") || usage
eval set -- "$opts"

while true; do
    case "$1" in
        -h | --help) usage 0;;
        -v | --verbose) opt_verbose=opt_verbose; shift ;;
        --) shift; break ;;
        *) abort "🐛 INTERNAL: unrecognized option '$1'" ;;
    esac
done

if [[ $# -gt 0 ]]; then
    ssid="${1:-}"
    shift
    if [[ $# -gt 0 ]]; then
        usage
    fi
fi


##############################################################################
#### Config

# Required for macOS Sonoma+
WIFI_UNREDACTOR=~/Applications/wifi-unredactor.app/Contents/MacOS/wifi-unredactor
WIFI_PREF_FILE="/Library/Preferences/com.apple.wifi.known-networks.plist"

#### Method 1: compare MAC addresses

mac_state="unknown"

if [[ -z "${ssid:-}" ]]; then
    iface="en0"

    # Resolve Wi-Fi device if not en0
    wifi_dev=$(networksetup -listallhardwareports | awk '/Wi-Fi/{getline; print $2}')
    if [[ -n "$wifi_dev" ]]; then
        iface="$wifi_dev"
    fi

    info "Interface: $iface"

    # Current MAC
    current_mac=$(ifconfig "$iface" | awk '/ether/{print $2}')
    info "Current MAC: $current_mac"

    # Hardware MAC
    hw_mac=$(networksetup -getmacaddress "$iface" | awk '{print $3}')
    info "Hardware MAC: $hw_mac"

    # Compare MACs
    if [[ "$current_mac" == "$hw_mac" ]]; then
        mac_state="disabled"
    else
        mac_state="enabled"
    fi
fi

#### Method 2: Check Wi-Fi Preferences

pref_state="unknown"

if [[ -z "${ssid:-}" && -x "$WIFI_UNREDACTOR" ]]; then
    # No longe works on macOS Sonoma+ due to increased privacy
    #ssid=$(networksetup -getairportnetwork "$iface" 2>/dev/null | sed 's/^Current Wi-Fi Network: //')
    # Determine active SSID
    ssid=$("$WIFI_UNREDACTOR" | jq -r .ssid)
fi

if [[ -n "${ssid:-}" && -f "$WIFI_PREF_FILE" ]]; then
    info "SSID: $ssid"
    #ssid=' Free WiFi 5'  # 2026-04-17 It was set to `static` for testing
    #ssid='Guest Mesh WiFi'  # 2026-04-17 It was set to `off`
    #ssid='Mesh WiFi'  # 2026-04-17 It was nonexistent

    if ! sudo /usr/libexec/PlistBuddy -c "Print ':wifi.network.ssid.$ssid'" "$WIFI_PREF_FILE" &>/dev/null; then
        err "SSID '$ssid' not found in Wi-Fi Preferences. Can't determine private MAC setting from preferences."
    else
        pref_value=$(sudo /usr/libexec/PlistBuddy \
            -c "Print ':wifi.network.ssid.$ssid:PrivateMACAddressModeUserSetting'" \
            "$WIFI_PREF_FILE" 2>/dev/null || true)

        case "$pref_value" in
            ''|off) pref_state="disabled" ;;
            static|rotating) pref_state="enabled" ;;
        esac
    fi
fi

#### Result

info "---- Result ----"
info "MAC comparison: $mac_state"
info "Preference: $pref_state"

# Final determination
if [[ "$mac_state" == "enabled" || "$pref_state" == "enabled" ]]; then
    info "Conclusion: Private MAC is ENABLED"
    exit 0
elif [[ "$mac_state" == "disabled" || "$pref_state" == "disabled" ]]; then
    info "Conclusion: Private MAC is DISABLED"
    exit 1
else
    info "Conclusion: INCONCLUSIVE (check manually)"
    exit 2
fi
