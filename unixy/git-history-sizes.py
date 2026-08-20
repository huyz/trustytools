#!/usr/bin/env python3
"""
Usage:
    # Generate an analysis report (in .git/filter-repo/analysis)
    git filter-repo --analyze
    # Run this script
    python3 git-history-sizes.py

Example output:

```text
PACKED-HISTORY  UNPACKED-HISTORY    CURRENT  BLOBS  PATH
    800.0 MiB          810.0 MiB  200.0 MiB      4  foo.iso
    120.0 MiB            4.8 GiB    8.0 MiB    637  package-lock.json
```

`BLOBS` counts each unique blob SHA once, so it reflects the actual storage
cost (git de-duplicates identical content).  `CURRENT` shows the member path
present in `HEAD` (or the first member if none is present).

Renames are tracked by default: paths that git-filter-repo considers the same
logical file (via its `renames.txt` equivalence classes) are collapsed into a
single row, and a `BLOBS` column shows the number of **distinct historical
blobs** (unique content versions) for that logical file.
To consider all unique paths as distinct, use the `--no-track-renames` flag;
example output:

```text
./git-history-sizes --no-track-renames

PACKED-HISTORY  UNPACKED-HISTORY    CURRENT  PATH
    782.4 MiB          784.1 MiB  196.2 MiB  assets/video.mp4
    123.8 MiB            4.7 GiB    8.1 MiB  generated/data.json
     81.2 MiB          216.5 MiB          -  old/database.dump
     24.7 MiB            2.1 GiB  712.3 KiB  package-lock.json
```

A couple useful variants:
    # Top 200
    ./git-history-sizes -n 200

    # Everything
    ./git-history-sizes -n 0

    # Exact byte counts, useful for further processing
    ./git-history-sizes -n 0 --bytes

2026-08-20 Coded by OpenAI Codex and DeepSeek
"""

import argparse
import re
import subprocess
from pathlib import Path


def get_git_analysis_dir():
    """
    Return the default git-filter-repo analysis directory for the repository
    containing the current directory.

    Uses `git rev-parse --absolute-git-dir`, so this works when invoked from
    anywhere inside the repository -- the worktree root, a subdirectory, or
    even inside the .git directory itself.
    """
    proc = subprocess.run(
        ["git", "rev-parse", "--absolute-git-dir"],
        stdout=subprocess.PIPE,
        check=True,
    )
    git_dir = proc.stdout.decode().strip()
    return Path(git_dir) / "filter-repo" / "analysis"


def parse_size_report(path: Path):
    """
    Parse git-filter-repo's path-all-sizes.txt.

    Expected data lines resemble:

        42913700    1754245 <present>    package-lock.json
        14460503    1336163 2024-07-02   assets/foo.js

    Returns:
        path -> {
            "history_unpacked": ...,
            "history_packed": ...,
            "deleted": ...
        }
    """
    result = {}

    with path.open(encoding="utf-8", errors="surrogateescape") as f:
        for line in f:
            line = line.rstrip("\n")

            if not line or line.startswith("===") or line.startswith("Format:"):
                continue

            m = re.match(
                r"^\s*(\d+)\s+(\d+)\s+(\S+)\s+(.*)$",
                line,
            )
            if not m:
                continue

            unpacked, packed, deleted, pathname = m.groups()

            result[pathname] = {
                "history_unpacked": int(unpacked),
                "history_packed": int(packed),
                "deleted": deleted,
            }

    return result


def parse_renames_report(path: Path):
    """
    Parse git-filter-repo's renames.txt.

    Format is a series of equivalence-class blocks, one per logical file:

        oldname1 ->
            oldname2
            oldname3

    Every path in a block is a different name for the same logical file.

    Returns:
        path -> tuple of all paths in the same equivalence class
    """
    result = {}
    group = None

    with path.open(encoding="utf-8", errors="surrogateescape") as f:
        for line in f:
            line = line.rstrip("\n")

            if not line:
                continue

            if line.endswith("->"):
                group = (line[:-2].strip(),)
            else:
                group = group + (line.strip(),)

            for p in group:
                result[p] = group

    return result


def get_head_sizes():
    """
    Return path -> uncompressed blob size for every regular/blob-like
    path currently present in HEAD.

    `git ls-tree -r -l -z HEAD` produces records approximately like:

        100644 blob <sha> 12345<TAB>path
    """
    proc = subprocess.run(
        ["git", "ls-tree", "-r", "-l", "-z", "HEAD"],
        stdout=subprocess.PIPE,
        check=True,
    )

    result = {}

    for record in proc.stdout.split(b"\0"):
        if not record:
            continue

        metadata, pathname = record.split(b"\t", 1)
        fields = metadata.split()

        # mode, type, object-id, size
        if len(fields) != 4:
            continue

        object_type = fields[1]
        size = fields[3]

        # Submodules have type "commit" and size "-"
        if object_type != b"blob" or size == b"-":
            continue

        path = pathname.decode("utf-8", errors="surrogateescape")
        result[path] = int(size)

    return result


