#!/bin/bash
# Source: https://cameronnokes.com/blog/how-to-know-if-a-desktop-app-uses-electron/

target="${1:-/Applications}"

check() {
  if stat "$1/Contents/Frameworks/Electron Framework.framework" &> /dev/null; then
    echo "$1 uses Electron"
  fi
}

export -f check

find "$target" -maxdepth 2 -type d -name "*.app" -exec bash -c 'check "{}"' \; | sort
