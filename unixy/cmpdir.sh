#!/bin/bash
# Compares two directory trees using rsync. By default only does comparisons of filesizes and timestamps,
# but you can add `-c` to compare checksums.
# Usage: cmpdir [-c] [-i] source_dir target_dir
#
# Based on [ubuntu - Verifying a large directory after copy from one hard drive to another - Unix & Linux Stack Exchange](https://unix.stackexchange.com/a/313189/7281):
#
# ```shell
# rsync -ni -aH -c --delete --info=progress2 /SOURCE/FOLDER/ /TARGET/FOLDER 2>&1 | tee /tmp/rsync.FOLDER.log
# ```
#
#
# Be careful to end the first folder name (the source) with a `/`. The options are
#
# -   `-n` dry-run (make no changes)
# -   `-i` itemize changes
# -   `-a` archive mode: preserve (i.e. compare since we have `-n`) permissions, ownerships, symbolic links, etc. and recurse down directories
# -   `-H` preserve hard links
# -   `-c` skip based on checksum, not size and date
# -   `--delete` delete extraneous files from dest dirs

set -euo pipefail
shopt -s failglob
trap exit INT  # So that ^C will stop the entire script, not just the current subprocess

### Check arguments

usage() {
    echo "Usage: $0 [-c] [-i] source_dir target_dir" >&2
    echo "       -c : compare checksums (instead of just filesize and timestamp)" >&2
    echo "       -i : ignore extra files at the destination" >&2
    exit 1
}

opt_checksum=
opt_delete=--delete
while [[ $# -gt 2 ]]; do
    case "${1:-}" in
        -c) opt_checksum="$1" ;;
        -i) opt_delete= ;;
        *) usage ;;
    esac
    shift
done

if [[ $# != 2 ]]; then
    usage
fi
src="$1"
tar="$2"

if [[ ! -d "$src" ]]; then
    echo "${BASH_SOURCE[0]}: Error: source directory $src does not exist" >&2
    exit 1
fi
if [[ ! -d "$tar" ]]; then
    echo "${BASH_SOURCE[0]}: Error: Target directory $tar does not exist" >&2
    exit 1
fi

# Must end in slash to compare the contents of the directory
src="${src%%/}/"

##############################################################################
### Util

# shellcheck disable=SC2120
hr () {
	printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' "${1:--}"
}

### Display instructions

hr
cat <<'END'
𐄫 Legend

The output shows a code detailing the differences for each file or directory
that differs. There is no output if they are the same. The code has columns
`YXcstpoguax` where each character is a dot `.` if that aspect of the comparison
is ok, or a letter:

    Y is type of update:
    < sent (not appropriate in this case)
    > need to copy
    c missing file or directory
    h is hard link
    . no update
    * and rest of line is a message, eg *deleting
    X file type: f file  d dir  L symlink  D device S special file
    c checksum differs. + new item  " " same
    s size differs
    t timestamp differs
    p permissions differ
    o owner differ
    g group differ
    u (not used)
    a acl differ
    x extended attributes differ

For example,

    .d..t...... a/b/                    directory timestamp differs
    cL+++++++++ a/b/d -> /nosuch2       symbolic link missing
    cS+++++++++ a/b/f                   special file missing (a/b/f is a fifo)
    >f..t...... a/b/ff                  file timestamp differs
    hf          a/b/xx1 => a/b/xx       files should be a hard linked
    cLc.t...... a/b/z -> /tmp/hi2       symbolic link to different name
    cd+++++++++ a/c/                    directory missing
    >f+++++++++ a/c/i.10                missing file needs to be copied
END
hr


### Log output and error

# Create temporary file
# NOTE: macOS mktemp requires XXXXXXXX to be at the end.
tmpfile="$(mktemp "${TMP:-/tmp}/$(basename "$0").log.XXXXXXX")"

cat <<EOF

𐄫 Log file

For standard output and error: less "$tmpfile"

𐄫 Executing \`rsync\`…

EOF

# Redirect stdout `>` into a named pipe `>(…)` running `tee`
exec &> >(tee "$tmpfile")

### Execute

set -x
exec rsync --dry-run --itemize-changes -aH \
    ${opt_checksum:+"$opt_checksum"} \
    ${opt_delete:+"$opt_delete"} \
    --info=progress2 \
    --exclude='.DS_Store' \
    --exclude='.git' \
    --exclude='.idea' \
    --exclude='.mypy_cache' \
    --exclude='.venv' \
    --exclude='.vscode' \
    --exclude='node_modules' \
    --exclude='venv' \
    "$src" "$tar"
