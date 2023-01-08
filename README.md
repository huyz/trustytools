Trusty Tools
============

Overview
--------
These tools make up part of the toolset that [I](https://github.com/huyz) find
useful for everyday use.

Unixy folder
------------
These tools were initially created by me.

*   `carc`      - Simply and safely archive files with optional gpg encryption *   `cdiff`     - Wrapper for diff to add colors both at the line and word level
*   `clfu`      - Displays quick-reference for the top 100 commands at
                  [commandlinefu.com](http://commandlinefu.com)
*   `cmpdir`    - Wrapper for rsync to compare two directory trees by checksum
*   `decrypt`   - Simply decrypts all sorts of gpg-encrypted files
*   `encrypt`   - Simply encrypts files with gpg
*   `ldwhich`   - Finds location of a dynamic library by traversing the
                  search path, for Linux, OS X, and other Unix systems.
*   `list`      - Simply shows/lists files with the right pager(s) depending
                  on filename extension(s)
*   `markhub`   - Previews (Github-flavored) Markdown files in a web browser,
                  using [github.com](http://github.com/)'s stylesheet. Useful
                  for checking files, e.g. `README.mkd`, before pushing to
                  github.
*   `unln`      - Replaces a symlinked file with a copy so that it can be
                  edited separately
*   `untar`     - Extracts all or specific files from within a tar archive
                  that's possibly compressed and/or encrypted.  Files can be
                  filtered at the command-line and/or interactively. Supports
                  compress, gzip, bzip2, xz, gpg, pgp

Mac folder
----------

| Command                        | Description                                                                                                 |
| ------------------------------ | ----------------------------------------------------------------------------------------------------------- |
| `autoclear-clipboard`          | Automatically clears passwords from clipboard after a brief time (because Universal Clipboard is dangerous) |
| `bundle-id`                    | Displays the bundle ID of specific application (useful for `terminal-notifier`)                             |
| `eject`                        | Ejects a removable disk by user-friendly volume name                                                        |
| `list-installed-electron-apps` | Lists which of the installed Applications run Electron                                                      |
| `mountpoint`                   | Like on linux, checks if a file/dir is a mountpoint                                                         |
| `screencap-ocr`                | Lets you take a screenshot and puts the OCR'd text in your clipboard                                        |
| `show-dev-sig-of-running-apps` | Displays Dev Signatures of running apps                                                                     |

Contrib folder
--------------
These open-source tools were found here and there and aggregated because
they're quite useful but not easily available.

*   `relink`    - Relinks symbolic links by perl regular expression on the paths
                  of the links' targets.
*   `ip2geo`    - Given a hostname or IP address, spits out city, state, country
                  {From [commandlinefu.com](http://commandlinefu.com)}
*   `wp`        - Quickly queries Wikipedia (over DNS!)
                  {From [commandlinefu.com](http://commandlinefu.com)}
*   `netls`     - Graphs the number of connections for each connected remote
                  host
                  {From [commandlinefu.com](http://commandlinefu.com)}
*   `timed-run` - Run the specified program for a specified maximum number of
                  seconds
                  {By [Expect's Don Libes](http://sourceforge.net/projects/expect/)}
*   `timed-read` - Reads a line of input, but times out after the specified
                  number of seconds
                  {By [Expect's Don Libes](http://sourceforge.net/projects/expect/)}
*   `timed-choice` - Prompts user with several choices, but times out with a
                  default after the specified number of seconds
                  {By [Eugene Spafford](http://spaf.cerias.purdue.edu/)}
*   `mailtrim`  - Trim a standard Unix mbox file to the most recent specified
                  number of messages
                  {By [Michael Soulier](http://identi.ca/msoulier)}

MIT License
-----------

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

