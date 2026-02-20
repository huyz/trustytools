#!/bin/bash
# Sets DNS-over-HTTPS (DoH) for Chromium-based browsers (Chrome, Edge, Brave) via Managed
# Preferences, which will override any user preferences and can't be easily bypassed by the user.
# This is intended to be used in conjunction with a local DoH proxy like dnscrypt-proxy or
# Cloudflare's cloudflared, but you can also use a public DoH resolver such as Control D or NextDNS

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
    #    "company.thebrowser.Browser" \
    #    "com.google.Chrome" \
    for i in \
        "com.brave.Browser" \
        "com.microsoft.edgemac" \
    ; do
        file="/Library/Managed Preferences/$user/$i.plist"
        if [[ -e "$file" ]]; then
            #echo "$file already exists. Skipping." >&2
            continue
        fi

        echo "  𐄭 Creating ${file} and setting DoH…"
        sudo mkdir -p "/Library/Managed Preferences/$user"
        cat <<EOF | sudo sh -c "cat > '$file'"
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
    echo "𐄬 Restarting cfprefsd daemon for changes to take effect…"
    sudo pkill -f 'cfprefsd daemon'|| true
fi
