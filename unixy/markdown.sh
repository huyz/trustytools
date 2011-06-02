#!/bin/sh
# markdown - Preview (Github-flavored) Markdown files in a web browser.
#            Useful to checking files before pushing to github.
#
# Version:          1.0
# Platforms:        OS X, GNU/Linux (not yet tested), Cygwin (not yet tested)
# Requires:         upskirt, web browser
# Created on:       2011-06-02

# Copyright (C) 2011 Huy Z, http://huyzing.com/
# 
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
# 
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

#############################################################################
##### Configuration

# (Optional) This script will launch your normal browser for viewing HTML
# but you can override here.  You can use basename or full path.
#BROWSER=

# Name of upskirt executable.  You can use basename or full path.
UPSKIRT=upskirt

# Timeout in secs before automatic cleanup of temporary HTML files.
# Increase if your browser takes a long time to launch and display
CLEANUP_TIMEOUT=10

##### End of Configuration
#############################################################################

### Init

execname=`basename $0`

# Check for upskirt
notfound=
case "$UPSKIRT" in
  /*) [ -x "$UPSKIRT" ] || notfound=1 ;;
  *)  hash "$UPSKIRT" >&/dev/null || notfound=1 ;;
esac
if [ -n "$notfound" ]; then
  echo "$execname: ERROR: 'upskirt' not found." >&2
  echo "$execname:        Download from 'https://github.com/tanoku/upskirt'," >&2
  echo "$execname:        compile, and install in your PATH." >&2
  exit 1
fi

if [ -z $BROWSER ]; then
  case $OSTYPE in
    darwin*) BROWSER=open ;;
    cygwin)  BROWSER=cygstart ;;
    *) 
      BROWSER=
      for i in xdg-open gnome-open chromium-browser chrome firefox opera; do
        hash $i >& /dev/null && BROWSER=$i && break
      done
      if [ -z "$BROWSER" ]; then
        echo "$execname: ERROR: web browser not found." >&2
        echo "$execname:        Edit configuration in file '$0'." >&2
        exit 1
      fi
      ;;
  esac
fi

if [ -z "$TMPDIR" ]; then
  if [ -d "$HOME/tmp" ]; then
    TMPDIR=$HOME/tmp
  else
    TMPDIR=/tmp
  fi
fi
PREFIX=$TMPDIR/.markdown.$$

### Usage

if [ $# -eq 0 ]; then
  echo "Usage: $execname:file..." >&2
  exit 1
fi

### Main

num=0
for i in "$@"; do
  outfile=${PREFIX}.$num.html
  if "$UPSKIRT" "$i" > $outfile; then
    # Hopefully, your browser is smart enough to open new tabs
    $BROWSER $outfile
  fi
  (( num = $num + 1 ))
done

echo "Converted (check your browser)."

### Cleanup

# Prompt for cleanup permission
#echo "Now, delete temporary HTML files? (y for yes) \c"
#read answer
#case $answer in
#  y*|Y*)
#    rm -f $PREFIX*
#    ;;
#esac

# Delayed automatically cleanup
# NOTE: $PREFIX must not have any spaces
sh -c "sleep $CLEANUP_TIMEOUT; rm -f $PREFIX*" &
