#!/bin/sh

echo "status dir" | bconsole | \
    egrep -v '^Connecting to Director|^1000 OK: |^Enter a period to cancel a command|^status dir$|^Using default Catalog name=|-dir Version: |^Daemon started |^==='
