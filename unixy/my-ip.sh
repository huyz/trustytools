#!/bin/bash
# Returns your IPv4 or IPv6 address by querying different providers.
# Usage: my-ip [-h|--help] [-v|--verbose] [-4] [-6]

#set -x

#### Preamble (v2025-08-22)

set -uo pipefail
shopt -s failglob
# shellcheck disable=SC2329
function trap_err { echo "$(basename "${BASH_SOURCE[0]}"): ERR signal on line $(caller)" >&2; }
#jjtrap trap_err ERR
trap exit INT  # So that ^C will stop the entire script, not just the current subprocess
export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

GETOPT=getopt
NC=nc
CURL=curl
WGET=wget
OPENSSL=openssl
SSH=ssh

# shellcheck disable=SC2034
SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")
script=${BASH_SOURCE[0]}
while [[ -L "$script" ]]; do
    script=$(readlink "$script")
done
# shellcheck disable=SC2034
SCRIPT_DIR=$(dirname "$script")

#### Options

# Defaults
opt_verbose=
opt_ipv4=
opt_ipv6=

function usage {
    local exit_code="${1:-1}"
    cat <<END >&2
Usage: $SCRIPT_NAME [-h|--help] [-v|--verbose] [file...]
        -h|--help: get help
        -v|--verbose: turn on verbose mode
        -4: use IPv4 only
        -6: use IPv6 only
END
    exit "$exit_code"
}

opts=$($GETOPT --options hnv46 --long help,dry-run,verbose --name "$SCRIPT_NAME" -- "$@") || usage
eval set -- "$opts"

while true; do
    case "$1" in
        -h | --help) usage 0 ;;
        -v | --verbose) opt_verbose=opt_verbose; shift ;;
        -4) opt_ipv4=opt_ipv4; shift ;;
        -6) opt_ipv6=opt_ipv6; shift ;;
        #-a | --argument) opt_argument="$2"; shift 2 ;;
        --) shift; break ;;
        *) abort "🐛 INTERNAL: unrecognized option '$1'" ;;
    esac
done



##############################################################################
#### Config

flag_any=
flag_ipv4=-4
flag_ipv6=-6

CURL_FLAGS=(--silent --fail --max-time 2)
WGET_FLAGS=(--quiet --output-document=- --timeout=2 --tries=1)
OPENSSL_FLAGS=(-quiet -connect)
SSH_FLAGS=(-q -o StrictHostKeyChecking=accept-new -o ConnectTimeout=2 -o BatchMode=yes)

case "$OSTYPE" in
    darwin*) NC_FLAGS=(-G 2) ;;
    *) NC_FLAGS=(-w 2) ;;
esac

#### Init

ip=
ip4=
ip6=

# Determines whether the machine even has an IPv6 address, as we don't want to
# even try to make such a connection and risk hanging.
case "$OSTYPE" in
darwin*)
    # Ignore link-local fe80:: and loopback
    if ifconfig 2>/dev/null | grep -E "inet6 [23][0-9a-f]" -q; then
        has_ipv6=1
    fi
    ;;
*)
    if ip -6 addr show scope global | grep -q 'inet6'; then
        has_ipv6=1
    fi
    ;;
esac

if [[ -z $opt_ipv4 && -z $opt_ipv6 ]]; then
    query_any=1
fi
if [[ (-n $opt_verbose || -n $opt_ipv4) && -z $opt_ipv6 ]]; then
    query_ipv4=1
fi
if [[ -n ${has_ipv6:-} && (-n $opt_verbose || -n $opt_ipv6) && -z $opt_ipv4 ]]; then
    query_ipv6=1
fi


##############################################################################
#### Util

function check_done {
    if [[ -n $opt_verbose ]]; then
        return 0
    fi
    if [[ -z ${ip4:-} && -n $opt_ipv4 && -z $opt_ipv6 ]]; then
        return 0
    fi
    if [[ -n ${has_ipv6:-} && -z ${ip6:-} && -n $opt_ipv6 && -z $opt_ipv4 ]]; then
        return 0
    fi
    if [[ -z ${ip:-} ]]; then
        return 0
    fi

    # We're done
    echo "$ip"
    exit 0
}

