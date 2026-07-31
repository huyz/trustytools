#!/usr/bin/env bash
# Returns your IPv4 or IPv6 address by querying different providers.
# Usage: my-ip [-h|--help] [-v|--verbose] [-4] [-6]

# Check for bash 4.4+ for namerefs, `readarray -d`, associative arrays, etc.
if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4) )); then
    echo "${BASH_SOURCE[0]}: ERROR: bash v4.4+ required." >&2
    exit 1
fi

#set -x

#### Preamble (v2025-08-22)

set -uo pipefail
shopt -s failglob extglob
# shellcheck disable=SC2329
function trap_err { echo "$(basename "${BASH_SOURCE[0]}"): ERR signal on line $(caller)" >&2; }
#jjtrap trap_err ERR
trap exit INT  # So that ^C will stop the entire script, not just the current subprocess
export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

readonly GETOPT=getopt
readonly NC=nc
readonly CURL=curl
readonly WGET=wget
readonly OPENSSL=openssl
readonly SSH=ssh

# shellcheck disable=SC2034
SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")
script=${BASH_SOURCE[0]}
while [[ -L "$script" ]]; do
    script=$(readlink "$script")
done
# shellcheck disable=SC2034
SCRIPT_DIR=$(dirname "$script")

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
opt_debug=
opt_ipv4=
opt_ipv6=
opt_providers=()
opt_exclude=()

function usage {
    local -r exit_code="${1:-1}"
    cat <<END >&2
Usage: $SCRIPT_NAME [-h|--help] [-v|--verbose] [-4] [-6]
        -h|--help: get help
        -v|--verbose: turn on verbose mode (show all answers instead of first)
        -4: use IPv4 only
        -6: use IPv6 only
    --providers LIST: comma-separated provider symbols; may be repeated
    --exclude LIST: comma-separated provider symbols to exclude; may be repeated
END
    exit "$exit_code"
}

opts=$($GETOPT --options hnvd46 --long help,dry-run,debug,verbose,providers:,exclude: --name "$SCRIPT_NAME" -- "$@") || usage
eval set -- "$opts"

while true; do
    case "$1" in
        -h | --help) usage 0 ;;
        -d | --debug) opt_debug=opt_debug; shift ;;
        -v | --verbose) opt_verbose=opt_verbose; shift ;;
        -4) opt_ipv4=opt_ipv4; shift ;;
        -6) opt_ipv6=opt_ipv6; shift ;;
        --providers) opt_providers+=("$2"); shift 2 ;;
        --exclude) opt_exclude+=("$2"); shift 2 ;;
        #-a | --argument) opt_argument="$2"; shift 2 ;;
        --) shift; break ;;
        *) abort "🐛 INTERNAL: unrecognized option '$1'" ;;
    esac
done



##############################################################################
#### Config

# Default providers.
# 2026-07-14 Exclude ident because it's been broken for months
# 2026-01-25 Exclude google because it gives a different IP than Cloudflare (and we care about
#   Cloudflare for srv-crowdsec-allow-ip.sh)
#readonly -a ALLOWED_PROVIDERS=(ident ifconfig ipify ipinfo google cloudflare opendns)
readonly -a ALLOWED_PROVIDERS=(ifconfig ipify ipinfo cloudflare opendns)

providers=("${ALLOWED_PROVIDERS[@]}")
declare -A ALLOWED_PROVIDER_SET=()
declare -A ENABLED_PROVIDER_SET=()
declare -A resolved_provider_set=()
declare -A excluded_provider_set=()
declare -Ar WEB_PROVIDER_URL=(
    [ident]=https://ident.me
    [ifconfig]=https://ifconfig.me
    [ipify]=https://api64.ipify.org
    [ipinfo]=https://ipinfo.io/ip
)

for provider in "${ALLOWED_PROVIDERS[@]}"; do
    ALLOWED_PROVIDER_SET["$provider"]=1
done

