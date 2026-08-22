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
#   4. Find and print the current registry tag(s) for that digest.
#
# Prerequisites:
# - curl
# - jq
# - docker CLI
# - authenticated gh CLI with read:packages scope, optional fast path for GHCR
# - skopeo, only for registries other than Docker Hub and GHCR
#
# TIP:
# - To list all the Repo digests for your containers:
#    docker image ls --digests --format 'table {{.Repository}}\t{{.Tag}}\t{{.Digest}}\t{{.ID}}\t{{.CreatedSince}}\t{{.Size}}'
# - To query all local containers:
#   docker-image-tags $(docker ps -a --format "{{.Names}}")
#
# 2026-08-22 Authored mostly by DeepSeek V4 Flash and OpenAI's GPT 5.6 Sol

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
else
    _install_cmd="sudo apt install"
    GETOPT="getopt"
    REALPATH="realpath"
    command -v "${JQ:=jq}" &>/dev/null || \
        { echo "$0: ERROR: \`$_install_cmd jq\` to install $JQ." >&2; exit 1; }
    command -v "${DOCKER:=docker}" &>/dev/null || \
        { echo "$0: ERROR: \`$_install_cmd docker\` to install $DOCKER." >&2; exit 1; }
#    _install_cmd="brew install"
#    HOMEBREW_PREFIX=$( (/home/linuxbrew/.linuxbrew/bin/brew --prefix || brew --prefix) 2>/dev/null )
fi
command -v "${CURL:=curl}" &>/dev/null ||
    { echo "$0: ERROR: \`$_install_cmd curl\` to install $CURL." >&2; exit 1; }

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

#### Options

# Defaults
opt_verbose=
opt_debug=
opt_ghcr_method=auto

function usage {
    local exit_code="${1:-1}"
    cat <<END >&2
Usage: $SCRIPT_NAME [-h|--help] [-v|--verbose] [-d|--debug] [--ghcr-method method] <container-name-or-id> [...]
        -h|--help: get help
        -v|--verbose: turn on verbose mode
        -d|--debug: turn on debug mode
        --ghcr-method: select the GHCR lookup method (default: $opt_ghcr_method):
            auto: try the Packages API, then prompt if credentials are unusable
            packages: use only the GitHub Packages API; never prompt or fall back
            anonymous: use only the anonymous OCI scan; never prompt
END
    exit "$exit_code"
}

opts=$($GETOPT --options hvnd --long help,verbose,dry-run,debug,ghcr-method: --name "$SCRIPT_NAME" -- "$@") || usage
eval set -- "$opts"

while true; do
    case "$1" in
        -h | --help) usage 0;;
        -v | --verbose) opt_verbose=opt_verbose; shift ;;
        -d | --debug) opt_debug=opt_debug; shift ;;
        --ghcr-method) opt_ghcr_method="$2"; shift 2 ;;
        --) shift; break ;;
        *) abort "🐛 INTERNAL: unrecognized option '$1'" ;;
    esac
done

case "$opt_ghcr_method" in
auto | packages | anonymous) ;;
*) abort "--ghcr-method must be 'auto', 'packages', or 'anonymous'" ;;
esac

if [[ $# -lt 1 ]]; then
    usage 1
fi

# Look up an active GHCR package version by immutable digest. GitHub's Packages
# API exposes the digest, timestamps, and current tags in the same object, so
# no tag-by-tag manifest lookup is needed.
#
# Return values:
#   0: version found (the version object is printed as compact JSON)
#   1: API queried successfully, but no active version has this digest
#   2: API could not be queried (usually authentication or rate limiting)
function ghcr_package_version_by_digest {
    local ghcr_repository="$1"
    local digest="$2"
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
        # creation timestamp as the recency signal before selecting the digest.
        # shellcheck disable=SC2016  # jq expression, not a shell expansion
        match=$(
            $JQ -sc --arg digest "$digest" '
                (add // [])
                | sort_by(.created_at)
                | reverse
                | first(.[] | select(.name == $digest)) // empty
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

# Print every current GHCR tag whose manifest has the requested digest. This
# uses only GHCR's anonymous OCI Registry API, but requires one request per tag.
function ghcr_tags_by_digest_anonymously {
    local ghcr_repository="$1"
    local digest="$2"
    local auth_header realm service scope token
    local tags="" next_url next_link page_tags tag manifest_digest
    local header_tmp body_tmp checked=0
    local -a token_args spinner=('|' '/' '-' $'\\')

    if ! auth_header=$(
        $CURL -sS -D - -o /dev/null "https://ghcr.io/v2/$ghcr_repository/tags/list" |
            awk 'tolower($1) == "www-authenticate:" { $1=""; sub(/^ /, ""); print; exit }' |
            tr -d '\r'
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
    info "Requesting an anonymous GHCR pull token"
    if ! token=$(
        $CURL "${token_args[@]}" "$realm" |
            $JQ -r '.token // .access_token // empty'
    ); then
        return 1
    fi
    [[ -n "$token" ]] || return 1

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
                awk 'tolower($1) == "docker-content-digest:" { gsub("\r", "", $2); print $2; exit }' "$header_tmp"
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

##############################################################################
#### Main

container_index=0
for container in "$@"; do
    if (( container_index > 0 )); then
        separator_columns="${COLUMNS:-$(tput cols 2>/dev/null || true)}"
        (( separator_columns > 0 )) || separator_columns=80
        printf '%*s\n' "$separator_columns" '' | tr ' ' '-'
    fi
    ((++container_index))
    skip_container=

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
echo "Package digest: ${repo_digest##*@}"
echo
echo "Local tag:  $local_tag"
echo
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
                skip_container=1
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
            if ! $CURL -fsS -o "$response_tmp" "$next_url"; then
                rm -f "$response_tmp"
                abort "Failed to list tags for $repo"
            fi
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
        SKOPEO="${SKOPEO:-skopeo}"
        command -v "$SKOPEO" &>/dev/null ||
            abort "Install skopeo to query registry '$first_component'"

        info "Listing tags with skopeo for $repo"
        tags=$(
            $SKOPEO list-tags "docker://$repo" |
                $JQ -r '.Tags[]?'
        )
        while IFS= read -r tag; do
            [[ -z "$tag" ]] && continue
            info "Resolving registry tag with skopeo: $tag"
            if ! manifest_digest=$(
                $SKOPEO inspect --format '{{.Digest}}' "docker://$repo:$tag" 2>/dev/null
            ); then
                continue
            fi
            if [[ "${manifest_digest#sha256:}" == "$repo_sha" ]]; then
                registry_tags+="$tag"$'\n'
            fi
        done <<<"$tags"
        registry_tags=${registry_tags%$'\n'}
    fi
    ;;
esac

if [[ -n "$skip_container" ]]; then
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
done
