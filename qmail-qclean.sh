#!/bin/sh

# $Id: qmail-qclean.sh,v 1.1 2004-06-28 05:29:23 turbo Exp $

cd /var/qmail/queue/mess || exit 1
for file in `find -type f `; do
    spam=

    if grep -q '^Subject: \*\*\*\*SPAM\*\*\*\*' $file; then
	spam=1
    elif grep -q '^X-Spam-Status: Yes' $file; then
	spam=1
    elif ! spamc -cf -U /var/cache/spamd/socket < $file > /dev/null; then
	spam=1
    fi

    if [ ! -z "$spam" ]; then
	qfile=`basename $file`
	FILES=`find .. -name $qfile`
	echo $FILES
	rm $FILES
    fi
done
