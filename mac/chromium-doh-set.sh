#!/bin/bash
# shellcheck shell=bash

#### Preamble (v2025-08-22)

set -euo pipefail
shopt -s failglob
# shellcheck disable=SC2329
function trap_err { echo "$(basename "${BASH_SOURCE[0]}"): ERR signal on line $(caller)" >&2; }
trap trap_err ERR
trap exit INT  # So that ^C will stop the entire script, not just the current subprocess
export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

# shellcheck disable=SC2034
SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")
script=${BASH_SOURCE[0]}
while [[ -L "$script" ]]; do
    script=$(readlink "$script")
done
# shellcheck disable=SC2034
SCRIPT_DIR=$(dirname "$script")

##############################################################################
#### Args

USER="${USER:-"$(whoami)"}"


if [[ $# -lt 1 || "$1" == -h || "$1" == --help ]]; then
    echo "Usage: $SCRIPT_NAME <DoH_url> [user…]" >&2
    echo "  Default user: $USER" >&2
    exit 1
fi

doh_url="$1"
shift

users=("$@")

### Init

if [[ ${#users[@]} -eq 0 ]]; then
    users=("$USER")
fi

#### Main

restart_cfprefsd=

for user in "${users[@]}"; do
    [[ -d "/Users/$user" ]] || continue

    echo "𐄬 Checking Chromium Managed Preferences for user ${user}…"
    # Skip Arc Browser now that it's been abandoned
    #"/Library/Managed Preferences/$user/company.thebrowser.Browser.plist" \
    for i in \
        "/Library/Managed Preferences/$user/com.brave.Browser.plist" \
        "/Library/Managed Preferences/$user/com.google.Chrome.plist" \
        "/Library/Managed Preferences/$user/com.microsoft.edgemac.plist" \
    ; do
        if [[ -e "$i" ]]; then
            #echo "$i already exists. Skipping." >&2
            continue
        fi

        echo "  𐄭 Creating ${i} and setting DoH…"
        sudo mkdir -p "/Library/Managed Preferences/$user"
        cat <<EOF | sudo sh -c "cat > '$i'"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>DnsOverHttpsMode</key>
    <string>secure</string>
    <key>DnsOverHttpsTemplates</key>
    <string>$doh_url</string>
</dict>
</plist>
EOF

        restart_cfprefsd=1
    done
done

if [[ -n $restart_cfprefsd ]]; then
    echo "𐄬 Restarting cfprefsd for changes to take effect…"
    # This will restart cfprefsd for all users, including root
    sudo pkill cfprefsd || true
fi
