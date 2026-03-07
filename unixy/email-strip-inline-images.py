#!/usr/bin/env python3
# This script is needed because Postbox & Thunderbird let you delete attachments but don't let
# you delete inline images, which can be a problem if you want to save space.
#
# - Accepts one or more Maildir message paths as arguments.
# - Removes inline images larger than X KB.
# - Replaces <img> tags referencing those images with a note:
#   <span>[NOTE YYYY-MM-DD: manually deleted]</span>
# - Inserts a visible placeholder MIME part describing the removed image (content-type, filename, size).
# - Leaves attachments (Content-Disposition: attachment) untouched.
# - Rewrites the message safely so it continues to work with Dovecot and mail clients like Mozilla Thunderbird.
#
# Usage:
#   strip_inline_images.py <size_kb> <mailfile> [mailfile...]
#       Specify size of -1 to remove all inline images regardless of size.
#
# 2026-03-07 Coded by ChatGPT-5

import sys
import os
import re
import datetime
from email import policy
from email.parser import BytesParser
from email.generator import BytesGenerator
from email.message import EmailMessage
from io import BytesIO

NOTE_DATE = datetime.date.today().isoformat()


def size_kb(part):
    payload = part.get_payload(decode=True)
    if payload is None:
        return 0
    return len(payload) / 1024


def create_placeholder(part):
    ct = part.get_content_type()
    cid = part.get("Content-ID", "")
    fn = part.get_filename()
    size = len(part.get_payload(decode=True) or b"")

    text = f"""
[NOTE {NOTE_DATE}: manually deleted]

Removed inline MIME part:
Content-Type: {ct}
Content-ID: {cid}
Filename: {fn}
Size: {size} bytes
""".strip()

    new = EmailMessage()
    new.set_content(text)
    return new


def strip_images(msg, threshold_kb, removed_cids):

    if not msg.is_multipart():
        return

    new_parts = []

    for part in msg.get_payload():

        if part.is_multipart():
            strip_images(part, threshold_kb, removed_cids)
            new_parts.append(part)
            continue

        ct = part.get_content_type()
        disp = part.get_content_disposition()
        cid = part.get("Content-ID")

        if (
            ct.startswith("image/")
            and (disp in (None, "inline"))
            and size_kb(part) >= threshold_kb
        ):
            if cid:
                removed_cids.add(cid.strip("<>"))

            new_parts.append(create_placeholder(part))
        else:
            new_parts.append(part)

    msg.set_payload(new_parts)


def rewrite_html(msg, removed_cids):

    if not msg.is_multipart():
        return

    for part in msg.walk():

        if part.get_content_type() != "text/html":
            continue

        html = part.get_payload(decode=True).decode(
            part.get_content_charset() or "utf-8",
            errors="replace",
        )

        for cid in removed_cids:
            pattern = re.compile(
                r'<img[^>]+src=["\']cid:' + re.escape(cid) + r'["\'][^>]*>',
                re.IGNORECASE,
            )

            html = pattern.sub(
                f'<span>[NOTE {NOTE_DATE}: manually deleted]</span>',
                html,
            )

        part.set_payload(html)
        part.set_charset("utf-8")


def process_file(path, threshold_kb):

    with open(path, "rb") as f:
        msg = BytesParser(policy=policy.default).parse(f)

    removed_cids = set()

    strip_images(msg, threshold_kb, removed_cids)

    if removed_cids:
        rewrite_html(msg, removed_cids)

    if not removed_cids:
        print(f"[skip] {path}")
        return

    buf = BytesIO()
    BytesGenerator(buf, policy=policy.default).flatten(msg)

    with open(path, "wb") as f:
        f.write(buf.getvalue())

    print(f"[modified] {path}  removed={len(removed_cids)}")


def main():

    if len(sys.argv) < 3:
        print("usage: strip_inline_images.py <size_kb> <mailfile> [mailfile...]")
        sys.exit(1)

    threshold_kb = float(sys.argv[1])

    for path in sys.argv[2:]:

        if not os.path.isfile(path):
            print(f"[error] not file: {path}")
            continue

        try:
            process_file(path, threshold_kb)
        except Exception as e:
            print(f"[error] {path}: {e}")


if __name__ == "__main__":
    main()
