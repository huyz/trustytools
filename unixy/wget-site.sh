#!/bin/sh
# Based on http://www.kossboss.com/linux---wget-full-website

# Other options to consider: --no-clobber
exec wget -v --limit-rate=200k --convert-links --random-wait -r -p -E -e robots=off -U mozilla "$@"
