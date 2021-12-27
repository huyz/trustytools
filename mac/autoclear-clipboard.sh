#!/bin/bash
# 2020-06-27 Automatically clears the pasteboard if it contains a password-looking for too long.
# Counter-measure against Universal Pasteboard, which is dangerous as iOS apps will
# often read the pasteboard when they launch (e.g, TikTok)

### Config

DEBUG=

# In seconds
CHECK_INTERVAL=15

# If set to 1, only clears output that is password-like: a specific length and no whitespace and doesn't start
# with http
CLEAR_PASSWORD_ONLY=1

### End of Config

prev_content=

while true; do
  content="$(pbpaste)"

  if [[ -z "$content" ]]; then
    [[ -n $DEBUG ]] && echo "Nothing. Skipping..." >&2
    :

  elif [[ "$content" = "$prev_content" ]]; then
    if (( SECONDS - prev_seconds >= CHECK_INTERVAL )); then
      [[ -n $DEBUG ]] && echo "Stale. Erasing..." >&2
      pbcopy </dev/null
      prev_content=
    else
      [[ -n $DEBUG ]] && echo "Still fresh. Holding..." >&2
    fi

  elif [[ -z $CLEAR_PASSWORD_ONLY ]]; then
    [[ -n $DEBUG ]] && echo "New. Storing..." >&2
    prev_content="$content"
    prev_seconds=$SECONDS

  elif [[ ${#content} -ge 8 && ${#content} -le 30 && "$(<<<"$content" sed 's/[[:space:]]//g')" == "$content" && "$content" != http* ]]; then
    [[ -n $DEBUG ]] && echo "New password. Storing..." >&2
    prev_content="$content"
    prev_seconds=$SECONDS
  else
    [[ -n $DEBUG ]] && echo "New non-password. Skipping..." >&2
    prev_content=
  fi

  sleep 1
done
