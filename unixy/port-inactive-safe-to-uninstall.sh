#!/bin/bash
# Lists all the MacPorts packages that have an inactive and active version
# installed.  The inactive version is thus safe to uninstall.

(
    echo "Port Inactive Active"
    echo "---- -------- ------"
    join -1 1 -2 1 <(port echo inactive | sort) <(port echo active | sort)
) \
    | column -t -c 3
