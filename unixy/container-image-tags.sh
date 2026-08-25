#!/bin/bash
# Given a Docker container, local image, or registry digest, this checks
# whether its known local tag still points to the same remote digest. It can
# then find every current remote registry tag for that digest. Each argument
# is classified by its shape and, where necessary, by probing the local Docker
# daemon.
#
# The lookup is done using the image's RepoDigest (e.g. repo@sha256:...).
# The RepoDigest is the manifest digest that Docker resolved from a registry
# when the image was pulled, so it is the only digest that can be matched up
# against the registries.  In contrast, the local image ID (a hash of the
# local image config) cannot be used to match registry tags.
#
# Why not use Skopeo for every registry?  Skopeo can list tags and inspect a
# tag's manifest, but it cannot reverse-lookup tags by digest.  Its generic
# approach therefore requires one manifest lookup per tag.  Docker Hub's tags
# API and GitHub's Packages API include digests and tags in their paginated
# results, making those common lookups much faster.  Skopeo remains the
# portable fallback for other OCI registries and their configured credentials.
#
# Steps:
#   1. Resolve each argument as a container, local image, or registry digest.
#   2. Find the associated repository digest.
#   3. Check whether the known local tag still points to that remote digest.
#   4. Optionally find and print every current registry tag for that digest.
#
# Prerequisites:
# - curl
# - jq
# - docker CLI
# - registry credentials configured by docker login, skopeo login, or podman
#   login, for private registries
# - Docker Hub username and PAT, only if an exhaustive anonymous scan is refused
# - authenticated gh CLI with read:packages scope, optional fast path for GHCR
# - skopeo, for private-registry fallback and registries other than Docker Hub
#   and GHCR
#
# TIP:
# - To list all the Repo digests for your containers:
#    docker image ls --digests --format 'table {{.Repository}}\t{{.Tag}}\t{{.Digest}}\t{{.ID}}\t{{.CreatedSince}}\t{{.Size}}'
# - To query all local containers:
#   container-image-tags $(docker ps -a --format "{{.Names}}")
#
# 2026-08-22 Authored mostly by DeepSeek V4 Flash and OpenAI's GPT 5.6 Sol

#### Preamble (v2026-08-24)

set -Eeuo pipefail
shopt -s failglob inherit_errexit
SCRIPT_NAME=${BASH_SOURCE[0]##*/}
# shellcheck disable=SC2329
function trap_err { local rc=$?; printf '%s: ERROR: command failed with status %d at %s:%d: %s\n' \
    "$SCRIPT_NAME" "$rc" "${BASH_SOURCE[1]}" "${BASH_LINENO[0]}" "$BASH_COMMAND" >&2; return "$rc"; }
trap trap_err ERR
trap 'exit 130' INT  # Exit this shell on SIGINT rather than continuing after an interrupted command
PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

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
else
    _install_cmd="sudo apt install"
    GETOPT="getopt"
    REALPATH="realpath"
    command -v "${JQ:=jq}" &>/dev/null || \
        { echo "$0: ERROR: \`$_install_cmd jq\` to install $JQ." >&2; exit 1; }
    command -v "${DOCKER:=docker}" &>/dev/null || \
        { echo "$0: ERROR: \`$_install_cmd docker\` to install $DOCKER." >&2; exit 1; }
fi
command -v "${CURL:=curl}" &>/dev/null ||
    { echo "$0: ERROR: \`$_install_cmd curl\` to install $CURL." >&2; exit 1; }

SCRIPT=$("$REALPATH" --no-symlinks "${BASH_SOURCE[0]}")
# shellcheck disable=SC2034
SCRIPT_DIR=$(dirname -- "$SCRIPT")

#### Utils

# shellcheck disable=SC2329
function run_cmd {
    [[ -z ${opt_verbose-} ]] || { printf '#❯'; printf ' %q' "$@"; printf '\n'; } >&2 || true
    [[ -n ${opt_dry_run-} ]] || "$@"
}

# shellcheck disable=SC2329
function debug { [[ -z ${opt_debug-} ]] || printf "%s: 🔧 DEBUG: %s\n" "$SCRIPT_NAME" "$*" >&2; }
# shellcheck disable=SC2329
function info { [[ -z ${opt_verbose-} ]] || printf "%s\n" "$*" >&2; }
# shellcheck disable=SC2329
function warn { printf "%s: ⚠️ WARNING: %s\n" "$SCRIPT_NAME" "$*" >&2; }
# shellcheck disable=SC2329
function err { printf "%s: ❗ ERROR: %s\n" "$SCRIPT_NAME" "$*" >&2; }
# shellcheck disable=SC2329
function abort { printf "%s: ❌ ERROR: %s\n" "$SCRIPT_NAME" "$*" >&2; exit 1; }

function notice { printf "ℹ️ %s\n" "$*" >&2; }

#### Options

# Defaults
opt_verbose=
opt_debug=
opt_ghcr_method=auto
opt_local_only=
opt_all=
docker_hub_token=

function usage {
    cat <<END
Usage: $SCRIPT_NAME [-h|--help] [-v|--verbose] [-d|--debug] [-l|--local-only | -a|--all] [--ghcr-method method] <container-or-image-or-digest> [...]
        -h|--help: get help
        -v|--verbose: turn on verbose mode
        -d|--debug: turn on debug mode
        -l|--local-only: only check whether each known local tag still points to the local digest; never prompt or scan
        -a|--all: check each known local tag, then scan for every remote tag matching the digest; never prompt
        --ghcr-method: select the GHCR tag-check and exhaustive-scan method (default: $opt_ghcr_method):
            auto: check public tags anonymously; use the Packages API for exhaustive scans and private-tag fallback
            packages: use only the GitHub Packages API; never prompt or fall back
            anonymous: use only the anonymous OCI scan; never prompt

By default, each known local tag is checked first, then you are asked whether
to scan the registry for every tag that points to the same digest.
Docker Hub scans start anonymously. If deeper pagination requires sign-in, an
interactive run can exchange a username and PAT for an in-memory access token.
Private registry access reuses credentials configured by docker login, skopeo
login, or podman login; credential values are never passed on this command line.

Arguments are interpreted as follows:
        repository@sha256:...: use this registry digest directly
        repository:*: immediately match every local tag in that repository
        image name with an explicit tag: inspect that exact local image
        SHA-like value: try a local container ID, then a local image ID, then a registry digest
        image name without a tag (including names with '/'): try ':latest', then match every local repository tag
        any other value: try a container name before treating it as an image name
END
}

opts=$("$GETOPT" --options hvalnd --long help,verbose,all,local-only,dry-run,debug,ghcr-method: --name "$SCRIPT_NAME" -- "$@") || { usage >&2; exit 2; }
eval set -- "$opts"

while true; do
    case "$1" in
        -h | --help) usage; exit 0 ;;
        -v | --verbose) opt_verbose=opt_verbose; shift ;;
        -d | --debug) opt_debug=opt_debug; shift ;;
        -l | --local-only) opt_local_only=opt_local_only; shift ;;
        -a | --all) opt_all=opt_all; shift ;;
        --ghcr-method) opt_ghcr_method="$2"; shift 2 ;;
        --) shift; break ;;
        *) abort "🐛 INTERNAL: unrecognized option '$1'" ;;
    esac
