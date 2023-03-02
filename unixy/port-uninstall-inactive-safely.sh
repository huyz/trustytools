#!/bin/bash
# Lists all the MacPorts packages that have an inactive and active version
# installed and offers to uninstall the inactive version(s).
# This is an even safer version of the second, safe phase of `port reclaim`, which
# offers to uninstall all inactive packages, as this script
# makes sure that at least one version (usually later) is installed and active.

port-inactive-safe-to-uninstall

echo
read -r -p "𐄫 Uninstall inactive versions? [y/N] " response

if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    join -1 1 -2 1 <(port echo inactive | sort) <(port echo active | sort) \
        | cut -f1-2 -d" " \
        | xargs -n 2 -I '{}' sh -c 'echo "𐄬 Uninstalling {}…"; sudo port uninstall {}'
fi
