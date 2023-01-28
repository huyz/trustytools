#!/bin/bash
# List keys in ssh-agent with corresponding filenames (if found).
# Note: this won't work well if connected to a forwarded remote agent.
#
# Based on:
# https://unix.stackexchange.com/questions/58969/how-to-list-keys-added-to-ssh-agent-with-ssh-add/566474#566474

ssh-add -l | \
    while read -r line; do
        keysize="${line%% *}"
        fingerprint="$(echo "$line" | cut -d' ' -f2)"
        for file in ~/.ssh/*.pub; do
            printf "%s | %s\n" \
                "$(ssh-keygen -lf "$file")" \
                "${file//$HOME\/.ssh\//}"
        done | column -t -s '|' | grep "$fingerprint" \
            || echo "$keysize $line";
    done
