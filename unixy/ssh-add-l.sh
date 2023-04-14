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
            candidate_fp="$(ssh-keygen -lf "$file")"
            if [[ "$candidate_fp" == *"$fingerprint"* ]]; then
                echo "${file//$HOME\/.ssh\//}"
                pub="$(<"$file")"
                if [[ "$pub" == ssh-rsa* ]]; then
                    pub="$(<"$file" sed -E 's/(.{40}).*(.{50})/\1 … \2/')"
                fi
                printf "  %s\n  %s\n" \
                    "$candidate_fp" \
                    "$pub"

            fi
        done \
            || echo "$keysize $line";
    done
