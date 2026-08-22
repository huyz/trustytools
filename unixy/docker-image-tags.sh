#!/bin/bash
# Given the name or ID of a Docker container, this prints the repository and
# tag(s) of the image that container is using, if any, by querying Docker Hub
# or GitHub Container Registry.
#
# The lookup is done using the image's RepoDigest (e.g. repo@sha256:...).
# The RepoDigest is the manifest digest that Docker resolved from a registry
# when the image was pulled, so it is the only digest that can be matched up
# against the registries.  In contrast, the local image ID (a hash of the
# local image config) cannot be used to match registry tags.
#
# Steps:
#   1. Take a container name or ID.
#   2. Find which local Docker image that container is using.
#   3. Find that image's RepoDigest.
#   4. Check Docker Hub / GHCR and print the tag(s) pointing at that digest.
#
# Prerequisites:
# - jq
# - docker CLI
#
# TIP:
# To list all the Repo digests for your containers:
#    docker image ls --digests --format 'table {{.Repository}}\t{{.Tag}}\t{{.Digest}}\t{{.ID}}\t{{.CreatedSince}}\t{{.Size}}'
#
# 2026-08-22 Authored mostly by DeepSeek V4 Flash

#### Preamble (v2026-08-14)

set -euo pipefail
shopt -s failglob
# shellcheck disable=SC2329
function trap_err { echo "$(basename "${BASH_SOURCE[0]}"): ERR signal on line $(caller)" >&2; }
trap trap_err ERR
trap exit INT  # So that ^C will stop the entire script, not just the current subprocess
export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

if [[ $OSTYPE == darwin* ]]; then
    HOMEBREW_PREFIX=$( (/opt/homebrew/bin/brew --prefix || /usr/local/bin/brew --prefix || brew --prefix) 2>/dev/null )
    _install_cmd="brew install"
    [[ -x "${GETOPT:="$HOMEBREW_PREFIX/opt/gnu-getopt/bin/getopt"}" ]] || \
        { echo "$0: ERROR: \`$_install_cmd gnu-getopt\` to install $GETOPT." >&2; exit 1; }
    [[ -x "${REALPATH:="$HOMEBREW_PREFIX/bin/grealpath"}" ]] || \
        { echo "$0: ERROR: \`$_install_cmd coreutils\` to install $REALPATH." >&2; exit 1; }
    [[ -x "${JQ:="$HOMEBREW_PREFIX/bin/jq"}" ]] || \
        { echo "$0: ERROR: \`$_install_cmd jq\` to install $JQ." >&2; exit 1; }
    [[ -x "${DOCKER:="$HOMEBREW_PREFIX/bin/docker"}" ]] || \
        { echo "$0: ERROR: \`$_install_cmd docker\` to install $DOCKER." >&2; exit 1; }
    [[ -x "${SORT:="$HOMEBREW_PREFIX/bin/gsort"}" ]] || \
        { echo "$0: ERROR: \`$_install_cmd coreutils\` to install $SORT." >&2; exit 1; }
else
    _install_cmd="sudo apt install"
    GETOPT="getopt"
    REALPATH="realpath"
    command -v "${JQ:=jq}" &>/dev/null || \
        { echo "$0: ERROR: \`$_install_cmd jq\` to install $JQ." >&2; exit 1; }
    command -v "${DOCKER:=docker}" &>/dev/null || \
        { echo "$0: ERROR: \`$_install_cmd docker\` to install $DOCKER." >&2; exit 1; }
    command -v "${SORT:=sort}" &>/dev/null || \
        { echo "$0: ERROR: \`$_install_cmd coreutils\` to install $SORT." >&2; exit 1; }
#    _install_cmd="brew install"
#    HOMEBREW_PREFIX=$( (/home/linuxbrew/.linuxbrew/bin/brew --prefix || brew --prefix) 2>/dev/null )
fi

# shellcheck disable=SC2034
SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")
# a) Uncomment to expand symlinks in order to find the proper .envrc for direnv
#SCRIPT=$($REALPATH "${BASH_SOURCE[0]}")
# b) Uncomment in the general case
SCRIPT=$($REALPATH --no-symlinks "${BASH_SOURCE[0]}")
# shellcheck disable=SC2034
SCRIPT_DIR=$(dirname "$SCRIPT")

#### Utils

# shellcheck disable=SC2059,SC2329
function run_cmd {
    [[ -z ${opt_verbose-} ]] || printf "#❯%s\n" "$(printf " %q" "$@")" || true
    [[ -n ${opt_dry_run-} ]] || "$@"
}

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

#### Config

# Config: number of digest characters to compare (partial match)
CHECK_DIGEST_CHARS="${CHECK_DIGEST_CHARS:-7}"

#### Options

