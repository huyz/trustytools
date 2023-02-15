#!/usr/bin/env bash
# Returns the bounds of the display where the mouse is located in the form:
#   x y width height
# To use from AppleScript:
#   set displayBounds to do shell script "PATH=/opt/homebrew/bin:$PATH /Users/huyz/bin/get-bounds-of-mouse-display | xargs -n 1 echo"
#   set displayBounds to the paragraphs of displayBounds


[ "${BASH_VERSINFO:-0}" -ge 4 ] || { echo "${BASH_SOURCE[0]}: Error: bash v4+ required." >&2; exit 1; }

set -euo pipefail
shopt -s failglob
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

#### Checks

# Check that Homebrew executables are installed
for cmd in cliclick displayplacer; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "$SCRIPT_NAME: Error: $cmd not found.  Run: \`brew install $cmd\`" >&2
        exit 1
    fi
done

#### Main

displays="$(displayplacer list | perl -ne '
    ($width, $height) = ($1, $2) if /^Resolution:\s+(\d+)x(\d+)$/;
    if (defined($width) and /^Origin:\s+\(([\d-]+),([\d-]+)\).*$/) {
        $x = $1;
        $y = $2;
        print "$x $y $width $height\n";
        undef($width);
    }
')"
readarray -t displays <<< "$displays"

mouse="$(cliclick p | sed 's/,/ /')"
read -r mouse_x mouse_y <<< "$mouse"

for display in "${displays[@]}"; do
    read -r x y width height <<< "$display"
    if ((mouse_x >= x && mouse_x < x + width && mouse_y >= y && mouse_y < y + height)); then
        echo "$x $y $width $height"
        exit 0
    fi
done

echo "$SCRIPT_NAME: Error: Mouse ($mouse_x, $mouse_y) is not on any display" >&2
echo "  Displays found:" >&2
count=1
for display in "${displays[@]}"; do
    echo "   $count) $display" >&2
    ((count++))
done

exit 1
