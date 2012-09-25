#!/bin/bash
# Installs all binaries into ~/bin

if [ ! -e setup.sh ]; then
  echo "ERROR: This script needs to be run from within the git repository" >&2
  exit 1
fi

GIT=$PWD

[ -d ~/bin ] || mkdir ~/bin
cd ~/bin

for i in $GIT/*.*; do
  target=$(basename "${i%%.*}")
  if [ -x "$i" -a ! -e "$target" ]; then
    echo ln -s "$i" "$target"
    ln -s "$i" "$target"
  fi
done
