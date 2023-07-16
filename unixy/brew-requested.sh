#!/bin/sh
# Lists all requested packagse

# Source:
#   https://apple.stackexchange.com/questions/412352/list-all-homebrew-packages-explicitly-installed-by-the-user-without-deps/438632#438632
brew info --json=v2 --installed \
    | jq -r '.formulae[] | select(any(.installed[]; .installed_on_request)).full_name'
