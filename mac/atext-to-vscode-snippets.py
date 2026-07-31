#!/usr/bin/env python3
# Converts from aText snippets to VS Code snippets
# 2026-07-31 ChatGPT 5.6 Sol (medium)
#
# Usage:
#   atext-to-vscode-snippets atext-replacements.plist atext.code-snippets
# For language-specific snippets:
#   atext-to-vscode-snippets atext-replacements.plist shell.code-snippets --scope shellscript
"""
Convert an aText plist export to a VS Code snippets JSON file.

Supported aText constructs:

    【|】                         -> $0
    【field:name】                -> ${1:name}
    【date:short】                -> ${CURRENT_YEAR}-${CURRENT_MONTH}-${CURRENT_DATE}
    【time:short】                -> ${CURRENT_HOUR}:${CURRENT_MINUTE}
    【key:↩ ...】                 -> newline
    【key:⌫ ... count:N】         -> removes N preceding characters
    【snippet:...】               -> preserved and reported as unsupported

Unknown aText macros are preserved verbatim and reported on stderr.

Unsupported:
- aText plist export doesn't designate when the text are shell commands to be executed.
  (e.g. <string>date -Idate -u</string>)
"""

from __future__ import annotations

import argparse
import json
import plistlib
import re
import sys
from collections import Counter
from datetime import datetime
from pathlib import Path
from typing import Any


ATEXT_MACRO_RE = re.compile(r"【([^】]*)】")
FIELD_RE = re.compile(r"^field:(.+)$")
KEY_COUNT_RE = re.compile(r"\bcount:(\d+)\b")
KEY_CODE_RE = re.compile(r"\bcode:(\d+)\b")

DATE_FORMATS = {
    "short": "${CURRENT_YEAR}-${CURRENT_MONTH}-${CURRENT_DATE}",
    "medium": "${CURRENT_MONTH_NAME_SHORT} ${CURRENT_DATE}, ${CURRENT_YEAR}",
    "long": "${CURRENT_MONTH_NAME} ${CURRENT_DATE}, ${CURRENT_YEAR}",
    "full": (
        "${CURRENT_DAY_NAME}, ${CURRENT_MONTH_NAME} "
        "${CURRENT_DATE}, ${CURRENT_YEAR}"
    ),
    "yyyy-MM-dd": "${CURRENT_YEAR}-${CURRENT_MONTH}-${CURRENT_DATE}",
    "yyyy-MM-dd EEE": (
        "${CURRENT_YEAR}-${CURRENT_MONTH}-${CURRENT_DATE} "
        "${CURRENT_DAY_NAME_SHORT}"
    ),
    "yyyy-MM-dd EEEE": (
        "${CURRENT_YEAR}-${CURRENT_MONTH}-${CURRENT_DATE} "
        "${CURRENT_DAY_NAME}"
    ),
    "yyyyMMdd": "${CURRENT_YEAR}${CURRENT_MONTH}${CURRENT_DATE}",
    "yy-M-d": (
        "${CURRENT_YEAR/^..(.*)$/${1}/}-${CURRENT_MONTH/^0//}"
        "-${CURRENT_DATE/^0//}"
    ),
    "dd-MM-yyyy": "${CURRENT_DATE}-${CURRENT_MONTH}-${CURRENT_YEAR}",
    "d-M-yy": (
        "${CURRENT_DATE/^0//}-${CURRENT_MONTH/^0//}"
        "-${CURRENT_YEAR/^..(.*)$/${1}/}"
    ),
    "EEE, MMM d, ''yy": (
        "${CURRENT_DAY_NAME_SHORT}, ${CURRENT_MONTH_NAME_SHORT} "
        "${CURRENT_DATE/^0//}, '${CURRENT_YEAR/^..(.*)$/${1}/}"
    ),
    "EEEE, MMMM dd, yyyy": (
        "${CURRENT_DAY_NAME}, ${CURRENT_MONTH_NAME} ${CURRENT_DATE}, "
        "${CURRENT_YEAR}"
    ),
    "unix": "${CURRENT_SECONDS_UNIX}",
}

TIME_FORMATS = {
    "short": "${CURRENT_HOUR}:${CURRENT_MINUTE}",
    "medium": "${CURRENT_HOUR}:${CURRENT_MINUTE}:${CURRENT_SECOND}",
    "HH:mm": "${CURRENT_HOUR}:${CURRENT_MINUTE}",
    "HH:mm:ss": "${CURRENT_HOUR}:${CURRENT_MINUTE}:${CURRENT_SECOND}",
}