done

case "$opt_ghcr_method" in
auto | packages | anonymous) ;;
*) abort "--ghcr-method must be 'auto', 'packages', or 'anonymous'" ;;
esac

if [[ -n "$opt_local_only" && -n "$opt_all" ]]; then
    abort "--local-only and --all are mutually exclusive"
fi

[[ $# -ge 1 ]] || { usage >&2; exit 1; }

# Skopeo reads credentials written by skopeo/podman login and, as a fallback,
# Docker's config.json (including credential helpers).  Keep all Skopeo calls
# behind these helpers so private-registry behavior is consistent for the
# direct tag check and the exhaustive reverse lookup.
function skopeo_is_available {
    SKOPEO="${SKOPEO:-skopeo}"
    command -v "$SKOPEO" &>/dev/null
}

function skopeo_has_registry_credentials {
    local registry="$1"

    skopeo_is_available &&
        "$SKOPEO" login --get-login "$registry" >/dev/null 2>&1
}

function skopeo_digest_for_tag {
    local image_reference="$1"

    skopeo_is_available || return 127
    "$SKOPEO" inspect --format '{{.Digest}}' "docker://$image_reference" 2>/dev/null
}

function skopeo_tags_by_digest {
    local repository="$1"
    local digest="$2"
    local tags tag manifest_digest
    local checked=0
    local matches=
    local -a spinner=('|' '/' '-' $'\\')

    skopeo_is_available || return 127
    info "Listing registry tags with skopeo for $repository"
    tags=$(
        "$SKOPEO" list-tags "docker://$repository" |
            $JQ -r '.Tags[]?'
    ) || return 1

    if [[ -z ${opt_verbose-} ]]; then
        printf 'Searching registry tags with skopeo... %s (0 checked)' "${spinner[0]}" >&2
    fi
    while IFS= read -r tag; do
        [[ -n "$tag" ]] || continue
        info "Resolving registry tag with skopeo: $tag"
        if manifest_digest=$(skopeo_digest_for_tag "$repository:$tag"); then
            if [[ "$manifest_digest" == "$digest" ]]; then
                matches+="${matches:+$'\n'}$tag"
            fi
        fi
        ((++checked))
        if [[ -z ${opt_verbose-} ]]; then
            printf '\rSearching registry tags with skopeo... %s (%d checked)' \
                "${spinner[checked % 4]}" "$checked" >&2
        fi
    done <<<"$tags"
    if [[ -z ${opt_verbose-} ]]; then
        printf '\rSearching registry tags with skopeo... done (%d checked)\n' "$checked" >&2
    fi

    printf '%s' "$matches"
}

# Look up an active GHCR package version by immutable digest or current tag.
# GitHub's Packages API exposes the digest, timestamps, and current tags in the
# same object, so no tag-by-tag manifest lookup is needed.
#
# Return values:
#   0: version found (the version object is printed as compact JSON)
#   1: API queried successfully, but no active version matched
#   2: API could not be queried (usually authentication or rate limiting)
function ghcr_package_version {
    local ghcr_repository="$1"
    local selector="$2"
    local wanted="$3"
    local owner package_name package_encoded owner_kind endpoint response_tmp match
    local queried_api=

    owner="${ghcr_repository%%/*}"
    package_name="${ghcr_repository#*/}"
    if [[ -z "$owner" || -z "$package_name" || "$package_name" == "$owner" ]]; then
        return 2
    fi

    # shellcheck disable=SC2016  # jq expression, not a shell expansion
    package_encoded=$($JQ -rn --arg value "$package_name" '$value | @uri')

    command -v "${GH:=gh}" &>/dev/null || return 2
    response_tmp=$(mktemp)

    # A GHCR namespace can belong to either an organization or a user. Try
    # both owner-specific Packages API endpoints.
    for owner_kind in orgs users; do
        endpoint="/$owner_kind/$owner/packages/container/$package_encoded/versions?per_page=100"
        info "Searching GitHub package versions for $owner_kind/$owner/$package_name"
        if ! "$GH" api --paginate "$endpoint" >"$response_tmp" 2>/dev/null; then
            continue
        fi
        queried_api=1

        # gh emits one JSON array per page. Combine the pages and use GitHub's
        # creation timestamp as the recency signal before selecting a version.
        # shellcheck disable=SC2016  # jq expression, not a shell expansion
        match=$(
            $JQ -sc --arg selector "$selector" --arg wanted "$wanted" '
                (add // [])
                | sort_by(.created_at)
                | reverse
                | first(
                    .[]
                    | select(
                        if $selector == "digest" then
                            .name == $wanted
                        else
                            (.metadata.container.tags // [] | index($wanted)) != null
                        end
                    )
                ) // empty
            ' "$response_tmp"
        )
        if [[ -n "$match" ]]; then
            rm -f "$response_tmp"
            printf '%s\n' "$match"
            return 0
        fi
    done

    rm -f "$response_tmp"
    [[ -n "$queried_api" ]] && return 1
    return 2
}

function ghcr_package_version_by_digest {
    ghcr_package_version "$1" digest "$2"
}

function ghcr_package_version_by_tag {
    ghcr_package_version "$1" tag "$2"
}

# Request a repository-scoped anonymous GHCR pull token.
function ghcr_anonymous_pull_token {
    local ghcr_repository="$1"
    local auth_header realm service scope token
    local -a token_args

    if ! auth_header=$(
        $CURL -sS -D - -o /dev/null "https://ghcr.io/v2/$ghcr_repository/tags/list" |
            perl -ne 'if (/^www-authenticate:\s*(.*)/i) { print "$1\n"; exit }'
    ); then
        return 1
    fi
    realm=$(sed -n 's/.*realm="\([^"]*\)".*/\1/p' <<<"$auth_header")
    service=$(sed -n 's/.*service="\([^"]*\)".*/\1/p' <<<"$auth_header")
    scope=$(sed -n 's/.*scope="\([^"]*\)".*/\1/p' <<<"$auth_header")
    [[ -n "$realm" ]] || return 1

    token_args=(-fsS -G)
    [[ -n "$service" ]] && token_args+=(--data-urlencode "service=$service")
    [[ -n "$scope" ]] && token_args+=(--data-urlencode "scope=$scope")
    token=$(
        $CURL "${token_args[@]}" "$realm" |
            $JQ -r '.token // .access_token // empty'
    ) || return 1
    [[ -n "$token" ]] || return 1
    printf '%s\n' "$token"
}

# Return the current remote digest for one public GHCR tag without enumerating
# any other tags. A missing tag returns 1; authentication or transport failures
# return 2.
function ghcr_digest_for_tag_anonymously {
    local ghcr_repository="$1"
    local tag="$2"
    local tag_encoded token header_tmp http_code manifest_digest

    token=$(ghcr_anonymous_pull_token "$ghcr_repository") || return 2
    tag_encoded=$($JQ -rn --arg value "$tag" '$value | @uri')
    header_tmp=$(mktemp)
    if ! http_code=$(
        $CURL -sS -I -D "$header_tmp" -o /dev/null -w '%{http_code}' \
            -H "Authorization: Bearer $token" \
            -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json' \
            "https://ghcr.io/v2/$ghcr_repository/manifests/$tag_encoded"
    ); then
        rm -f "$header_tmp"
        return 2
    fi
    if [[ "$http_code" == 404 ]]; then
        rm -f "$header_tmp"
        return 1
    fi
    if [[ "$http_code" != 200 ]]; then
        debug "Anonymous GHCR tag lookup returned HTTP $http_code for $ghcr_repository:$tag"
        rm -f "$header_tmp"
        return 2
    fi

    manifest_digest=$(
        perl -ne 'if (/^docker-content-digest:\s*(\S+)/i) { print "$1\n"; exit }' "$header_tmp"
    )
    rm -f "$header_tmp"
    [[ -n "$manifest_digest" ]] || return 2
    printf '%s\n' "$manifest_digest"
}

# Honor the requested GHCR method while preferring the inexpensive public
# manifest check in auto mode. The Packages API fallback also supports private
# packages when gh has read:packages access.
function ghcr_digest_for_tag {
    local ghcr_repository="$1"
    local tag="$2"
    local manifest_digest package_version lookup_status

    if [[ "$opt_ghcr_method" != packages ]]; then
        if manifest_digest=$(ghcr_digest_for_tag_anonymously "$ghcr_repository" "$tag"); then
            printf '%s\n' "$manifest_digest"
            return 0
        else
            lookup_status=$?
        fi
        if [[ "$lookup_status" == 1 || "$opt_ghcr_method" == anonymous ]]; then
            return "$lookup_status"
        fi
    fi

    if package_version=$(ghcr_package_version_by_tag "$ghcr_repository" "$tag"); then
        manifest_digest=$($JQ -r '.name // empty' <<<"$package_version")
        [[ -n "$manifest_digest" ]] || return 2
        printf '%s\n' "$manifest_digest"
        return 0
    else
        lookup_status=$?
    fi

    if [[ "$lookup_status" == 2 && "$opt_ghcr_method" == auto ]] &&
            manifest_digest=$(skopeo_digest_for_tag "ghcr.io/$ghcr_repository:$tag"); then
        info "Resolved private GHCR tag with configured registry credentials"
        printf '%s\n' "$manifest_digest"
        return 0
    fi
    return "$lookup_status"
}

# Return the digest in one Docker Hub tag record without walking paginated tag
# results. A missing tag returns 1; authentication or transport failures
# return 2.
function docker_hub_digest_for_tag {
    local hub_repository="$1"
    local tag="$2"
    local tag_encoded response_tmp http_code manifest_digest
    local -a request_args

    tag_encoded=$($JQ -rn --arg value "$tag" '$value | @uri')
    response_tmp=$(mktemp)
    request_args=(-sS -o "$response_tmp" -w '%{http_code}')
    if [[ -n "$docker_hub_token" ]]; then
        request_args+=(-H "Authorization: Bearer $docker_hub_token")
    fi
    if ! http_code=$(
        $CURL "${request_args[@]}" \
            "https://hub.docker.com/v2/repositories/$hub_repository/tags/$tag_encoded"
    ); then
        rm -f "$response_tmp"
        return 2
    fi
    case "$http_code" in
    200)
        manifest_digest=$($JQ -r '.digest // empty' "$response_tmp")
        rm -f "$response_tmp"
        [[ -n "$manifest_digest" ]] || return 2
        printf '%s\n' "$manifest_digest"
        ;;
    404)
        rm -f "$response_tmp"
        return 1
        ;;
    *)
        debug "Docker Hub tag lookup returned HTTP $http_code for $hub_repository:$tag"
        rm -f "$response_tmp"
        return 2
        ;;
    esac
}

# Exchange a Docker Hub username and PAT for a short-lived API access token.
# Credentials are read from the controlling terminal, sent through stdin, and
# retained only long enough to perform the exchange.
function docker_hub_token_interactively {
    local identifier secret response http_code response_body token error_message

    if [[ ! -t 0 && ! -t 1 && ! -t 2 ]]; then
        return 2
    fi
    printf 'Docker Hub username: ' >&2
    IFS= read -r identifier </dev/tty || return 2
    [[ -n "$identifier" ]] || { warn "Docker Hub username cannot be empty"; return 1; }

    printf 'Docker Hub personal access token ("Public Repo Read-only" minimum): ' >&2
    IFS= read -rs secret </dev/tty || return 2
    printf '\n' >&2
    [[ -n "$secret" ]] || { warn "Docker Hub personal access token cannot be empty"; return 1; }

    if ! response=$(
        printf '%s\n%s\n' "$identifier" "$secret" |
            $JQ -Rnc '{identifier: input, secret: input}' |
            $CURL -sS -w $'\n%{http_code}' \
                -H 'Content-Type: application/json' \
                --data-binary @- \
                'https://hub.docker.com/v2/auth/token'
    ); then
        secret=
        warn "Docker Hub authentication request failed"
        return 1
    fi
    secret=
    http_code="${response##*$'\n'}"
    response_body="${response%$'\n'*}"
    response=

    if [[ "$http_code" == 200 ]]; then
        token=$($JQ -r '.access_token // .token // empty' <<<"$response_body")
        response_body=
        if [[ -n "$token" ]]; then
            printf '%s\n' "$token"
            return 0
        fi
        warn "Docker Hub authentication response did not contain an access token"
        return 1
    fi

    error_message=$(
        $JQ -r '(.detail // .message // .error // empty) | if type == "string" then . else tostring end' \
            <<<"$response_body" 2>/dev/null || true
    )
    response_body=
    warn "Docker Hub authentication failed (HTTP $http_code)${error_message:+: $error_message}"
    return 1
}

# Explain why anonymous pagination stopped and offer authentication or a
# per-image skip. The access token is printed on success; return 1 for skip and
# 2 when no controlling terminal is available.
function choose_docker_hub_authentication {
    local failure_message="$1"
    local choice token auth_status

    if [[ ! -t 0 && ! -t 1 && ! -t 2 ]]; then
        return 2
    fi
    echo "$SCRIPT_NAME: Docker Hub refused further anonymous tag pagination." >&2
    [[ -z "$failure_message" ]] || echo "  $failure_message" >&2
    echo "  [a] Authenticate for this run with a Docker Hub username and PAT" >&2
    echo "  [s] Skip this image" >&2
    while true; do
        printf 'Choose [a/s]: ' >&2
        IFS= read -r choice </dev/tty || return 2
        case "$choice" in
        a | A)
            if token=$(docker_hub_token_interactively); then
                printf '%s\n' "$token"
                return 0
            else
                auth_status=$?
            fi
            (( auth_status == 2 )) && return 2
            ;;
        s | S)
            return 1
            ;;
        esac
    done
}

