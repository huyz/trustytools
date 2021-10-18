#!/bin/bash
# - Extracts text from screencap on macOS via Google Cloud Vision API's Text Detection
#   https://apple.stackexchange.com/questions/244557/screenshot-to-ocr-on-os-x/354036#354036
# - Works great when binding to shift-command-6, e.g. with BetterTouchTool or QuickSilver.
#
# Prerequisites:
# - If invoking from command line, starting with Catalina, permissions must be
#   granted beforehand (to Terminal.app and/or iTerm2):
#   https://apple.stackexchange.com/questions/374158/why-is-screencapture-taking-the-screenshot-of-the-desktop-image-and-not-the-wind/384417#384417
# - Google Cloud Vision API must be enabled in the Google Cloud Console, and a
#   service key must be generated. You will have to create a Billing Account with
#   a credit card, but you get 1000 units per month for free
#   https://cloud.google.com/vision/pricing
# - Save the service credentials JSON file somewhere and `export
#   GOOGLE_APPLICATION_CREDENTIALS=<path>` in your shell login scripts.
# - `brew install google-cloud-sdk` for the `gcloud auth` command

set -euo pipefail
shopt -s failglob

#
# Check Prerequisites
#

if ! command -v gcloud >& /dev/null; then
    echo "$0: error: gcloud could not be found. Try \`brew install gcloud-sdk\`" >&2
    exit 1
fi
if [[ -z "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]]; then
    echo "$0: error: GOOGLE_APPLICATION_CREDENTIALS envvar is not set" >&2
    exit 1
fi

GCLOUD_TOKEN="$(gcloud auth application-default print-access-token)"
if [[ -z "${GCLOUD_TOKEN:-}" ]]; then
    echo "$0: error: could not get gcloud auth token. Did you set the GOOGLE_APPLICATION_CREDENTIALS envvar?" >&2
    exit 1
    echo 
fi

#
# Init
#

# Create temporary file
# NOTE: macOS mktemp requires XXXXXXXX to be at the end
screenshot="$(mktemp "${TMP:-/tmp}/$(basename "$0").png.XXXXXXX")"
cleanup() {
  [ -e "$screenshot" ] && rm -f "$screenshot"
}
trap cleanup HUP INT QUIT TERM EXIT

#
# Main
#

# Take screenshot interactively
screencapture -i "$screenshot"
[[ ! -e "$screenshot" || ! -s "$screenshot" ]] && exit
# echo "Temporary file: $screenshot" >&2
# open "$screenshot"

# TIP: to give hints about languages:
# "imageContext": {
#   "languageHints": [
#     "en"
#   ]
# }
if curl -sH"Authorization: Bearer $GCLOUD_TOKEN" \
   -HContent-Type:application/json\;charset=utf-8 \
   https://vision.googleapis.com/v1/images:annotate \
   -d@<(printf %s '{
      "requests": [{
        "image": {
          "content": "'"$(base64 "$screenshot")"'"
        },
        "features": [
          {
            "maxResults": 1000,
            "type": "DOCUMENT_TEXT_DETECTION"
          }
        ]
      }]
    }') | \
   jq -r '.responses[0].fullTextAnnotation.text' |
   pbcopy
then
  osascript -e 'display notification "Successfully extracted to clipboard" with title "screencap-ocr" sound name "Blow"'
  osascript -e 'display dialog (the clipboard) with title "screencap-ocr" buttons {"OK"} default button 1'
else
  osascript -e 'display notification "Failed to extract to clipboard" with title "screencap-ocr" sound name "Basso"'
fi