# Defaults
opt_verbose=
opt_debug=
# NOTE:
# - 2026-08-22 For GHCR, we didn't actually look up the default maximum number of tags returned by the GHCR API,
#   so we don't know what the effective limit would be.
# - 2026-08-22 For Docker Hub, we don't paginate, so we effectively have a limit of 100 already.
opt_ghcr_limit=100

function usage {
    local exit_code="${1:-1}"
    cat <<END >&2
Usage: $SCRIPT_NAME [-h|--help] [-v|--verbose] [-d|--debug] [--ghcr-limit value] <container-name-or-id>
        -h|--help: get help
        -v|--verbose: turn on verbose mode
        -d|--debug: turn on debug mode
        --ghcr-limit: to speed up GHCR, limit tags to check (default: $opt_ghcr_limit).
            Tags are sorted first so version-like tags (e.g. "1.2.3" or "v1.2.3")
            are checked first, newest first; other tags keep their original
            order. Set to 0 for unlimited.
END
    exit "$exit_code"
}

opts=$($GETOPT --options hvnd --long help,verbose,dry-run,debug,ghcr-limit: --name "$SCRIPT_NAME" -- "$@") || usage
eval set -- "$opts"

while true; do
    case "$1" in
        -h | --help) usage 0;;
        -v | --verbose) opt_verbose=opt_verbose; shift ;;
        -d | --debug) opt_debug=opt_debug; shift ;;
        --ghcr-limit) opt_ghcr_limit="$2"; shift 2 ;;
        --) shift; break ;;
        *) abort "🐛 INTERNAL: unrecognized option '$1'" ;;
    esac
done

