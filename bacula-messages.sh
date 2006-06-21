#!/bin/sh

# $Id: bacula-messages.sh,v 1.2 2006-06-21 10:30:26 turbo Exp $

echo 'messages' | bconsole | \
    egrep -v '^Connecting to Director|^1000 OK: |^Enter a period to cancel a command|^messages$'
