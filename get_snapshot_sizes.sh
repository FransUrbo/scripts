#!/bin/sh

TMP=`tempfile -d /tmp/`

TOT=0
zfs list -t snapshot -o used | egrep -v '0$' | \
    grep -v USED | \
    while read line; do
	size=`echo "$line" | sed 's@[KMG]$@@'`
        if echo "$line" | egrep -q 'M$'; then
            size=`echo "scale=2; $size * 1024" | bc`
        elif echo "$line" | egrep -q 'G$'; then
            size=`echo "scale=2; $size * 1024 * 1024" | bc`
        fi

        TOT=`echo "scale=2; $TOT + $size" | bc`
        echo "$TOT" > $TMP
    done

TOT=`cat $TMP` ; rm $TMP
TOT=`echo "scale=0; $TOT / 1024 / 1024" | bc`
echo "TOT: $TOT"GB
