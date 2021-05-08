#!/bin/sh
# Source: https://apple.stackexchange.com/a/394594/6278

#script to eject all external drives
disks=$(diskutil list external | sed -n '/[Ss]cheme/s/.*B *//p')

if [ "$disks" ]; then
    echo "$disks" | while read -r line ; do
        diskutil unmountDisk "/dev/$line"
    done
else
    echo "No external disks to eject."
fi
