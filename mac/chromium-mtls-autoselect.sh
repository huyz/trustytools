#!/bin/bash
# Eliminate pop-ups for selecting mTLS client certificates in Chromium-based browsers (Chrome, Edge,
# Brave) by setting the AutoSelectCertificateForUrls preference to match all URLs and allow any
# certificate.

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

if [[ "${1:-}" == -h || "${1:-}" == --help ]]; then
    echo "Usage: $SCRIPT_NAME [user…]" >&2
    echo "  Default user: $USER" >&2
    exit 1
fi

users=("$@")

### Init

if [[ ${#users[@]} -eq 0 ]]; then
    users=("$USER")
fi

#### Main

for user in "${users[@]}"; do
    [[ -d "/Users/$user" ]] || continue

    restart_cfprefsd=

    echo "𐄬 Updating Chromium Preferences for user ${user}…"
    # Skip Arc Browser now that it's been abandoned
    #"company.thebrowser.Browser" \
    for i in \
        "com.brave.Browser" \
        "com.google.Chrome" \
        "com.microsoft.edgemac" \
    ; do
        if [[ "$user" != "$USER" ]]; then
            sudo=sudo
        else
            sudo=
        fi

        file="/Users/$user/Library/Preferences/$i.plist"

        echo "  𐄭 Setting AutoSelectCertificateForUrls default for ${file}…"
        if ! $sudo test -e "$file"; then
            echo "ERROR: $file does not exist. Skipping." >&2
            continue
        fi
        $sudo defaults write "$file" AutoSelectCertificateForUrls -array
        $sudo defaults write "$file" AutoSelectCertificateForUrls -array-add -string '{"pattern":"*","filter":{}}'

        restart_cfprefsd=1
    done

    if [[ -n $restart_cfprefsd ]]; then
        echo "  𐄭 Restarting cfprefsd agent for changes to take effect…"
        $sudo pkill -u "$user" -f 'cfprefsd agent'|| true
    fi
done
