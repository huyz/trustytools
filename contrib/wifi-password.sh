#!/bin/bash
# shellcheck shell=bash
#
# Sources:
# - https://github.com/rauchg/wifi-password/issues/34#issuecomment-2041637530
# - https://github.com/rauchg/wifi-password/issues/34#issuecomment-2598663661
# - https://github.com/rauchg/wifi-password/issues/34#issuecomment-2599781966

#### Preamble (v2025-02-09)

set -uo pipefail
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

if [[ -n "${1:-}" ]]; then
    ssid="$1"
else
    wifi_if="$(scutil <<< "list" | awk -F/ '/en[0-9]+\/AirPort$/ {print $(NF-1);exit}')"
    echo "Wi-Fi interface:  $wifi_if"
    ssid="$(networksetup -getairportnetwork "${wifi_if}" | sed -En 's/Current Wi-Fi Network: (.*)$/\1/p')"
    [[ -n "$ssid" ]] || { echo "$SCRIPT_NAME: ERROR: retrieving current ssid. are you connected?" >&2; exit 1; }
    echo "Wi-Fi SSID:       $ssid"
fi

echo -e "\033[90mGetting password from macOS Keychain… \033[39m"
secout="$(security find-generic-password -ga "${ssid}" 2>&1 >/dev/null)"
(( $? == 128 )) && { echo "$SCRIPT_NAME: user canceled Keychain prompt." >&2; exit 1; }

pass="$(sed -En 's/^password: "(.*)"$/\1/p' <<<"$secout")"
[[ -n "$pass" ]] || { echo "$SCRIPT_NAME: ERROR: password for \"${ssid}\" not found in Keychain" >&2; exit 1; }
echo -e "\033[96m ✓ ${pass} \033[39m"
