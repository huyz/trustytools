#!/bin/sh
# Creates symlinks from Applications' UUID-named folders to human-friendly app names

DESTDIR=/private/var/mobile/AppLinks

if [ -d "$DESTDIR" ]; then
  rm "$DESTDIR"/*
else
  mkdir "$DESTDIR" || exit 1
fi

# For iOS8
for i in /private/var/mobile/Containers/Bundle/Application/*/*.app; do
  base="$(basename "$i")"
  target="$DESTDIR/$base"
  ln -s "$(dirname "$i")" "$target"
done
