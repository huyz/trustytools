#!/bin/bash
# List the fingerprints and comments of all the private keys

set -euo pipefail
shopt -s failglob
function trap_err { echo "ERR signal on line $(caller)" >&2; }
trap trap_err ERR
trap exit INT

#### Main

cd ~/.ssh

for i in *.pub; do
    i="${i%.*}"
    printf "%s" "$(ssh-keygen -l -f "$i")"
    echo " | $i"
done | column -t -s '|'
