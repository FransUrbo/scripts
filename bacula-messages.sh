#!/bin/sh

echo 'messages' | bconsole | \
    egrep -v '^Connecting to Director|^1000 OK: |^Enter a period to cancel a command|^messages$'