def get_blob_counts():
    """
    Return path -> set of distinct blob SHAs that ever appeared at that path.

    Uses `git rev-list --objects --all`, which lists each (sha, path) pair
    once, so identical content re-committed at the same path is counted only
    once.

    Note: `-z` is deliberately not used here because it only NUL-delimits
    the object IDs and drops the paths entirely.
    """
    proc = subprocess.run(
        ["git", "rev-list", "--objects", "--all"],
        stdout=subprocess.PIPE,
        check=True,
    )

    result = {}

    for line in proc.stdout.splitlines():
        parts = line.split(b" ", 1)
        if len(parts) != 2:
            continue  # commit/tag object, no path

        sha, path = parts
        if path.endswith(b"/"):
            continue  # tree object

        path = path.decode("utf-8", errors="surrogateescape")
        result.setdefault(path, set()).add(sha.decode("ascii"))

    return result


def build_plain_rows(history, current):
    rows = []

    for pathname, info in history.items():
        rows.append(
            (
                info["history_packed"],
                info["history_unpacked"],
                current.get(pathname),
                info["deleted"],
                pathname,
            )
        )

    return rows


def build_rename_grouped_rows(history, current, renames, blob_counts):
    """
    Group paths by git-filter-repo's rename equivalence classes.

    Each row is one logical file:
        (packed, unpacked, current_size, blob_count, current_path)
    """
    # Group history paths by equivalence class, keyed on the canonical path.
    groups = {}
    for pathname in history:
        group = renames.get(pathname, (pathname,))
        groups.setdefault(group[0], set()).add(pathname)

    rows = []

    for key, members in groups.items():
        packed = sum(history[m]["history_packed"] for m in members)
        unpacked = sum(history[m]["history_unpacked"] for m in members)

        # Prefer a member present in HEAD; otherwise fall back to the canonical path.
        current_path = next((m for m in members if m in current), key)
        current_size = current.get(current_path)

        # Distinct blobs across all member paths.
        blobs = set()
        for m in members:
            blobs.update(blob_counts.get(m, ()))

        rows.append((packed, unpacked, current_size, len(blobs), current_path))

    return rows


def human_size(n):
    if n is None:
        return "-"

    units = ["B", "KiB", "MiB", "GiB", "TiB"]
    value = float(n)

    for unit in units:
        if abs(value) < 1024 or unit == units[-1]:
            if unit == "B":
                return f"{int(value)} B"
            return f"{value:.1f} {unit}"
        value /= 1024


def main():
    parser = argparse.ArgumentParser(
        description="Rank Git paths by cumulative packed history size."
    )
    parser.add_argument(
        "--analysis",
        type=Path,
        default=None,
        help="git-filter-repo analysis directory (default: the repo's "
        ".git/filter-repo/analysis, resolved from anywhere in the repo)",
    )
    parser.add_argument(
        "-n",
        "--limit",
        type=int,
        default=50,
        help="number of rows to display; 0 means all (default: 50)",
    )
    parser.add_argument(
        "--bytes",
        action="store_true",
        help="show exact byte counts rather than human-readable sizes",
    )
    parser.add_argument(
        "--track-renames",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="collapse rename histories into a single logical file and show "
        "the number of distinct historical blobs (default: on); use "
        "--no-track-renames for the original per-path grouping",
    )
    args = parser.parse_args()

    if args.analysis is None:
        args.analysis = get_git_analysis_dir()

    report = args.analysis / "path-all-sizes.txt"

    if not report.exists():
        raise SystemExit(
            f"{report} not found.\n"
            "Run this first:\n\n"
            "    git filter-repo --analyze"
        )

    history = parse_size_report(report)
    current = get_head_sizes()

    if args.track_renames:
        renames_file = args.analysis / "renames.txt"

        if not renames_file.exists():
            raise SystemExit(
                f"{renames_file} not found.\n"
                "Run this first:\n\n"
                "    git filter-repo --analyze"
            )

        renames = parse_renames_report(renames_file)
        blob_counts = get_blob_counts()
        rows = build_rename_grouped_rows(history, current, renames, blob_counts)
    else:
        rows = build_plain_rows(history, current)

    rows.sort(key=lambda row: row[0], reverse=True)

    if args.limit:
        rows = rows[: args.limit]

    if args.bytes:
        format_size = lambda n: "-" if n is None else str(n)
    else:
        format_size = human_size

    if args.track_renames:
        headers = ("PACKED-HISTORY", "UNPACKED-HISTORY", "CURRENT", "BLOBS", "PATH")
        formatted = [
            (
                format_size(packed),
                format_size(unpacked),
                format_size(current_size),
                str(blobs),
                pathname,
            )
            for packed, unpacked, current_size, blobs, pathname in rows
        ]
    else:
        headers = ("PACKED-HISTORY", "UNPACKED-HISTORY", "CURRENT", "PATH")
        formatted = [
            (
                format_size(packed),
                format_size(unpacked),
                format_size(current_size),
                pathname,
            )
            for packed, unpacked, current_size, deleted, pathname in rows
        ]

    widths = [
        max(len(headers[i]), *(len(row[i]) for row in formatted))
        for i in range(len(headers) - 1)
    ]

    print(
        "  ".join(f"{headers[i]:>{widths[i]}}" for i in range(len(widths)))
        + f"  {headers[-1]}"
    )

    for row in formatted:
        print(
            "  ".join(f"{row[i]:>{widths[i]}}" for i in range(len(widths)))
            + f"  {row[-1]}"
        )


if __name__ == "__main__":
    main()