if [[ $# -ne 1 ]]; then
    usage 1
fi

##############################################################################
#### Main

container="$1"

# 1) Find the local Docker image that this container is using.
image_id=$(
    $DOCKER container inspect "$container" --format '{{.Image}}'
) || abort "Cannot inspect container '$container'"

# 2) Find that image's RepoDigest.  The RepoDigest (e.g. repo@sha256:...) is
#    the manifest digest resolved from the registry at pull time, which is the
#    digest to match against.  Do NOT use the image ID -- that is only a local
#    digest of the image config and cannot be matched to registry tags.
repo_digest=$(
    $DOCKER image inspect "$image_id" \
        --format='{{range .RepoDigests}}{{println .}}{{end}}' |
        head -n1
)

if [[ -z "$repo_digest" ]]; then
    echo "No repository digest found for image '$image_id' (used by container '$container')" >&2
    exit 1
fi

# Split e.g. "nginx@sha256:abcd..." into repo and digest.
repo="${repo_digest%%@*}"
repo_sha="${repo_digest##*@}"

# Canonicalize the digest: strip any "sha256:" prefix
repo_sha="${repo_sha#sha256:}"
# Only compare the first $CHECK_DIGEST_CHARS characters (partial match)
digest_prefix="${repo_sha:0:$CHECK_DIGEST_CHARS}"

# Local tag, if any, for display (a container can be running an untagged image).
local_tag=$(
    $DOCKER image inspect "$image_id" \
        --format='{{range .RepoTags}}{{println .}}{{end}}' |
        head -n1
)
if [[ -z "$local_tag" || "$local_tag" == "<none>:<none>" ]]; then
    local_tag="<none>"
else
    local_tag="${local_tag##*:}"
fi

echo "Container: $container"
echo
echo "Local Image ID: $image_id"
echo "Repository:     $repo"
echo "Repository sha: $repo_sha"
echo
echo "Local tag:  $local_tag"
echo
echo "Registry tag(s):"

case "$repo" in
ghcr.io/*)
    # GitHub Container Registry (ghcr.io) - use the OCI Registry API directly.
    # Anonymous access works for public packages; no GitHub repo permissions needed.
    ghcr_path="${repo#ghcr.io/}"

    # --- Bearer-token challenge flow (anonymous) ---
    # The first request returns 401 with a WWW-Authenticate header telling us
    # where to request an anonymous token.
    auth_header=$(
        curl -sS -D - -o /dev/null \
            "https://ghcr.io/v2/$ghcr_path/tags/list" |
            awk 'tolower($1) == "www-authenticate:" { $1=""; sub(/^ /, ""); print; exit }' |
            tr -d '\r'
    )
    realm=$(sed -n 's/.*realm="\([^"]*\)".*/\1/p' <<<"$auth_header")
    service=$(sed -n 's/.*service="\([^"]*\)".*/\1/p' <<<"$auth_header")
    scope=$(sed -n 's/.*scope="\([^"]*\)".*/\1/p' <<<"$auth_header")

    if [[ -z "$realm" ]]; then
        echo "Error: Could not determine token realm from GHCR" >&2
        exit 1
    fi

    token_url="$realm"
    query=""
    [[ -n "$service" ]] && query="service=$service"
    [[ -n "$scope" ]] && query="${query:+&}scope=$scope"
    [[ -n "$query" ]] && token_url+="?$query"

    info "Invoking: curl -fsS \"$token_url\""
    token=$(curl -fsS "$token_url" | $JQ -r '.token // .access_token // empty')
    if [[ -z "$token" ]]; then
        echo "Error: Could not obtain anonymous token from GHCR" >&2
        exit 1
    fi

    # --- Get the list of tags ---
    info "Invoking: curl -fsS -H \"Authorization: Bearer <token>\" \"https://ghcr.io/v2/$ghcr_path/tags/list\""
    tags_response=$(
        curl -fsS \
            -H "Authorization: Bearer $token" \
            "https://ghcr.io/v2/$ghcr_path/tags/list"
    ) || {
        echo "Error: Failed to list tags for $repo (is the package public?)" >&2
        exit 1
    }
    tags=$($JQ -r '.tags[]?' <<<"$tags_response")

    # Sort tags before trimming to --ghcr-limit, so the limit checks the most
    # relevant tags first.  Tags that look like version numbers (e.g. "1.2.3"
    # or "v1.2.3") come first, newest first (`sort -Vr`); all other tags
    # (e.g. "latest", "nightly") keep their original relative order.
    if [[ -n "$tags" ]]; then
        tags=$(
            {
                # Non-version-like tags are first, in their original relative order.
                awk '!/^[vV]?[0-9]+(\.[0-9]+)+(-.*)?$/' <<<"$tags"
                # Version-like tags (optional 'v'/'V' followed by a digit),
                # newest version first.
                awk '/^[vV]?[0-9]+(\.[0-9]+)+(-.*)?$/' <<<"$tags" | $SORT -Vr -s
            }
        )
    fi
    if [[ "$opt_ghcr_limit" -gt 0 ]]; then
        tags=$(head -n "$opt_ghcr_limit" <<<"$tags")
    fi
    info "Found remote tags: $(tr '\n' ' ' <<<"$tags")"

    # --- For each tag, fetch the manifest and compare its digest ---
    # The RepoDigest of a local image is the digest of the manifest (or
    # manifest list) that the tag pointed at when the image was pulled.
    # Querying a tag's manifest returns that same digest in the
    # Docker-Content-Digest response header, so that's what we compare.
    accept="application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json"
    hub_tags=""
    header_tmp=$(mktemp)
    while IFS= read -r tag; do
        [[ -z "$tag" ]] && continue
        info "Invoking: curl -fsS -H \"Authorization: Bearer <token>\" -H \"Accept: $accept\" -D $header_tmp -o /dev/null \"https://ghcr.io/v2/$ghcr_path/manifests/$tag\""
        if ! curl -fsS \
                -H "Authorization: Bearer $token" \
                -H "Accept: $accept" \
                -D "$header_tmp" \
                -o /dev/null \
                "https://ghcr.io/v2/$ghcr_path/manifests/$tag" 2>/dev/null; then
            continue
        fi
        manifest_digest=$(awk 'tolower($1) == "docker-content-digest:" { gsub("\r", "", $2); print $2; exit }' "$header_tmp")

        if [[ -n $opt_verbose ]]; then
            debug "Comparing tag '$tag' with manifest digest '$manifest_digest' against prefix '$digest_prefix'" >&2
        fi

        # Explicit startswith check: does the manifest digest begin with our prefix?
        case "${manifest_digest#sha256:}" in
        "$digest_prefix"*)
            hub_tags+="$tag"$'\n'
            info "✔️ Found matching registry tag: $tag"
            ;;
        esac
    done <<<"$tags"
    rm -f "$header_tmp"
    hub_tags=${hub_tags%$'\n'}
    ;;

*)
    # Docker Hub.  The RepoDigest may be prefixed with "docker.io/" and/or
    # use the "library/" prefix for official images; normalize for the API.
    hub_repo="$repo"
    case "$repo" in
    docker.io/* | index.docker.io/*)
        # e.g. docker.io/library/nginx -> library/nginx
        hub_repo="${repo#*/}"
        ;;
    */*/*)
        echo "Repository $repo is not supported by this script" >&2
        exit 1
        ;;
    esac

    # Official images are stored under library/<repo> in Docker Hub.
    if [[ "$hub_repo" != */* ]]; then
        hub_repo="library/$hub_repo"
    fi

    info "Invoking: curl -fsS \"https://hub.docker.com/v2/repositories/$hub_repo/tags/?page_size=100\""

    # The tag-level ".digest" in the Hub API is the same manifest digest the
    # RepoDigest records, so compare against it.
    hub_tags=$(
        curl -fsS \
            "https://hub.docker.com/v2/repositories/$hub_repo/tags/?page_size=100" |
            $JQ -r --arg digest_prefix "$digest_prefix" '
                .results[]
                | select((.digest // "") | ltrimstr("sha256:") | startswith($digest_prefix))
                | .name
                '
    )
    ;;
esac

echo "Registry tag(s):"
printf '%s\n' "${hub_tags:-<not found>}"
