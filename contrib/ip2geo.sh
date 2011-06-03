#!/bin/sh
# 2010-10-15
# Source: http://www.commandlinefu.com/commands/view/1205/find-geographical-location-of-an-ip-address

lynx -dump http://www.ip-adress.com/ip_tracer/?QRY=$1|grep address|egrep 'city|state|country'|awk '{print $3,$4,$5,$6,$7,$8}'|sed 's/ip address flag //'|sed 's/My//'
