#!/bin/sh
# Filename:         bundle-id.sh
# Version:          0.1
# Description:
#   On OS X, gives the bundle ID of an application.
#   Useful for terminal-notifier.
#
# Platforms:        OS X
# Source:           https://github.com/huyz/trustytools
# Author:           Huy Z, http://huyz.us/
# Created on:       2014-06-17
#
# Usage:
#   bundle-id "Finder" ...

exec osascript -e "id of app \"$*\""
