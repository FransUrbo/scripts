#!/bin/sh

i=1
exportfs  | grep ^/ | sed 's@ .*@@' | sort --ignore-case | \
while read share; do
    printf "%6s: %-80s\n" $i $share
    i=`expr $i + 1`
done