# Ask whether to perform the exhaustive reverse lookup after the known local
# tag has been checked. Return 0 for scan, 1 for no scan, and 2 when prompting
# is unavailable.
function choose_remote_tag_scan {
    local choice

    if [[ ! -t 0 && ! -t 1 && ! -t 2 ]]; then
        return 2
    fi
    while true; do
        printf 'Scan for every remote tag that matches this digest? [y/N]: ' >&2
        IFS= read -r choice </dev/tty || return 2
        case "$choice" in
        y | Y | yes | YES | Yes) return 0 ;;
        '' | n | N | no | NO | No) return 1 ;;
        esac
    done
}

# Print every current GHCR tag whose manifest has the requested digest. This
# uses only GHCR's anonymous OCI Registry API, but requires one request per tag.
function ghcr_tags_by_digest_anonymously {
    local ghcr_repository="$1"
    local digest="$2"
    local token
    local tags="" next_url next_link page_tags tag manifest_digest
    local header_tmp body_tmp checked=0
    local -a spinner=('|' '/' '-' $'\\')

    info "Requesting an anonymous GHCR pull token"
    token=$(ghcr_anonymous_pull_token "$ghcr_repository") || return 1

    header_tmp=$(mktemp)
    body_tmp=$(mktemp)
    next_url="https://ghcr.io/v2/$ghcr_repository/tags/list?n=100"
    while [[ -n "$next_url" ]]; do
        info "Listing GHCR tags from: $next_url"
        if ! $CURL -fsS -H "Authorization: Bearer $token" \
                -D "$header_tmp" -o "$body_tmp" "$next_url"; then
            rm -f "$header_tmp" "$body_tmp"
            return 1
        fi

        page_tags=$($JQ -r '.tags[]?' "$body_tmp")
        if [[ -n "$page_tags" ]]; then
            tags+="${tags:+$'\n'}$page_tags"
        fi

        next_link=$(
            perl -ne '
                if (/^Link:\s*(.*)/i) {
                    for (split /,\s*/, $1) {
                        if (/<([^>]+)>;\s*rel="next"/) {
                            print "$1\n";
                            exit;
                        }
                    }
                }
            ' "$header_tmp"
        )
        case "$next_link" in
        http://* | https://*) next_url="$next_link" ;;
        /*) next_url="https://ghcr.io$next_link" ;;
        *) next_url="" ;;
        esac
    done

    if [[ -z ${opt_verbose-} ]]; then
        printf 'Searching GHCR tags anonymously... %s (0 checked)' "${spinner[0]}" >&2
    fi
    while IFS= read -r tag; do
        [[ -n "$tag" ]] || continue
        info "Resolving GHCR tag: $tag"
        if $CURL -fsS -H "Authorization: Bearer $token" \
                -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json' \
                -D "$header_tmp" -o /dev/null \
                "https://ghcr.io/v2/$ghcr_repository/manifests/$tag" 2>/dev/null; then
            manifest_digest=$(
                perl -ne 'if (/^docker-content-digest:\s*(\S+)/i) { print "$1\n"; exit }' "$header_tmp"
            )
            if [[ "$manifest_digest" == "$digest" ]]; then
                printf '%s\n' "$tag"
            fi
        fi
        ((++checked))
        if [[ -z ${opt_verbose-} ]]; then
            printf '\rSearching GHCR tags anonymously... %s (%d checked)' \
                "${spinner[checked % 4]}" "$checked" >&2
        fi
    done <<<"$tags"
    if [[ -z ${opt_verbose-} ]]; then
        printf '\rSearching GHCR tags anonymously... done (%d checked)\n' "$checked" >&2
    fi

    rm -f "$header_tmp" "$body_tmp"
}

# Ask how to proceed when the Packages API cannot be used. The selected action
# is printed as either "refresh" or "anonymous".
function choose_ghcr_fallback {
    local can_refresh="$1"
    local choice

    if [[ ! -t 0 && ! -t 1 && ! -t 2 ]]; then
        return 1
    fi

    echo "$SCRIPT_NAME: GitHub Packages API credentials with read:packages scope are unavailable." >&2
    if [[ -n "$can_refresh" ]]; then
        echo "  [r] Run 'gh auth refresh -s read:packages', then retry" >&2
        echo "  [a] Use the slower anonymous OCI tag scan" >&2
        echo "  [s] Skip GHCR lookup and exit" >&2
        while true; do
            printf "Choose [r/a/s]: " >&2
            IFS= read -r choice </dev/tty || return 1
            case "$choice" in
            r | R) printf 'refresh\n'; return 0 ;;
            a | A) printf 'anonymous\n'; return 0 ;;
            s | S) printf 'skip\n'; return 0 ;;
            esac
        done
    fi

    printf "The gh CLI is unavailable. [y] Use the slower anonymous OCI tag scan [s] Skip and exit. Choose [y/s]: " >&2
    IFS= read -r choice </dev/tty || return 1
    case "$choice" in
    y | Y | yes | YES | Yes) printf 'anonymous\n' ;;
    s | S) printf 'skip\n' ;;
    *) return 1 ;;
    esac
}

# Resolve a local image reference and populate the image fields used by the
# main lookup.  An image can exist locally without a RepoDigest, so an empty
# repo_digest still counts as a successful image resolution.
function inspect_local_image {
    local image_ref="$1"
    local preferred_repository="${2:-}"
    local preferred_tag="${3:-}"
    local repo_digests repo_tags candidate candidate_repository

    if ! image_id=$(
        $DOCKER image inspect "$image_ref" --format '{{.Id}}' 2>/dev/null
    ); then
        return 1
    fi
    repo_digests=$(
        $DOCKER image inspect "$image_id" \
            --format='{{range .RepoDigests}}{{println .}}{{end}}' 2>/dev/null
    ) || return 1
    repo_tags=$(
        $DOCKER image inspect "$image_id" \
            --format='{{range .RepoTags}}{{println .}}{{end}}' 2>/dev/null
    ) || return 1
    local_image_version=$(
        $DOCKER image inspect "$image_id" \
            --format='{{with index .Config.Labels "org.opencontainers.image.version"}}{{.}}{{end}}' 2>/dev/null
    ) || return 1

    repo_digest=
    local_tag=
    if [[ -n "$preferred_repository" ]]; then
        while IFS= read -r candidate; do
            [[ -n "$candidate" ]] || continue
            if [[ "${candidate%%@*}" == "$preferred_repository" ]]; then
                repo_digest="$candidate"
                break
            fi
        done <<<"$repo_digests"
        if [[ -n "$preferred_tag" ]] && grep -Fxq -- "$preferred_tag" <<<"$repo_tags"; then
            local_tag="$preferred_tag"
        else
            while IFS= read -r candidate; do
                [[ -n "$candidate" ]] || continue
                candidate_repository="${candidate%:*}"
                if [[ "$candidate_repository" == "$preferred_repository" ]]; then
                    local_tag="$candidate"
                    break
                fi
            done <<<"$repo_tags"
        fi
    else
        repo_digest="${repo_digests%%$'\n'*}"
        local_tag="${repo_tags%%$'\n'*}"
    fi
}

# Print every distinct local image ID whose repository name exactly matches
# the requested untagged name.  Tags are deliberately ignored here.
function image_ids_for_repository {
    local wanted_repository="$1"
    local image_rows repository image_id_candidate
    local matches=

    image_rows=$(
        $DOCKER image ls --no-trunc --format '{{.Repository}}\t{{.ID}}' 2>/dev/null
    ) || return 1
    while IFS=$'\t' read -r repository image_id_candidate; do
        if [[ "$repository" == "$wanted_repository" && -n "$image_id_candidate" ]]; then
            matches+="${matches:+$'\n'}$image_id_candidate"
        fi
    done <<<"$image_rows"

    [[ -n "$matches" ]] || return 1
    printf '%s\n' "$matches" | sort -u
}

# Strip an explicit tag from an image reference without mistaking a registry
# port (as in localhost:5000/repo) for a tag.
function repository_from_image_reference {
    local image_reference="$1"
    local final_component

    image_reference="${image_reference%%@*}"
    final_component="${image_reference##*/}"
    if [[ "$final_component" == *:* ]]; then
        image_reference="${image_reference%:*}"
    fi
    printf '%s\n' "$image_reference"
}

