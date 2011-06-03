#!/bin/sh
# Filename:         ldwhich.zsh
# Version:          0.1
# Description:
#   Finds location of a dynamic library by traversing the dynamic library
#   search path, for Linux, OS X, and other Unix systems.
#
# Platforms:        Linux, OS X, IRIX, HP-UX
# Source:           https://github.com/huyz/trustytools
# Author:           Huy Z, http://huyz.us/
# Updated on:       2011-06-03
# Created on:       1996-05-01
#
# Installation:
#   On Irix, this file can be linked to ldwhich32, to search the respect
#   environment variable.
#
# Usage:
#   ldwhich [-a] simple_name ...
#     Finds dynamic library in the search path, where simple_name is
#     for example "c", not "libc.so".
#     -a will show all matches, not just the first.
#   ldwhich
#     Prints out the content of the dynamic library search path
#     environment variable (but not system default directories).

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
[ "x$ZSH_VERSION" = "x" ] && exec zsh -f "$0" "$@"

local _pathref _path _lib _ext
local _found _anyfound

# New: Enable _all at all times
#local _all
local _all=1

# Depending on invocation name
case $0 in
  *32(|sh|zsh))
    _pathref=LD_LIBRARYN32_PATH
    _path="$LD_LIBRARYN32_PATH"
    ;;
  *)
    # Depending on arch
    case $OSTYPE in
      hpux*)   _pathref=LPATH; _path="$LPATH" ;;
      darwin*) _pathref=DYLD_LIBRARY_PATH; _path="$DYLD_LIBRARY_PATH" ;;
      *)       _pathref=LD_LIBRARY_PATH; _path="$LD_LIBRARY_PATH" ;;
    esac
esac

if [[ $# -eq 0 ]]; then
  echo "$_pathref=$_path"
else
  # Flags
  if [[ "$1" = -* ]]; then
    if [[ "$1" != -a ]]; then
      echo "Usage: $0 [[-a] library ...]"
      echo "       -a will print out all the paths of the library"
      exit 1
    fi
    _all=1
    shift
  fi

  for _lib in "$@"; do
    _found=
    _lib=${_lib#lib}
    _lib=$_lib:r

    # ld.so.conf is for linux
    for _path in ${(s,:,)_path} \
        /lib /usr/lib \
        `cat /etc/ld.so.conf 2>/dev/null`; do
      for _ext in sl so dylib; do
        if [[ -f "$_path/lib${_lib}.$_ext" ]]; then
          echo "$_path/lib${_lib}.$_ext"
          _found=1
          [[ -z $_all ]] && break 2
        fi
      done
    done
    if [[ -n $_found ]]; then
      _anyfound=1
    else
      echo "lib$_lib.(sl|so|dylib) not found"
    fi
  done

  [[ -z $_anyfound ]] && exit 1
fi
exit 0
