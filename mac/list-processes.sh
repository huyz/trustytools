#!/bin/bash
# Lists running processes, by name and bundle ID.
# By default, outputs a table.
# Use -J or --json option to output in JSON.

set -euo pipefail
shopt -s failglob extglob
# shellcheck disable=SC2329
function trap_err { echo "ERR signal on line $(caller)" >&2; }
trap trap_err ERR
trap exit INT
export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'


#### Options

function usage {
    echo "Usage: $0 [-h|--help] [-J|--json]
    -J|--json: Output in JSON format.
"
    exit 1
}

if [[ $# -gt 1 || "${1-}" == @(-h|--help) ]]; then
    usage
elif [[ "${1-}" == @(-J|--json) ]]; then
    opt_json=opt_json
fi


# AppleScript to get the list of running processes in JSON.
read -r -d '' as_script <<'EOF' || true
----------------------------------------------------------------
use AppleScript version "2.5"
use framework "Foundation"
use scripting additions
--use script "FileManagerLib" version "2.3.3"
----------------------------------------------------------------

----------------------------------------------------------------
-- Source: https://www.macscripter.net/t/property-lists-json-and-applescript/67485?u=macspitter
-- pass a string, list, record or number, and either a path to save the result to, or missing value to have it returned as text
on convertASToJSON:someASThing saveTo:posixPath
	--convert to JSON data
	set {theData, theError} to current application's NSJSONSerialization's dataWithJSONObject:someASThing options:0 |error|:(reference)
	if theData is missing value then error (theError's localizedDescription() as text) number -10000
	if posixPath is missing value then -- return string
		-- convert data to a UTF8 string
		set someString to current application's NSString's alloc()'s initWithData:theData encoding:(current application's NSUTF8StringEncoding)
		return someString as text
	else
		-- write data to file
		theData's writeToFile:posixPath atomically:true
		return result as boolean -- returns false if save failed
	end if
end convertASToJSON:saveTo:


tell application "System Events" to set processesList to {name, bundle identifier} of every application process

its convertASToJSON:processesList saveTo:(missing value)
EOF


if [[ -n ${opt_json-} ]]; then
    # jq manipulation for output as json
    jq_script='
        # Input is an array with 2 long arrays, the first with process names,
        # the second with corresponding process bundle IDs.

        [                                   # create an array to be output
            transpose                       # transpose to an array of small arrays/pairs (name, and bundle ID)
            | sort_by(.[0])                 # sort by the first element (the name)
            | .[]                           # iterate through array of processes
            | {name: .[0], bundleId: .[1]}  # for each process, output an object with the name and bundle ID
        ]
'
    osascript <<<"$as_script"| jq -r "$jq_script"
else
    # jq manipulation for output as a table
    # See: https://stackoverflow.com/a/39144364/161972
    jq_script='
        # Input is an array with 2 long arrays, the first with process names,
        # the second with corresponding process bundle IDs.

        transpose                       # transpose to an array of small arrays/pairs (name, and bundle ID)
        | sort_by(.[0])                 # sort by the first element (the name)
        |
            (
                ["name", "bundle ID"]   # create a title row
                | (
                    .,                  # output the title row
                    map(length * "-")   # output similar row whose elements are dashes of same length as the title array elements
                )
            ),
            .[]                         # output through array of processes: one row per process
        | @tsv                          # output entire input as tab-separated values (for column to process)
'
    # column: convert the tabs into a variable number of spaces so that the columns are aligned.
    osascript <<<"$as_script"| jq -r "$jq_script" | column -ts $'\t'
fi

