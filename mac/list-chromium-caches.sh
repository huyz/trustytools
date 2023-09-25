#!/usr/bin/env bash
# Total up the damage of junk Chromium/Electron cache folders

file_count=0
total_size=0

readarray -t dirs < <(fd --type directory '^((|Code |Dawn|GPU|Script)Cache|CacheStorage|.*_crx_cache)$' ~/"Library/Application Support")

for dir in "${dirs[@]}"; do
    echo "$dir"
    # Count files and size
    count=$(find "$dir" -type f | wc -l)
    size=$(du -sk "$dir" | awk '{print $1}')

    # Increment counters
    file_count=$((file_count + count))
    total_size=$((total_size + size))
done

echo
echo "Number of Cache Folders: ${#dirs[@]}"
echo "Total File Count: $file_count"
echo "Total File Size: $total_size KiB"


