#!/bin/sh

# $Id: bacula-status.sh,v 1.2 2006-06-21 10:30:26 turbo Exp $

echo "status dir" | bconsole | \
    egrep -v '^Connecting to Director|^1000 OK: |^Enter a period to cancel a command|^status dir$|^Using default Catalog name=|-dir Version: |^Daemon started |^==='
