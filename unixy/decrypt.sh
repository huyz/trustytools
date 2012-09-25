#!/bin/sh
# $RCSfile: decrypt,v $ $Revision: 1.7 $ $Date: 2011/05/19 08:11:10 $
# Encrypts specified files
# 2011-05-18 Handles all types of encrypted files

if [ $# -eq 0 ]; then
  echo "Usage: $0 file..." >&2
  exit 1
fi

if ! which gpg >/dev/null 2>&1; then
  echo "ERROR: $0: can't find gpg" >&2
  exit 1
fi

for i in "$@"; do
  case "$i" in
    *.3des|*.gpg)
      [ $# -gt 0 ] && echo "=== $i"
      out="${i%.gpg}"
      out="${out%.3des}"
      gpg -d -o "$out" "$i" && touch -r "$i" "$out"
      ;;
    *)
      echo "WARNING: skipping $i; must be named *.3des" >&2
      ;;
  esac
done
