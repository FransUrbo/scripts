#!/bin/bash

set -e

find -maxdepth 1 -type d -name '[A-Za-z0-9]*' | \
	egrep -v '\.zfs|\.Apple' | \
	sort | \
	while read dir; do
		if [ ! -d "$dir/.zfs" ]; then
			dir=`echo "$dir" | sed 's@^\./@@'`
			echo -n "$dir: "

			mv "$dir" "$dir.OLD"
			zfs_create "share/TV_Series/$dir"
			echo -n "."

			find "$dir.OLD" -type f -o -type l | \
				sort | \
				grep -v '\.Apple' | \
				while read file; do
					mv "$file" "$dir"
				done
			echo -n "."

			[ -d "$dir.OLD/.AppleDouble" ] && \
				rm -Rf "$dir.OLD/.AppleDouble"
			rmdir "$dir.OLD"
			echo -n "."

			echo
		fi
	done
