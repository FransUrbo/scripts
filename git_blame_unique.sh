#!/bin/sh

if [ -z "$1" ]; then
    echo "Usage: `basename $0` <blame_file>"
    exit 1
fi

echo `git blame "$1" | sed 's@ .*@@' | sort | uniq | egrep -v '^00000000$|^\^'`