function rebuild_enabled_provider_set {
    ENABLED_PROVIDER_SET=()
    local provider=
    for provider in "${providers[@]}"; do
        ENABLED_PROVIDER_SET["$provider"]=1
    done
}

function provider_is_allowed {
    [[ -v ALLOWED_PROVIDER_SET[$1] ]]
}

function provider_is_enabled {
    [[ -v ENABLED_PROVIDER_SET[$1] ]]
}

function add_providers_from_csv {
    local -n _target_array="$1"
    local -n _target_set="$2"
    local -r csv="$3"
    local -a entries=()
    local entry=""
    local trimmed=""

    readarray -td ',' entries < <(printf '%s,' "$csv")
    for entry in "${entries[@]}"; do
        trimmed="${entry,,}"
        trimmed="${trimmed##+([[:space:]])}"
        trimmed="${trimmed%%+([[:space:]])}"
        [[ -n $trimmed ]] || continue

        provider_is_allowed "$trimmed" \
            || abort "Invalid provider '$trimmed'. Allowed: ${ALLOWED_PROVIDERS[*]}"

        if [[ ! -v _target_set[$trimmed] ]]; then
            _target_set["$trimmed"]=1
            _target_array+=("$trimmed")
        fi
    done
}

resolved_providers=()
excluded_providers=()

