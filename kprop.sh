#!/bin/sh

# $Id: kprop.sh,v 1.1 2002-11-20 19:51:42 turbo Exp $

kdclist="kerberos2.bayour.com"

# Dump the database
kdb5_util dump /var/lib/krb5kdc/slave_datatrans

TMPFILE=`tempfile -p kprp.`

# Progagate the database to the slave KDC's
for kdc in $kdclist; do
    /usr/sbin/kprop -f /var/lib/krb5kdc/slave_datatrans $kdc > /dev/null 2> $TMPFILE
    RES="$?"
    if [ "$RES" -gt 0 ]; then
    	echo "Result from kprop: '$RES'"
	cat $TMPFILE
	rm -f $TMPFILE
    fi
done
