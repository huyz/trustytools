#!/bin/bash
# List the fingerprints and comments of all the private keys

for i in ~/.ssh/*.pub; do ssh-keygen -l -f "${i%.*}"; done
