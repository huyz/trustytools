#!/bin/sh
# huy 2017-07-03
# For all running third-party apps, show the development signatures

# Source: https://www.reddit.com/r/apple/comments/6kpm4t/macos_terminal_alternative_to_antivirus/
for i in `ps axo pid`; do
  # sed: skip the other Authorities in the chain
  codesign -dvv $i 2>&1 | sed -n 's/^Executable=//p; /^Authority/{p;q;}'
  echo
  printf . >&2
done | \
  # Sort (uniquely) by paragraph, while skipping non-Apple apps
  # source: https://www.commandlinefu.com/commands/view/8439/-multiline-unique-paragraph-sort-with-case-insensitive-option-i
  gawk 'BEGIN {
    RS="\n\n"
    if (ARGV[1]=="-i") IGNORECASE=1
    ARGC=1
  }
  {
    if (IGNORECASE)
      Text[tolower($0)]=$0
    else
      Text[$0]=$0
  }
  END {
    N=asort(Text)
    for(i=1;i<=N;i++)
      if (match(Text[i], "Authority=Software Signing") == 0)
        printf "%s\n\n", Text[i]
  }' -i | \
  less
