#!/usr/bin/env bash
# Displays biggest objects in git repo
#
# Prerequisites: git-filter-repo

# Check for bash 4 for `readarray`, associatve arrays, etc.
[ "${BASH_VERSINFO:-0}" -ge 4 ] || { echo "${BASH_SOURCE[0]}: ERROR: bash v4+ required." >&2; exit 1; }

#### Preamble (template v2026-08-201)

set -euo pipefail
shopt -s failglob
# shellcheck disable=SC2329
function trap_err { echo "$(basename "${BASH_SOURCE[0]}"): ERR signal on line $(caller)" >&2; }
trap trap_err ERR
trap exit INT  # So that ^C will stop the entire script, not just the current subprocess
export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

command -v "${GIT_FILTER_REPO:=git-filter-repo}" &>/dev/null || \
    { echo "$0: ERROR: git-filter-repo not found. Install using Homebrew or your system package manager." >&2; exit 1; }

#### Main

# Map from sha to filename (with relative path). Some objects in git rev-list --objects --all
# have no path at all (for example, unreachable or root objects), so skip those.
declare -A sha_to_filename
while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    sha="${line%% *}"
    path="${line#"$sha"}"
    path="${path# }"
    if [[ -n "$path" ]]; then
        sha_to_filename["$sha"]="$path"
    fi
done < <(git rev-list --objects --all)

# NOTE:
# - columns of verify-pack -v: object-name type size size-in-packfile offset-in-packfile [depth base-object-name]
# - sed: quit at "non delta" to speed things up
git verify-pack -v .git/objects/pack/*.idx \
    | sed '/non delta/q' \
    | sort -k 3 -n -r \
    | while read -r line; do
        sha="${line%% *}"
        size="$(awk '{ print $3 }' <<< "$line")"
        if [[ -n "$(awk '{ print $7 }' <<< "$line")" ]]; then
            delta="Δ"
        else
            delta=
        fi
        filename="${sha_to_filename[$sha]:-}"
        printf "%s\t%s\t%s\n" "$size" "$delta" "$filename"
    done | less
