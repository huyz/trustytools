#!/bin/sh
# $RCSfile: decrypt,v $ $Revision: 1.7 $ $Date: 2011/05/19 08:11:10 $
# Decrypts specified files, prompting for passphrase only once

if [ $# -eq 0 ]; then
  echo "Usage: $0 file..." >&2
  exit 1
fi

if ! which gpg >/dev/null 2>&1; then
  echo "ERROR: $0: can't find gpg" >&2
  exit 1
fi

echo "Enter passphrase: \c"
stty -echo
read passphrase
stty echo

for i in "$@"; do
  case "$i" in
    *.3des|*.gpg)
      [ $# -gt 0 ] && echo "=== $i"
      out="${i%.gpg}"
      out="${out%.3des}"
      echo "$passphrase" | gpg --passphrase-fd 0 --batch -q -d -o "$out" "$i" && touch -r "$i" "$out"
      ;;
    *)
      echo "WARNING: skipping $i; must be named *.3des or #*.gpg" >&2
      ;;
  esac
done
