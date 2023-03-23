#!/bin/bash
# 2023-03-13 https://api.ident.me/

#### Config

if [[ ${1-} == -v ]]; then
    opt_verbose=1
fi

#### util

function query {
    local _ip="$1"

    [[ -n ${opt_verbose-} ]] && echo "Got: $_ip" >&2
    [[ -z $ip ]] && ip="$_ip"
}

#### Main

query "$(dig txt ch +short whoami.cloudflare @1.1.1.1 | sed -n 's/"\(.*\)"/\1/p')"

if command -v curl &>/dev/null; then
    if [[ -z $ip || -n ${opt_verbose-} ]]; then
        # Timeout: 2 seconds
        query "$(curl -s -m 2 ipinfo.io | sed -n 's/.*"ip":.*"\(.*\)".*/\1/p')"
    fi
fi

# NOTE: The first dig doesn't work well behind a Captive portal.
#    (command -v dig &>/dev/null &&
#        (dig +short @ident.me ||
#        dig +short @tnedi.me)) ||
[[ -z $ip || -n ${opt_verbose-} ]] && query "$(
    (command -v nc &>/dev/null &&
        (nc ident.me 23 < /dev/null ||
        nc tnedi.me 23 < /dev/null)) ||
    (command -v curl &>/dev/null &&
        (curl -sf ident.me ||
        curl -sf tnedi.me)) ||
    (command -v wget &>/dev/null &&
        (wget -qO- ident.me ||
        wget -qO- tnedi.me)) ||
    (command -v openssl &>/dev/null &&
        (openssl s_client -quiet -connect ident.me:992 2> /dev/null ||
        openssl s_client -quiet -connect tnedi.me:992 2> /dev/null)) ||
    (command -v ssh &>/dev/null &&
        (ssh -qo StrictHostKeyChecking=accept-new ident.me ||
        ssh -qo StrictHostKeyChecking=accept-new tnedi.me))
)"



if [[ -n $ip ]]; then
    echo "$ip"
else
    echo "${BASH_SOURCE[0]}: Could not find public IP." >&2
    exit 1
fi
