#!/bin/bash
# Get geographical information for IP addresses (or hostnames)

if [[ "$1" == -h ]]; then
    echo "Usage: $0 [ip_address|hostname]"
    exit 0
fi

for arg in "$@"; do
    # If a hostname (not an IPv4 or IPv6 address), convert to IP address
    if ! [[ "$arg" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && ! [[ "$arg" =~ ^[0-9a-fA-F:]+$ ]]; then
        if command -v jq >/dev/null 2>&1; then
            ip_address=$(curl -s "https://dns.google.com/resolve?name=$arg&type=A" | \
                jq -cr '.Answer[] | select(.type == 1) | .data' | head -n 1)
        else
            # Convert hostname to IP address. (Skip all CNAMEs)
            ip_address=$(dig +short "$arg" | grep -v '\.$' | head -n 1)
        fi
        if [[ -n "$ip_address" ]]; then
            arg="$ip_address"
        fi
    fi

    curl -s https://ipwho.is/"$arg" | \
    if command -v jq >/dev/null 2>&1; then
        # Pipe through jq to get syntax highlighting
        jq .
    else
        cat
    fi
done
