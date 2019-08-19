#!/bin/sh
# 2014-11-20 Useful for deleting iTunesMetadata.plist to prevent App Store updates

DESTDIR=/private/var/mobile/AppLinks

if [ -d "$DESTDIR" ]; then
  rm "$DESTDIR"/*
else
  mkdir "$DESTDIR" || exit 1
fi

for i in /private/var/mobile/Containers/Bundle/Application/*/*.app; do
  base="$(basename "$i")"
  target="$DESTDIR/$base"
  if [ -e "$target" ]; then
    echo "Error: $target already exists" >&2
  else
    echo "$target"
    ln -s "$(dirname "$i")" "$target"
  fi
done