if [[ ${#opt_providers[@]} -gt 0 ]]; then
    for csv in "${opt_providers[@]}"; do
        add_providers_from_csv resolved_providers resolved_provider_set "$csv"
    done
else
    resolved_providers=("${providers[@]}")
fi

for csv in "${opt_exclude[@]}"; do
    add_providers_from_csv excluded_providers excluded_provider_set "$csv"
done

debug "Resolved providers: ${resolved_providers[*]}"
debug "Resolved provider set size: ${#resolved_provider_set[@]}"
debug "Excluded providers: ${excluded_providers[*]-}"

providers=()
for provider in "${resolved_providers[@]}"; do
    skip=
    [[ -v excluded_provider_set[$provider] ]] && skip=1
    [[ -n $skip ]] || providers+=("$provider")
done

[[ ${#providers[@]} -gt 0 ]] || abort "No providers left after applying --providers/--exclude"

rebuild_enabled_provider_set

debug "Providers: ${providers[*]}"

# shellcheck disable=SC2034
flag_any=
# shellcheck disable=SC2034
flag_ipv4=-4
# shellcheck disable=SC2034
flag_ipv6=-6

readonly -a CURL_FLAGS=(--silent --fail --max-time 2)
readonly -a WGET_FLAGS=(--quiet --output-document=- --timeout=2 --tries=1)
readonly -a OPENSSL_FLAGS=(-quiet -connect)
readonly -a SSH_FLAGS=(-q -o StrictHostKeyChecking=accept-new -o ConnectTimeout=2 -o BatchMode=yes)

case "$OSTYPE" in
    darwin*) NC_FLAGS=(-G 2) ;;
    *) NC_FLAGS=(-w 2) ;;
esac
readonly -a NC_FLAGS

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
    # 2026-07-14 Doesn't w ork:
    #
    # 2025-09-17 Strange, at a cafe where they seem to have IPv6, Cloudflare won't return anything for
    #      dig -4 txt ch +short whoami.cloudflare @1.1.1.1
    #    but Google has no such problem
    # 2025-09-15 ping times to ident.me are bad as they are in Finland so we don't bother with
    #    ident.me for our initial command invocations.
    for cmd_flags in \
        "txt +short o-o.myaddr.google.com @ns1.google.com" \
        "txt ch +short whoami.cloudflare @1dot1dot1dot1.cloudflare-dns.com" \
        "+short myip.opendns.com @resolver1.opendns.com" \
    ; do
        provider=$(echo "$cmd_flags" | perl -lpe 's/.*? (?:[-\w]+\.)+?((?!com)\w+)(\.com)? .*/$1/')
        provider_is_enabled "$provider" || continue
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
                debug "dig $flags $cmd_flags"
                query "$provider dig $ipv" \
                    "$(dig $flags $cmd_flags \
                    | sed -nE 's/^"?([^"]+)"?$/\1/p')"
            fi
        done
    done
fi

if command -v "$NC" &>/dev/null && provider_is_enabled ident; then
    # 2025-09-17 Hmm based on my query to ident.me, nc does fall back to IPv4 more often than other
    #   apps
    for ipv in any ipv4 ipv6; do
        query_key="query_$ipv"
        flag_key="flag_$ipv"
        if [[ -n ${!query_key:-} ]]; then
            debug "$NC ${!flag_key:-} ${NC_FLAGS[*]} ident.me 23"
            query "ident $NC $ipv" \
                "$("$NC" ${!flag_key:-} "${NC_FLAGS[@]}" ident.me 23)"
        fi
    done
fi

# shellcheck disable=SC2066
for web_command in "$CURL"; do
    if command -v "$web_command" &>/dev/null; then
        case "$web_command" in
            *curl) flags=("${CURL_FLAGS[@]}") ;;
            *wget) flags=("${WGET_FLAGS[@]}") ;;
        esac
        for provider in "${providers[@]}"; do
            [[ -v WEB_PROVIDER_URL[$provider] ]] || continue
            url="${WEB_PROVIDER_URL[$provider]}"
            for ipv in any ipv4 ipv6; do
                query_key="query_$ipv"
                flag_key="flag_$ipv"
                if [[ -n ${!query_key:-} ]]; then
                    if [[ $provider == ipinfo ]]; then
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
                    debug "$web_command ${!flag_key:-} ${flags[*]} $url"
                    query "$provider $web_command $ipv" \
                        "$("$web_command" ${!flag_key:-} "${flags[@]}" "$url" \
                        | sed 's/.*"ip":.*"\(.*\)".*/\1/')"
                fi
            done
        done
    fi
done

# In verbose mode, we don't do all types of IPv because that would be redundant with curl
if command -v "$WGET" &>/dev/null && provider_is_enabled ident; then
    if [[ -n $opt_ipv4 ]]; then
        ipv=ipv4
    elif [[ -n $opt_ipv6 && -n ${has_ipv6:-} ]]; then
        ipv=ipv6
    else
        ipv=any
    fi
    query_key="query_$ipv"
    flag_key="flag_$ipv"
    debug "$WGET ${!flag_key:-} ${WGET_FLAGS[*]} https://ident.me"
    query "ident $WGET $ipv" \
        "$("$WGET" ${!flag_key:-} "${WGET_FLAGS[@]}" https://ident.me </dev/null \
        || "$WGET" ${!flag_key:-} "${WGET_FLAGS[@]}" https://tnedi.me </dev/null)"
fi

if command -v "$OPENSSL" &>/dev/null && provider_is_enabled ident; then
    ## 2025-09-17 Doesn't work; I get "Connection refused"
    for ipv in any ipv4 ipv6; do
        query_key="query_$ipv"
        flag_key="flag_$ipv"
        if [[ -n ${!query_key:-} ]]; then
            query "ident $OPENSSL $ipv" \
                "$("$OPENSSL" s_client ${!flag_key:-} "${OPENSSL_FLAGS[@]}" ident.me:992 2>/dev/null)"
        fi
    done
fi

if command -v "$SSH" &>/dev/null && provider_is_enabled ident; then
    for ipv in any ipv4 ipv6; do
        query_key="query_$ipv"
        flag_key="flag_$ipv"
        if [[ -n ${!query_key:-} ]]; then
            query "ident $SSH $ipv" \
                "$("$SSH" ${!flag_key:-} "${SSH_FLAGS[@]}" ident.me)"
        fi
    done
fi

#### End

if [[ -z ${ip:-} ]]; then
    echo "$SCRIPT_NAME: ERROR: Could not find public IP." >&2
    exit 1
fi

exit 0
