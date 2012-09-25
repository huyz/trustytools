#!/bin/sh
# $RCSfile: carc,v $ $Revision: 1.18 $ $Date: 2012/09/25 20:58:17 $
# Archives the given files into a gzip'd tar file, optionally encrypted.

# We actually want zsh
[ "x$ZSH_VERSION" = "x" ] && exec zsh -f "$0" "$@"

### Configuration

opt_verbose=v
opt_encrypt=

### Usage

usage()
{
  echo "Usage: $0 [options] archive_prefix file...
  Options:
    -e : encrypt using gpg 3DES
    -q : run quietly"
  exit 1
}
while getopts "eq" opt; do
  case $opt in
    e) [[ -n $opt_encrypt ]] && opt_encrypt= || opt_encrypt=.3des ;;
    q) [[ -n $opt_verbose ]] && opt_verbose= || opt_verbose=v ;;
    \?) usage ;;
  esac
done
shift $(( $OPTIND - 1 ))
[[ $# -lt 2 ]] && usage
 
### Action

# Check if archive already exists
if [[ -e "$1.tbz$opt_encrypt" ]]; then
  echo "File '$1:t.tbz$opt_encrypt' exists. Overwrite (y/N)? \c"
  read ans
  [[ "$ans" != [yY]* ]] && exit 1

  # NOTE: we delete the file so gpg doesn't give the overwrite prompt again
  \rm -f "$1.tbz$opt_encrypt"
fi

# Encrypt
if [[ -n $opt_encrypt ]]; then
  tar -cf - "${(@)argv[2,-1]}" |
#    gzip -c |
    bzip2 -c |
    gpg -c --cipher-algo 3DES -o "$1.tbz.3des"
# Don't encrypt
else
  tar -c${opt_verbose}jf "$1.tbz" "${(@)argv[2,-1]}"
fi