function query {
    local _provider="$1" _ip="$2"

    # Check for IPv4 or IPv6 formats
    case "$_ip" in
        # IPv4
        ([0-9]*\.[0-9]*\.[0-9]*\.[0-9]*)
            if [[ -n ${query_any:-} || -n ${query_ipv4:-} ]]; then
                ip4="$_ip"
                [[ -n ${ip:-} ]] || ip="$_ip"
            fi
            ;;
        # IPv6 (very loose check)
        (*:*:*)
            if [[ -n ${query_any:-} || -n ${query_ipv6:-} ]]; then
                ip6="$_ip"
                [[ -n ${ip:-} ]] || ip="$_ip"
            fi
            ;;
        # Not recognized
        ('')
            [[ -n ${opt_verbose-} ]] && printf "%-20s %s\n" "$_provider" "<empty>"
            return 1 ;;
        (*)
            [[ -n ${opt_verbose-} ]] && printf "%-20s %s\n" "$_provider" "<unrecognized: $_ip>"
            return 1 ;;
    esac
    if [[ -z ${ip:-} && -z $opt_ipv4 && -z $opt_ipv6 ]]; then
        ip="$_ip"
    fi
    [[ -n ${opt_verbose-} ]] && printf "%-20s %s\n" "$_provider" "$_ip"

    check_done
    return 0
}

#### Main

# NOTE: When not run in verbose mode, the caller is looking for a single answer, so
#   we try to prioritize fast methods and providers first.

if command -v dig &>/dev/null; then
    # 2025-09-17 Strange, at a cafe where they seem to have IPv6, Cloudflare won't return anything for
    #      dig -4 txt ch +short whoami.cloudflare @1.1.1.1
    #    but Google has no such problem
    # 2025-09-15 ping times to ident.me are bad as they are in Finland so we don't bother with
    #    ident.me for our initial command invocations.
    for cmd_flags in \
        "txt +short o-o.myaddr.google.com @ns1.google.com" \
        "txt ch +short whoami.cloudflare @1dot1dot1dot1.cloudflare-dns.com" \
    ; do
        provider=$(echo "$cmd_flags" | perl -lpe 's/.*? (?:[-\w]+\.)+?((?!com)\w+)(\.com)? .*/$1/')
        for ipv in any ipv4 ipv6; do
            query_key="query_$ipv"
            flag_key="flag_$ipv"
            if [[ -n ${!query_key:-} ]]; then
                flags="${!flag_key:-}"
                if [[ "$cmd_flags" == *myip.opendns* ]]; then
                    case "$ipv" in
                        # 2025-09-16 I guessed the ANY query and it seems to work for opendns
                        # but not sure if that can be relied on
                        any) flags="$flags ANY" ;;
                        ipv4) flags="$flags A" ;;
                        ipv6) flags="$flags AAAA" ;;
                    esac
                fi
                # shellcheck disable=SC2086
                query "$provider dig $ipv" \
                    "$(dig $flags $cmd_flags \
                    | sed -n 's/"\(.*\)"/\1/p')"
            fi
        done
    done

fi

if command -v "$NC" &>/dev/null; then
    # 2025-09-17 Hmm based on my query to ident.me, nc does fall back to IPv4 more often than other
    #   apps
    for domain in \
        ident.me \
    ; do
        provider=$(echo -n "$domain" | perl -lpe 's/.*?(?:^|[-\w]+\.|.*:\/\/)+?((?!com|org|me|io)\w+)(?:\.com|\.org|\.me|\.io)?$/$1/')
        for ipv in any ipv4 ipv6; do
            query_key="query_$ipv"
            flag_key="flag_$ipv"
            if [[ -n ${!query_key:-} ]]; then
                query "$provider $NC $ipv" \
                    "$("$NC" ${!flag_key:-} "${NC_FLAGS[@]}" "$domain" 23)"
            fi
        done
    done
fi

