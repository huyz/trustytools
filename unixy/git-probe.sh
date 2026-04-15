#!/bin/bash
# Give some quick stats on a new git repo
# https://piechowski.io/post/git-commands-before-reading-code/

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
#### Main

#cd "$SCRIPT_DIR/.."

(
    echo
    echo "=== Active? Commit count by month ==="
    git log --format='%ad' --date=format:'%Y-%m' | sort | uniq -c || true

    echo
    echo "=== Who? Contributors ==="
    git shortlog -sn --no-merges || true

    echo
    echo "=== Churn? 20 most-changed files in the last year ==="
    git log --format=format: --name-only --since="1 year ago" | sort | uniq -c | sort -nr | head -20 || true

    echo
    echo "=== Buggy? 20 most-fixed files in the last year ==="
    git log -i -E --grep="fix|bug|broken" --name-only --format='' | sort | uniq -c | sort -nr | head -20 || true

    echo
    echo "=== Firefighting? Revert and hotfix frequency ==="
    git log --oneline --since="1 year ago" | grep -iE 'revert|hotfix|emergency|rollback' || true
) | ${PAGER:-less}
