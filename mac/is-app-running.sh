#!/bin/bash
# Return success if given app is running
# If the name of the app has two or more dots, it's assumed to be the bundle identifier.


#### Preamble (v2023-08-28)

set -euo pipefail
shopt -s failglob
# shellcheck disable=SC2317
function trap_err { echo "ERR signal on line $(caller)" >&2; }
trap trap_err ERR
trap exit INT
export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

if [[ $OSTYPE == darwin* ]]; then
    HOMEBREW_PREFIX="$( (/opt/homebrew/bin/brew --prefix || /usr/local/bin/brew --prefix || brew --prefix) 2>/dev/null)"

    [ -x "${TIMEOUT:="$HOMEBREW_PREFIX/bin/timeout"}" ] || \
        { echo "$0: Error: \`brew install coreutils\` to install $TIMEOUT." >&2; exit 1; }
else
    TIMEOUT="timeout"
fi


##############################################################################
#### Main

app="$1"

if [[ "$app" == *.*.* ]]; then
    property="bundle identifier"
elif [[ "$app" == "iTerm2" ]]; then
    # Running process shows up as "iTerm"
    property="bundle identifier"
    app="com.googlecode.iterm2"
elif [[ "$app" == "Visual Studio Code" ]]; then
    # In the case of "Visual Studio Code", the process name shows up as "Electron" and is hidable by "Code" or bundle ID
    property="bundle identifier"
    app="com.microsoft.VSCode"
elif [[ "$app" == "IntelliJ IDEA" ]]; then
    # Running process shows up as "idea"
    property="bundle identifier"
    app="com.jetbrains.intellij"
else
    property="name"
fi

if $TIMEOUT 10 osascript -e "tell application \"System Events\" to ($property of processes) contains \"$app\"" | grep -q 'true'; then
    exit 0
else
    exit 1
fi

# Alternative implementation:
#if osascript -e "
#tell application \"System Events\"
#    if (name of processes) contains \"$app\"
#        error number 0
#    else
#        error number -1
#    end if
#end tell
#" 2>&1 >/dev/null | grep -qF -- '(-1)'; then
#    exit 1
#else
#    exit 0
#fi