# shellcheck disable=SC2066
for web_command in "$CURL"; do
    if command -v "$web_command" &>/dev/null; then
        case "$web_command" in
            *curl) flags=("${CURL_FLAGS[@]}") ;;
            *wget) flags=("${WGET_FLAGS[@]}") ;;
        esac
        # 2025-09-17 ipinfo: temporarily used http instead of https, as their LetsEncrypt SSL cert
        #   expired for several hours
        for url in \
            https://ipinfo.io/ip \
            https://api64.ipify.org \
            https://ident.me \
        ; do
            provider=$(echo -n "$url" | perl -lpe 's/.*?(?:^|[-\w]+\.|.*:\/\/)+?((?!com|org|me|io)\w+)(?:\.com|\.org|\.me|\.io)?(?:\/.*)?$/$1/')
            for ipv in any ipv4 ipv6; do
                query_key="query_$ipv"
                flag_key="flag_$ipv"
                if [[ -n ${!query_key:-} ]]; then
                    if [[ $url == *ipinfo* ]]; then
                        if [[ $ipv == ipv6 ]]; then
                            url=https://v6.ipinfo.io/ip
                        elif [[ $ipv == any ]]; then
                            # 2025-09-17 I don't think this is supported. We need an hostname that
                            # handles both IPv4 and IPv6.
                            # This employee at https://news.ycombinator.com/item?id=36951259 claimed
                            # in 2023-08-01 that it's dual-stack but that's not what I'm seeing.
                            continue
                        fi
                    fi
                    # shellcheck disable=SC2086
                    query "$provider $web_command $ipv" \
                        "$("$web_command" ${!flag_key:-} "${flags[@]}" "$url" \
                        | sed 's/.*"ip":.*"\(.*\)".*/\1/')"
                fi
            done
        done
    fi
done

# In verbose mode, we don't do all types of IPv because that would be redundant with curl
if command -v "$WGET" &>/dev/null; then
    if [[ -n $opt_ipv4 ]]; then
        ipv=ipv4
    elif [[ -n $opt_ipv6 && -n ${has_ipv6:-} ]]; then
        ipv=ipv6
    else
        ipv=any
    fi
    query_key="query_$ipv"
    flag_key="flag_$ipv"
    query "ident $WGET $ipv" \
        "$("$WGET" ${!flag_key:-} "${WGET_FLAGS[@]}" https://ident.me </dev/null \
        || "$WGET" ${!flag_key:-} "${WGET_FLAGS[@]}" https://tnedi.me </dev/null)"
fi

if command -v "$OPENSSL" &>/dev/null; then
    ## 2025-09-17 Doesn't work; I get "Connection refused"
    for host in \
        ident.me:992 \
    ; do
        provider=$(echo -n "$host" | perl -lpe 's/.*?(?:^|[-\w]+\.|.*:\/\/)+?((?!com|org|me|io)\w+)(?:\.com|\.org|\.me|\.io)?(?::\d+)?$/$1/')
        for ipv in any ipv4 ipv6; do
            query_key="query_$ipv"
            flag_key="flag_$ipv"
            if [[ -n ${!query_key:-} ]]; then
                query "$provider $OPENSSL $ipv" \
                    "$("$OPENSSL" s_client ${!flag_key:-} "${OPENSSL_FLAGS[@]}" "${host}" 2>/dev/null)"
            fi
        done
    done
fi

if command -v "$SSH" &>/dev/null; then
    for domain in \
        ident.me \
    ; do
        provider=$(echo -n "$domain" | perl -lpe 's/.*?(?:^|[-\w]+\.|.*:\/\/)+?((?!com|org|me|io)\w+)(?:\.com|\.org|\.me|\.io)?$/$1/')
        for ipv in any ipv4 ipv6; do
            query_key="query_$ipv"
            flag_key="flag_$ipv"
            if [[ -n ${!query_key:-} ]]; then
                query "$provider $SSH $ipv" \
                    "$("$SSH" ${!flag_key:-} "${SSH_FLAGS[@]}" "$domain")"
            fi
        done
    done
fi

#### End

if [[ -z ${ip:-} ]]; then
    echo "$SCRIPT_NAME: ERROR: Could not find public IP." >&2
    exit 1
fi

exit 0
