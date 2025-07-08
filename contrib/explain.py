#!/usr/bin/env python3

import sys
import urllib.parse
import webbrowser

url = "http://explainshell.com/explain?cmd=" + urllib.parse.quote(' '.join(sys.argv[1:]))
webbrowser.open_new(url)
