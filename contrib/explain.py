#!/usr/bin/env python

import sys
import urllib
import webbrowser

url = "http://explainshell.com/explain?cmd=" + urllib.quote(' '.join(sys.argv[1:]))
webbrowser.open_new(url)
