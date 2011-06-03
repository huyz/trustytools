#!/bin/sh
# Filename:         clfu.sh
# Version:          0.1
# Description:
#   Quick-reference for the top 100 commands at commandlinefu.com
#
# Source:           https://github.com/huyz/trustytools
# Author:           Huy Z, http://huyzing.com/
# Created on:       2010-10-16
#
# Usage:            just run it

curl -s \
  www.commandlinefu.com/commands/browse/sort-by-votes/plaintext \
  www.commandlinefu.com/commands/browse/sort-by-votes/plaintext/25 \
  www.commandlinefu.com/commands/browse/sort-by-votes/plaintext/50 \
  www.commandlinefu.com/commands/browse/sort-by-votes/plaintext/75 \
| grep -v "commandlinefu.com by" | nl -b 'p^ *#' -n ln | less -F
