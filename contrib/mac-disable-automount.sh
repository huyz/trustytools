#!/bin/bash
# Add all specified volumes to /etc/fstab to disable automounting
# Source: https://akrabat.com/prevent-an-external-drive-from-auto-mounting-on-macos/
#
# Note: Encrypted disks are unlocked before the fstab file is read. In order for
# this procedure to work with an encrypted disk, you must first mount the disk,
# unlock it, and save the password in your keychain.
#   Source: https://discussions.apple.com/docs/DOC-7942


[ "${EUID:-$UID}" -eq 0 ] || exec sudo -p '[sudo] password for %u: ' -H "$BASH" "$0" "$@"

set -euo pipefail
shopt -s failglob
# shellcheck disable=SC2317
function trap_err { echo "ERR signal on line $(caller)" >&2; }
trap trap_err ERR
trap exit INT
export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
#SCRIPT="$($REALPATH -s "${BASH_SOURCE[0]}")"
#SCRIPT_DIR="$(dirname "$SCRIPT")"

#### Config

FSTAB=/etc/fstab

#### Main

if [[ $# -eq 0 ]]; then
    echo "Usage: $SCRIPT_NAME disk_name…" >&2
    exit 1
fi

# Add an volume as not auto-mounted to the /etc/fstab file
# by its identifier. Also pass in the volume name to add a
# comment on that line so that we can identify it later.
function add_identifier {
    ID=$1
    VOLUME_NAME=$2
    if [ -z "$VOLUME_NAME" ] ; then
        echo "add_identifier() takes two parameters: ID and VOLUME_NAME"
        exit 2
    fi

    # get UUID and TYPE from `diskutil info $ID`
    UUID="$(diskutil info "$ID" | grep "Volume UUID" | awk '{print $NF}')"
    TYPE="$(diskutil info "$ID" | grep "Type (Bundle)" | awk '{print $NF}')"

    # Remove this UUID from fstab file
    sed -i '' "/^UUID=$UUID/d" $FSTAB

    # Add this UUID to fstab file
    echo "Adding $UUID ($VOLUME_NAME) to $FSTAB …"
    echo "UUID=$UUID none $TYPE rw,noauto  # $VOLUME_NAME" | tee -a $FSTAB >/dev/null
}

for name in "$@"; do
    # Iterate over list of identifiers and volume names from `diskutil info`
    diskutil list | perl -lne 'print if s/^ *\d+: +(?:.*?(?:[Ss]cheme|Volume)|\w+) +([\w\s-]+?)\s{2,}.*\s(disk.*)/$1|$2/' | while read -r line
    do
        # Example of $line:
        #    1: APFS Volume Swiftsure Clone - Data 592.1 GB disk4s1

        VOLUME_NAME="${line%|*}"
        ID="${line#*|}"

        [[ "$VOLUME_NAME" != "$name"* ]] && continue

        add_identifier "$ID" "$VOLUME_NAME"
    done
done
