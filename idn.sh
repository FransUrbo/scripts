#!/bin/sh

if [ -z "$1" ]; then
    echo "Usage: `basename $0` <utf8_string>"
    exit 1
fi

echo -n "$1 = "
echo $1 | CHARSET='UTF-8' idn -a --quiet
