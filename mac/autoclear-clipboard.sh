#!/bin/bash
# 2020-06-27 Automatically clears the pasteboard if it contains a password-looking for too long.
# Counter-measure against Apple's Universal Pasteboard, which is dangerous as iOS apps will
# often read the pasteboard when they launch (e.g, TikTok).
#
# WARNING: clipboard managers such as Paste will still record them in the history.
#
# --- Testing ---
# To test:
#   - `lunchy stop com.example.autoclear-clipboard``
#   - Change CHECK_INTERVAL from 12 to 2
#   - `~/bin/autoclear-clipboard``
#
# Postive cases:
#   PAssword!@12345
#   P/Assword-12345
#   Password@12345
#   PAss!123
# Negative cases:
#   PAssword -12345                         # Has space
#   PAssword	-12345                      # Has tab
#   PAss!12                                 # Too short
#   PAssword!@12345PAssword!@12345678       # Too long
#   /PAssword-12345                         # Starts with slash
#   http://googl3.com/                      # Starts with http
#   file://localhost:0/                       # Starts with file
#   screenshot.2023-04-12T141507Z           # Starts with screenshot

#### Preamble (v2024-01-14)

set -euo pipefail
shopt -s failglob extglob
# shellcheck disable=SC2329
function trap_err { echo "ERR signal on line $(caller)" >&2; }
trap trap_err ERR
trap exit INT  # So that ^C will stop the entire script, not just the current subprocess
export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

##############################################################################

#### Config

DEBUG=

# In seconds
CHECK_INTERVAL=12
# To debug:
#CHECK_INTERVAL=2

# If set to 1, only clears output that is password-like: a specific length and no whitespace and doesn't start
# with http
CLEAR_PASSWORD_ONLY=1

#### Main

prev_content=

while true; do
    content="$(pbpaste)"

    if [[ -z "$content" ]]; then
        [[ -n $DEBUG ]] && echo "Nothing. Skipping..." >&2
        :

    elif [[ "$content" = "$prev_content" ]]; then
        if ((SECONDS - prev_seconds >= CHECK_INTERVAL)); then
            [[ -n $DEBUG ]] && echo "Stale. Erasing..." >&2
            pbcopy < /dev/null
            prev_content=
        else
            [[ -n $DEBUG ]] && echo "Still fresh. Holding..." >&2
        fi

    elif [[ -z $CLEAR_PASSWORD_ONLY ]]; then
        [[ -n $DEBUG ]] && echo "New. Storing..." >&2
        prev_content="$content"
        prev_seconds=$SECONDS

    # What looks like a password:
    # - length: 8 to 32, inclusive
    # - no whitespace
    # - doesn't start with common prefixes
    # - doesn't look like a path
    # - and looks like a decently-formatted password:
    #   - two or more lowercase letters
    #   - one or more uppercase letters
    #   - one or more digits
    #   - one or more of the following special characters: !@#$%^&*-
    #   Based on https://stackoverflow.com/questions/4670639/regex-match-a-strong-password-with-two-or-more-special-characters/4670743#4670743
    elif [[ ${#content} -ge 8 && ${#content} -le 32 \
            && "$content" != *\ * \
            && "$content" != *$'\t'* \
            && ! "$content" =~ ^\.?/[-_/[:alnum:]]+$ \
            && "$content" != @(http|file|screenshot)* ]] \
        && perl -lne 'exit(! /^(?=(?:.*[a-z]){2})(?=(?:.*[A-Z]){1})(?=(?:.*\d){1})(?=(?:.*[!@#$%^&*-]){1}).{8,}$/);' <<<"$content"; then

        [[ -n $DEBUG ]] && echo "New password. Storing..." >&2
        prev_content="$content"
        prev_seconds=$SECONDS
    else
        [[ -n $DEBUG ]] && echo "New non-password. Skipping..." >&2
        prev_content=
    fi

    sleep 1
done
