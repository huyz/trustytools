#!/bin/bash
# Lists running processes, by name and bundle ID.

# For jq, see: https://stackoverflow.com/a/39144364/161972
osascript <<EOF | jq -r 'sort_by(.name) | ( ["name", "bundle ID"] | (., map(length*"-")) ), ( .[] | [.name, .bundleId] ) | @tsv' | column -ts $'\t'

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



tell application "System Events" to set runningProcesses to every application process


set processesList to {}

get the properties of (first item of runningProcesses)

repeat with P in runningProcesses
    try
        copy {|name|:(name of P), |bundleId|:(bundle identifier of P)} to end of processesList
    on error errMsg
        # Catch errors like:
        #   System Events got an error: CanÕt get application process "BitdefenderVirusScanner".
        # NOTE: log only logs while running in AppleScript Editor or when running via
        #   osascript (to stderr in that case) - the output will be lost in other
        #   cases, such as when applications run a script with the NSAppleScript
        #   Cocoa class.
        log "Error: process might have quit: " & errMsg
    end try
end repeat

its convertASToJSON:processesList saveTo:(missing value)
EOF
