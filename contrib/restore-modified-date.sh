#!/bin/bash
# Undoes the damage that chkbit did to the modification dates of directories:
# restores the modification dates of directories from backup.

# 2024-11-26 Based on https://gist.github.com/porg/b6b3160f41c5c6ce7ced5a4982d4aa2e#file-cp-date-modified-sh
#   but scoped to directories only and traverses target instead of traversing backup.


# When debugging
#set -x

#### Preamble (v2024-04-25.1)

# Requires root
#[ "${EUID:-$UID}" -eq 0 ] || exec sudo -p '[sudo] password for %u: ' -H "$BASH" "$0" "$@"
#[ "${EUID:-$UID}" -eq 0 ] || { echo "${BASH_SOURCE[0]}: ERROR: must be run as root" >&2; exit 1; }

# Check for bash 4 for `readarray`
#[ "${BASH_VERSINFO:-0}" -ge 4 ] || { echo "${BASH_SOURCE[0]}: ERROR: bash v4+ required." >&2; exit 1; }

set -euo pipefail
shopt -s failglob
# shellcheck disable=SC2317
function trap_err { echo "ERR signal on line $(caller)" >&2; }
trap trap_err ERR
trap exit INT
export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

_install_cmd='brew install'
if [[ $OSTYPE == darwin* ]]; then
    if [[ "${EUID:-$UID}" -eq 0 ]]; then
        _install_cmd='sudo port install'
        MAC_PREFIX=/opt/local
        [[ -x "${GETOPT:="$MAC_PREFIX/bin/getopt"}" ]] || \
            { echo "$0: ERROR: \`$_install_cmd util-linux\` to install $GETOPT." >&2; exit 1; }
    else
        HOMEBREW_PREFIX="$( (/opt/homebrew/bin/brew --prefix || /usr/local/bin/brew --prefix || brew --prefix) 2>/dev/null)"
        MAC_PREFIX="$HOMEBREW_PREFIX"
        [[ -x "${GETOPT:="$MAC_PREFIX/opt/gnu-getopt/bin/getopt"}" ]] || \
            { echo "$0: ERROR: \`$_install_cmd gnu-getopt\` to install $GETOPT." >&2; exit 1; }
    fi
    [[ -x "${REALPATH:="$MAC_PREFIX/bin/grealpath"}" ]] || \
        { echo "$0: ERROR: \`$_install_cmd coreutils\` to install $REALPATH." >&2; exit 1; }
    DATE="gdate"
    STAT="gstat"
    TOUCH="gtouch"
else
    HOMEBREW_PREFIX="$( (/home/linuxbrew/.linuxbrew/bin/brew --prefix || brew --prefix) 2>/dev/null)"
    GETOPT="getopt"
    REALPATH="realpath"
    DATE="date"
    STAT="stat"
    TOUCH="touch"
fi

# shellcheck disable=SC2034
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
# a) Uncomment to expand symlinks in order to find the proper .envrc for direnv
#SCRIPT="$($REALPATH "${BASH_SOURCE[0]}")"
# b) Uncomment in the general case
SCRIPT="$($REALPATH --no-symlinks "${BASH_SOURCE[0]}")"
# shellcheck disable=SC2034
SCRIPT_DIR="$(dirname "$SCRIPT")"

#### Options

# Defaults
opt_dry_run=
opt_verbose=
opt_after=
opt_before=
#opt_argument=default

function usage {
    cat <<END >&2
Usage: $SCRIPT_NAME [-h|--help] [-n|--dry-run] [-v|--verbose] [-a date|--after date] [-b date|--before date] BACKUP_DIR TARGET_DIR
        -h|--help: get help
        -n|--dry-run: simulate write actions as much as possible
        -v|--verbose: turn on verbose mode
        -a|--after:  only update files whose modification dates are newer than this time, inclusive
        -b|--before: only update files whose modification dates are older than this time, inclusive

    Loops through all subdirectories of TARGET_DIR, inclusively.
    For each subdir in TARGET_DIR, seeks a corresponding subdir in BACKUP_DIR.
    - If not found in backup, the subdir is skipped.
    - If found and they have the same modification timestamps, do nothing.
    - If found and the moddates differ, the moddate is copied from backup to target.
END
    exit 1
}

opts=$($GETOPT --options hnva:b: --long help,dry-run,verbose,after:,before: --name "$SCRIPT_NAME" -- "$@") || usage
eval set -- "$opts"

