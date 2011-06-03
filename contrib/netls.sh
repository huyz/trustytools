#!/bin/sh
# 2010-10-16
# Source: http://www.commandlinefu.com/commands/view/2012/graph-of-connections-for-each-hosts

netstat -aW | grep ESTABLISHED | awk '{print $5}' | awk -F: '{print $1}' | sort | uniq -c | awk '{ printf("%s\t%s\t",$2,$1) ; for (i = 0; i < $1; i++) {printf("*")}; print "" }' | column -t