class ConversionWarnings:
    def __init__(self) -> None:
        self.unsupported: Counter[str] = Counter()

    def add(self, macro: str) -> None:
        self.unsupported[macro] += 1

    def print(self) -> None:
        if not self.unsupported:
            return

        print(
            "\nWarning: unsupported aText macros were preserved verbatim:",
            file=sys.stderr,
        )
        for macro, count in self.unsupported.items():
            suffix = f" ({count} occurrences)" if count > 1 else ""
            print(f"  【{macro}】{suffix}", file=sys.stderr)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Convert an aText plist export to VS Code snippets JSON."
    )
    parser.add_argument(
        "input",
        type=Path,
        help="Input aText plist file",
    )
    parser.add_argument(
        "output",
        nargs="?",
        type=Path,
        help="Output JSON file; defaults to stdout",
    )
    parser.add_argument(
        "--scope",
        help=(
            "Optional VS Code snippet scope, such as "
            "'shellscript' or 'python,javascript'"
        ),
    )
    parser.add_argument(
        "--name-prefix",
        default="aText",
        help="Prefix used for generated snippet names (default: %(default)s)",
    )
    parser.add_argument(
        "--drop-unsupported",
        action="store_true",
        help="Remove unsupported aText macros instead of preserving them",
    )
    parser.add_argument(
        "--indent",
        type=int,
        default=2,
        help="JSON indentation width (default: %(default)s)",
    )
    parser.add_argument(
        "--filter-out-regex",
        help="Regex for shortcuts to skip entirely (default: %(default)s)",
    )
    parser.add_argument(
        "--stop-processing",
        help=(
            "Shortcut that stops loading any remaining entries "
            "(default: %(default)s)"
        ),
    )
    return parser.parse_args()


def load_plist(
    path: Path,
    *,
    filter_out_re: Optional[re.Pattern[str]] = None,
    stop_processing: Optional[str] = None,
) -> list[dict[str, Any]]:
    try:
        with path.open("rb") as file:
            data = plistlib.load(file)
    except OSError as error:
        raise SystemExit(f"Cannot read {path}: {error}") from error
    except plistlib.InvalidFileException as error:
        raise SystemExit(f"Invalid plist file {path}: {error}") from error

    if not isinstance(data, list):
        raise SystemExit(
            f"Expected the plist root to be an array, got {type(data).__name__}"
        )

    entries: list[dict[str, Any]] = []

    for index, item in enumerate(data, start=1):
        if not isinstance(item, dict):
            print(
                f"Warning: skipping plist item {index}: expected a dictionary",
                file=sys.stderr,
            )
            continue

        phrase = item.get("phrase")
        shortcut = item.get("shortcut")

        if not isinstance(phrase, str) or not isinstance(shortcut, str):
            print(
                f"Warning: skipping plist item {index}: "
                "'phrase' and 'shortcut' must both be strings",
                file=sys.stderr,
            )
            continue

        if filter_out_re and filter_out_re.match(shortcut):
            continue

        if shortcut == stop_processing:
            break

        entries.append(item)

    return entries


def escape_snippet_text(text: str) -> str:
    """
    Escape literal characters that VS Code interprets as snippet syntax.

    This is applied to ordinary aText text before generated VS Code snippet
    placeholders are inserted.
    """
    return text.replace("\\", "\\\\").replace("$", "\\$")


def parse_date_or_time_macro(macro: str) -> str | None:
    if macro.startswith("date:"):
        raw_value = macro.removeprefix("date:").strip()
        formats = DATE_FORMATS
    elif macro.startswith("time:"):
        raw_value = macro.removeprefix("time:").strip()
        formats = TIME_FORMATS
    else:
        return None

    if len(raw_value) >= 2 and raw_value[0] == raw_value[-1] == '"':
        value = raw_value[1:-1]
    else:
        value_parts: list[str] = []
        for token in raw_value.split():
            if re.match(r"^[A-Za-z_]+:.*$", token):
                break
            value_parts.append(token)

        value = " ".join(value_parts)

    if macro.startswith("time:"):
        return formats.get(value) or render_time_format(value)

    return formats.get(value)


def render_time_format(value: str) -> str | None:
    now = datetime.now().astimezone()

    if value == "long":
        return now.strftime("%H:%M:%S %Z")

    if value == "full":
        return now.strftime("%H:%M:%S %Z")

    if value == "h:mm a":
        return now.strftime("%I:%M %p").lstrip("0")

    if value == "h:mm a, zzz":
        return now.strftime("%I:%M %p, %Z").lstrip("0")

    if value == "hh 'o''clock' a, zzzz":
        return now.strftime("%I o'clock %p, %Z")

    if value == "unix":
        return str(int(now.timestamp()))

    return None


