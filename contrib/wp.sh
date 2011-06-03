#!/bin/sh
# 2010-10-16
# Source: http://www.commandlinefu.com/commands/view/2829/query-wikipedia-via-console-over-dns

blah=$(echo $* | sed -e 's/ /_/g')
exec dig +short txt $blah.wp.dg.cx
#exec host -t txt $blah.wp.dg.cx
