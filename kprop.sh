#!/bin/sh

# $Id: kprop.sh,v 1.2 2003-03-29 09:45:42 turbo Exp $

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
    fi
done
rm -f $TMPFILE
