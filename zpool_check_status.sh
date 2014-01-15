#!/bin/sh

# celia(ZFSRoot):~# zpool list -H -o name,free,health
# share   2.10T   ONLINE
zpool list -H -o name,free,health | \
    while read line; do
	set -- `echo "$line"`
        if [ "$3" -ne "ONLINE" ]; then
            echo "$3: $1"
        fi
    done
