#!/bin/bash
# Wrapper for diff to add colors both at the line and word level:
# - colordiff colors the line differences
# - git's diff-highlight colors the hunks within the line differences

set -euo pipefail
shopt -s failglob
trap exit INT  # So that ^C will stop the entire script, not just the current subprocess

### Preamble

if ! command -v colordiff >& /dev/null; then
    case "$OSTYPE" in
        darwin*)
            echo "$0: error: colordiff could not be found. Run \`brew install colordiff\`" >&2
            ;;
        *)
            echo "$0: error: colordiff could not be found. Run \`apt install colordiff\`" >&2
            ;;
    esac
    exit 1
fi

case "$OSTYPE" in
    darwin*)
        BREW="$(brew --prefix)"
        DIFFH="$BREW/share/git-core/contrib/diff-highlight/diff-highlight"
        if [[ -z "$DIFFH" ]]; then
            echo "$0: error: diff-highlight could not be found. Run \`brew install git\`" >&2
            exit 1
        fi
        ;;
    *)
        DIFFH=/usr/share/doc/git/contrib/diff-highlight
        if [[ -z "$DIFFH" ]]; then
            echo "$0: error: diff-highlight could not be found. Run \`apt install git\`" >&2
            exit 1
        fi
        ;;
esac

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 first_string second_string" >&2
    exit 1
fi

colordiff -u "$1" "$2" | "$DIFFH"