while true; do
    case "$1" in
        -h | --help) usage ;;
        -n | --dry-run) opt_dry_run=opt_dry_run; shift ;;
        -v | --verbose) opt_verbose=opt_verbose; shift ;;
        -a | --after) opt_after="$2"; shift 2 ;;
        -b | --before) opt_before="$2"; shift 2 ;;
        --) shift; break ;;
        *) echo "$SCRIPT_NAME: INTERNAL ERROR: '$1'" >&2; exit 1 ;;
    esac
done

if [[ -n $opt_after ]]; then
    if ! opt_after_ts="$($DATE --date="$opt_after" '+%s')"; then
        #echo "$SCRIPT_NAME: ERROR: invalid 'after' date '$opt_after'" >&2
        exit 1
    fi
fi
if [[ -n $opt_before ]]; then
    if ! opt_before_ts="$($DATE --date="$opt_before" '+%s')"; then
        #echo "$SCRIPT_NAME: ERROR: invalid 'before' date '$opt_before'" >&2
        exit 1
    fi
fi


if [[ $# -ne 2 ]]; then
    usage
fi

backupDir="$1"
targetDir="$2"

# shellcheck disable=SC2059,SC2317
function run_cmd {
    [[ -z ${opt_verbose-} ]] || printf "#❯%s\n" "$(printf " %q" "$@")" || true
    [[ -n ${opt_dry_run-} ]] || "$@"
}

##############################################################################
#### Init

if [[ ! -d "$backupDir" ]]; then
    echo "$SCRIPT_NAME: ERROR: No directory at BACKUP_DIR $backupDir" >&2
    exit 1
fi

if [[ ! -d "$targetDir" ]]; then
    echo "$SCRIPT_NAME: ERROR: No directory at TARGET_DIR $targetDir" >&2
    exit 1
fi


##############################################################################
#### Main

#cd "$SCRIPT_DIR/.."
#eval "$(direnv export bash 2>/dev/null)"

echo "𐄫 LEGEND:"
echo
echo "File Name.ext"
echo "  Backup's creation date"
echo "  Backup's modification date"
echo "  Target's modification date"
echo
echo "  🟢 Backup and target have same moddate. No need to act."
echo "  🟡 Backup's moddate differs. --> Target moddate is restored from backup."
echo "  🔴 Backup file not found."
echo

echo "𐄫 PROCESSING…"
echo
found=0
notfound=0
changed=0

while IFS= read -r file; do
    targetFileCreation="$($STAT --format '%w' "$targetDir/$file")"
    targetFileModification="$($STAT --format '%y' "$targetDir/$file")"
    targetFileModificationTS="$($DATE --date="$targetFileModification" '+%s')"

    if [[ -n ${opt_after_ts:-} && "$targetFileModificationTS" -lt "$opt_after_ts" ]]; then
        if [[ -n $opt_verbose ]]; then
            echo "𐄬 $file"
            echo "   skipped because modification date is before $opt_after" >&2
            echo
        fi
        continue
    fi
    if [[ -n ${opt_before_ts:-} && "$targetFileModificationTS" -gt "$opt_before_ts" ]]; then
        if [[ -n $opt_verbose ]]; then
            echo "𐄬 $file"
            echo "   skipped because modification date is after $opt_before" >&2
            echo
        fi
        continue
    fi

    echo "𐄬 $file"
    echo "   $targetFileCreation creation"
    echo "   $targetFileModification ───┐"
    if [[ -e "$backupDir/$file" ]] ; then
        ((found++))
        backupFileModification=$($STAT --format '%y' "$backupDir/$file")
        if [[ "$backupFileModification" == "$targetFileModification" ]] ; then
            echo "🟢 $backupFileModification √ ─┘"
        else
            run_cmd $TOUCH -m --reference="$backupDir/$file" "$targetDir/$file"
            ((changed++))
            echo "🟡 $backupFileModification ≠  └───> Restored from backup ✅"
        fi
    else
        ((notfound++))
        echo "🔴 Not in backup dir!   ─┘"
    fi

    echo
done < <(set -e; cd "$targetDir"; find . -depth -type d)


echo
echo "𐄫 SUMMARY:"
echo
echo "  Not found: $notfound"
echo "  Found: $found"
echo "  Changed: $changed"
