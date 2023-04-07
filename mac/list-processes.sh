#!/bin/bash
# Lists running processes, by name and bundle ID.

# For jq, see: https://stackoverflow.com/a/39144364/161972
jq_script='
    # Input is an array with 2 long arrays, the first with names, the second with bundle IDs.

    transpose                       # transpose to an array of small arrays/pairs (name, and bundle ID)
    | sort_by(.[0])                 # sort by the first element (the name)
    |
        (
            ["name", "bundle ID"]   # create a title array
            | (
                .,                  # output the title array
                map(length * "-")   # output similar array whose elements are dashes of same length as the title array elements
            )
        ),
        .[]                         # iterate through array of processes
    | @tsv                          # output as tab-separated values that
'

# column: convert the tabs into a variable number of spaces so that the columns are aligned.
osascript <<EOF | jq -r "$jq_script" | column -ts $'\t'


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
