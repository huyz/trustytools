#!/usr/bin/env bash
# Downsamples all specified files or retina images with the `@2x.png` suffix.
# Source: https://stackoverflow.com/questions/8087997/automatic-resizing-for-non-retina-image-versions/24946633#24946633
#
# Caveats:
# - Might want to use ImageMagick's `convert` instead of macOS `sips`, as `sips`` seems to fail for some indexed PNGs

# Check for bash 4 for `readarray`
[ "${BASH_VERSINFO:-0}" -ge 4 ] || { echo "${BASH_SOURCE[0]}: Error: bash v4+ required." >&2; exit 1; }

set -euo pipefail
shopt -s failglob
trap exit INT  # So that ^C will stop the entire script, not just the current subprocess


#### Construct file list

if [[ $# -gt 0 ]]; then
    files=("$@")
else
    readarray -t files < <(find . -name "*@2x.png")
fi

#### Process

for file in "${files[@]}"; do
    [[ "$file" = *@1x.png ]] && continue

    outfile="${file%.png}"
    outfile="${outfile%@2x}"
    if [[ "$outfile.png" == "$file" ]]; then
        outfile="${outfile%.png}@x1x.png"
    else
        outfile="${outfile%.png}.png"
    fi

    if [[ "$file" -nt "$outfile" ]]; then
        if [[ "$(dirname "$file")" = *Images.xcassets ]]; then
            echo "Skipping Xcode image asset: $file"
        else
            width="$(sips -g "pixelWidth" "$file" | awk 'FNR>1 {printf "%.0f\n", $2/2}')"
            height="$(sips -g "pixelHeight" "$file" | awk 'FNR>1 {printf "%.0f\n", $2/2}')"
            sips -z "$height" "$width" "$file" --out "$outfile"
            test "$outfile" -nt "$file" || exit 1
        fi
    fi
done
