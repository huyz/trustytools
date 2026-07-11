#!/bin/bash
# Sets DNS-over-HTTPS (DoH) for Chromium-based browsers (Chrome, Edge, Brave) via Managed
# Preferences, which will override any user preferences and can't be easily bypassed by the user.
# This is intended to be used in conjunction with a local DoH proxy like dnscrypt-proxy or
# Cloudflare's cloudflared, but you can also use a public DoH resolver such as Control D or NextDNS
# Usage:
#   chromium-doh-set-to-controld [--global] <DoH_url> [user…]
#        --global: Write system-level managed preferences (conflicts with user arguments)

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

function usage {
    echo "Usage: $SCRIPT_NAME [--global] <DoH_url> [user…]" >&2
    echo "  Default user: $USER" >&2
    echo "  --global: Write system-level managed preferences (conflicts with user arguments)" >&2
}

function ensure_plist_exists {
    local file=$1

    if [[ -e "$file" ]]; then
        return
    fi

    sudo mkdir -p "$(dirname "$file")"
    cat <<'EOF' | sudo sh -c "cat > '$file'"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
EOF
}

function ensure_plist_string {
    local file=$1
    local key=$2
    local desired=$3
    local current

    if current=$(sudo /usr/libexec/PlistBuddy -c "Print :$key" "$file" 2>/dev/null); then
        if [[ "$current" == "$desired" ]]; then
            return
        fi
        sudo /usr/libexec/PlistBuddy -c "Set :$key $desired" "$file"
    else
        sudo /usr/libexec/PlistBuddy -c "Add :$key string $desired" "$file"
    fi

    restart_cfprefsd=1
}


if [[ $# -lt 1 || "$1" == -h || "$1" == --help ]]; then
    usage
    exit 1
fi

is_global=
while [[ $# -gt 0 ]]; do
    case "$1" in
        --global)
            is_global=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        -*)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

if [[ $# -lt 1 ]]; then
    usage
    exit 1
fi

doh_url="$1"
shift

users=("$@")

if [[ -n "$is_global" && ${#users[@]} -gt 0 ]]; then
    echo "Error: --global conflicts with user arguments." >&2
    usage
    exit 1
fi

### Init

if [[ -z "$is_global" && ${#users[@]} -eq 0 ]]; then
    users=("$USER")
fi

#### Main

restart_cfprefsd=

if [[ -n "$is_global" ]]; then
    echo "𐄬 Checking Chromium Managed Preferences at system level…"
    # Skip Arc Browser now that it's been abandoned
    #    "company.thebrowser.Browser" \
    for i in \
        "com.brave.Browser" \
        "com.google.Chrome" \
        "com.microsoft.edgemac" \
    ; do
        file="/Library/Managed Preferences/$i.plist"
        echo "  𐄭 Ensuring ${file} has DoH settings…"
        ensure_plist_exists "$file"
        ensure_plist_string "$file" "DnsOverHttpsMode" "secure"
        ensure_plist_string "$file" "DnsOverHttpsTemplates" "$doh_url"
    done
else
    for user in "${users[@]}"; do
        [[ -d "/Users/$user" ]] || continue

        echo "𐄬 Checking Chromium Managed Preferences for user ${user}…"
        # Skip Arc Browser now that it's been abandoned
        #    "company.thebrowser.Browser" \
        for i in \
            "com.brave.Browser" \
            "com.google.Chrome" \
            "com.microsoft.edgemac" \
        ; do
            file="/Library/Managed Preferences/$user/$i.plist"
            echo "  𐄭 Ensuring ${file} has DoH settings…"
            ensure_plist_exists "$file"
            ensure_plist_string "$file" "DnsOverHttpsMode" "secure"
            ensure_plist_string "$file" "DnsOverHttpsTemplates" "$doh_url"
        done
    done
fi

if [[ -n $restart_cfprefsd ]]; then
    echo "𐄬 Restarting cfprefsd daemon for changes to take effect…"
    sudo pkill -f 'cfprefsd daemon'|| true
fi
