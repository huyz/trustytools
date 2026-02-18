#!/usr/bin/env python3
# 2026-02-17 Written by ChatGPT, debugged by GLM-5 (via Kilo Code)

import subprocess
import time
import re
from dataclasses import dataclass


# ---- configuration ----
INTERVAL = 5  # seconds between samples

FREE_PCT_WARN = 15
WIRED_PCT_WARN = 50
COMPRESS_WARN_LOW = 25
COMPRESS_WARN_HIGH = 35
SWAP_RATE_WARN = 100        # pages/sec
PAGEOUT_RATE_WARN = 50      # pages/sec
THROTTLED_WARN = 0
# ------------------------


@dataclass
class MemoryStats:
    total: int
    free: int
    wired: int
    compressor: int
    swapins: int
    swapouts: int
    pageouts: int
    throttled: int


def run_memory_pressure() -> str:
    result = subprocess.run(
        ["memory_pressure"],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout


def parse_stats(output: str) -> MemoryStats:
    def extract(pattern: str) -> int:
        match = re.search(pattern, output)
        return int(match.group(1)) if match else 0

    return MemoryStats(
        total=extract(r"The system has \d+ \((\d+) pages"),
        free=extract(r"Pages free:\s+(\d+)"),
        wired=extract(r"Pages wired down:\s+(\d+)"),
        compressor=extract(r"Pages used by compressor:\s+(\d+)"),
        swapins=extract(r"Swapins:\s+(\d+)"),
        swapouts=extract(r"Swapouts:\s+(\d+)"),
        pageouts=extract(r"Pageouts:\s+(\d+)"),
        throttled=extract(r"Pages throttled:\s+(\d+)"),
    )


def percent(part: int, total: int) -> float:
    return (part / total) * 100 if total else 0.0


def main():
    print(f"…sampling over {INTERVAL} seconds…")
    s1 = parse_stats(run_memory_pressure())
    time.sleep(INTERVAL)
    s2 = parse_stats(run_memory_pressure())
    print()

    free_pct = percent(s2.free, s2.total)
    wired_pct = percent(s2.wired, s2.total)
    comp_pct = percent(s2.compressor, s2.total)

    swapin_rate = (s2.swapins - s1.swapins) / INTERVAL
    swapout_rate = (s2.swapouts - s1.swapouts) / INTERVAL
    pageout_rate = (s2.pageouts - s1.pageouts) / INTERVAL

    print(f"Free memory: {free_pct:.2f}%")
    if free_pct < FREE_PCT_WARN:
        print(f"  WARNING: below {FREE_PCT_WARN}% threshold")

    print(f"Wired memory: {wired_pct:.2f}% of RAM")
    if wired_pct > WIRED_PCT_WARN:
        print(f"  WARNING: very high wired proportion (>{WIRED_PCT_WARN}%)")

    print(f"Compressed memory: {comp_pct:.2f}% of RAM")
    if comp_pct > COMPRESS_WARN_HIGH:
        print(f"  WARNING: severe compression load (>{COMPRESS_WARN_HIGH}%)")
    elif comp_pct > COMPRESS_WARN_LOW:
        print(f"  WARNING: elevated compression load (>{COMPRESS_WARN_LOW}%)")

    print(f"Swapin rate: {swapin_rate:.1f} pages/sec")
    if swapin_rate > SWAP_RATE_WARN:
        print(f"  WARNING: high swapin rate (>{SWAP_RATE_WARN} pages/sec)")

    print(f"Swapout rate: {swapout_rate:.1f} pages/sec")
    if swapout_rate > SWAP_RATE_WARN:
        print(f"  WARNING: high swapout rate (>{SWAP_RATE_WARN} pages/sec)")

    print(f"Pageout rate: {pageout_rate:.1f} pages/sec")
    if pageout_rate > PAGEOUT_RATE_WARN:
        print(f"  WARNING: sustained paging I/O (>{PAGEOUT_RATE_WARN} pages/sec)")

    print(f"Pages throttled: {s2.throttled}")
    if s2.throttled > THROTTLED_WARN:
        print(f"  WARNING: memory pressure throttling detected (>{THROTTLED_WARN})")


if __name__ == "__main__":
    main()