# Find locally known repository digests whose complete SHA matches a bare
# registry digest.  A content digest does not identify its repository, so this
# local metadata is required before a registry can be queried.
function repo_digests_for_sha {
    local wanted_sha="$1"
    local image_ids candidate_repo_digests image candidate digest
    local matches=

    image_ids=$($DOCKER image ls --no-trunc --quiet 2>/dev/null) || return 1
    while IFS= read -r image; do
        [[ -n "$image" ]] || continue
        candidate_repo_digests=$(
            $DOCKER image inspect "$image" \
                --format='{{range .RepoDigests}}{{println .}}{{end}}' 2>/dev/null
        ) || continue
        while IFS= read -r candidate; do
            [[ -n "$candidate" ]] || continue
            digest="${candidate##*@}"
            if [[ "${digest#sha256:}" == "$wanted_sha" ]]; then
                matches+="${matches:+$'\n'}$candidate"
            fi
        done <<<"$candidate_repo_digests"
    done <<<"$image_ids"

    [[ -n "$matches" ]] || return 1
    printf '%s\n' "$matches" | sort -u
}

##############################################################################
#### Main

input_index=0
for input in "$@"; do
    if (( input_index > 0 )); then
        separator_columns="${COLUMNS:-$(tput cols 2>/dev/null || true)}"
        (( separator_columns > 0 )) || separator_columns=80
        printf '%*s\n' "$separator_columns" '' | tr ' ' '-'
    fi
    ((++input_index))
    skip_input=
    container=
    image_id=
    local_image_version=
    repo_digest=
    local_tag=
    wildcard_image_ids=
    wildcard_reference=
    wildcard_repository=

    # A full repository digest is already unambiguous and does not need local
    # Docker metadata.
    if [[ "$input" == *@* ]]; then
        if [[ "$input" =~ ^.+@sha256:[0-9a-f]{64}$ ]]; then
            repo_digest="$input"
            notice "Interpreting '$input' as a complete registry digest reference."
        else
            abort "'$input' looks like a registry digest reference, but expected repository@sha256:<64 lowercase hex characters>"
        fi

    # SHA-like inputs are inherently ambiguous because Docker container IDs and
    # local image IDs are both hashes.  Probe in the documented order.
    elif [[ "$input" =~ ^([Ss][Hh][Aa]256:)?[0-9a-fA-F]{12,64}$ ]]; then
        if resolved_image_id=$(
            $DOCKER container inspect "$input" --format '{{.Image}}' 2>/dev/null
        ); then
            container="$input"
            inspect_local_image "$resolved_image_id" ||
                abort "Container '$container' refers to image '$resolved_image_id', but that image cannot be inspected"
            notice "Resolved SHA-like '$input' as a local container ID (image $image_id)."
        elif inspect_local_image "$input"; then
            notice "Resolved SHA-like '$input' as local image ID $image_id."
        else
            registry_sha="$input"
            [[ "$registry_sha" == *:* ]] && registry_sha="${registry_sha#*:}"
            notice "No local container or image ID matched '$input'; assuming it is a registry digest."
            if [[ ! "$registry_sha" =~ ^[0-9a-f]{64}$ ]]; then
                abort "A registry digest must contain exactly 64 lowercase hex characters; pass repository@sha256:<digest> if it is not locally known"
            fi
            if ! matching_repo_digests=$(repo_digests_for_sha "$registry_sha"); then
                abort "Cannot determine the repository for sha256:$registry_sha from local images; pass repository@sha256:$registry_sha"
            fi
            repo_digest="${matching_repo_digests%%$'\n'*}"
            if [[ "$matching_repo_digests" == *$'\n'* ]]; then
                warn "sha256:$registry_sha is associated with multiple local repositories; using '$repo_digest'. Pass a complete repository@sha256:... argument to select another."
            else
                notice "Recovered registry reference '$repo_digest' from local image metadata."
            fi
        fi

    # A slash identifies an image name, as does an explicit tag in the final path
    # component.  A literal :* requests an immediate wildcard scan.  For names
    # without an explicit tag, prefer Docker's normal implicit :latest resolution
    # and only then broaden the name to a :* match.
    elif [[ "$input" == */* || "${input##*/}" == *:* ]]; then
        preferred_repository=$(repository_from_image_reference "$input")
        final_component="${input##*/}"
        if [[ "$final_component" == *:* && "${final_component##*:}" == '*' ]]; then
            if ! wildcard_image_ids=$(image_ids_for_repository "$preferred_repository"); then
                abort "Cannot find any local image in repository '$preferred_repository'"
            fi
            wildcard_reference="$input"
            wildcard_repository="$preferred_repository"
            wildcard_count=0
            while IFS= read -r wildcard_image_id; do
                [[ -n "$wildcard_image_id" ]] && ((++wildcard_count))
            done <<<"$wildcard_image_ids"
            notice "Explicit wildcard '$input' requested; immediately checking $wildcard_count distinct local image(s)."
        elif [[ "$final_component" == *:* ]]; then
            inspect_local_image "$input" "$preferred_repository" "$input" ||
                abort "Cannot inspect local image '$input'"
            notice "Interpreting '$input' as a tagged local image reference."
        elif inspect_local_image "$input" "$preferred_repository" "$preferred_repository:latest"; then
            notice "Resolved '$input' using its implicit ':latest' tag; not scanning other local tags."
        elif wildcard_image_ids=$(image_ids_for_repository "$preferred_repository"); then
            wildcard_reference="$preferred_repository:*"
            wildcard_repository="$preferred_repository"
            wildcard_count=0
            while IFS= read -r wildcard_image_id; do
                [[ -n "$wildcard_image_id" ]] && ((++wildcard_count))
            done <<<"$wildcard_image_ids"
            notice "No local '$input:latest' image was found; interpreting '$input' as '$input:*' and checking $wildcard_count distinct local image(s)."
        else
            abort "Cannot find any local image in repository '$preferred_repository'"
        fi

    # Otherwise prefer a container name, then permit an image name without an
    # explicit tag.  The image lookup follows the same :latest-before-:* rule.
    else
        if resolved_image_id=$(
            $DOCKER container inspect "$input" --format '{{.Image}}' 2>/dev/null
        ); then
            container="$input"
            inspect_local_image "$resolved_image_id" ||
                abort "Container '$container' refers to image '$resolved_image_id', but that image cannot be inspected"
            notice "Resolved '$input' as a local container name (image $image_id)."
        elif inspect_local_image "$input" "$input" "$input:latest"; then
            notice "No container named '$input' was found; resolved the image using its implicit ':latest' tag and will not scan other local tags."
        elif wildcard_image_ids=$(image_ids_for_repository "$input"); then
            wildcard_reference="$input:*"
            wildcard_repository="$input"
            wildcard_count=0
            while IFS= read -r wildcard_image_id; do
                [[ -n "$wildcard_image_id" ]] && ((++wildcard_count))
            done <<<"$wildcard_image_ids"
            notice "No container or local '$input:latest' image was found; interpreting '$input' as '$input:*' and checking $wildcard_count distinct local image(s)."
        else
            abort "Cannot resolve '$input' as a local container name or local image repository"
        fi
    fi

    # Most arguments resolve to one lookup.  An untagged repository without a
    # local :latest image can expand to multiple distinct image IDs.
    images_to_process="${wildcard_image_ids:-__current_resolution__}"
    wildcard_output_index=0
    seen_wildcard_repo_digests=
    while IFS= read -r image_to_process; do
        skip_input=
        if [[ "$image_to_process" != __current_resolution__ ]]; then
            container=
            inspect_local_image "$image_to_process" "$wildcard_repository" || {
                warn "Cannot inspect wildcard image match '$image_to_process'; skipping it"
                continue
            }
        fi

    if [[ -z "$repo_digest" ]]; then
        if [[ -n "$container" ]]; then
            echo "No repository digest found for image '$image_id' (used by container '$container')" >&2
        elif [[ -n "$wildcard_image_ids" ]]; then
            warn "No repository digest found for wildcard image '$image_id'; skipping it"
            continue
        else
            echo "No repository digest found for image '$image_id'" >&2
        fi
        exit 1
    fi

    if [[ -n "$wildcard_image_ids" ]]; then
        if grep -Fxq -- "$repo_digest" <<<"$seen_wildcard_repo_digests"; then
            notice "Skipping local image $image_id because repository digest '$repo_digest' was already checked."
            continue
        fi
        seen_wildcard_repo_digests+="${seen_wildcard_repo_digests:+$'\n'}$repo_digest"
        if (( wildcard_output_index > 0 )); then
            separator_columns="${COLUMNS:-$(tput cols 2>/dev/null || true)}"
            (( separator_columns > 0 )) || separator_columns=80
            printf '%*s\n' "$separator_columns" '' | tr ' ' '-'
        fi
        ((++wildcard_output_index))
        notice "Resolved '$wildcard_reference' to local image $image_id."
    fi

    # Split e.g. "nginx@sha256:abcd..." into repo and digest.
    repo="${repo_digest%%@*}"
    repo_sha="${repo_digest##*@}"

    # Canonicalize the digest: strip any "sha256:" prefix
    repo_sha="${repo_sha#sha256:}"

    if [[ -z "$local_tag" || "$local_tag" == "<none>:<none>" ]]; then
        local_tag="<none>"
    else
        local_tag="${local_tag##*:}"
    fi

    # Classify the registry once so the direct local-tag check and the optional
    # exhaustive scan use the same normalization.
    registry_kind=other
    first_component="${repo%%/*}"
    case "$repo" in
    ghcr.io/*)
        registry_kind=ghcr
        ghcr_path="${repo#ghcr.io/}"
        ;;
    *)
        if [[ "$repo" != */* ||
                "$first_component" != *.* && "$first_component" != *:* &&
                "$first_component" != localhost ]] ||
                [[ "$first_component" == docker.io ||
                "$first_component" == index.docker.io ||
                "$first_component" == registry-1.docker.io ]]; then
            registry_kind=docker-hub
            hub_repo="$repo"
            case "$hub_repo" in
            docker.io/* | index.docker.io/* | registry-1.docker.io/*)
                hub_repo="${hub_repo#*/}"
                ;;
            esac
            if [[ "$hub_repo" != */* ]]; then
                hub_repo="library/$hub_repo"
            fi
        fi
        ;;
    esac

    if [[ -n "$container" ]]; then
        echo "Container: $container"
        echo
    fi
    if [[ -n "$image_id" ]]; then
        echo "Local Image ID: $image_id"
        if [[ -n "$local_image_version" ]]; then
            echo "Image version:  $local_image_version"
        fi
    fi
    echo "Repository:     $repo"
    echo "Package digest: ${repo_digest##*@}"
    echo
    if [[ -n "$image_id" ]]; then
        echo "Local tag:  $local_tag"
    fi

    if [[ "$local_tag" == "<none>" ]]; then
        echo "Remote tag check: unavailable because this image has no known local tag"
    else
        remote_tag_reference="$repo:$local_tag"
        remote_tag_digest=
        case "$registry_kind" in
        docker-hub)
            if remote_tag_digest=$(docker_hub_digest_for_tag "$hub_repo" "$local_tag"); then
                remote_tag_status=0
            else
                remote_tag_status=$?
            fi
            if [[ "$remote_tag_status" == 2 ]] &&
                    remote_tag_digest=$(skopeo_digest_for_tag "$remote_tag_reference"); then
                info "Resolved Docker Hub tag with configured registry credentials"
                remote_tag_status=0
            fi
            ;;
        ghcr)
            if remote_tag_digest=$(ghcr_digest_for_tag "$ghcr_path" "$local_tag"); then
                remote_tag_status=0
            else
                remote_tag_status=$?
            fi
            ;;
        other)
            skopeo_is_available ||
                abort "Install skopeo to check registry tag '$remote_tag_reference'"
            if remote_tag_digest=$(skopeo_digest_for_tag "$remote_tag_reference"); then
                remote_tag_status=0
            else
                remote_tag_status=2
            fi
            ;;
        esac

        case "$remote_tag_status" in
        0)
            if [[ "${remote_tag_digest#sha256:}" == "$repo_sha" ]]; then
                echo "Remote tag check: MATCH — $remote_tag_reference still points to ${repo_digest##*@}"
            else
                echo "Remote tag check: MISMATCH — $remote_tag_reference now points to $remote_tag_digest"
            fi
            ;;
        1)
            echo "Remote tag check: NOT FOUND — $remote_tag_reference no longer exists at the registry"
            ;;
        *)
            abort "Failed to check remote tag '$remote_tag_reference'"
            ;;
        esac
    fi
    echo

    if [[ -n "$opt_local_only" ]]; then
        continue
    fi
    if [[ -z "$opt_all" ]]; then
        if choose_remote_tag_scan; then
            :
        else
            scan_choice_status=$?
            if (( scan_choice_status == 1 )); then
                continue
            fi
            abort "Cannot prompt to scan remote tags; rerun with --local-only or --all"
        fi
    fi

    registry_tags=""
    ghcr_lookup_status=""
    ghcr_version_json=""

    case "$repo" in
    ghcr.io/*)
        ghcr_path="${repo#ghcr.io/}"
        ghcr_digest="sha256:$repo_sha"
        if [[ "$opt_ghcr_method" == anonymous ]]; then
            if ! registry_tags=$(ghcr_tags_by_digest_anonymously "$ghcr_path" "$ghcr_digest"); then
                abort "Anonymous GHCR lookup failed for $repo (is the package public?)"
            fi
            ghcr_lookup_status=anonymous
        else
            while true; do
                if ghcr_version_json=$(ghcr_package_version_by_digest "$ghcr_path" "$ghcr_digest"); then
                    ghcr_lookup_status=found
                    registry_tags=$($JQ -r '.metadata.container.tags[]?' <<<"$ghcr_version_json")
                    break
                fi
                case "$?" in
                1)
                    ghcr_lookup_status=not-found
                    break
                    ;;
                esac

                if [[ "$opt_ghcr_method" == auto ]] &&
                        skopeo_has_registry_credentials ghcr.io; then
                    notice "Using configured registry credentials for private GHCR lookup."
                    if ! registry_tags=$(skopeo_tags_by_digest "$repo" "$ghcr_digest"); then
                        abort "Authenticated Skopeo lookup failed for $repo"
                    fi
                    ghcr_lookup_status=skopeo
                    break
                fi

                if [[ "$opt_ghcr_method" == packages ]]; then
                    abort "GitHub Packages API lookup failed; authenticate gh with read:packages scope"
                fi

                if command -v "${GH:=gh}" &>/dev/null; then
                    can_refresh=1
                else
                    can_refresh=""
                fi
                if ! ghcr_choice=$(choose_ghcr_fallback "$can_refresh"); then
                    abort "GHCR lookup cancelled; no usable GitHub Packages credentials and anonymous scanning was not approved"
                fi

                case "$ghcr_choice" in
                refresh)
                    if ! "$GH" auth refresh -s read:packages </dev/tty >/dev/tty; then
                        warn "gh authentication refresh failed"
                    fi
                    # Retry the Packages API whether refresh succeeded or failed:
                    # the authentication flow may still have updated the token.
                    ;;
                anonymous)
                    if ! registry_tags=$(ghcr_tags_by_digest_anonymously "$ghcr_path" "$ghcr_digest"); then
                        abort "Anonymous GHCR lookup failed for $repo (is the package public?)"
                    fi
                    ghcr_lookup_status=anonymous
                    break
                    ;;
                skip)
                    skip_input=1
                    break
                    ;;
                esac
            done
        fi
        ;;

    *)
        first_component="${repo%%/*}"
        if [[ "$repo" != */* ||
                "$first_component" != *.* && "$first_component" != *:* &&
                "$first_component" != localhost ]] ||
                [[ "$first_component" == docker.io ||
                "$first_component" == index.docker.io ||
                "$first_component" == registry-1.docker.io ]]; then
            # Docker Hub. Normalize official images and follow every API page.
            hub_repo="$repo"
            case "$hub_repo" in
            docker.io/* | index.docker.io/* | registry-1.docker.io/*)
                hub_repo="${hub_repo#*/}"
                ;;
            esac
            if [[ "$hub_repo" != */* ]]; then
                hub_repo="library/$hub_repo"
            fi

            next_url="https://hub.docker.com/v2/repositories/$hub_repo/tags/?page_size=100"
            response_tmp=$(mktemp)
            while [[ -n "$next_url" ]]; do
                info "Listing Docker Hub tags from: $next_url"
                docker_hub_request_args=(-sS -o "$response_tmp" -w '%{http_code}')
                if [[ -n "$docker_hub_token" ]]; then
                    docker_hub_request_args+=(-H "Authorization: Bearer $docker_hub_token")
                fi
                if ! docker_hub_http_code=$(
                    $CURL "${docker_hub_request_args[@]}" "$next_url"
                ); then
                    rm -f "$response_tmp"
                    abort "Failed to list tags for $repo"
                fi
                docker_hub_error_message=$(
                    $JQ -r '
                        (.message // .detail // .error // empty)
                        | if type == "string" then gsub("[\\r\\n]+"; " ") else tostring end
                    ' "$response_tmp" 2>/dev/null || true
                )
                case "$docker_hub_http_code" in
                200) ;;
                401 | 403)
                    if [[ -n "$docker_hub_token" ]]; then
                        rm -f "$response_tmp"
                        abort "Authenticated Docker Hub request failed with HTTP $docker_hub_http_code${docker_hub_error_message:+: $docker_hub_error_message}"
                    fi
                    if skopeo_has_registry_credentials docker.io; then
                        notice "Using configured registry credentials for private Docker Hub lookup."
                        if ! registry_tags=$(skopeo_tags_by_digest "$repo" "sha256:$repo_sha"); then
                            rm -f "$response_tmp"
                            abort "Authenticated Skopeo lookup failed for $repo"
                        fi
                        next_url=
                        break
                    fi
                    if docker_hub_token=$(
                        choose_docker_hub_authentication \
                            "HTTP $docker_hub_http_code${docker_hub_error_message:+: $docker_hub_error_message}"
                    ); then
                        continue
                    else
                        docker_hub_auth_status=$?
                    fi
                    if (( docker_hub_auth_status == 1 )); then
                        notice "Skipping Docker Hub lookup for $repo."
                        skip_input=1
                        break
                    fi
                    rm -f "$response_tmp"
                    abort "Docker Hub authentication requires an interactive terminal"
                    ;;
                *)
                    rm -f "$response_tmp"
                    abort "Docker Hub tag listing failed with HTTP $docker_hub_http_code${docker_hub_error_message:+: $docker_hub_error_message}"
                    ;;
                esac
                # shellcheck disable=SC2016  # jq expression, not a shell expansion
                matching_tags=$(
                    $JQ -r --arg digest "$repo_sha" '
                        .results[]
                        | select(((.digest // "") | ltrimstr("sha256:")) == $digest)
                        | .name
                    ' "$response_tmp"
                )
                if [[ -n "$matching_tags" ]]; then
                    registry_tags+="${registry_tags:+$'\n'}$matching_tags"
                fi
                next_url=$($JQ -r '.next // empty' "$response_tmp")
            done
            rm -f "$response_tmp"
        else
            # For other OCI registries, skopeo supplies the same registry-level
            # algorithm and reuses configured registry credentials when available.
            skopeo_is_available ||
                abort "Install skopeo to query registry '$first_component'"
            registry_tags=$(skopeo_tags_by_digest "$repo" "sha256:$repo_sha") ||
                abort "Skopeo lookup failed for $repo"
        fi
        ;;
    esac

    if [[ -n "$skip_input" ]]; then
        continue
    fi

    echo "Registry tag(s):"
    printf '%s\n' "${registry_tags:-<none>}"

    case "$ghcr_lookup_status" in
    found)
        package_current_tags=$(
            $JQ -r '
                .metadata.container.tags // []
                | if length == 0 then "none" else join(", ") end
            ' <<<"$ghcr_version_json"
        )
        echo
        echo "GHCR package info:"
        echo "Created:      $($JQ -r '.created_at // "unknown"' <<<"$ghcr_version_json")"
        echo "Updated:      $($JQ -r '.updated_at // "unknown"' <<<"$ghcr_version_json")"
        if [[ "$package_current_tags" == none ]]; then
            echo "Note: the digest is still an active GHCR package version, but no current tag points to it."
        fi
        ;;
    not-found)
        warn "No active GHCR package version was found for sha256:$repo_sha"
        ;;
    anonymous)
        if [[ -z "$registry_tags" ]]; then
            warn "No current GHCR tag was found for sha256:$repo_sha"
        fi
        ;;
    esac
    done <<<"$images_to_process"
done
