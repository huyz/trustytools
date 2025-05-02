#!/usr/bin/env osascript
# Saves the current window positions and sizes of all open applications into a new AppleScript script
# which can be used to restore the window positions.
# Tries to be smart about matching on window name prefixes (IDEs), profile names (browsers),
# and window numbers (terminals)
#
# FIXME:
# - 2025-03-03 System Events got an error: CanÕt get window "Tor Browser" of application process "firefox".

-- For sorting using AppleScriptObjC
use AppleScript version "2.5"
use framework "Foundation"
use scripting additions


-- Replaces characters in the given text
on replace_chars(theText, searchChar, replacementChar)
    if theText is missing value then return missing value

    set AppleScript's text item delimiters to searchChar
    set the_items to every text item of theText
    set AppleScript's text item delimiters to replacementChar
    set theText to the_items as string
    set AppleScript's text item delimiters to ""
    return theText
end replace_chars

on sortiTermWindowsByAltID(windowRecords)
    set sortedList to {}
    repeat with winRecord in windowRecords
        set inserted to false
        set winAltID to altID of winRecord
        set newList to {}

        -- Insert sorted
        repeat with sortedRecord in sortedList
            set sortedAltID to altID of sortedRecord
            if (not inserted) and (winAltID < sortedAltID) then
                set end of newList to winRecord
                set inserted to true
            end if
            set end of newList to sortedRecord
        end repeat

        if not inserted then
            set end of newList to winRecord
        end if
        set sortedList to newList
    end repeat
    return sortedList
end sortiTermWindowsByAltID


