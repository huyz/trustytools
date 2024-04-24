# Trusty Tools

## Overview

These tools make up part of the toolset that [I](https://github.com/huyz) find
useful for everyday use.

## Unixy folder

| Command                          | Description                                                                                                                                                                                                           |
| -------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `brew-deptree`                   | Displays dependency tree for all installed packages                                                                                                                                                                   |
| `brew-installed-sizes`           | List installed Homebrew formulae and their sizes                                                                                                                                                                      |
| `brew-requested`                 | List all `requested` Homebrew formulae                                                                                                                                                                                |
| `carc`                           | Simply and safely archive files with optional gpg encryption                                                                                                                                                          |
| `cdiff`                          | Wrapper for diff to add colors both at the line and word level                                                                                                                                                        |
| `clfu`                           | Displays quick-reference for the top 100 commands at [commandlinefu.com](http://commandlinefu.com)                                                                                                                    |
| `cmpdir`                         | Wrapper for rsync to compare two directory trees by checksum                                                                                                                                                          |
| `decrypt`                        | Simply decrypts all sorts of gpg-encrypted files                                                                                                                                                                      |
| `encrypt`                        | Simply encrypts files with gpg                                                                                                                                                                                        |
| `gh-remote-add-fork`             | Lets you interactively select forks (or the upstream's forks) to add as remotes to your local checkout                                                                                                                |
| `git-list-big-objects`           | Lists the biggest objects in a git repository                                                                                                                                                                         |
| `jetbrains-macros-text-keycodes` | Help for JetBrains IDE macros.xml editing: converts a string to type into the proper XML                                                                                                                              |
| `ldwhich`                        | Finds location of a dynamic library by traversing the search path, for Linux, OS X, and other Unix systems.                                                                                                           |
| `list`                           | Simply shows/lists files with the right pager(s) depending on filename extension(s)                                                                                                                                   |
| `markhub`                        | Previews (Github-flavored) Markdown files in a web browser, using [github.com](http://github.com/)'s stylesheet.<br>Useful for checking files, e.g. `README.mkd`, before pushing to github.                           |
| `merge-config-history`           | Helps you keep up with the updated default configs of new versions of apps (e.g., kitty, broot) when you've already customized your version                                                                           |
| `my-ip`                          | Uses online services to determine the public IP address                                                                                                                                                               |
| `ssh-add-l`                      | Better listing of keys added to SSH agent (includes filenames)                                                                                                                                                        |
| `ssh-keygen-l`                   | Better listing of private keys (includes comments)                                                                                                                                                                    |
| `unln`                           | Replaces a symlinked file with a copy so that it can be edited separately                                                                                                                                             |
| `untar`                          | Extracts all or specific files from within a tar archive that's possibly compressed and/or encrypted.<br>Files can be filtered at the command-line and/or interactively. Supports compress, gzip, bzip2, xz, gpg, pgp |
| `vault-kv-fzf`                   | Interactive browser for viewing HashiCorp Vault KV store                                                                                                                                                              |

## Mac folder

| Command                           | Description                                                                                                                                                |
| --------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `autoclear-clipboard`             | Automatically clears passwords from clipboard after a brief time (because Universal Clipboard is dangerous)                                                |
| `bundle-id`                       | Displays the bundle ID of specific application (useful for `terminal-notifier`)                                                                            |
| `eject`                           | Ejects a removable disk by user-friendly volume name                                                                                                       |
| `get-bounds-of-mouse-display`     | Displays the bounds of the display where the mouse is                                                                                                      |
| `is-app-running`                  | Checks if the given application (using macOS friendly name) is running                                                                                     |
| `list-anytrans-backups`           | Lists all the mobile device backups made by iMobie AnyTrans                                                                                                |
| `list-chromium-caches`            | Lists all the Chromium/Electron cache folders and their sizes                                                                                              |
| `list-installed-electron-apps`    | Lists which of the installed Applications run Electron                                                                                                     |
| `list-mobilesync-backups`         | Lists all the mobile device backups made by macOS                                                                                                          |
| `list-processes`                  | Lists running processes as seen from "System Events"                                                                                                       |
| `list-tm-backups`                 | Lists all the Time Machine backups                                                                                                                         |
| `mac-info`                        | Prints out one line of info about macOS software and hardware of the current machine (`macOS 14.4.1 23E224 (Sonoma) MacBookPro18,2 (Apple M1 Max, arm64)`) |
| `mountpoint`                      | Like on linux, checks if a file/dir is a mountpoint                                                                                                        |
| `port-inactive-safe-to-uninstall` | List inactive MacPorts package versions that have active replacements                                                                                      |
| `port-pip-find-packages`          | For the MacPorts Python interpreters, lists all the pip packages and whether they were installed via MacPorts                                              |
| `port-uninstall-inactive-safely`  | Uninstalls inactive MacPorts package versions that have active replacements                                                                                |
| `quit-app`                        | Closes an application (using macOS friendly name); often works better than `pkill`, e.g. for Google Drive                                                  |
| `screencap-ocr`                   | Lets you take a screenshot and puts the OCR'd text in your clipboard                                                                                       |
| `show-dev-sig-of-running-apps`    | Displays Dev Signatures of running apps                                                                                                                    |
| `unretina`                        | Reduces the resolution of Retina screenshots to regular resolution                                                                                         |

## Contrib folder

Other folks' scripts found here and there.

| Command                      | Description                                                                                                                                                  |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `git-quote-string-multiline` | Helper for creating complex git aliases, in particular quoting special characters                                                                            |
| `ip2geo`                     | Given a hostname or IP address, spits out city, state, country {From [commandlinefu.com](http://commandlinefu.com)}                                          |
| `mac-disable-automount`      | Disables the automounting of specified volumes on macOS                                                                                                      |
| `netls`                      | Graphs the number of connections for each connected remote host {From [commandlinefu.com](http://commandlinefu.com)}                                         |
| `relink`                     | Relinks symbolic links by perl regular expression on the paths of the links' targets.                                                                        |
| `rgf`                        | ripgrep-fzf combo {From [fzf](https://github.com/junegunn/fzf/blob/master/ADVANCED.md#switching-between-ripgrep-mode-and-fzf-mode)}                          |
| `timed-run`                  | Run the specified program for a specified maximum number of seconds {By [Expect's Don Libes](http://sourceforge.net/projects/expect/)}                       |
| `timed-read`                 | Reads a line of input, but times out after the specified number of seconds {By [Expect's Don Libes](http://sourceforge.net/projects/expect/)}                |
| `timed-choice`               | Prompts user with several choices, but times out with a default after the specified number of seconds {By [Eugene Spafford](http://spaf.cerias.purdue.edu/)} |
| `mailtrim`                   | Trim a standard Unix mbox file to the most recent specified number of messages {By [Michael Soulier](http://identi.ca/msoulier)}                             |
| `wp`                         | Quickly queries Wikipedia (over DNS!) {From [commandlinefu.com](http://commandlinefu.com)}                                                                   |
| `wrap-in-pty`                | Wrap a command invocation in PTY (so that the command doesn't act any differently than in an interactive terminal)                                           |


# MIT License


Non-contrib tools are copyrighted (C) 2011 Huy Z and are subject to the
following license:

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

