#!/bin/bash
# Because JetBrains make it hard to edit macros, sometimes it's just easier to edit the XML directly.
# This script helps edit macros where the only difference is the text string for
# the macro to type out.
#
# 1. Close the IDE
# 2. Open in your editor the latest ~/Library/Application Support/JetBrains/IntelliJIdea20*/options/macros.xml
# 3. Find the macro you want to edit
# 4. Run this script and enter the text you want macro to type out
# 5. Copy and paste the output of this script into macros.xml

#### Preamble (v2024-01-14)

set -euo pipefail
shopt -s failglob
# shellcheck disable=SC2329
function trap_err { echo "ERR signal on line $(caller)" >&2; }
trap trap_err ERR
trap exit INT  # So that ^C will stop the entire script, not just the current subprocess
export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

#SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

#### Main

# Prompt for a string

read -r -p "Enter the text to convert to keycodes: " text

# Convert to keycodes
text_keycodes=
html_escaped_text=
for (( i = 0; i < ${#text}; i++ )); do
    char="${text:i:1}"

    keycode=$(printf "%d" "'$(tr '[:lower:]' '[:upper:]' <<<"$char")")

    # Append to text_keycodes
    [[ -z $text_keycodes ]] || text_keycodes+=";"
    text_keycodes+="$keycode:0"

    # Append to HTML-excaped text
    [[ "$char" == ' ' ]] && char='&#x20;'
    html_escaped_text+="${char//&/&amp;}"
done
echo "<typing text-keycode=\"$text_keycodes\">$html_escaped_text</typing>"