on run
    -- List of applications that have variable window names but hopefully stable window numbers
    set indexedWindowApps to { Â
        "com.apple.Terminal", Â
        "com.googlecode.iterm2", Â
        "net.kovidgoyal.kitty" Â
    }

    -- List of applications that could have multiple windows but we almost always only keep one
    --"com.jetbrains.android-studio", Â
    --"com.jetbrains.appcode", Â
    --"com.jetbrains.appcode.ce", Â
    --"com.jetbrains.clion", Â
    --"com.jetbrains.clion.ce", Â
    --"com.jetbrains.datagrip", Â
    --"com.jetbrains.datagrip.ce", Â
    --"com.jetbrains.goland", Â
    --"com.jetbrains.goland.ce", Â
    --"com.jetbrains.intellij", Â
    --"com.jetbrains.intellij.ce", Â
    --"com.jetbrains.phpstorm", Â
    --"com.jetbrains.phpstorm.ce", Â
    --"com.jetbrains.pycharm", Â
    --"com.jetbrains.pycharm.ce", Â
    --"com.jetbrains.rider", Â
    --"com.jetbrains.rider.ce", Â
    --"com.jetbrains.rubymine", Â
    --"com.jetbrains.rubymine.ce", Â
    --"com.jetbrains.webstorm", Â
    --"com.jetbrains.webstorm.ce", Â
    --"com.apple.Safari", Â
    --"com.apple.SafariTechnologyPreview", Â
    --"com.apple.WebKit.Networking", Â
    --"com.apple.WebKit.PluginProcess", Â
    --"com.apple.WebKit.WebContent", Â
    --"com.kagi.kagimacOS", Â
    --"com.microsoft.Edge", Â
    --"company.thebrowser.Browser", Â
    --"org.mozilla.firefox", Â
    --"org.mozilla.firefoxdeveloperedition" Â

    -- List of applications which often have multiple windows that we want to differentiate
    -- by window name substring
    -- NOTE: I don't know yet if Cursor's bundleId will change; I assume it will so I have to use special
    -- `starts with` logic
    set multiWindowApps to indexedWindowApps & { Â
        "com.microsoft.VSCode", Â
        "com.microsoft.VSCodeInsiders", Â
        "com.todesktop.230313mzl4w4u92", Â
        "com.exafunction.windsurf", Â
        "com.brave.Browser", Â
        "com.google.Chrome", Â
        "org.chromium.Chromium" Â
    }

    set outputScript to "#!/usr/bin/env osascript\n\n"
    set outputScript to outputScript & "-- Window position restoration script\n"
    set outputScript to outputScript & "-- Generated on " & (current date) & "\n\n"

    tell application "System Events"
        -- Get all running processes that are visible
        set processList to bundle identifier of every process whose visible is true
        -- Sort in order to facilitate diffs of output, using AppleScriptObjC
        set array to current application's NSArray's arrayWithArray:processList
        set processList to (array's sortedArrayUsingSelector:"localizedStandardCompare:") as list

        -- Output the same definition of sortiTermWindowsByAltID as above
        set outputScript to outputScript & "on sortiTermWindowsByAltID(windowRecords)\n"
        set outputScript to outputScript & "    set sortedList to {}\n"
        set outputScript to outputScript & "    repeat with winRecord in windowRecords\n"
        set outputScript to outputScript & "        set inserted to false\n"
        set outputScript to outputScript & "        set winAltID to altID of winRecord\n"
        set outputScript to outputScript & "        set newList to {}\n"
        set outputScript to outputScript & "        repeat with sortedRecord in sortedList\n"
        set outputScript to outputScript & "            set sortedAltID to altID of sortedRecord\n"
        set outputScript to outputScript & "            if (not inserted) and (winAltID < sortedAltID) then\n"
        set outputScript to outputScript & "                set end of newList to winRecord\n"
        set outputScript to outputScript & "                set inserted to true\n"
        set outputScript to outputScript & "            end if\n"
        set outputScript to outputScript & "            set end of newList to sortedRecord\n"
        set outputScript to outputScript & "        end repeat\n"
        set outputScript to outputScript & "        if not inserted then\n"
        set outputScript to outputScript & "            set end of newList to winRecord\n"
        set outputScript to outputScript & "        end if\n"
        set outputScript to outputScript & "        set sortedList to newList\n"
        set outputScript to outputScript & "    end repeat\n"
        set outputScript to outputScript & "    return sortedList\n"
        set outputScript to outputScript & "end sortiTermWindowsByAltID\n\n"

        set outputScript to outputScript & "tell application \"System Events\"\n"

        repeat with bundleId in processList
            set processList to name of every process whose bundle identifier is bundleId
            set processName to item 1 of processList

            set windowList to windows of (first process whose bundle identifier is bundleId)

            -- Arc: sometimes there are invisible windows that are sized 600x600 that we want t skip
            -- filter out all these windows
            if (bundleId as string) is "company.thebrowser.Browser" then
                set filteredWindowList to {}
                repeat with aWindow in windowList
                    set winSize to size of aWindow
                    set winName to name of aWindow
                    if winSize is {600, 600} and winName is "" then
                        log "[x] WARNING: Skipping invisible window sized 600x600 for " & processName
                    else
                        set end of filteredWindowList to aWindow
                    end if
                end repeat
                set windowList to filteredWindowList
            end if

            if (count of windowList) > 0 then
                -- Activate application
                -- app_mode_loader is for Simple Chat Hub (extension turned into an app)
                --if {"idea", "app_mode_loader", "Electron"} contains processName then
                --    set outputScript to outputScript & "tell application id \"" & bundleId & "\"\n"
                --else
                --    set outputScript to outputScript & "tell application \"" & processName & "\"\n"
                --end if
                --set outputScript to outputScript & "    activate\n"
                --set outputScript to outputScript & "end tell\n"

-- FIXME(huy) 2025-02-21: the windowList is different when it comes from "tell application" vs. "System Events"
--    and there are different properties: `execution error: Canðt get every text item of missing value.`
--                -- Try to get a deterministic order for certain apps
--                if (bundleId as string) is "com.googlecode.iterm2" then
--                    set sortedWindows to {}
--                    tell application "iTerm"
--                        repeat with win in windows
--                            -- iTerm windows have "alternate identifier" property: "window-1", "window-2"
--                            set altID to alternate identifier of win
--                            set end of sortedWindows to {windowRef:win, altID:altID}
--                        end repeat
--                    end tell
--                    set sortedWindows to my sortiTermWindowsByAltID(sortedWindows)
--
--                    set windowList to {}
--                    repeat with winRecord in sortedWindows
--                        set end of windowList to windowRef of winRecord
--                    end repeat

                -- If this is an app for which we expect to only have one window
                if multiWindowApps does not contain bundleId and bundleId does not start with "com.todesktop." then
                    -- Only take the first window (below, we'll loop through every single window
                    -- regardless of window name or number to set the bounds to those of that first
                    -- window)
                    set windowList to {item 1 of windowList}
                end if

                repeat with currentWindowIndex from 1 to (count of windowList)
                    set currentWindow to item currentWindowIndex of windowList

                    try
                        if processName is "Electron" then
                            -- VS Code, VS Code Insiders, and Windsurf get confused because they all
                            -- have the process name of "Electron"; the workaround is to iterate
                            -- through the window list starting from bundle ID again and again
                            set winPosition to position of (item currentWindowIndex of (windows of (first process whose bundle identifier is bundleId)))
                            set winSize to size of (item currentWindowIndex of (windows of (first process whose bundle identifier is bundleId)))
                            set winName to name of (item currentWindowIndex of (windows of (first process whose bundle identifier is bundleId)))
                        else
                            set winPosition to position of currentWindow
                            set winSize to size of currentWindow
                            set winName to name of currentWindow
                        end if
                        log "[-] " & processName & " (" & bundleId & "): " & my replace_chars(winName, "\"", "\\\"")

                        if winName is missing value then
                            log "[x] WARNING: Skipping window with no name for " & processName
                        else
                            set comparisonVerb to "contains"

                            -- NOTE: `do shell script` must be told to current application to avoid error-and-fallback in Replies
                            tell current application
                                -- For certain apps, we narrow the window name to the key substring (for
                                -- browsers, that's the profile name)
                                if {"com.google.Chrome", "org.chromium.Chromium", "com.brave.Browser", "com.microsoft.Edge"} contains bundleId then
                                    set winName to do shell script "echo " & quoted form of winName & " | sed -E 's/.* (- (Google Chrome|Chromium|Brave|Microsoft Edge) - .*)/\\1/'"
                                    set comparisonVerb to "ends with"
                                else if {"com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.exafunction.windsurf"} contains bundleId or bundleId starts with "com.todesktop." then
                                    -- Take all the characters up to the first opening square bracket
                                    set winName to do shell script "echo " & quoted form of winName & " | sed -E 's/^([^\\[]*\\[).*/\\1/'"
                                    set comparisonVerb to "starts with"
                                end if
                            end tell

                            if winName is "" then
                                set comparisonVerb to "is"
                            else
                                -- Escape double quotes in window name
                                set winName to my replace_chars(winName, "\"", "\\\"")
                            end if


                            set outputScript to outputScript & "    log \"[-] " & processName & " (" & bundleId & "): " & winName & "\"\n"
                            set outputScript to outputScript & "    try -- assuming the process is running\n"
                            set outputScript to outputScript & "        set windowList to windows of (first process whose bundle identifier is \"" & bundleId & "\")\n"

                            -- Output the code that does the same sorting for the case when bundleId is "com.googlecode.iterm2"
                            if (bundleId as string) is "com.googlecode.iterm2" then
                                set outputScript to outputScript & "\n"
                                set outputScript to outputScript & "        set sortedWindows to {}\n"
                                set outputScript to outputScript & "        tell application \"iTerm\"\n"
                                set outputScript to outputScript & "            repeat with win in windowList\n"
                                set outputScript to outputScript & "                set altID to alternate identifier of win\n"
                                set outputScript to outputScript & "                set end of sortedWindows to {windowRef:win, altID:altID}\n"
                                set outputScript to outputScript & "            end repeat\n"
                                set outputScript to outputScript & "        end tell\n"
                                set outputScript to outputScript & "        set sortedWindows to my sortiTermWindowsByAltID(sortedWindows)\n"
                                set outputScript to outputScript & "\n"
                                set outputScript to outputScript & "        set windowList to {}\n"
                                set outputScript to outputScript & "        repeat with winRecord in sortedWindows\n"
                                set outputScript to outputScript & "            set end of windowList to windowRef of winRecord\n"
                                set outputScript to outputScript & "        end repeat\n\n"
                            end if

                            set outputScript to outputScript & "    on error\n"
                            set outputScript to outputScript & "        log \"  [!] Failed to get windows for " & bundleId & "\"\n"
                            set outputScript to outputScript & "        set windowList to {}\n"
                            set outputScript to outputScript & "    end try\n"
                            set outputScript to outputScript & "    repeat with windowIndex from 1 to (count of windowList)\n"
                            --log "Processing window: " & winName

                            -- NOTE: Cursor doesn't have process name "Electron" and doesn't run
                            -- into the same problem as the other VS Code-like apps (but Cursor
                            -- should still have "starts with" as comparisonVerb)
                            if processName is "Electron" then
                                -- As above, VS Code, VS Code Insiders, and Windsurf get confused because they all
                                -- have the process name of "Electron"; the workaround is to iterate
                                -- through the window list starting from bundle ID again and again
                                set outputScript to outputScript & "        if name of (item windowIndex of (windows of (first process whose bundle identifier is \"" & bundleId & "\"))) starts with \"" & winName & "\" then\n"
                                set outputScript to outputScript & "            set position of (item windowIndex of (windows of (first process whose bundle identifier is \"" & bundleId & "\"))) to {" & (item 1 of winPosition) & ", " & (item 2 of winPosition) & "}\n"
                                set outputScript to outputScript & "            set size of (item windowIndex of (windows of (first process whose bundle identifier is \"" & bundleId & "\"))) to {" & (item 1 of winSize) & ", " & (item 2 of winSize) & "}\n"
                                set outputScript to outputScript & "        end if\n"
                            else
                                set outputScript to outputScript & "        set aWindow to item windowIndex of windowList\n"
                                if indexedWindowApps contains bundleId then
                                    set outputScript to outputScript & "        if windowIndex is " & currentWindowIndex & " then\n"
                                else if multiWindowApps contains bundleId then
                                    set outputScript to outputScript & "        if name of aWindow " & comparisonVerb & " \"" & winName & "\" then\n"
                                end if
                                set outputScript to outputScript & "            set position of aWindow to {" & (item 1 of winPosition) & ", " & (item 2 of winPosition) & "}\n"
                                set outputScript to outputScript & "            set size of aWindow to {" & (item 1 of winSize) & ", " & (item 2 of winSize) & "}\n"
                                if indexedWindowApps contains bundleId or multiWindowApps contains bundleId then
                                    set outputScript to outputScript & "        end if\n"
                                end if
                            end if
                            set outputScript to outputScript & "    end repeat\n"
                            set outputScript to outputScript & "\n"
                        end if
                    on error errMsg
                        log errMsg
                    end try
                end repeat
            end if
        end repeat

        set outputScript to outputScript & "end tell\n\n"
        set outputScript to outputScript & "return\n"
    end tell

    set outputPath to (POSIX path of (path to home folder)) & "bin/window-layout-restore"
    do shell script "mkdir -p " & quoted form of POSIX path of (path to home folder) & "bin"

    -- Delete the file if it already exists
    do shell script "rm -f " & quoted form of POSIX path of outputPath

    -- Write script to file
    set outputFile to open for access (outputPath as POSIX file) with write permission
    write outputScript to outputFile as Çclass utf8È
    close access outputFile

    -- Make file executable
    do shell script "chmod +x " & quoted form of POSIX path of outputPath

    log ""
    return "Window restoration script has been saved as '~/bin/window-layout-restore'"
end run
