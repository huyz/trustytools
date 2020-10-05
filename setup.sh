#!/bin/bash
# Installs all binaries into ~/bin

### Preamble

case "$OSTYPE" in
    darwin*)
        READLINK=/usr/local/bin/greadlink
        if [[ ! -x $READLINK ]]; then
            echo "$0: error: $READLINK could not be found. Run \`brew install coreutils\`" >&2
            exit 1
        fi
        GETOPT=/usr/local/opt/gnu-getopt/bin/getopt
        if [[ ! -x $GETOPT ]]; then
            echo "$0: error: $GETOPT could not be found. Run \`brew install gnu-getopt\`" >&2
            exit 1
        fi
        ;;
    *)
        READLINK=readlink
        GETOPT=getopt
        ;;
esac

SCRIPT="$($READLINK -f "${BASH_SOURCE[0]}")"
SCRIPT_NAME="$(basename "$SCRIPT")"
SCRIPT_DIR="$(dirname "$SCRIPT")"

### Usage

usage()
{
  cat <<END >&2
Usage: $SCRIPT_NAME [-h|--help] [-n|--dry-run] [-a value|--argument value] [file...]
       -h|--help: get help
       -n|--dry-run: don't make any modifications
       -f|--force: overwrite symlinks
END
  exit 1
}

### Option defaults

opt_dry_run=
opt_force=

### Options

opts=$($GETOPT --options hnf --long help,dry-run,force --name "$SCRIPT_NAME" -- "$@")
[ $? != 0 ] && usage
eval set -- "$opts"

while true; do
  case "$1" in
    -h | --help) usage ;;
    -n | --dry-run) opt_dry_run=1; shift ;;
    -f | --force) opt_force=f; shift ;;
    --) shift; break ;;
    *) echo "$SCRIPT_NAME: Internal error!" >&2; exit 1 ;;
  esac
done

[[ $# -gt 0 ]] && usage

### Function

function symlink {
    target="$1"
    link_name="$2"

    if [[ -h "$link_name" ]]; then
        link_target="$(readlink "$link_name")"
        if [[ "$link_target" != "$target" ]]; then
            if [[ -z $opt_force ]]; then
                echo "$SCRIPT_NAME: error: $link_name is pointing to $link_target" >&2
                return 1
            fi
        else
            return 0
        fi
    elif [[ -e "$link_name" ]]; then
        echo "$SCRIPT_NAME: error: $link_name already exists" >&2
        return 1
    fi

    echo ln -s$opt_force "$1" "$2"
    [[ -z $opt_dry_run ]] && ln -s$opt_force "$1" "$2"
}

### Contents of subdirs

cd ~/bin

for subdir in contrib mac unixy; do
    # Install mac scripts only on mac
    case "$subdir" in
        */mac/*)
        case "$OSTYPE" in
            darwin*) ;;
            *) continue ;;
        esac
    esac

    case "$subdir" in
        */*) prefix=../.. ;;
        *) prefix=.. ;;
    esac

    relative_dir="$prefix/${SCRIPT_DIR#$HOME/}"

    for i in "$relative_dir"/$subdir/*; do
        link_name="$(basename "$i")"
        link_name=${link_name%.*}
        [[ $link_name = +ARCHIVED ]] && continue
        symlink "$i" "$link_name"
    done
done

