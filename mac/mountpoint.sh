#!/bin/bash
# Equivalent of Linux's mountpoint for macOS

set -euo pipefail
shopt -s failglob
trap exit INT

if [[ "$1" == "-q" ]]; then
    quiet=1
    shift
else
    quiet=
fi

if [[ $# -ne 1 ]]; then
    echo "Usage: ${0##*/} [-q] directory|file" >&2
    exit 1
fi

dir="$1"

if [[ ! -e "$dir" ]]; then
    [[ -n $quiet ]] || echo "${0##*/}: $dir: No such file or directory" >&2
    exit 1
elif mount | grep -q "on $(realpath "$dir") ("; then
    [[ -n $quiet ]] || echo "$dir is a mountpoint"
    exit 0
else
    [[ -n $quiet ]] || echo "$dir is not a mountpoint"
    exit 32
fi
