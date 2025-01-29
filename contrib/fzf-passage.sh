#! /usr/bin/env bash
# Usage:
#    fzf-passage -c  [to put in clipboard]
#    fzf-passage -q  [to show QR code]
# 2025-01-29 from https://github.com/FiloSottile/passage/blob/4e4c5ae14be91833791d45608f50868175c1490f/README

set -eou pipefail

PREFIX="${PASSAGE_DIR:-$HOME/.passage/store}"
FZF_DEFAULT_OPTS=""
name="$(find "$PREFIX" -type f -name '*.age' | \
    sed -e "s|$PREFIX/||" -e 's|\.age$||' | \
    fzf --height 40% --reverse --no-multi)"

passage "${@}" "$name"
