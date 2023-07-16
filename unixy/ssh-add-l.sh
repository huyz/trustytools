#!/bin/bash
# List keys in ssh-agent with corresponding filenames (if found).
# Note: this won't work well if connected to a forwarded remote agent.
#
# Based on:
# https://unix.stackexchange.com/questions/58969/how-to-list-keys-added-to-ssh-agent-with-ssh-add/566474#566474

count=1
ssh-add -l | \
    while read -r line; do
        if [[ "$line" == *"agent has no identities"* ]]; then
            echo "$line"
            break
        fi
        keysize="${line%% *}"
        fingerprint="$(echo "$line" | cut -d' ' -f2)"
        matched=
        for filename in ~/.ssh/*.pub; do
            candidate_fp="$(ssh-keygen -lf "$filename")"
            if [[ "$candidate_fp" == *"$fingerprint"* ]]; then
                filename_short="${filename//$HOME\/.ssh\//}"
                pub="$(<"$filename")"
                if [[ "$pub" == ssh-rsa* ]]; then
                    pub="$(<"$filename" sed -E 's/(.{40}).*(.{50})/\1 … \2/')"
                fi
                printf "%2s. %s\n    %s\n      %s\n" \
                    "$count" \
                    "$candidate_fp" \
                    "${filename_short}:" \
                    "$pub"
                (( count++ ))
                matched=1
            fi
        done
        if [[ -z "${matched-}" ]]; then
            printf "%2s. %s\n" \
                    "$count" \
                    "$keysize $line"
            (( count++ ))
        fi
    done
