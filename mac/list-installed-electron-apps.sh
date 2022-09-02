#!/bin/bash
# Source: https://cameronnokes.com/blog/how-to-know-if-a-desktop-app-uses-electron/

if [[ $# -eq 0 ]]; then
  set -- /Applications
  [[ -d ~/Applications ]] && set -- "$@" ~/Applications
fi

check() {
  if stat "$1/Contents/Frameworks/Electron Framework.framework" &> /dev/null; then
    echo "$1 uses Electron"
  fi
}

export -f check

find "$@" -maxdepth 2 -type d -name "*.app" -exec bash -c 'check "$1"' bash {} \; | sort
