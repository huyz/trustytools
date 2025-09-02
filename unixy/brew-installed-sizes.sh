#!/bin/bash
# Lists all installed packages, sorted by size
# Usage: use -v to let brew do the sizing, but much slower

#### Preamble (v2023-04-10)

set -euo pipefail
shopt -s failglob
# shellcheck disable=SC2329
function trap_err { echo "ERR signal on line $(caller)" >&2; }
trap trap_err ERR
trap exit INT
export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

if [[ $OSTYPE == darwin* ]]; then
    HOMEBREW_PREFIX="$( (/opt/homebrew/bin/brew --prefix || /usr/local/bin/brew --prefix || brew --prefix) 2>/dev/null)"
    [ -x "${GETOPT:="$HOMEBREW_PREFIX/opt/gnu-getopt/bin/getopt"}" ] || \
        { echo "$0: Error: \`brew install gnu-getopt\` to install $GETOPT." >&2; exit 1; }
    [ -x "${XARGS:="$HOMEBREW_PREFIX/bin/gxargs"}" ] || \
        { echo "$0: Error: \`brew install findutils\` to install $XARGS." >&2; exit 1; }
else
    HOMEBREW_PREFIX="$( (/home/linuxbrew/.linuxbrew/bin/brew --prefix || brew --prefix) 2>/dev/null)"
    GETOPT="getopt"
    XARGS="xargs"
fi
BREW="$HOMEBREW_PREFIX/bin/brew"

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

#### Options

function usage {
#Usage: $SCRIPT_NAME [-h|--help] [-n|--dry-run] [-v|--verbose] [-a value|--argument value] [file...]
    cat <<END >&2
Usage: $SCRIPT_NAME [-h|--help] [-v|--verbose] [file...]
        -h|--help: get help
        -v|--verbose: turn on verbose mode (slower)
END
#        -a value|--argument value: pass value to the argument option
    exit 1
}

# Defaults
opt_verbose=

#opts=$($GETOPT --options hnva: --long help,dry-run,verbose,argument: --name "$SCRIPT_NAME" -- "$@") || usage
opts=$($GETOPT --options hv --long help,verbose --name "$SCRIPT_NAME" -- "$@") || usage
eval set -- "$opts"

while true; do
    case "$1" in
        -h | --help) usage ;;
        -v | --verbose) opt_verbose=opt_verbose; shift ;;
        #-a | --argument) opt_argument="$2"; shift 2 ;;
        --) shift; break ;;
        *) echo "$SCRIPT_NAME: Internal error: '$1'" >&2; exit 1 ;;
    esac
done

#### Main

if [[ -z "$opt_verbose" ]]; then
    du -d 1 -h "$HOMEBREW_PREFIX/Cellar" |
        sort -h |
        perl -ne 'print "$2 $1\n" if m,^(\S+).*/Cellar/(.*),' |
        column -t
else
    # Sources:
    # - https://stackoverflow.com/questions/40065188/get-size-of-each-installed-formula-in-homebrew/52900850#52900850
    # - https://stackoverflow.com/questions/40065188/get-size-of-each-installed-formula-in-homebrew/64041990#64041990
    $BREW list --formula |
        $XARGS --max-procs=8 -I {} \
        bash -c "brew info --formula {} |
            sed -n 's/^.*[0-9]* files, \(.*\)).*$/\1/p' |
            awk '"'
                BEGIN { printf "{}\t(" }
                FNR == 2 P { printf "+" }
                { printf "%s",$1 }
                /[0-9]$/{ s+=$1 };
                /[kK][bB]$/{ s+=$1*1024; next }
                /[mM][bB]$/{ s+=$1*(1024*1024); next };
                /[gG][bB]$/{ s+=$1*(1024*1024*1024); next };
                END {
                    suffix=" KMGT";
                    for (i=1; s > 1024 && i < length(suffix); i++) s /= 1024;
                    printf ")\t%0.1f%s\n",s,substr(suffix, i, 1), $3;
                }'"'" |
        # Move total column to second column (Take first column, take last column, and re-add them to the front of the row)
        perl -lane 'unshift @F, shift @F, pop @F; print "@F"' |
        sort -h -k2 - |
        column -t
fi
