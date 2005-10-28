#!/bin/sh

# $Id: kprop.sh,v 1.5 2005-10-28 07:41:45 turbo Exp $

kdclist="kerberos2.bayour.com"

fix_error() {
    fs=`echo $1` ; msg=`echo $2` ; error=1

    while [ $error -ge 1 -a $error -le 3 ]; do
	if echo $msg | grep -qi 'read-only'; then
	    # Error: FS readonly

	    mount -o remount,rw $fs
	    touch /tmp/$$ > /dev/null 2>&1 
	    if [ "$?" == "0" ]; then
		error=0
	    else
		# Didn't work. Try again.
		umount /tmp && mount /tmp
		error=`expr $error + 1`
	    fi
#	elif echo $msg | grep -qi 'No space left on device'; then
#	    # Error: FS full
#	    #fs=`mount | egrep 'ext[23] \(rw\)' | grep -v /vice | sed -e 's@.*on @@' -e 's@\ .*@@'`
#
#	    # Not sure how I should handle this...
	fi
    done

    if [ "$error" -gt "0" ]; then
	exit 1
    fi
}

# Dump the database
OUTPUT=`kdb5_util dump /var/lib/krb5kdc/slave_datatrans 2>&1`
if [ "$?" == "1" ]; then
    fix_error /var/lib/krb5kdc "$OUTPUT"
fi

TMPFILE=`tempfile -p kprp. 2>&1`
if [ "$?" == "1" ]; then
    fix_error /tmp "$TMPFILE"
    TMPFILE=`tempfile -p kprp. 2>&1`
fi

# Progagate the database to the slave KDC's
for kdc in $kdclist; do
    /usr/sbin/kprop -f /var/lib/krb5kdc/slave_datatrans $kdc > /dev/null 2> $TMPFILE
    RES="$?"
    if [ "$RES" -gt 0 ]; then
    	echo "Result from kprop ($kdc): '$RES'"
	cat $TMPFILE
    fi
done
rm -f $TMPFILE
