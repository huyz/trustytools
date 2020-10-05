#!/bin/sh
# $RCSfile: encrypt,v $ $Revision: 1.6 $ $Date: 2011/05/19 08:10:50 $
# Encrypts specified files
# 2011-05-18 Updated to use asymmetric encryption

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
      echo "WARNING: skipping $i" >&2
      ;;
    *)
      [ $# -gt 0 ] && echo "=== $i"
      # 2011-05-18 Switching to asymmetric encryption
      #gpg -c --cipher-algo 3DES -o "$i.3des" "$i"
      if gpg -e --default-recipient-self "$i"; then
        touch -r "$i" "$i.gpg" || echo "$0: touch failed with $?" >&2
        exit 0
      else
        exit $?
      fi
      ;;
  esac
done
