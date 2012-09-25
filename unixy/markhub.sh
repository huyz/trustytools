#!/bin/sh
# Filename:         markhub.sh
# Version:          0.2
# Description:
#   Preview (Github-flavored) Markdown files in a web browser. using github's
#   stylesheet.  Useful for checking files, e.g. README.mkd, before pushing to
#   github.
#
# Platforms:        OS X, GNU/Linux (not yet tested), Cygwin (not yet tested)
# Depends:          sundown, web browser
# Source:           https://github.com/huyz/trustytools
# Author:           Huy Z, http://huyz.us/
# Created on:       2011-06-02
#
# Installation:
# 1. Download https://github.com/vmg/sundown.git, compile, and install in your
#    PATH
# 2. Put this script in your PATH, e.g.:
#    ln -s ~/git/huyz/trustytools/unixy/markhub.sh ~/bin/markhub
#
# Usage:
#    markhub markdown_file ...

# Copyright (C) 2011 Huy Z
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

# Name of sundown executable.  You can use basename or full path.
SUNDOWN=sundown

# Timeout in secs before automatic cleanup of temporary HTML files.
# Increase if your browser takes a long time to launch and display
CLEANUP_TIMEOUT=30

##### End of Configuration
#############################################################################

### Init

execname=`basename $0`

# Check for sundown
notfound=
case "$SUNDOWN" in
  /*) [ -x "$SUNDOWN" ] || notfound=1 ;;
  *)  hash "$SUNDOWN" >&/dev/null || notfound=1 ;;
esac
if [ -n "$notfound" ]; then
  echo "$execname: ERROR: 'sundown' not found." >&2
  echo "$execname:        Download from https://github.com/vmg/sundown ," >&2
  echo "$execname:        compile, and install in your PATH." >&2
  exit 1
fi

if [ -z $BROWSER ]; then
  case $OSTYPE in
    darwin*) BROWSER=open ;;
    cygwin)  BROWSER=cygstart ;;
    *) 
      BROWSER=
      for i in xdg-open gnome-open chromium-browser chrome firefox opera elinks links w3m lynx; do
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
  echo "Usage: $execname markdown_file ..." >&2
  exit 1
fi

### Main

num=0
for i in "$@"; do
  # Get the stylesheet from github
  # 2012-09-24 For some reason I can't just reference it
  wget --quiet -O ${PREFIX}.documentation.css https://raw.github.com/github/github-flavored-markdown/gh-pages/shared/css/documentation.css
  wget --quiet -O ${PREFIX}.screen.css https://raw.github.com/github/github-flavored-markdown/gh-pages/stylesheets/screen.css

  outfile=${PREFIX}.$num.html

  cat <<END >$outfile
<!DOCTYPE html>
  <html>
    <head> 
      <meta charset='utf-8'> 
      <link href="$(basename ${PREFIX}.documentation.css)" media="screen" rel="stylesheet" type="text/css">
      <link href="$(basename ${PREFIX}.screen.css)" media="screen" rel="stylesheet" type="text/css">

      <style>
        /* From inspecting element on github.com */
        #readme .markdown-body, #readme .plain {
          padding: 30px;
        }
      </style>
    </head>
<body>
  <div id="readme" class="announce instapaper_body md" data-path="/">
    <article class="markdown-body entry-content" itemprop="mainContentOfpage">
END

  if "$SUNDOWN" "$i" >> $outfile; then
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

# Delayed automatic cleanup
# WARNING: $PREFIX must not have any spaces
sh -c "sleep $CLEANUP_TIMEOUT; rm -f $PREFIX*" &
