#!/bin/bash
# Installs all binaries into ~/bin

#### Preamble (v2023-01-19)

# If this script must be run as root
#[ $EUID -eq 0 ] || { echo "${BASH_SOURCE[0]}: Error: must be run as root" >&2; exit 1; }
#[ $EUID -eq 0 ] || exec sudo "$BASH" "$0" "$@"

set -euo pipefail
shopt -s failglob
function trap_err { echo "ERR signal on line $(caller)" >&2; }
trap trap_err ERR
trap exit INT

### Preamble

case "$OSTYPE" in
    darwin*)
        HOMEBREW_PREFIX="$( (brew --prefix || /opt/homebrew/bin/brew --prefix || /usr/local/bin/brew --prefix) 2> /dev/null)"
        READLINK="$HOMEBREW_PREFIX/bin/greadlink"
        if [[ ! -x $READLINK ]]; then
            echo "$0: error: $READLINK could not be found. Run \`brew install coreutils\`" >&2
            exit 1
        fi
        REALPATH="$HOMEBREW_PREFIX/bin/grealpath"
        if [[ ! -x $REALPATH ]]; then
            echo "$0: error: $REALPATH could not be found. Run \`brew install coreutils\`" >&2
            exit 1
        fi
        GETOPT="$HOMEBREW_PREFIX/opt/util-linux/bin/getopt"
        if [[ ! -x $GETOPT ]]; then
            echo "$0: error: $GETOPT could not be found. Run \`brew install util-linux\`" >&2
            exit 1
        fi
        ;;
    *)
        READLINK=readlink
        REALPATH=realpath
        GETOPT=getopt
        ;;
esac

# FIXME: we're going to use realpath -s to get a pretty path, but this only works if the
# script is called when the current directory is where the symlink is going to be created (e.g., ~)
# So `./setup.sh` won't work, but `cd ~ && git/+huy/dot-shared/setup.sh` will
SCRIPT="$($REALPATH -s "${BASH_SOURCE[0]}")"
SCRIPT_NAME="$(basename "$SCRIPT")"
SCRIPT_DIR="$(dirname "$SCRIPT")"


### Usage

usage()
{
    cat <<END >&2
    Usage: $SCRIPT_NAME [-h|--help] [-n|--dry-run] [-f|--force] [file...]
        -h|--help: get help
        -n|--dry-run: don't make any modifications
        -f|--force: overwrite symlinks
END
    exit 1
}

### Option defaults

opt_dry_run=
opt_force=
opt_pretty_path=

### Options

opts=$($GETOPT --options hnfp: --long help,dry-run,force,pretty-path --name "$SCRIPT_NAME" -- "$@")
# shellcheck disable=SC2181
[ $? != 0 ] && usage
eval set -- "$opts"

while true; do
    case "$1" in
        -h | --help) usage ;;
        -n | --dry-run)
            opt_dry_run=1
            shift
            ;;
        -f | --force)
            opt_force=fn
            shift
            ;;
        -p | --pretty-path)
            opt_pretty_path="$1"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "$SCRIPT_NAME: Internal error!" >&2
            exit 1
            ;;
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
        if [[ -z $opt_force ]]; then
            echo "$SCRIPT_NAME: error: non-symlink $link_name already exists, so can't symlink to $target" >&2
            return 1
        else
            echo "$SCRIPT_NAME: warning: non-symlink $link_name already exists. Overwriting by symlinking to ${target}…" >&2
        fi
    fi

    echo ln -s$opt_force "$1" "$2"
    [[ -z $opt_dry_run ]] && ln -s$opt_force "$1" "$2"
}
### Contents of base

if [[ -n $opt_pretty_path && "$($REALPATH "$SCRIPT_DIR")" != "$($REALPATH "$opt_pretty_path")" ]]; then
    echo "$SCRIPT_NAME: Error: $SCRIPT_DIR is not the same as $opt_pretty_path" >&2
    exit 1
fi

relative_dir="${opt_pretty_path:-"$SCRIPT_DIR"}"
relative_dir="${relative_dir#"$HOME/"}"

### Contents of subdirs

cd ~/bin

for subdir in contrib docker mac unixy; do
    # Install mac scripts only on mac
    [[ $subdir == 'mac' && $OSTYPE != darwin* ]] && continue

    case "$subdir" in
        */*) prefix=../.. ;;
        *) prefix=.. ;;
    esac

    relative_dir="$prefix/${SCRIPT_DIR#"$HOME"/}"

    for i in "$relative_dir"/"$subdir"/*; do
        link_name="$(basename "$i")"
        link_name=${link_name%.*}
        [[ $link_name = +ARCHIVED ]] && continue
        symlink "$i" "$link_name"
    done
done