def key_macro_replacement(macro: str) -> tuple[str, int] | None:
    """
    Return (inserted_text, backspace_count) for supported key macros.
    """
    if not macro.startswith("key:"):
        return None

    count_match = KEY_COUNT_RE.search(macro)
    count = int(count_match.group(1)) if count_match else 1
    code_match = KEY_CODE_RE.search(macro)

    key_description = macro.removeprefix("key:").split(maxsplit=1)[0]

    if key_description in {"↩", "⏎", "return", "enter"}:
        return "\n" * count, 0

    if key_description in {"⌫", "backspace"}:
        return "", count

    if key_description in {"⇥", "tab"}:
        return "\t" * count, 0

    if code_match and len(key_description) == 1:
        return key_description * count, 0

    if code_match and key_description in {"⎋", "escape", "esc"}:
        return "", 0

    return None


def remove_preceding_characters(parts: list[str], count: int) -> None:
    while count > 0 and parts:
        tail = parts[-1]

        if len(tail) <= count:
            count -= len(tail)
            parts.pop()
        else:
            parts[-1] = tail[:-count]
            count = 0


def convert_phrase(
    phrase: str,
    warnings: ConversionWarnings,
    *,
    drop_unsupported: bool,
) -> str:
    parts: list[str] = []
    field_numbers: dict[str, int] = {}
    next_field_number = 1
    position = 0

    for match in ATEXT_MACRO_RE.finditer(phrase):
        parts.append(escape_snippet_text(phrase[position : match.start()]))

        macro = match.group(1)

        if macro == "|":
            parts.append("$0")

        elif field_match := FIELD_RE.match(macro):
            field_name = field_match.group(1).strip()

            # Repeated fields use the same tab stop, making them linked.
            if field_name not in field_numbers:
                field_numbers[field_name] = next_field_number
                next_field_number += 1

            number = field_numbers[field_name]
            escaped_default = (
                field_name.replace("\\", "\\\\")
                .replace("$", "\\$")
                .replace("}", "\\}")
            )
            parts.append(f"${{{number}:{escaped_default}}}")

        elif date_or_time_replacement := parse_date_or_time_macro(macro):
            parts.append(date_or_time_replacement)

        elif key_replacement := key_macro_replacement(macro):
            inserted_text, backspace_count = key_replacement
            if backspace_count:
                remove_preceding_characters(parts, backspace_count)
            else:
                parts.append(inserted_text)

        else:
            warnings.add(macro)
            if not drop_unsupported:
                parts.append(escape_snippet_text(match.group(0)))

        position = match.end()

    parts.append(escape_snippet_text(phrase[position:]))
    return "".join(parts)


def unique_snippet_name(
    prefix: str,
    shortcut: str,
    existing_names: set[str],
) -> str:
    base = f"{prefix}: {shortcut}"
    name = base
    sequence = 2

    while name in existing_names:
        name = f"{base} ({sequence})"
        sequence += 1

    existing_names.add(name)
    return name


def build_snippets(
    entries: list[dict[str, Any]],
    *,
    scope: str | None,
    name_prefix: str,
    warnings: ConversionWarnings,
    drop_unsupported: bool,
) -> dict[str, dict[str, Any]]:
    snippets: dict[str, dict[str, Any]] = {}
    names: set[str] = set()

    for entry in entries:
        shortcut = entry["shortcut"]
        phrase = entry["phrase"]

        converted = convert_phrase(
            phrase,
            warnings,
            drop_unsupported=drop_unsupported,
        )

        snippet: dict[str, Any] = {
            "prefix": shortcut,
            # An array is preferable for multiline snippet bodies.
            "body": converted.split("\n"),
            "description": f"Imported from aText: {shortcut}",
        }

        if scope:
            snippet["scope"] = scope

        name = unique_snippet_name(name_prefix, shortcut, names)
        snippets[name] = snippet

    return snippets


def write_json(
    snippets: dict[str, dict[str, Any]],
    output: Path | None,
    *,
    indent: int,
) -> None:
    encoded = json.dumps(
        snippets,
        ensure_ascii=False,
        indent=indent,
    )
    encoded += "\n"

    if output is None:
        sys.stdout.write(encoded)
        return

    try:
        output.write_text(encoded, encoding="utf-8")
    except OSError as error:
        raise SystemExit(f"Cannot write {output}: {error}") from error


def main() -> None:
    args = parse_args()
    try:
        filter_out_re = re.compile(args.filter_out_regex) if args.filter_out_regex else None
    except re.error as error:
        raise SystemExit(f"Invalid --filter-out-regex: {error}") from error

    entries = load_plist(
        args.input,
        filter_out_re=filter_out_re,
        stop_processing=args.stop_processing,
    )
    warnings = ConversionWarnings()

    snippets = build_snippets(
        entries,
        scope=args.scope,
        name_prefix=args.name_prefix,
        warnings=warnings,
        drop_unsupported=args.drop_unsupported,
    )

    write_json(snippets, args.output, indent=args.indent)
    warnings.print()


if __name__ == "__main__":
    main()
